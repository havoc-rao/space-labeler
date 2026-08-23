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
    /// Monotonic token bumped on ⌘R; the name field reacts by grabbing
    /// focus and selecting its contents.
    @State private var renameRequestToken = 0
    /// Row the pointer is currently hovering (the Delete-key target).
    @State private var hoveredID: UInt64?
    /// Row armed for deletion: the first Delete press sets it (red trash
    /// icon hint), a second Delete press actually removes it.
    @State private var pendingDeleteID: UInt64?
    /// Whether the full 12-color palette is expanded (default: one row).
    @State private var showAllColors = false
    @State private var keyObserver: NSObjectProtocol?

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
            hoveredID = nil
            pendingDeleteID = nil
            installKeyMonitor()
            installKeyObserver()
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
                Text(appVersion)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
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

    /// "v0.1.0 (1)" — marketing version and build number from the bundle.
    private var appVersion: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return "v\(short) (\(build))"
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(.secondary)
    }

    private var currentCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                RenameTextField(
                    text: $nameBuffer,
                    placeholder: L10n.t("field.spaceName"),
                    focusRequestToken: renameRequestToken,
                    onEditingChanged: { editing in
                        // While editing, the menu bar label stays frozen; it
                        // refreshes when the edit session ends (⏎/Esc/click-away).
                        store.isRenaming = editing
                    }
                )
                .onChange(of: nameBuffer) { newValue in
                    var l = store.label(for: bufferedID)
                    l.name = newValue
                    store.update(bufferedID, l)
                }

                // ⏎ hint: the edit commits and focus returns to the list.
                Image(systemName: "return")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(store.isRenaming ? Color.accentColor : Color.secondary)
                    .help(L10n.t("hint.enterToSubmit"))
            }

            colorPicker
        }
        .padding(11)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.055))
        )
    }

    /// Color picker: in both states the swatches keep their natural 28×24
        /// footprint; expanding only adds height (a second row), and the
        /// chevron always sits in the 7th cell of the first row, so the
        /// two states never re-flow horizontally.
        private var colorPicker: some View {
            let collapsed = collapsedPaletteColors()
            return Grid(horizontalSpacing: 6, verticalSpacing: 6) {
                GridRow {
                    ForEach(collapsed, id: \.self) { hex in
                        swatchCell(hex)
                    }
                    // The chevron is the 7th cell right after the
                    // swatches — no padding cell needed.
                    colorExpandButton
                }
                if showAllColors {
                    GridRow {
                        ForEach(SpacePalette.darkColors, id: \.self) { hex in
                            swatchCell(hex)
                        }
                    }
                }
            }
        }

        /// Uniform grid cell footprint (28 wide × 24 tall) so the light row,
        /// the dark row and the chevron all line up on the same 8 columns.
        private func swatchCell(_ hex: String) -> some View {
            swatch(hex: hex).frame(width: 28, height: 24)
        }

        private var emptyCell: some View {
            Color.clear.frame(width: 28, height: 24)
        }

    private var colorExpandButton: some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) {
                showAllColors.toggle()
            }
        } label: {
            Image(systemName: showAllColors ? "chevron.up" : "chevron.down")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        // Same footprint as a swatch cell, with a pointing-hand cursor on
        // hover. The whole cell is the hit area.
        .frame(width: 28, height: 24)
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .help(L10n.t(showAllColors ? "hint.collapseColors" : "hint.expandColors"))
    }

    /// One row while collapsed: the light row, or the dark row when the
