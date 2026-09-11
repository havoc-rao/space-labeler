import XCTest

@testable import SpaceLabeler

final class RelaunchFlowTests: XCTestCase {

    /// The pending re-grant mark (set right before a reset/update relaunch)
    /// must be consumable exactly once at the next launch, and must never
    /// survive as a stale flag into a second launch.
    func test_pendingAccessibilityReGrant_isConsumedOnce() {
        let suiteName = "RelaunchFlowTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertFalse(
            RelaunchFlow.consumePendingAccessibilityReGrant(defaults: defaults),
            "no pending re-grant before the reset/update flow schedules one"
        )

        RelaunchFlow.scheduleAccessibilityReGrant(defaults: defaults)
        XCTAssertTrue(
            RelaunchFlow.consumePendingAccessibilityReGrant(defaults: defaults),
            "the relaunch must carry the re-grant intent to the next launch"
        )
        XCTAssertFalse(
            RelaunchFlow.consumePendingAccessibilityReGrant(defaults: defaults),
            "the mark must be cleared after one consume so a later manual launch is not prompted"
        )
    }
}