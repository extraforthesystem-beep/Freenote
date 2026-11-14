import SwiftUI
import XCTest
@testable import NoteApp

@MainActor
final class AppMotionTests: XCTestCase {
    private let movingTokens: [Animation] = [AppMotion.quick, AppMotion.standard, AppMotion.emphasized]

    private let allTokens: [Animation] = [
        AppMotion.quick, AppMotion.standard, AppMotion.emphasized, AppMotion.fade,
    ]

    func testMovementIsRemovedUnderReduceMotion() {
        for token in movingTokens {
            XCTAssertNil(AppMotion.resolved(token, reduceMotion: true))
        }
    }

    func testFadeSurvivesReduceMotion() {
        XCTAssertEqual(AppMotion.resolved(AppMotion.fade, reduceMotion: true), AppMotion.fade)
    }

    func testTokensAreUnchangedWithoutReduceMotion() {
        for token in allTokens {
            XCTAssertEqual(AppMotion.resolved(token, reduceMotion: false), token)
        }
    }

    func testSpacingIsStrictlyIncreasingAndEven() {
        let scale = [
            AppSpacing.xxs, AppSpacing.xs, AppSpacing.s, AppSpacing.m,
            AppSpacing.l, AppSpacing.xl, AppSpacing.xxl, AppSpacing.xxxl,
        ]

        for (smaller, larger) in zip(scale, scale.dropFirst()) {
            XCTAssertLessThan(smaller, larger)
        }

        for value in scale {
            XCTAssertEqual(value.truncatingRemainder(dividingBy: 2), 0)
        }
    }

    func testRadiusIsStrictlyIncreasing() {
        let scale = [
            AppRadius.xs, AppRadius.s, AppRadius.m,
            AppRadius.l, AppRadius.xl, AppRadius.xxl,
        ]

        for (smaller, larger) in zip(scale, scale.dropFirst()) {
            XCTAssertLessThan(smaller, larger)
        }
    }
}
