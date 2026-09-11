import AppKit
import Foundation

/// Coordinates the two "restart & re-grant Accessibility" flows:
///
/// - Settings → Clean stale Accessibility records: after `tccutil reset`
///   wipes the TCC table, the **running** process still holds the grant
///   macOS snapshotted at launch, so a restart is mandatory before the
///   permission can be re-granted.
/// - Updates / reinstall ("Download & Restart"): the swapped-in build
///   carries a fresh ad-hoc signature, so macOS may reset the grant — the
///   relaunched app asks for it again.
///
/// Both flows call `scheduleAccessibilityReGrant()` right before relaunching.
/// The next launch consumes the mark in `resumeIfNeeded()` and, only when
/// the permission is still missing, pops the system authorization dialog.
enum RelaunchFlow {
    /// UserDefaults key carrying the re-grant intent across the process
    /// restart. Lives in the standard suite (keyed by bundle id), so it
    /// survives the updater's bundle swap too.
    private static let pendingAccessibilityReGrantKey = "relaunch.pendingAccessibilityReGrant"

    /// Marks the next launch to re-request the Accessibility permission.
    /// Called right before a reset/update relaunch; consumed once at launch.
    static func scheduleAccessibilityReGrant(defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: pendingAccessibilityReGrantKey)
    }

    /// Returns true (and clears the mark) when a relaunch requested an
    /// Accessibility re-grant. Separated from `resumeIfNeeded()` so tests can
    /// pin the consume-once behavior down with an injected defaults suite.
    static func consumePendingAccessibilityReGrant(defaults: UserDefaults = .standard) -> Bool {
        guard defaults.bool(forKey: pendingAccessibilityReGrantKey) else { return false }
        defaults.removeObject(forKey: pendingAccessibilityReGrantKey)
        return true
    }

    /// Launch hook: when the previous run ended with
    /// `scheduleAccessibilityReGrant()` (reset or update relaunch),
    /// re-requests the Accessibility permission once the saved trust state
    /// for the fresh process has settled.
    @MainActor
    static func resumeIfNeeded() {
        guard consumePendingAccessibilityReGrant() else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            guard !SkyLight.isAccessibilityTrusted else { return }
            SkyLight.promptForAccessibility()
        }
    }

    /// Restarts the app: a detached script waits for this process to exit,
    /// then `open`s the bundle again — the same wait-then-open pattern as the
    /// updater's swap-and-relaunch script, so the relaunch never races the
    /// termination. Terminates the app as part of the restart.
    @MainActor
    static func relaunch() {
        let bundlePath = Bundle.main.bundlePath
        let script = """
            #!/bin/bash
            while pgrep -x "SpaceLabeler" >/dev/null 2>&1; do sleep 0.3; done
            open "\(bundlePath)"
            """
        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("space-labeler-relaunch-\(Int(Date().timeIntervalSince1970 * 1000)).sh")
        do {
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = [scriptURL.path]
            try process.run()
        } catch {
            // Last resort: a detached shell that opens the bundle after a
            // beat. If even that fails, the user relaunches manually.
            let fallback = Process()
            fallback.executableURL = URL(fileURLWithPath: "/bin/sh")
            fallback.arguments = ["-c", "(sleep 1; open \"\(bundlePath)\") &"]
            try? fallback.run()
        }
        NSApp.terminate(nil)
    }
}