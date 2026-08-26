import XCTest

@testable import SpaceLabeler

final class SpaceStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "SpaceLabelerTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func test_labelForUnknownID_autoAssignsAndPersists() {
        let store = SpaceStore(defaults: defaults)
        let label = store.label(for: 42)

        XCTAssertEqual(label.name, "Space 1")
        XCTAssertFalse(label.colorHex.isEmpty)
        XCTAssertTrue(label.colorHex.hasPrefix("#"))
        XCTAssertNotNil(defaults.data(forKey: "SpaceLabels.v1"))
    }

    func test_update_persistsAcrossInstances() {
        let store1 = SpaceStore(defaults: defaults)
        _ = store1.label(for: 99)
        store1.update(99, SpaceLabel(name: "Code", colorHex: "#4ECDC4"))

        let store2 = SpaceStore(defaults: defaults)
        let loaded = store2.labels[99]

        XCTAssertEqual(loaded?.name, "Code")
        XCTAssertEqual(loaded?.colorHex, "#4ECDC4")
    }

    func test_remove_deletesLabelAndPersists() {
        let store1 = SpaceStore(defaults: defaults)
        store1.update(99, SpaceLabel(name: "Code", colorHex: "#4ECDC4"))
        store1.update(100, SpaceLabel(name: "Docs", colorHex: "#FFE66D"))

        store1.remove(99)

        XCTAssertNil(store1.labels[99])
        XCTAssertEqual(store1.labels[100]?.name, "Docs")

        let store2 = SpaceStore(defaults: defaults)
        XCTAssertNil(store2.labels[99])
        XCTAssertEqual(store2.labels[100]?.name, "Docs")
    }

    func test_autoAssign_rotatesPaletteDeterministically() {
        let store = SpaceStore(defaults: defaults)

        // autoAssign computes n = labels.count + 1 then picks colors[n % count].
        // Six successive assignments from an empty store cycle through the
        // palette starting at index 1. Expected values come from the shared
        // palette itself so this test asserts the rotation behavior, not a
        // snapshot of specific hex values.
        let expected = (1...6).map { SpacePalette.colors[$0 % SpacePalette.colors.count] }

        for (i, expectedColor) in expected.enumerated() {
            let label = store.label(for: UInt64(100 + i))
            XCTAssertEqual(label.colorHex, expectedColor, "iteration \(i)")
        }
    }

    func test_load_handlesCorruptedDefaults() {
        defaults.set(Data([0xFF, 0x00, 0xFF, 0x00]), forKey: "SpaceLabels.v1")

        let store = SpaceStore(defaults: defaults)

        XCTAssertTrue(store.labels.isEmpty, "Store should come up empty when defaults are corrupted, not crash")
    }

    func test_prune_removesOrphanedLabelsAndPersists() {
        let store1 = SpaceStore(defaults: defaults)
        store1.update(10, SpaceLabel(name: "Work", colorHex: "#111111"))
        store1.update(20, SpaceLabel(name: "Stale", colorHex: "#222222"))
        store1.update(30, SpaceLabel(name: "Play", colorHex: "#333333"))

        store1.prune(keeping: [10, 30])

        XCTAssertNil(store1.labels[20], "Orphaned label should be removed")
        XCTAssertEqual(store1.labels[10]?.name, "Work")
        XCTAssertEqual(store1.labels[30]?.name, "Play")

        let store2 = SpaceStore(defaults: defaults)
        XCTAssertNil(store2.labels[20], "Prune must persist")
        XCTAssertEqual(store2.labels.count, 2)
    }

    func test_prune_withAllValidIDs_keepsEverything() {
        let store = SpaceStore(defaults: defaults)
        store.update(10, SpaceLabel(name: "A", colorHex: "#111111"))
        store.update(20, SpaceLabel(name: "B", colorHex: "#222222"))

        store.prune(keeping: [10, 20, 999])

        XCTAssertEqual(store.labels.count, 2)
        XCTAssertNotNil(store.labels[10])
        XCTAssertNotNil(store.labels[20])
    }

    func test_prune_emptyStore_isNoOp() {
        let store = SpaceStore(defaults: defaults)
        store.prune(keeping: [1, 2, 3])
        XCTAssertTrue(store.labels.isEmpty)
    }
}
