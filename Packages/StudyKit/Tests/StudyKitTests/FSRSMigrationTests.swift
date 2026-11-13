import Foundation
import StudyKit
import Testing

/// Review states written by the SM-2 scheduler are the app's existing review
/// history. These tests pin that they decode, that migration keeps every SM-2
/// field and the due date, and that FSRS can grade the migrated card.
@Suite("FSRS migration")
struct FSRSMigrationTests {
    private let scheduler = FSRSScheduler()

    /// The exact JSON an SM-2 state wrote: no `stability`, no `difficulty`.
    private func legacyStateJSON(
        cardID: UUID,
        now: Date = testNow
    ) -> Data {
        let dueDate = now.timeIntervalSinceReferenceDate
        let reviewedAt = now.addingTimeInterval(-18 * 86_400).timeIntervalSinceReferenceDate
        let json = """
        {
          "cardID": "\(cardID.uuidString)",
          "easeFactor": 2.1,
          "intervalDays": 18,
          "repetitions": 5,
          "dueDate": \(dueDate),
          "lastReviewedAt": \(reviewedAt),
          "lapses": 2
        }
        """
        return Data(json.utf8)
    }

    @Test func legacySM2JSONDecodesWithoutLosingHistory() throws {
        let cardID = UUID()
        let decoded = try JSONDecoder().decode(
            ReviewState.self,
            from: legacyStateJSON(cardID: cardID)
        )

        #expect(decoded.cardID == cardID)
        #expect(decoded.easeFactor == 2.1)
        #expect(decoded.intervalDays == 18)
        #expect(decoded.repetitions == 5)
        #expect(decoded.dueDate == testNow)
        #expect(decoded.lastReviewedAt == testNow.addingTimeInterval(-18 * 86_400))
        #expect(decoded.lapses == 2)
        #expect(decoded.stability == nil)
        #expect(decoded.difficulty == nil)
    }

    @Test func theLegacyReviewStateFileShapeStillDecodes() throws {
        let cardID = UUID()
        let setID = UUID()
        let json = """
        { "sets": { "\(setID.uuidString)": { "\(cardID.uuidString)": \(String(data: legacyStateJSON(cardID: cardID), encoding: .utf8) ?? "{}") } } }
        """
        struct StateFile: Codable {
            var sets: [String: [String: ReviewState]]
        }

        let file = try JSONDecoder().decode(StateFile.self, from: Data(json.utf8))

        #expect(file.sets[setID.uuidString]?[cardID.uuidString]?.lapses == 2)
        #expect(file.sets[setID.uuidString]?[cardID.uuidString]?.intervalDays == 18)
    }

    @Test func migrationKeepsDueDateAndReviewHistory() throws {
        let legacy = try JSONDecoder().decode(
            ReviewState.self,
            from: legacyStateJSON(cardID: UUID())
        )

        let migrated = scheduler.migrate(legacy)

        #expect(migrated.cardID == legacy.cardID)
        #expect(migrated.dueDate == legacy.dueDate)
        #expect(migrated.lastReviewedAt == legacy.lastReviewedAt)
        #expect(migrated.intervalDays == legacy.intervalDays)
        #expect(migrated.repetitions == legacy.repetitions)
        #expect(migrated.lapses == legacy.lapses)
        #expect(migrated.easeFactor == legacy.easeFactor)
        #expect(migrated.stability == 18)
        #expect((migrated.difficulty ?? 0) >= 1 && (migrated.difficulty ?? 0) <= 10)
    }

    @Test func migrationIsIdempotent() {
        let migrated = scheduler.migrate(
            scheduler.migrate(
                ReviewState(
                    cardID: UUID(),
                    easeFactor: 2.5,
                    intervalDays: 7,
                    repetitions: 3,
                    dueDate: testNow,
                    lastReviewedAt: testNow.addingTimeInterval(-7 * 86_400)
                )
            )
        )
        let twice = scheduler.migrate(migrated)

        #expect(migrated == twice)
    }

    @Test func aCardThatWasNeverReviewedIsLeftForItsFirstGrade() {
        let fresh = ReviewState.new(cardID: UUID(), now: testNow)

        let migrated = scheduler.migrate(fresh)

        #expect(migrated.stability == nil)
        #expect(migrated.difficulty == nil)
        #expect(migrated.dueDate == testNow)
    }

    @Test func migratedCardsScheduleWithFSRS() throws {
        let legacy = try JSONDecoder().decode(
            ReviewState.self,
            from: legacyStateJSON(cardID: UUID())
        )
        let migrated = scheduler.migrate(legacy)

        let reviewed = scheduler.review(state: migrated, quality: 4, now: testNow)

        #expect(reviewed.lapses == legacy.lapses)
        #expect(reviewed.repetitions == legacy.repetitions + 1)
        #expect(reviewed.lastReviewedAt == testNow)
        #expect(reviewed.stability != migrated.stability)
        #expect(reviewed.intervalDays >= 1)
        #expect(reviewed.dueDate == testNow.addingTimeInterval(Double(reviewed.intervalDays) * 86_400))
    }

    @Test func aMigratedStateRoundTripsThroughItsFileFormat() throws {
        let legacy = try JSONDecoder().decode(
            ReviewState.self,
            from: legacyStateJSON(cardID: UUID())
        )
        let migrated = scheduler.migrate(legacy)
        let reviewed = scheduler.review(state: migrated, quality: 3, now: testNow)

        let data = try JSONEncoder().encode(reviewed)
        let decoded = try JSONDecoder().decode(ReviewState.self, from: data)

        #expect(decoded == reviewed)
        #expect(decoded.stability != nil)
        #expect(decoded.difficulty != nil)
    }

    @Test func reEncodingAnUnreviewedLegacyStateInventsNoFSRSValues() throws {
        let legacy = try JSONDecoder().decode(
            ReviewState.self,
            from: legacyStateJSON(cardID: UUID())
        )

        let data = try JSONEncoder().encode(legacy)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let fields = try #require(json)

        #expect(fields["stability"] == nil)
        #expect(fields["difficulty"] == nil)
        #expect(fields["intervalDays"] as? Int == 18)
        #expect(fields["lapses"] as? Int == 2)
    }

    @Test func fourLapsesFlagTheCardAsALeech() {
        #expect(ReviewState(cardID: UUID(), dueDate: testNow, lapses: 3).isLeech == false)

        let leech = ReviewState(cardID: UUID(), dueDate: testNow, lapses: 4)
        #expect(leech.isLeech)
        #expect(ReviewState.leechThreshold == 4)
    }

    @Test func aFourthLapseIsReachedThroughGrading() {
        var state = ReviewState(
            cardID: UUID(),
            intervalDays: 5,
            repetitions: 2,
            dueDate: testNow,
            lastReviewedAt: testNow.addingTimeInterval(-5 * 86_400),
            lapses: 3,
            stability: 5,
            difficulty: 6
        )
        #expect(state.isLeech == false)

        state = scheduler.review(state: state, quality: 1, now: testNow)

        #expect(state.lapses == 4)
        #expect(state.isLeech)
    }
}
