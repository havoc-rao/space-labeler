import XCTest

@testable import SpaceLabeler

final class SpaceFilterTests: XCTestCase {
    func test_blankQuery_matchesEverything() {
        XCTAssertTrue(SpaceFilter.matches(name: "Work", desktop: 1, query: ""))
        XCTAssertTrue(SpaceFilter.matches(name: "Work", desktop: 1, query: "   "))
        XCTAssertTrue(SpaceFilter.matches(name: "", desktop: 0, query: ""))
    }

    func test_matchesNameCaseInsensitively() {
        XCTAssertTrue(SpaceFilter.matches(name: "Design", desktop: 2, query: "design"))
        XCTAssertTrue(SpaceFilter.matches(name: "Design", desktop: 2, query: "sig"))
        XCTAssertTrue(SpaceFilter.matches(name: "聊天", desktop: 2, query: "天"))
        XCTAssertFalse(SpaceFilter.matches(name: "Design", desktop: 2, query: "code"))
    }

    func test_matchesDesktopNumber() {
        XCTAssertTrue(SpaceFilter.matches(name: "Work", desktop: 3, query: "3"))
        XCTAssertTrue(SpaceFilter.matches(name: "Work", desktop: 13, query: "3"))
        XCTAssertFalse(SpaceFilter.matches(name: "Work", desktop: 3, query: "4"))
    }

    func test_desktopZero_neverMatchesItsNumberText() {
        // When the numbering API is unavailable the desktop is 0 and no
        // badge is shown — typing "0" must not list every unnumbered Space.
        XCTAssertFalse(SpaceFilter.matches(name: "Work", desktop: 0, query: "0"))
        XCTAssertTrue(SpaceFilter.matches(name: "0day", desktop: 0, query: "0"))
    }

    func test_queryTrimsSurroundingWhitespace() {
        XCTAssertTrue(SpaceFilter.matches(name: "Work", desktop: 1, query: "  work  "))
        XCTAssertFalse(SpaceFilter.matches(name: "Work", desktop: 1, query: " work code "))
    }
}
