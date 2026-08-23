import XCTest

@testable import SpaceLabeler

final class SkyLightSmokeTests: XCTestCase {

    /// If Apple removes or renames CGSMainConnectionID / CGSGetActiveSpace,
    /// dlsym resolution fails and currentSpaceID() returns nil. This test
    /// fails loudly on the macos-latest CI matrix row the first time the
    /// Xcode/runner image is rolled forward to a macOS that broke the private
    /// API. That early warning is the entire reason this test exists.
    func test_currentSpaceID_returnsNonNil() {
        let id = SkyLight.currentSpaceID()
        XCTAssertNotNil(
            id,
            "SkyLight private API symbol resolution failed — Apple may have changed CGSGetActiveSpace"
        )
    }

    /// The Space-enumeration symbols (CGSCopySpacesForDisplay,
    /// CGSCopyManagedDisplayForSpace, CGSSpaceGetType) power the "click a
    /// Space to jump to it" feature. Same failure-loudly-in-CI intent as the
    /// read-only symbols above.
    func test_switchSymbols_resolve() {
        XCTAssertTrue(
            SkyLight.switchSymbolsAvailable,
            "SkyLight switch symbols failed to resolve — Apple may have changed CGSCopySpacesForDisplay"
        )
    }

    /// The fallback hardware keycodes (used only when the symbolic-hotkey
    /// preferences are unreadable) must mirror the system's default Ctrl+1…9
    /// binding. A past bug swapped desktop 5/6 ('5' is keycode 23, '6' is 22),
    /// so lock the table down against regressions.
    func test_defaultDesktopKeycodes_matchSystemDefaults() {
        let expected: [Int: UInt16] = [
            1: 18, 2: 19, 3: 20, 4: 21, 5: 23, 6: 22, 7: 26, 8: 28, 9: 25,
        ]
        XCTAssertEqual(SkyLight.defaultDesktopKeycodes.mapValues { UInt16($0) }, expected)
    }

    /// The "Switch to Desktop N" symbolic hotkeys live at IDs 118…126 on
    /// modern macOS; 79…87 belong to Mission Control navigation (Ctrl+←/→)
    /// and must never be read as desktop shortcuts. When the preferences are
    /// readable, the returned mapping must only contain desktops 1…9 with a
    /// plausible keycode (18 = digit '1' … 29 = digit '0').
    func test_desktopShortcuts_readsModernSymbolicHotkeyIDs() {
        let shortcuts = SkyLight.desktopShortcuts()
        guard !shortcuts.isEmpty else {
            return // preferences unreadable on this machine — nothing to assert
        }
        XCTAssertTrue(shortcuts.keys.allSatisfy { (1...9).contains($0) })
        XCTAssertTrue(shortcuts.values.allSatisfy { (18...29).contains(Int($0.keycode)) })
    }
}