/// currently-selected hue lives there, so the selection mark never
/// disappears behind the hidden row.
    private func collapsedPaletteColors() -> [String] {
        let current = store.label(for: bufferedID).colorHex
        if let index = SpacePalette.colors.firstIndex(of: current),
            index >= SpacePalette.lightColors.count
        {
            return SpacePalette.darkColors
        }
        return SpacePalette.lightColors
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
        let isPendingDelete = id == pendingDeleteID
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
            // Live "Desktop N" number (the Ctrl+N shortcut this Space maps
            // to right now). nil for orphaned IDs — show nothing then.
            if let n = SkyLight.desktopNumber(for: id) {
                Text(L10n.t("badge.desktop", n))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
            Button {
                deleteLabel(id)
            } label: {
                Image(systemName: isPendingDelete ? "trash.fill" : "trash")
                    .font(.system(size: isPendingDelete ? 12 : 11))
                    .foregroundStyle(isPendingDelete ? Color.red : Color.secondary)
                    .scaleEffect(isPendingDelete ? 1.2 : 1)
                    .animation(.easeOut(duration: 0.12), value: isPendingDelete)
            }
            .buttonStyle(.plain)
            .help(L10n.t(isPendingDelete ? "hint.deletePending" : (isCurrent ? "help.resetLabel" : "help.removeLabel")))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(rowBackground(isCurrent: isCurrent, isSelected: isSelected, isHovered: hoveredID == id, isPendingDelete: isPendingDelete))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(
                    isPendingDelete ? Color.red.opacity(0.7)
                        : (isSelected ? Color.accentColor.opacity(0.7) : Color.clear),
                    lineWidth: 1.2
                )
        )
        .animation(.easeOut(duration: 0.12), value: selectedID)
        .animation(.easeOut(duration: 0.12), value: pendingDeleteID)
        .contentShape(Rectangle())
        .onTapGesture { jump(to: id) }
        .onHover { hovering in
            if hovering {
                hoveredID = id
                guard !isCurrent else { return }
                NSCursor.pointingHand.push()
            } else {
                if hoveredID == id { hoveredID = nil }
                NSCursor.pop()
            }
        }
        .help(L10n.t(isCurrent ? "help.currentSpace" : "help.clickToSwitch"))
    }

    private func rowBackground(isCurrent: Bool, isSelected: Bool, isHovered: Bool, isPendingDelete: Bool) -> Color {
        if isPendingDelete { return Color.red.opacity(0.1) }
        if isCurrent { return Color.accentColor.opacity(0.16) }
        if isSelected { return Color.accentColor.opacity(0.08) }
        if isHovered { return Color.white.opacity(0.05) }
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
                // Except Esc, which ends the rename session and returns
                // ↑/↓/⏎ to the list.
                if event.keyCode == 53 {
                    self.endRenaming()
                    return nil
                }
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
            case 51, 117:  // ⌫ / ⌦ — arms the hovered row, then deletes it
                self.handleDelete()
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

    /// Delete key: targets the hovered row, falling back to the ↑/↓-selected
    /// row (hover tracking inside the popover's ScrollView is not always
    /// reliable). The first press arms the row — red trash hint, and the
    /// selection follows so the feedback is unmistakable — and the second
    /// press deletes it; the pointer may leave the row in between.
    private func handleDelete() {
        let target = hoveredID ?? selectedID
        if let id = target, pendingDeleteID != id {
            pendingDeleteID = id
            selectedID = id
            return
        }
        guard let id = pendingDeleteID else { return }
        deleteLabel(id)
    }

    /// Removes a saved label (or resets the current Space's label to a
    /// fresh default name + color) and clears the pending-delete state.
    private func deleteLabel(_ id: UInt64) {
        store.remove(id)
        if id == monitor.currentSpaceID {
            syncBuffer()
        }
        if id == selectedID {
            selectedID = monitor.currentSpaceID
        }
        pendingDeleteID = nil
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

    /// ⌘R: bump the request token; the name field responds by grabbing focus
    /// and selecting its current contents so typing replaces them right away.
    private func startRenaming() {
        renameRequestToken += 1
    }

    /// Esc while renaming: give keyboard control (↑/↓/⏎) back to the list.
    private func endRenaming() {
        NSApp.keyWindow?.makeFirstResponder(nil)
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

/// NSTextField wrapper. Unlike SwiftUI's TextField — whose text binding does
/// not update while an input method is composing (marked text, e.g. pinyin) —
/// the delegate hears about every editing change, so renaming updates the
/// store live instead of only after ⏎ confirms the composition.
private struct RenameTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    /// Increment to request focus + select-all (⌘R).
    var focusRequestToken: Int
    /// Fired when the editing session starts / ends (⏎, Esc, click-away).
    var onEditingChanged: (Bool) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(string: text)
        field.placeholderString = placeholder
        field.bezelStyle = .roundedBezel
        field.font = .systemFont(ofSize: 13)
        field.focusRingType = .default
        field.delegate = context.coordinator
        field.target = context.coordinator
        field.action = #selector(Coordinator.commit(_:))
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        // Compare against the live field-editor string, which includes any
        // uncommitted IME text; never overwrite mid-composition — that would
        // interrupt the input method.
        let current = field.currentEditor()?.string ?? field.stringValue
        if current != text {
            field.stringValue = text
        }
        let coordinator = context.coordinator
        if coordinator.focusToken != focusRequestToken {
            coordinator.focusToken = focusRequestToken
            DispatchQueue.main.async {
                field.selectText(nil)
            }
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: RenameTextField
        var focusToken = 0

        init(_ parent: RenameTextField) {
            self.parent = parent
        }

        /// Fires on every keystroke — including IME composition updates —
        /// so the label persists live (pinyin included) rather than only on ⏎.
        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            let editorText = field.currentEditor()?.string ?? field.stringValue
            parent.text = editorText
        }

        func controlTextDidBeginEditing(_ obj: Notification) {
            parent.onEditingChanged(true)
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            parent.onEditingChanged(false)
        }

        /// ⏎: commit the final text, then drop focus back to the Space list
        /// so ↑/↓ and ⏎ keep working for navigation.
        @objc func commit(_ sender: Any?) {
            guard let field = sender as? NSTextField else { return }
            parent.text = field.stringValue
            field.window?.makeFirstResponder(nil)
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
