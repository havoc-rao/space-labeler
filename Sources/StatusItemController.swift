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
    private var cancellables = Set<AnyCancellable>()

    /// System-wide ^⇧↑ hotkey, registered via Carbon. Unlike NSEvent global
    /// monitors, Carbon hotkeys do NOT require the Accessibility permission,
    /// and the system delivers them to us before any frontmost app sees them.
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
        guard id.signature == hotKeySignature, id.id == hotKeyID else { return noErr }
        Task { @MainActor in
            shared?.togglePopover(nil)
        }
        return noErr
    }

    private static let hotKeySignature: OSType = 0x5350_4C31  // "SPL1"
    private static let hotKeyID: UInt32 = 1
    @MainActor private static weak var shared: StatusItemController?

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    init(monitor: SpaceMonitor, store: SpaceStore) {
        self.monitor = monitor
        self.store = store

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 290, height: 430)
        popover.contentViewController = NSHostingController(
            rootView: EditorPopover(monitor: monitor, store: store, onJump: { [weak self] in
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
    }

    deinit {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }

    /// Registers the system-wide ^⇧↑ hotkey so the popover can be toggled from
    /// any app without Accessibility permission.
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

        let id = EventHotKeyID(signature: Self.hotKeySignature, id: Self.hotKeyID)
        let hotKeyStatus = RegisterEventHotKey(
            UInt32(kVK_UpArrow),
            UInt32(controlKey | shiftKey),
            id,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        if hotKeyStatus != noErr {
            NSLog("SpaceLabeler: RegisterEventHotKey failed: %d", hotKeyStatus)
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
