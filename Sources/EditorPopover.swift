import AppKit
import SwiftUI

struct EditorPopover: View {
    @ObservedObject var monitor: SpaceMonitor
    @ObservedObject var store: SpaceStore

    /// Called after a successful jump so the host can close the popover.
    var onJump: (() -> Void)?

    @State private var nameBuffer: String = ""
    @State private var bufferedID: UInt64 = 0
    @State private var jumpError: String?
    @State private var showSettings = false
    /// Space currently selected via the ↑/↓ keys.
    @State private var selectedID: UInt64?
    @State private var keyMonitor: Any?
    /// Whether the name field is focused (⌘R toggles it on).
    @FocusState private var nameFocused: Bool
    @State private var keyObserver: NSObjectProtocol?

    private let palette = ["#FF6B6B", "#4ECDC4", "#FFE66D", "#95E1D3", "#C7B8EA", "#FFA07A"]

    private var sortedIDs: [UInt64] { store.labels.keys.sorted() }

    var body: some View {
        Group {
            if showSettings {
                SettingsView(onDone: { showSettings = false })
            } else {
                mainContent
            }
        }
        .frame(width: 290)
        .onAppear {
            syncBuffer()
            selectedID = monitor.currentSpaceID
            installKeyMonitor()
            installKeyObserver()
            focusOnList()
        }
        .onDisappear {
            removeKeyMonitor()
            removeKeyObserver()
        }
        .onChange(of: monitor.currentSpaceID) { _ in syncBuffer() }
    }

    private var mainContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel(L10n.t("section.current"))
            currentCard

            sectionLabel(L10n.t("section.all"))
            spaceList

