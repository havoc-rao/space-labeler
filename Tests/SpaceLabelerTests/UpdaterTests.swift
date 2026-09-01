import XCTest

@testable import SpaceLabeler

final class UpdaterTests: XCTestCase {

    func test_parsesCleanVersions() {
        XCTAssertEqual(AppVersion(raw: "0.1.0")?.description, "0.1.0")
        XCTAssertEqual(AppVersion(raw: "v1.2.3")?.description, "1.2.3")
        XCTAssertEqual(AppVersion(raw: "V10.20.30")?.description, "10.20.30")
    }

    func test_rejectsMalformedVersions() {
        XCTAssertNil(AppVersion(raw: ""))
        XCTAssertNil(AppVersion(raw: "1.2"), "two components are not a valid release version")
        XCTAssertNil(AppVersion(raw: "1.2.3.4"), "four components are not a valid release version")
        XCTAssertNil(AppVersion(raw: "1.2.x"))
        XCTAssertNil(AppVersion(raw: "-1.0.0"))
        XCTAssertNil(AppVersion(raw: "v0.2.0-beta.1"), "prerelease tags must not parse")
    }

    func test_ordering() {
        XCTAssertLessThan(AppVersion(raw: "0.1.0")!, AppVersion(raw: "0.2.0")!)
        XCTAssertLessThan(AppVersion(raw: "0.9.9")!, AppVersion(raw: "1.0.0")!)
        XCTAssertEqual(AppVersion(raw: "1.0.0")!, AppVersion(raw: "1.0.0")!)
        XCTAssertGreaterThan(AppVersion(raw: "1.10.0")!, AppVersion(raw: "1.9.9")!)
    }

    func test_updateDetection() {
        let current = AppVersion(raw: "0.1.0")!
        XCTAssertTrue(AppVersion(raw: "0.2.0")! > current, "a higher version is an update")
        XCTAssertFalse(AppVersion(raw: "0.1.0")! > current, "the same version is not an update")
        XCTAssertFalse(AppVersion(raw: "0.0.9")! > current, "a lower version is not an update")
    }

    /// The SHA-256 hex format the updater uses to verify downloaded zips —
    /// lower-case hex, matching what the release workflow writes to latest.json.
    func test_sha256Digest_isLowercaseHex() throws {
        let fm = FileManager.default
        let url = fm.temporaryDirectory.appendingPathComponent("sha256-\(UUID().uuidString).bin")
        try Data("hello".utf8).write(to: url)
        defer { try? fm.removeItem(at: url) }

        let digest = try UpdaterState.sha256(of: url)
        XCTAssertEqual(
            digest,
            "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
        )
        XCTAssertEqual(digest, digest.lowercased(), "digest must be lower-case hex")
    }
}
