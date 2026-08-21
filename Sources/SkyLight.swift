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

    // MARK: - Shortcut enablement detection

    /// Numbers (1-based) whose "Switch to Desktop N" shortcut is enabled,
    /// read from the same preferences that back System Settings →
    /// Keyboard → Keyboard Shortcuts → Mission Control. Empty when
    /// unreadable. Symbolic hotkey IDs: 79=Desktop 1 … 87=Desktop 9.
    static func enabledDesktopShortcuts() -> Set<Int> {
        guard let prefs = UserDefaults(suiteName: "com.apple.symbolichotkeys"),
            let all = prefs.dictionary(forKey: "AppleSymbolicHotKeys")
        else { return [] }
        let mapping: [String: Int] = [
            "79": 1, "80": 2, "81": 3, "82": 4, "83": 5,
            "84": 6, "85": 7, "86": 8, "87": 9,
        ]
        var result = Set<Int>()
        for (key, desktop) in mapping {
            guard let entry = all[key] as? [String: Any],
                let flag = entry["enabled"] as? Bool,
                flag
            else { continue }
            result.insert(desktop)
        }
        return result
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
    /// The enabled "Switch to Desktop N" set is read from the system shortcut
    /// preferences: if the target desktop's shortcut is not enabled there,
    /// we report `.shortcutNotEnabled` instead of sending a dead keystroke.
    /// If the preferences can't be read, the legacy 1...9 assumption applies.
    ///
    /// Requirements:
    /// - The user must enable the shortcuts in System Settings →
    ///   Keyboard → Keyboard Shortcuts → Mission Control.
    /// - The app must be granted Accessibility permission to post key events.
    ///
    /// Note: only works when the target Space is on the same display as the
    /// currently active one (Ctrl+N always acts on the current display).
    static func switchToSpace(id spaceID: UInt64) -> SwitchResult {
        guard switchSymbolsAvailable else { return .unavailable }
        guard let uuid = displayUUID(for: spaceID) else { return .notFound }
        let spaces = userSpaceIDs(onDisplay: uuid)
        guard let index = spaces.firstIndex(of: spaceID) else { return .notFound }
        let n = index + 1
        guard n <= 9 else { return .indexTooHigh(limit: 9) }
        let enabled = enabledDesktopShortcuts()
        // If the preferences are readable, require the exact shortcut.
        if !enabled.isEmpty, !enabled.contains(n) {
            return .shortcutNotEnabled(desktop: n)
        }
        guard AXIsProcessTrusted() else { return .accessibilityDenied }
        return postKey(CGKeyCode(17 + n), flags: .maskControl) ? .success : .unavailable
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
