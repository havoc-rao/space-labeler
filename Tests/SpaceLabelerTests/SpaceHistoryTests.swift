import XCTest

@testable import SpaceLabeler

/// Covers the ^⇧← Space-history model in `SpaceHistory`: back bookkeeping,
/// walk-back stability across overlapping in-flight jumps, failure
/// handling and input hygiene. There is deliberately no forward/redo
/// behaviour — desktops never move, so "previous Space" is a single,
/// deterministic direction.
final class SpaceHistoryTests: XCTestCase {

    /// Builds a history whose jump closure records every attempted jump and
    /// fails for the given rejected targets (default: all succeed).
    /// Returns (history, recorded jumps).
    private func makeHistory(
        maxBackEntries: Int = 32,
        rejecting rejected: Set<UInt64> = []
    ) -> (SpaceHistory, () -> [UInt64]) {
        var jumped: [UInt64] = []
        let history = SpaceHistory(maxBackEntries: maxBackEntries) { id in
            jumped.append(id)
            return !rejected.contains(id)
        }
        return (history, { jumped })
    }

    func test_firstArrival_seedsHistoryWithoutBackEntry() {
        let (history, _) = makeHistory()
        history.recordArrival(1)
        XCTAssertEqual(history.currentSpaceID, 1)
        XCTAssertTrue(history.back.isEmpty)
        XCTAssertFalse(history.goBack(), "nothing to go back to after the first arrival")
    }

    func test_back_returnsToPreviouslyActiveSpace() {
        let (history, jumped) = makeHistory()
        history.recordArrival(1)
        history.recordArrival(2)
        history.recordArrival(3)

        XCTAssertTrue(history.goBack())
        XCTAssertEqual(jumped().last, 2, "should jump to the Space active right before")
        XCTAssertEqual(history.back, [1])

        history.recordArrival(2)

        XCTAssertTrue(history.goBack())
        XCTAssertEqual(jumped().last, 1)
        XCTAssertTrue(history.back.isEmpty)

        history.recordArrival(1)

        XCTAssertFalse(history.goBack(), "history exhausted after walking all the way back")
    }

    func test_back_stepsStayStableWhileJumpInFlight() {
        // Two ^⇧← presses inside one switch animation: the intermediate
        // arrival must be recognised as our own switch, so the Space we
        // are walking through is not re-recorded and the steps stay stable.
        let (history, jumped) = makeHistory()
        for id in UInt64(1)...4 { history.recordArrival(id) }
        XCTAssertEqual(history.back, [1, 2, 3])

        XCTAssertTrue(history.goBack())  // → 3
        XCTAssertTrue(history.goBack())  // → 2, before 3 even lands
        XCTAssertEqual(history.back, [1])

        history.recordArrival(3)
        history.recordArrival(2)
        XCTAssertEqual(history.back, [1], "our own arrivals must not re-record")
        XCTAssertEqual(history.currentSpaceID, 2)

        XCTAssertTrue(history.goBack())
        XCTAssertEqual(jumped().last, 1)
    }

    func test_failedJump_leavesHistoryUntouched() {
        // Second Space can never be jumped to (shortcut disabled, ...).
        let (history, jumped) = makeHistory(rejecting: [2])
        history.recordArrival(1)
        history.recordArrival(2)
        history.recordArrival(3)

        XCTAssertFalse(history.goBack())
        XCTAssertEqual(jumped().last, 2, "the attempt was made")
        XCTAssertEqual(history.back, [1, 2], "no pop on failure")
        XCTAssertEqual(history.currentSpaceID, 3, "current Space unchanged")
    }

    func test_duplicateArrival_isIgnored() {
        let (history, _) = makeHistory()
        history.recordArrival(1)
        history.recordArrival(2)
        history.recordArrival(2)  // re-notified about the same Space
        XCTAssertEqual(history.back, [1], "duplicate must not re-record")
        history.recordArrival(3)
        XCTAssertEqual(history.back, [1, 2])
    }

    func test_zeroID_isIgnored() {
        let (history, _) = makeHistory()
        history.recordArrival(0)  // private API unavailable
        XCTAssertNil(history.currentSpaceID)
        XCTAssertFalse(history.goBack())

        history.recordArrival(7)
        XCTAssertEqual(history.currentSpaceID, 7)
        XCTAssertTrue(history.back.isEmpty, "0 must not appear in the back history")
    }

    func test_backHistory_isTrimmed() {
        let (history, _) = makeHistory(maxBackEntries: 3)
        for id in UInt64(1)...5 {
            history.recordArrival(id)
        }
        XCTAssertEqual(history.back, [2, 3, 4], "only the newest 3 entries survive")
    }
}
