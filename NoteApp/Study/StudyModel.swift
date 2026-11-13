import Foundation
import Observation
import StudyKit

/// Owns the study-set library and the review states beside it. Sets live in
/// their own folder under the app library; review scheduling is a local cache
/// that can be rebuilt if lost.
@MainActor
@Observable
final class StudyModel {
    private nonisolated struct StateFile: Codable, Sendable {
        var sets: [String: [String: ReviewState]] = [:]
    }

    let store: StudySetStore
    private let statesURL: URL

    private(set) var sets: [StudySet] = []
    private(set) var reviewStates: [String: [String: ReviewState]] = [:]
    private(set) var isLoading = true
    /// The last failure worth showing to the reader, including sets that could
    /// not be read. Cleared by a successful `load()`.
    var lastError: String?

    private var stateWriteTask: Task<Void, Never>?
    private var hasReportedStateWriteFailure = false

    init(root: URL) {
        store = StudySetStore(root: root)
        statesURL = root.appendingPathComponent("review-states.json", isDirectory: false)
    }

    /// Loads the library. Unreadable set files are reported in `lastError`
    /// instead of hiding every readable set.
    func load() async {
        isLoading = true
        do {
            try await store.open()
            let listing = try await store.listReportingIssues()
            sets = listing.sets
            sortSets()
            lastError = Self.message(for: listing.issues)
        } catch {
            lastError = error.localizedDescription
        }
        await loadStates()
        isLoading = false
    }

    /// Re-reads the library, clearing any previous error on success.
    func reload() async {
        await load()
    }

    func clearError() {
        lastError = nil
    }

