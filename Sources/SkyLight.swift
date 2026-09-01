import ApplicationServices
import CoreGraphics
import Foundation

/// Private CoreGraphics / SkyLight bindings for reading and switching Spaces.
///
/// macOS provides NSWorkspace.activeSpaceDidChangeNotification publicly, but gives
/// no public API for a stable Space identifier. yabai, Hammerspoon, and TotalSpaces
/// all relied on these undocumented symbols. They have been stable since ~10.11.
///
/// We resolve them at runtime via dlsym on the global symbol scope so the binary
/// does not hard-link to the private framework. If Apple ever removes them,
/// `currentSpaceID()` returns nil and the app degrades gracefully.
enum SkyLight {
    private typealias CGSMainConnectionIDFunc = @convention(c) () -> UInt32
    private typealias CGSGetActiveSpaceFunc = @convention(c) (UInt32) -> UInt64
    private typealias CGSCopyManagedDisplayForSpaceFunc = @convention(c) (UInt32, UInt64) -> Unmanaged<CFString>?
    private typealias CGSCopyManagedDisplaySpacesFunc = @convention(c) (UInt32, CFString) -> Unmanaged<CFArray>?

    private static let globalHandle: UnsafeMutableRawPointer? = dlopen(nil, RTLD_NOW)

    private static let mainConnectionID: CGSMainConnectionIDFunc? = {
        guard let handle = globalHandle,
            let sym = dlsym(handle, "CGSMainConnectionID")
        else { return nil }
        return unsafeBitCast(sym, to: CGSMainConnectionIDFunc.self)
    }()

    private static let getActiveSpace: CGSGetActiveSpaceFunc? = {
        guard let handle = globalHandle,
            let sym = dlsym(handle, "CGSGetActiveSpace")
        else { return nil }
        return unsafeBitCast(sym, to: CGSGetActiveSpaceFunc.self)
    }()

    /// Returns the display UUID ("Main", a UUID string, ...) that owns a Space.
    private static let copyManagedDisplayForSpace: CGSCopyManagedDisplayForSpaceFunc? = {
        guard let handle = globalHandle,
            let sym = dlsym(handle, "CGSCopyManagedDisplayForSpace")
        else { return nil }
        return unsafeBitCast(sym, to: CGSCopyManagedDisplayForSpaceFunc.self)
    }()

    /// Returns per-display dictionaries describing each display's Spaces in
    /// Mission Control order. This replaced the old `CGSCopySpacesForDisplay`
    /// (removed on macOS 26); see `userSpaceIDs(onDisplay:)`.
    private static let copyManagedDisplaySpaces: CGSCopyManagedDisplaySpacesFunc? = {
        guard let handle = globalHandle,
            let sym = dlsym(handle, "CGSCopyManagedDisplaySpaces")
        else { return nil }
        return unsafeBitCast(sym, to: CGSCopyManagedDisplaySpacesFunc.self)
    }()

    /// Whether all symbols needed to enumerate / switch Spaces resolved.
    /// Kept separate from `switchToSpace` results so tests can fail loudly
    /// when Apple breaks the private API on a future macOS.
    static var switchSymbolsAvailable: Bool {
        copyManagedDisplayForSpace != nil && copyManagedDisplaySpaces != nil
    }

    static func currentSpaceID() -> UInt64? {
        guard let cid = mainConnectionID?() else { return nil }
        return getActiveSpace?(cid)
    }

    /// Live Accessibility trust state. Queries TCC on every call, so it
    /// reflects a permission change made in System Settings without restart —
    /// except in the rare case the app must be relaunched to pick it up.
    static var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Triggers the system's Accessibility authorization dialog
    /// (System Settings → Privacy & Security → Accessibility). Call this
    /// when the user attempts a jump while untrusted — macOS pops the
    /// standard prompt that deep-links into the right settings pane.
    static func promptForAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Accessibility record reset

    /// Outcome of `resetAccessibilityRecords()`.
    enum AccessibilityResetResult: Equatable {
        case success
        case cancelled
        case failed(String)
    }

