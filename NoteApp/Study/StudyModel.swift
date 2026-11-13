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

    /// Records one grade. The in-memory state updates immediately; the file is
    /// written after a short pause so a burst of grades costs one write.
    func record(_ state: ReviewState, for setID: UUID) {
        var raw = reviewStates[setID.uuidString] ?? [:]
        raw[state.cardID.uuidString] = state
        reviewStates[setID.uuidString] = raw
        scheduleStateWrite()
    }

    func dueCount(for set: StudySet) -> Int {
        SpacedRepetitionScheduler(states: states(for: set.id))
            .dueCards(in: set, now: Date())
            .count
    }

    func set(withID id: UUID) -> StudySet? {
        sets.first { $0.id == id }
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