            if let jumpError {
                Text(jumpError)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            HStack {
                Button(L10n.t("button.preferences")) { showSettings = true }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                Button(L10n.t("button.quit")) { NSApplication.shared.terminate(nil) }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(13)
    }

    private func syncBuffer() {
        bufferedID = monitor.currentSpaceID
        nameBuffer = store.label(for: monitor.currentSpaceID).name
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(.secondary)
    }

    private var currentCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField(L10n.t("field.spaceName"), text: $nameBuffer)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 13))
                .focused($nameFocused)
                .onChange(of: nameBuffer) { newValue in
                    var l = store.label(for: bufferedID)
                    l.name = newValue
                    store.update(bufferedID, l)
                }

            HStack(spacing: 7) {
                ForEach(palette, id: \.self) { hex in
                    swatch(hex: hex)
                }
            }
        }
        .padding(11)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.055))
        )
    }

    private func swatch(hex: String) -> some View {
        let current = store.label(for: bufferedID)
        let isSelected = current.colorHex == hex
        return Circle()
            .fill(Color(hex: hex) ?? .white)
            .frame(width: 24, height: 24)
            .overlay(
                Circle().stroke(Color.white, lineWidth: isSelected ? 2 : 0)
            )
            .contentShape(Circle())
            .onTapGesture {
                var l = store.label(for: bufferedID)
                l.colorHex = hex
                store.update(bufferedID, l)
            }
    }

    private var spaceList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 1) {
                    ForEach(sortedIDs, id: \.self) { id in
                        spaceRow(id: id)
                            .id(id)
                    }
                }
            }
            .onChange(of: selectedID) { newID in
                guard let newID else { return }
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(newID, anchor: .center)
                }
            }
        }
    }

    private func spaceRow(id: UInt64) -> some View {
        let label = store.labels[id] ?? SpaceLabel(name: "?", colorHex: "#888888")
        let isCurrent = id == monitor.currentSpaceID
        let isSelected = id == selectedID
        return HStack(spacing: 9) {
            Circle()
                .fill(Color(hex: label.colorHex) ?? .gray)
                .frame(width: 10, height: 10)
            Text(label.name)
                .font(.system(size: 13))
            Spacer()
            if isCurrent {
                Text(L10n.t("badge.current"))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Button {
                store.remove(id)
                if isCurrent {
                    syncBuffer()
                }
                if id == selectedID {
                    selectedID = monitor.currentSpaceID
                }
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(L10n.t(isCurrent ? "help.resetLabel" : "help.removeLabel"))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(rowBackground(isCurrent: isCurrent, isSelected: isSelected))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isSelected ? Color.accentColor.opacity(0.7) : Color.clear, lineWidth: 1.2)
        )
        .animation(.easeOut(duration: 0.12), value: selectedID)
        .contentShape(Rectangle())
        .onTapGesture { jump(to: id) }
        .onHover { hovering in
            guard !isCurrent else { return }
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .help(L10n.t(isCurrent ? "help.currentSpace" : "help.clickToSwitch"))
    }

    private func rowBackground(isCurrent: Bool, isSelected: Bool) -> Color {
        if isCurrent { return Color.accentColor.opacity(0.16) }
        if isSelected { return Color.accentColor.opacity(0.08) }
        return Color.clear
    }

    /// ↑/↓ moves the selection through the Space list; ⏎ jumps to the
    /// selected Space. Key events are left alone while the name field is
    /// being edited, and any ⌃ combination is passed through (the ^⇧↑
    /// toggle hotkey must reach the app-level monitor).
    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [self] event in
            // Let the name TextField handle keys while it owns first responder.
            if let firstResponder = NSApp.keyWindow?.firstResponder, firstResponder is NSTextView {
                return event
            }
            switch event.keyCode {
            case 126:  // ↑
                if event.modifierFlags.contains(.control) { return event }
                self.moveSelection(-1)
                return nil
            case 125:  // ↓
                self.moveSelection(1)
                return nil
            case 36, 76:  // ⏎ / numpad ⏎
                self.jumpToSelected()
                return nil
            case 15:  // R
                if !event.modifierFlags.contains(.command) { return event }
                self.startRenaming()
                return nil
            default:
                return event
            }
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    /// AppKit auto-focuses the name TextField whenever the popover window
/// becomes key (initial first responder). @FocusState can't override that
/// once it has happened, so listen for the window becoming key and grab
/// the focus back — the Space list owns it by default, and ↑/↓ + ⏎ work
/// immediately. The user can still focus the field (click or ⌘R).
    private func installKeyObserver() {
        guard keyObserver == nil else { return }
        keyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { [self] _ in
            stealFocusFromNameField()
        }
    }

    private func removeKeyObserver() {
        if let keyObserver {
            NotificationCenter.default.removeObserver(keyObserver)
            self.keyObserver = nil
        }
    }

    private func stealFocusFromNameField() {
        // One runloop hop: the initial-first-responder assignment happens
        // right after the notification, so wait for it before stealing back.
        DispatchQueue.main.async {
            guard let window = NSApp.keyWindow,
                window.firstResponder is NSTextView
            else { return }
            window.makeFirstResponder(nil)
        }
    }

    private func focusOnList() {
        nameFocused = false
    }

    private func moveSelection(_ delta: Int) {
        guard !sortedIDs.isEmpty else { return }
        guard let current = selectedID, let index = sortedIDs.firstIndex(of: current) else {
            selectedID = monitor.currentSpaceID
            return
        }
        let newIndex = min(max(index + delta, 0), sortedIDs.count - 1)
        selectedID = sortedIDs[newIndex]
    }

    private func jumpToSelected() {
        guard let id = selectedID else { return }
        jump(to: id)
    }

    /// ⌘R: focus the name field (renaming the current Space) and select its
    /// current contents so typing replaces them right away.
    private func startRenaming() {
        nameFocused = true
        DispatchQueue.main.async {
            (NSApp.keyWindow?.firstResponder as? NSTextView)?.selectAll(nil)
        }
    }

    /// Switches to the Space. On success the host closes the popover; on
    /// failure an inline message explains how to fix it.
    private func jump(to id: UInt64) {
        jumpError = nil
        guard id != monitor.currentSpaceID else { return }
        switch SkyLight.switchToSpace(id: id) {
        case .success:
            onJump?()
        case .notFound:
            jumpError = L10n.t("error.notFound")
        case .indexTooHigh(let limit):
            jumpError = L10n.t("error.indexTooHigh", limit)
        case .shortcutNotEnabled(let desktop):
            jumpError = L10n.t("error.shortcutNotEnabled", desktop)
        case .accessibilityDenied:
            SkyLight.promptForAccessibility()
            jumpError = L10n.t("error.accessibility")
        case .unavailable:
            jumpError = L10n.t("error.unavailable")
        }
    }
}

extension Color {
    init?(hex: String) {
        var h = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if h.hasPrefix("#") { h.removeFirst() }
        guard h.count == 6, let v = UInt32(h, radix: 16) else { return nil }
        let r = Double((v >> 16) & 0xFF) / 255.0
        let g = Double((v >> 8) & 0xFF) / 255.0
        let b = Double(v & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }
}