    /// Wipes macOS's stored Accessibility (TCC) records for this app — the
    /// GUI equivalent of the Makefile's
    /// `sudo tccutil reset Accessibility com.jeremywatt.SpaceLabeler`
    /// (the `install` target runs it after every build).
    ///
    /// Every release is ad-hoc signed, so the code signature changes on each
    /// install/update. macOS keeps the old dead TCC entries under the same
    /// bundle id, and they can shadow a fresh grant: the STATUS check stays
    /// stuck on "not granted" even after the user enables the app. Resetting
    /// clears the whole table for this bundle id so the next grant lands
    /// cleanly — this is what fixes a zip install that "can't be used".
    ///
    /// Elevation goes through an in-process AppleScript `do shell script …
    /// with administrator privileges`, which reuses the system's own
    /// authorization dialog for the admin password — the app never handles
    /// the password itself. Blocks on the main thread until the dialog is
    /// dismissed (the security agent runs out-of-process, so the dialog UI
    /// stays responsive).
    @MainActor
    static func resetAccessibilityRecords() -> AccessibilityResetResult {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.jeremywatt.SpaceLabeler"
        let source =
            "do shell script \"/usr/bin/tccutil reset Accessibility \(bundleID)\" with administrator privileges"
        var error: NSDictionary?
        let script = NSAppleScript(source: source)
        _ = script?.executeAndReturnError(&error)
        guard let error else { return .success }
        // AppleScript reports the user cancelling the authorization dialog
        // as error -128 ("User canceled") — that is not a failure.
        if (error[NSAppleScript.errorNumber] as? Int) == -128 {
            return .cancelled
        }
        let message =
            (error[NSAppleScript.errorMessage] as? String)
            ?? (error[NSAppleScript.errorBriefMessage] as? String)
            ?? "Unknown AppleScript error"
        return .failed(message)
    }

    // MARK: - Shortcut enablement detection

    /// A "Switch to Desktop N" shortcut as configured in System Settings.
    /// `keycode`/`flags` are read from the same preferences the settings UI
    /// writes, so custom bindings (e.g. a non-default modifier) are honored.
    struct DesktopShortcut: Equatable {
        let desktop: Int
        let keycode: CGKeyCode
        let flags: CGEventFlags
    }

    /// Symbolic hotkey IDs for "Switch to Desktop 1…9" (118…126 on modern
    /// macOS). Do not use 79…87 — that range covers Mission Control
    /// navigation (e.g. Ctrl+←/→) and would read the wrong entries.
    private static let desktopShortcutIDs: [String: Int] = [
        "118": 1, "119": 2, "120": 3, "121": 4, "122": 5,
        "123": 6, "124": 7, "125": 8, "126": 9,
    ]

    /// ANSI hardware keycodes for Ctrl+1…9, used only when the symbolic-hotkey
    /// preferences cannot be read at all. (Note: '5' is keycode 23, '6' is 22.)
    static let defaultDesktopKeycodes: [Int: CGKeyCode] = [
        1: 18, 2: 19, 3: 20, 4: 21, 5: 23, 6: 22, 7: 26, 8: 28, 9: 25,
    ]

    /// Desktop numbers (1-based) whose "Switch to Desktop N" shortcut is
    /// enabled, paired with the exact key combination System Settings bound
    /// to it. Read from the same preferences that back Keyboard →
    /// Keyboard Shortcuts → Mission Control. Empty when unreadable.
    static func desktopShortcuts() -> [Int: DesktopShortcut] {
        guard let prefs = UserDefaults(suiteName: "com.apple.symbolichotkeys"),
            let all = prefs.dictionary(forKey: "AppleSymbolicHotKeys")
        else { return [:] }
        var result: [Int: DesktopShortcut] = [:]
        for (key, desktop) in desktopShortcutIDs {
            guard let entry = all[key] as? [String: Any],
                let flag = entry["enabled"] as? Bool,
                flag,
                let value = entry["value"] as? [String: Any],
                let params = value["parameters"] as? [Any],
                params.count >= 3,
                // parameters = (independent-of-keyboard-type flag, keycode, modifier flags)
                let keycodeNum = (params[1] as? NSNumber)?.intValue
            else { continue }
            let flagsNum = (params[2] as? NSNumber)?.intValue ?? 0
            result[desktop] = DesktopShortcut(
                desktop: desktop,
                keycode: CGKeyCode(keycodeNum),
                flags: CGEventFlags(rawValue: UInt64(flagsNum))
            )
        }
        return result
    }

    /// Numbers (1-based) whose "Switch to Desktop N" shortcut is enabled.
    /// Empty when the preferences are unreadable.
    static func enabledDesktopShortcuts() -> Set<Int> {
        Set(desktopShortcuts().keys)
    }

