import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var monitor: SpaceMonitor!
    private var store: SpaceStore!
    private var statusController: StatusItemController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        monitor = SpaceMonitor()
        store = SpaceStore()
        statusController = StatusItemController(monitor: monitor, store: store)
        // If the previous run ended in a reset/update relaunch, re-request
        // the Accessibility permission (the grant may not survive the new
        // launch, especially after a record reset or a reinstall).
        RelaunchFlow.resumeIfNeeded()
    }
}
