import AppKit
import Carbon.HIToolbox
import Combine
import SwiftUI

@MainActor
final class StatusItemController {
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private let monitor: SpaceMonitor
    private let store: SpaceStore
    private let history: SpaceHistory
    private let updater = UpdaterState()
    private var cancellables = Set<AnyCancellable>()

    /// System-wide ^⇧↑ (popover toggle) and ^⇧← (jump back to the
    /// previously-active Space) hotkeys, registered via Carbon. Unlike
    /// NSEvent global monitors, Carbon hotkeys do NOT require the
    /// Accessibility permission, and the system delivers them to us before
    /// any frontmost app sees them.
    private static let eventHandler: EventHandlerUPP = { _, eventRef, _ in
        var id = EventHotKeyID()
        GetEventParameter(
            eventRef,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &id
        )
        guard id.signature == hotKeySignature else { return noErr }
        switch id.id {
        case popoverHotKeyID:
            Task { @MainActor in
                shared?.togglePopover(nil)
            }
        case backHotKeyID:
            Task { @MainActor in
                shared?.goBackToPreviousSpace()
            }
        default:
            break
        }
        return noErr
    }

    private static let hotKeySignature: OSType = 0x5350_4C31  // "SPL1"
    private static let popoverHotKeyID: UInt32 = 1
    private static let backHotKeyID: UInt32 = 2
    @MainActor private static weak var shared: StatusItemController?

    private var hotKeyRefs: [UInt32: EventHotKeyRef] = [:]
    private var eventHandlerRef: EventHandlerRef?

    init(monitor: SpaceMonitor, store: SpaceStore) {
        self.monitor = monitor
        self.store = store
        self.history = SpaceHistory(jump: Self.performJump)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 290, height: 450)
        popover.contentViewController = NSHostingController(
            rootView: EditorPopover(
                monitor: monitor, store: store, updater: updater,
                onJump: { [weak self] in
                    self?.popover.performClose(nil)
                })
        )

        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover(_:))

        // React to Space changes.
        monitor.$currentSpaceID
            .receive(on: RunLoop.main)
            .sink { [weak self] id in
                self?.render(id: id)
            }
            .store(in: &cancellables)

        // Feed the ^⇧← back-to-previous history with every activation.
        monitor.$currentSpaceID
            .receive(on: RunLoop.main)
            .sink { [weak self] id in
                self?.history.recordArrival(id)
            }
            .store(in: &cancellables)

        // React to label edits (rename / recolor). While a name is being
        // edited the menu bar label is frozen: re-rendering on every
        // keystroke makes the status item's width change and jitters the
        // whole menu bar. It refreshes once the edit session ends.
        store.$labels
            .combineLatest(store.$isRenaming)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, isRenaming in
                guard let self, !isRenaming else { return }
                self.render(id: self.monitor.currentSpaceID)
            }
            .store(in: &cancellables)

        installHotKeys()

        // Silently check for a new release (at most once per day); the result
        // shows up in Preferences → Updates.
        updater.autoCheckIfDue()
    }

    deinit {
        for ref in hotKeyRefs.values {
            UnregisterEventHotKey(ref)
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }

    /// Registers the system-wide ^⇧↑ (popover) and ^⇧← (jump back to the
    /// previously-active Space) hotkeys so they work from any app without
    /// the Accessibility permission.
    private func installHotKeys() {
        Self.shared = self

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            Self.eventHandler,
            1,
            &eventType,
            nil,
            &eventHandlerRef
        )
        guard handlerStatus == noErr else {
            NSLog("SpaceLabeler: InstallEventHandler failed: %d", handlerStatus)
            return
        }

        let hotKeys: [(id: UInt32, keycode: UInt32)] = [
            (Self.popoverHotKeyID, UInt32(kVK_UpArrow)),
            (Self.backHotKeyID, UInt32(kVK_LeftArrow)),
        ]
        for hotKey in hotKeys {
            let id = EventHotKeyID(signature: Self.hotKeySignature, id: hotKey.id)
            var ref: EventHotKeyRef?
            let hotKeyStatus = RegisterEventHotKey(
                hotKey.keycode,
                UInt32(controlKey | shiftKey),
                id,
                GetApplicationEventTarget(),
                0,
                &ref
            )
            if hotKeyStatus != noErr {
                NSLog("SpaceLabeler: RegisterEventHotKey %d failed: %d", hotKey.id, hotKeyStatus)
            } else if let ref {
                hotKeyRefs[hotKey.id] = ref
            }
        }
    }

    /// ^⇧← — jump back to the previously-active Space (repeat to walk
    /// further back).
    private func goBackToPreviousSpace() {
        history.goBack()
    }

    /// Performs the back jump. Same requirements as clicking a Space in
    /// the popover: Accessibility permission plus the enabled
    /// "Switch to Desktop N" shortcuts. Failures stay silent (the hotkey
    /// does nothing) except for a missing Accessibility grant, which pops
    /// the system authorization dialog like the popover does.
    private static func performJump(_ id: UInt64) -> Bool {
        switch SkyLight.switchToSpace(id: id) {
        case .success:
            return true
        case .accessibilityDenied:
            SkyLight.promptForAccessibility()
            return false
        case .notFound, .indexTooHigh, .shortcutNotEnabled, .unavailable:
            NSLog("SpaceLabeler: back jump to Space %llu failed", id)
            return false
        }
    }

    private func showPopover() {
        guard let button = statusItem.button, !popover.isShown else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func render(id: UInt64) {
        guard let button = statusItem.button else { return }
        let label = store.label(for: id)
        let color = NSColor(hex: label.colorHex) ?? .labelColor

        let attributed = NSMutableAttributedString()
        attributed.append(
            NSAttributedString(
                string: "● ",
                attributes: [
                    .foregroundColor: color,
                    .font: NSFont.systemFont(ofSize: 13),
                ]
            ))
        attributed.append(
            NSAttributedString(
                string: label.name,
                attributes: [
                    .foregroundColor: NSColor.labelColor,
                    .font: NSFont.systemFont(ofSize: 13, weight: .medium),
                ]
            ))
        button.attributedTitle = attributed
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard statusItem.button != nil else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            showPopover()
        }
    }
}

extension NSColor {
    convenience init?(hex: String) {
        var h = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if h.hasPrefix("#") { h.removeFirst() }
        guard h.count == 6, let v = UInt32(h, radix: 16) else { return nil }
        let r = CGFloat((v >> 16) & 0xFF) / 255.0
        let g = CGFloat((v >> 8) & 0xFF) / 255.0
        let b = CGFloat(v & 0xFF) / 255.0
        self.init(srgbRed: r, green: g, blue: b, alpha: 1)
    }
}