    // MARK: - Space switching

    enum SwitchResult: Equatable {
        case success
        case notFound
        case indexTooHigh(limit: Int)
        case shortcutNotEnabled(desktop: Int)
        case accessibilityDenied
        case unavailable
    }

    /// The display UUID owning the given Space, or nil if the Space is not
    /// managed by any display (or the private symbol is unavailable).
    static func displayUUID(for spaceID: UInt64) -> String? {
        guard let cid = mainConnectionID?(),
            let fn = copyManagedDisplayForSpace,
            let raw = fn(cid, spaceID)
        else { return nil }
        return raw.takeRetainedValue() as String
    }

    /// Ordered user Space IDs on a display, filtered to type `.user` (desktop).
    /// This matches the numbering of the system "Switch to Desktop N" shortcuts.
    static func userSpaceIDs(onDisplay uuid: String) -> [UInt64] {
        guard let cid = mainConnectionID?(),
            let copy = copyManagedDisplaySpaces,
            let raw = copy(cid, uuid as CFString)
        else { return [] }
        let displays = raw.takeRetainedValue()
        for i in 0..<CFArrayGetCount(displays) {
            guard let ptr = CFArrayGetValueAtIndex(displays, i) else { continue }
            let dict = unsafeBitCast(ptr, to: CFDictionary.self)
            // Only look at the dict that describes the requested display.
            guard cfStringValue(dict, key: "Display Identifier") == uuid else { continue }
            guard let spaces = cfArrayValue(dict, key: "Spaces") else { continue }
            var result: [UInt64] = []
            for j in 0..<CFArrayGetCount(spaces) {
                guard let sp = CFArrayGetValueAtIndex(spaces, j) else { continue }
                let spaceDict = unsafeBitCast(sp, to: CFDictionary.self)
                // Only plain desktops; skip fullscreen app Spaces so the index
                // lines up with the "Desktop N" numbering.
                guard cfInt64Value(spaceDict, key: "type") == 0 else { continue }
                guard let id64 = cfInt64Value(spaceDict, key: "id64") else { continue }
                result.append(UInt64(bitPattern: id64))
            }
            return result
        }
        return []
    }

    /// Switches to a Space by synthesizing the system "Switch to Desktop N"
    /// shortcut (Ctrl+1...9). macOS performs the actual switch with its normal
    /// animation, so this is far more robust than any private "move to space"
    /// call — those either don't trigger a real switch or are long gone.
    ///
    /// The key combination comes straight from the symbolic-hotkey
    /// preferences: System Settings stores the exact keycode + modifiers for
    /// each enabled "Switch to Desktop N", so custom bindings work too. If
    /// the target desktop's shortcut is not enabled there, we report
    /// `.shortcutNotEnabled` instead of sending a dead keystroke. Only when
    /// the preferences can't be read at all does the legacy Ctrl+1...9
    /// assumption apply.
    ///
    /// Requirements:
    /// - The user must enable the shortcuts in System Settings →
    ///   Keyboard → Keyboard Shortcuts → Mission Control.
    /// - The app must be granted Accessibility permission to post key events.
    ///
    /// Note: only works when the target Space is on the same display as the
    /// currently active one (Ctrl+N always acts on the current display).
    /// 1-based position of a Space within its **own** display's user-space list.
    /// This is the number the system "Switch to Desktop N" shortcut targets
    /// on that specific display (Ctrl+N is always per-display).
    /// Returns nil for orphaned Spaces or when the private API is unavailable.
    static func desktopNumber(for spaceID: UInt64) -> Int? {
        guard switchSymbolsAvailable,
            let uuid = displayUUID(for: spaceID)
        else { return nil }
        let spaces = userSpaceIDs(onDisplay: uuid)
        guard let index = spaces.firstIndex(of: spaceID) else { return nil }
        return index + 1
    }

    /// Global 1-based desktop number across **all** displays concatenated in
    /// a stable order (physical display IDs ascending, then "Main").
    /// Use this for UI labels so "桌面 1…N" are unique even on multi-monitor
    /// setups — unlike `desktopNumber(for:)` which resets to 1 per display.
    static func globalDesktopNumber(for spaceID: UInt64) -> Int? {
        globalDesktopNumbers()?[spaceID]
    }

