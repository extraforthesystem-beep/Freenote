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

    /// The latest queued write; each write waits for the one before it.
    private var stateWriteTask: Task<Bool, Never>?
    /// Bumped whenever `sets` or `reviewStates` change. Readers of the memoised
    /// values below observe it, so a cached count cannot outlive its inputs.
    private(set) var stateRevision = 0
    /// The last computed `allStates` map, valid for one revision.
    private var memoisedAllStates: (revision: Int, value: [UUID: [UUID: ReviewState]])?
    /// Per-set due counts computed in one pass, valid for one revision.
    private var memoisedDueCounts: (revision: Int, value: [UUID: Int])?
    /// The newest revision known to be on disk. Equal to `stateRevision` when
    /// there is nothing to write.
    private var savedRevision = 0
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
            stateRevision &+= 1
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
            stateRevision &+= 1
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
            stateRevision &+= 1
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
            stateRevision &+= 1
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
            stateRevision &+= 1
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
    ///
    /// Memoised for the current `stateRevision`; the read of `stateRevision`
    /// keeps a view that uses it observing the underlying states.
    var allStates: [UUID: [UUID: ReviewState]] {
        let revision = stateRevision
        if let memoised = memoisedAllStates, memoised.revision == revision {
            return memoised.value
        }
        var result: [UUID: [UUID: ReviewState]] = [:]
        for set in sets {
            result[set.id] = states(for: set.id)
        }
        memoisedAllStates = (revision, result)
        return result
    }

    /// Records one grade. The in-memory state updates immediately; the file is
    /// written after a short pause so a burst of grades costs one write.
    func record(_ state: ReviewState, for setID: UUID) {
        var raw = reviewStates[setID.uuidString] ?? [:]
        raw[state.cardID.uuidString] = state
        reviewStates[setID.uuidString] = raw
        stateRevision &+= 1
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
        dueCountsBySet.values.reduce(0, +)
    }

    /// Due counts for every set, computed in one pass over the library and
    /// memoised until the sets or their states change.
    var dueCountsBySet: [UUID: Int] {
        let revision = stateRevision
        if let memoised = memoisedDueCounts, memoised.revision == revision {
            return memoised.value
        }
        let value = StudyQueue.dueCounts(
            in: sets,
            states: allStates,
            now: Date()
        )
        memoisedDueCounts = (revision, value)
        return value
    }

    func dueCount(for set: StudySet) -> Int {
        dueCountsBySet[set.id] ?? 0
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
        guard let data else { return }
        do {
            let decoded = try JSONDecoder().decode(StateFile.self, from: data)
            reviewStates = decoded.sets
            stateRevision &+= 1
        } catch {
            // The schedule is a rebuildable cache, so every card becomes new.
            // Keep the unreadable file for inspection instead of overwriting it.
            await setAsideUnreadableStates(at: url)
            lastError = Self.corruptStateMessage
        }
    }

    /// The message shown when `review-states.json` could not be decoded.
    private static let corruptStateMessage =
        "Review progress could not be read; cards were rescheduled as new."

    /// Moves an unreadable states file into `quarantine/`, the same way the
    /// library sets aside a file it cannot decode. A failed move leaves the
    /// original in place; a later write may replace it, but nothing is lost
    /// before then.
    private func setAsideUnreadableStates(at url: URL) async {
        let directory = url.deletingLastPathComponent()
            .appendingPathComponent("quarantine", isDirectory: true)
        let stamp = Int64((Date().timeIntervalSince1970 * 1_000).rounded())
        let destination = directory.appendingPathComponent(
            "\(stamp)-\(url.lastPathComponent)"
        )
        await Task.detached(priority: .utility) {
            let manager = FileManager.default
            do {
                try manager.createDirectory(
                    at: directory,
                    withIntermediateDirectories: true
                )
                try manager.moveItem(at: url, to: destination)
            } catch {
                // Leave the file where it is for the next attempt.
            }
        }.value
    }

    /// The message kept in `lastError` while grades cannot reach disk.
    private static let stateWriteFailureMessage =
        "Review progress could not be saved. Your grades still apply for this session."

    /// Writes the review states now, cancelling any pending debounce, and waits
    /// for the file. Returns false when the states could not be saved.
    ///
    /// Safe to call beside a scheduled write: writes are serialized and a
    /// snapshot already on disk is not written again.
    @discardableResult
    func flushStateWrite() async -> Bool {
        let revision = stateRevision
        let task = enqueueStateWrite(delay: .zero)
        if await task.value { return true }
        // Another write replaced this one (a second flush, or a grade that
        // arrived first). Wait for the latest one and report that snapshot.
        if let latest = stateWriteTask {
            _ = await latest.value
        }
        return savedRevision >= revision
    }

    /// Writes the review-state cache after `delay`, replacing any pending write.
    private func scheduleStateWrite(delay: Duration = .milliseconds(750)) {
        enqueueStateWrite(delay: delay)
    }

    /// Queues one write of the current snapshot.
    ///
    /// Each write waits for the one before it, so an older snapshot can never
    /// land after a newer one, and a canceled debounce still lets the write it
    /// already started finish before the next one begins.
    @discardableResult
    private func enqueueStateWrite(delay: Duration) -> Task<Bool, Never> {
        let previous = stateWriteTask
        previous?.cancel()
        let revision = stateRevision
        let snapshot = StateFile(sets: reviewStates)
        let url = statesURL
        let task: Task<Bool, Never> = Task { [weak self] in
            if delay > .zero {
                try? await Task.sleep(for: delay)
            }
            // One writer at a time: a newer snapshot never overtakes the one
            // it replaces. This runs before the cancellation check because a
            // replaced debounce must still keep the chain intact.
            _ = await previous?.value
            guard !Task.isCancelled else { return false }
            guard let self else { return false }
            // An earlier write already covered this snapshot.
            guard self.savedRevision < revision else { return true }
            let written = await Self.write(snapshot, to: url)
            self.noteStateWrite(revision: revision, written: written)
            return written
        }
        stateWriteTask = task
        return task
    }

    /// Encodes and writes one snapshot off the main actor.
    private nonisolated static func write(_ snapshot: StateFile, to url: URL) async -> Bool {
        await Task.detached(priority: .utility) { () -> Bool in
            guard let data = try? JSONEncoder().encode(snapshot) else { return false }
            do {
                try data.write(to: url, options: .atomic)
                return true
            } catch {
                return false
            }
        }.value
    }

    /// Records one write's outcome. The failure message stays in `lastError`
    /// until a later write succeeds; a cancelled write was replaced by a newer
    /// snapshot, so it does not report.
    private func noteStateWrite(revision: Int, written: Bool) {
        if written {
            savedRevision = max(savedRevision, revision)
            guard !Task.isCancelled else { return }
            hasReportedStateWriteFailure = false
            if lastError == Self.stateWriteFailureMessage {
                lastError = nil
            }
        } else if !Task.isCancelled, !hasReportedStateWriteFailure {
            hasReportedStateWriteFailure = true
            lastError = Self.stateWriteFailureMessage
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