    func createSet(title: String) async -> StudySet? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let set = StudySet(title: trimmed.isEmpty ? "Untitled Study Set" : trimmed)
        do {
            try await store.save(set)
            sets.append(set)
            sortSets()
            return set
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    /// Saves a set and reports whether the file was written.
    @discardableResult
    func save(_ set: StudySet) async -> Bool {
        var updated = set
        updated.updatedAt = Date()
        do {
            try await store.save(updated)
            if let index = sets.firstIndex(where: { $0.id == updated.id }) {
                sets[index] = updated
            } else {
                sets.append(updated)
            }
            sortSets()
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func delete(_ set: StudySet) async {
        do {
            try await store.delete(set.id)
            sets.removeAll { $0.id == set.id }
            reviewStates.removeValue(forKey: set.id.uuidString)
            scheduleStateWrite(delay: .zero)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func importCSV(from url: URL) async -> StudySet? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let title = url.deletingPathExtension().lastPathComponent
            // Reading and parsing a large CSV stays off the main actor.
            let set = try await Task.detached(priority: .userInitiated) { () throws -> StudySet in
                let data = try Data(contentsOf: url)
                return try StudySetCSV.importSet(from: data, title: title)
            }.value
            try await store.save(set)
            sets.append(set)
            sortSets()
            return set
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    func states(for setID: UUID) -> [UUID: ReviewState] {
        let raw = reviewStates[setID.uuidString] ?? [:]
        var result: [UUID: ReviewState] = [:]
        for (key, value) in raw {
            if let id = UUID(uuidString: key) {
                result[id] = value
            }
        }
        return result
    }

    /// Every set's states, for the schedulers that answer over several sets.
    var allStates: [UUID: [UUID: ReviewState]] {
        var result: [UUID: [UUID: ReviewState]] = [:]
        for set in sets {
            result[set.id] = states(for: set.id)
        }
        return result
    }

    /// Records one grade. The in-memory state updates immediately; the file is
    /// written after a short pause so a burst of grades costs one write.
    func record(_ state: ReviewState, for setID: UUID) {
        var raw = reviewStates[setID.uuidString] ?? [:]
        raw[state.cardID.uuidString] = state
        reviewStates[setID.uuidString] = raw
        scheduleStateWrite()
    }

    /// Every due card in the library, or in one set, notebook or page.
    func queue(
        now: Date = Date(),
        setID: UUID? = nil,
        notebookID: UUID? = nil,
        pageID: UUID? = nil
    ) -> [StudyQueueItem] {
        let scoped = if let setID {
            sets.filter { $0.id == setID }
        } else {
            sets
        }
        return StudyQueue.due(
            in: scoped,
            states: allStates,
            now: now,
            notebookID: notebookID,
            pageID: pageID
        )
    }

    /// Every card captured from a notebook or page, due or not.
    func cards(notebookID: UUID? = nil, pageID: UUID? = nil) -> [StudyQueueItem] {
        StudyQueue.cards(
            in: sets,
            states: allStates,
            now: Date(),
            notebookID: notebookID,
            pageID: pageID
        )
    }

    /// How many cards are due across the library, or in one set, notebook or page.
    func dueCount(setID: UUID? = nil, notebookID: UUID? = nil, pageID: UUID? = nil) -> Int {
        let scoped = if let setID {
            sets.filter { $0.id == setID }
        } else {
            sets
        }
        return StudyQueue.dueCount(
            in: scoped,
            states: allStates,
            now: Date(),
            notebookID: notebookID,
            pageID: pageID
        )
    }

    /// The library-wide count behind the "N due" badge.
    var totalDueCount: Int {
        dueCount()
    }

    func dueCount(for set: StudySet) -> Int {
        dueCount(setID: set.id)
    }

    /// Adds a card captured from a notebook page. Cards from the same notebook
    /// share one set, so repeated captures do not scatter across the library.
    @discardableResult
    func addCard(
        question: String,
        answer: String,
        notebookID: UUID,
        pageID: UUID,
        notebookTitle: String
    ) async -> Bool {
        let prompt = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return false }

        let existing = sets
            .filter { set in
                set.cards.contains { $0.sourceNotebookID == notebookID }
            }
            .max { $0.updatedAt < $1.updatedAt }

        var created = false
        let target: StudySet
        if let existing {
            target = existing
        } else if let newSet = await createSet(title: notebookTitle) {
            target = newSet
            created = true
        } else {
            return false
        }

        var updated = target
        updated.cards.append(
            StudyCard(
                question: prompt,
                answer: answer.trimmingCharacters(in: .whitespacesAndNewlines),
                sourceNotebookID: notebookID,
                sourcePageID: pageID
            )
        )
        let saved = await save(updated)
        if !saved, created {
            // A failed first capture leaves no empty set behind.
            await delete(target)
        }
        return saved
    }

    /// Replaces a card's text, keeping its id, source and schedule.
    @discardableResult
    func updateCard(_ cardID: UUID, in setID: UUID, question: String, answer: String) async -> Bool {
        let prompt = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty,
              var updated = set(withID: setID),
              let index = updated.cards.firstIndex(where: { $0.id == cardID })
        else { return false }

        updated.cards[index].question = prompt
        updated.cards[index].answer = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.cards[index].updatedAt = Date()
        return await save(updated)
    }

    /// Adds a second card beside a leech, with the same source page.
    @discardableResult
    func addCard(to setID: UUID, after card: StudyCard, question: String, answer: String) async -> Bool {
        let prompt = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, var updated = set(withID: setID) else { return false }

        updated.cards.append(
            StudyCard(
                question: prompt,
                answer: answer.trimmingCharacters(in: .whitespacesAndNewlines),
                sourceNotebookID: card.sourceNotebookID,
                sourcePageID: card.sourcePageID
            )
        )
        return await save(updated)
    }

    func set(withID id: UUID) -> StudySet? {
        sets.first { $0.id == id }
    }

    /// Starts a rewritten card's schedule over, so it leaves the leech list and
    /// is due again as a fresh card.
    func resetSchedule(cardID: UUID, in setID: UUID) {
        record(.new(cardID: cardID, now: Date()), for: setID)
    }

    // MARK: - Persistence

    private func sortSets() {
        sets.sort { left, right in
            if left.updatedAt != right.updatedAt { return left.updatedAt > right.updatedAt }
            return left.id.uuidString < right.id.uuidString
        }
    }

    private func loadStates() async {
        let url = statesURL
        let data = await Task.detached(priority: .utility) { () -> Data? in
            try? Data(contentsOf: url)
        }.value
        guard let data,
              let decoded = try? JSONDecoder().decode(StateFile.self, from: data)
        else { return }
        reviewStates = decoded.sets
    }

    /// Writes the review-state cache after `delay`, cancelling any pending write.
    private func scheduleStateWrite(delay: Duration = .milliseconds(750)) {
        let snapshot = StateFile(sets: reviewStates)
        let url = statesURL
        stateWriteTask?.cancel()
        stateWriteTask = Task { [weak self] in
            if delay > .zero {
                try? await Task.sleep(for: delay)
            }
            guard !Task.isCancelled else { return }
            let written = await Task.detached(priority: .utility) { () -> Bool in
                guard let data = try? JSONEncoder().encode(snapshot) else { return false }
                do {
                    try data.write(to: url, options: .atomic)
                    return true
                } catch {
                    return false
                }
            }.value
            guard let self, !Task.isCancelled else { return }
            if written {
                self.hasReportedStateWriteFailure = false
            } else if !self.hasReportedStateWriteFailure {
                self.hasReportedStateWriteFailure = true
                self.lastError = "Review progress could not be saved. Your grades still apply for this session."
            }
        }
    }

    private static func message(for issues: [StudySetLoadIssue]) -> String? {
        guard let first = issues.first else { return nil }
        if issues.count == 1 {
            return "One study set could not be read and was skipped. \(first.message)"
        }
        return "\(issues.count) study sets could not be read and were skipped. \(first.message)"
    }
}