    /// Maps every user Space ID on every managed display to its global
    /// 1-based desktop number, using the same display order as
    /// `globalDesktopNumber(for:)`. Returns nil when the private API is
    /// unavailable, so callers can distinguish "no data" from "no Spaces".
    static func globalDesktopNumbers() -> [UInt64: Int]? {
        guard switchSymbolsAvailable else { return nil }
        // Build a stable ordered list of all managed display UUIDs.
        var displayOrder: [String] = []
        // Physical displays first (stable by CGDisplayID).
        let seen = NSMutableSet()
        var maxDisplays: UInt32 = 0
        _ = CGGetOnlineDisplayList(0, nil, &maxDisplays)
        var ids = [UInt32](repeating: 0, count: Int(maxDisplays))
        _ = CGGetOnlineDisplayList(maxDisplays, &ids, &maxDisplays)
        for displayID in ids {
            guard let uuidRaw = CGDisplayCreateUUIDFromDisplayID(displayID),
                  let uuidStr = CFUUIDCreateString(kCFAllocatorDefault, uuidRaw.takeRetainedValue()) as String?,
                  !seen.contains(uuidStr)
            else { continue }
            seen.add(uuidStr)
            displayOrder.append(uuidStr)
        }
        // "Main" (logical main-display concept) last if not already present.
        if !seen.contains("Main") {
            displayOrder.append("Main")
        }
        // Concatenate user-space IDs in display order.
        var result: [UInt64: Int] = [:]
        var offset = 0
        for uuid in displayOrder {
            let spaces = userSpaceIDs(onDisplay: uuid)
            for (index, spaceID) in spaces.enumerated() {
                result[spaceID] = offset + index + 1
            }
            offset += spaces.count
        }
        return result
    }

    static func switchToSpace(id spaceID: UInt64) -> SwitchResult {
        guard switchSymbolsAvailable else { return .unavailable }
        guard let n = desktopNumber(for: spaceID) else { return .notFound }
        guard n <= 9 else { return .indexTooHigh(limit: 9) }
        let shortcuts = desktopShortcuts()
        let combo: (keycode: CGKeyCode, flags: CGEventFlags)
        if let shortcut = shortcuts[n] {
            combo = (shortcut.keycode, shortcut.flags)
        } else if shortcuts.isEmpty, let keycode = defaultDesktopKeycodes[n] {
            // Preferences unreadable: fall back to the default Ctrl+N binding.
            combo = (keycode, .maskControl)
        } else {
            // Preferences readable, but the target desktop's shortcut is off.
            return .shortcutNotEnabled(desktop: n)
        }
        guard AXIsProcessTrusted() else { return .accessibilityDenied }
        return postKey(combo.keycode, flags: combo.flags) ? .success : .unavailable
    }

    /// Posts a single key press/release to the system event tap.
    private static func postKey(_ keyCode: CGKeyCode, flags: CGEventFlags) -> Bool {
        guard let source = CGEventSource(stateID: .hidSystemState),
            let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
            let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        else { return false }
        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }

    // MARK: - CFDictionary helpers

    private static func rawValue(_ dict: CFDictionary, key: String) -> UnsafeRawPointer? {
        CFDictionaryGetValue(dict, unsafeBitCast(key as CFString, to: UnsafeRawPointer.self))
    }

    private static func cfStringValue(_ dict: CFDictionary, key: String) -> String? {
        guard let raw = rawValue(dict, key: key),
            CFGetTypeID(unsafeBitCast(raw, to: CFTypeRef.self)) == CFStringGetTypeID()
        else { return nil }
        return unsafeBitCast(raw, to: CFString.self) as String
    }

    private static func cfArrayValue(_ dict: CFDictionary, key: String) -> CFArray? {
        guard let raw = rawValue(dict, key: key),
            CFGetTypeID(unsafeBitCast(raw, to: CFTypeRef.self)) == CFArrayGetTypeID()
        else { return nil }
        return unsafeBitCast(raw, to: CFArray.self)
    }

    private static func cfInt64Value(_ dict: CFDictionary, key: String) -> Int64? {
        guard let raw = rawValue(dict, key: key),
            CFGetTypeID(unsafeBitCast(raw, to: CFTypeRef.self)) == CFNumberGetTypeID()
        else { return nil }
        let num = unsafeBitCast(raw, to: CFNumber.self)
        var value: Int64 = 0
        guard CFNumberGetValue(num, .sInt64Type, &value) else { return nil }
        return value
    }
}
