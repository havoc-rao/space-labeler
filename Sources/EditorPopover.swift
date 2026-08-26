import AppKit
import SwiftUI

struct EditorPopover: View {
    @ObservedObject var monitor: SpaceMonitor
    @ObservedObject var store: SpaceStore
    @ObservedObject var updater: UpdaterState

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
    /// Live "Desktop N" number per Space ID, refreshed when the popover
    /// opens and when the active Space changes. nil when the private API is
    /// unavailable — the list then falls back to ID order and pruning is
    /// skipped, so nothing is ever removed blindly.
    @State private var desktopNumbers: [UInt64: Int]?
    /// Live filter typed into the search field; rows that don't match drop
    /// out of the list.
    @State private var searchText: String = ""
    /// Whether the search field currently owns keyboard input. While it
    /// does, ↑/↓/⏎ steer the (filtered) list and ordinary typing passes
    /// through to filter live.
    @State private var searchActive = false
    /// Monotonic token bumped when the popover opens; the search field
    /// reacts by grabbing focus so typing filters immediately.
    @State private var searchFocusToken = 0

    /// Space rows in 桌面 1, 2, 3… order (global desktop number across all
    /// displays). Spaces whose "Desktop N" number is gone — deleted Spaces,
    /// abandoned fullscreen sessions — are dropped: they're not live
    /// desktops anymore. When the numbering API is unavailable, fall back
    /// to ID order with no badge so the list still works.
    private var rows: [(id: UInt64, desktop: Int)] {
        guard let desktopNumbers else {
            return store.labels.keys.sorted().map { ($0, 0) }
        }
        return store.labels.keys
            .compactMap { id in desktopNumbers[id].map { (id, $0) } }
            .sorted { $0.desktop < $1.desktop }
    }

    /// Whitespace-trimmed search query.
    private var trimmedQuery: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Rows after applying the search filter. Matching covers the label
    /// name and the live desktop number, so "3" or part of a name both
    /// narrow the list; a blank query shows everything.
    private var visibleRows: [(id: UInt64, desktop: Int)] {
        let query = trimmedQuery
        guard !query.isEmpty else { return rows }
        return rows.filter { row in
            SpaceFilter.matches(
                name: store.labels[row.id]?.name ?? "",
                desktop: row.desktop,
                query: query
            )
        }
    }

    private var sortedIDs: [UInt64] { visibleRows.map(\.id) }

    var body: some View {
        Group {
            if showSettings {
                SettingsView(updater: updater, onDone: { showSettings = false })
            } else {
                mainContent
            }
        }
        .frame(width: 290)
        .onAppear {
            refreshDesktopNumbers()
            syncBuffer()
            searchText = ""
            searchActive = false
            selectedID = defaultSelectedID
            hoveredID = nil
            pendingDeleteID = nil
            installKeyMonitor()
            installKeyObserver()
        }
        .onDisappear {
            removeKeyMonitor()
            removeKeyObserver()
        }
        .onChange(of: monitor.currentSpaceID) { _ in
            refreshDesktopNumbers()
            syncBuffer()
        }
        .onChange(of: searchText) { _ in
            keepSelectionInsideFilter()
        }
    }

    private var mainContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel(L10n.t("section.current"))
            currentCard

            allSpacesHeader
            searchBar
            listArea

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

    /// Re-reads the live "Desktop N" numbering and prunes labels whose Space
    /// no longer has one (deleted Spaces, abandoned fullscreen sessions).
    /// The active Space's label is always kept so the current card never
    /// churns. When the private API is unavailable the map stays nil and
    /// nothing is pruned.
    private func refreshDesktopNumbers() {
        desktopNumbers = SkyLight.globalDesktopNumbers()
        if let numbers = desktopNumbers {
            var valid = Set(numbers.keys)
            valid.insert(monitor.currentSpaceID)
            store.prune(keeping: valid)
        }
    }

    /// The row keyboard navigation should default to: the current Space when
    /// it appears in the (possibly filtered) list, otherwise the first row
    /// (the current Space may be a fullscreen app Space with no 桌面 number
    /// and no row of its own).
    private var defaultSelectedID: UInt64 {
        if visibleRows.contains(where: { $0.id == monitor.currentSpaceID }) {
            return monitor.currentSpaceID
        }
        return visibleRows.first?.id ?? monitor.currentSpaceID
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

    /// "所有 Space" header; while filtering, the live match count sits on
    /// the right so the narrowing is visible at a glance.
    private var allSpacesHeader: some View {
        HStack {
            sectionLabel(L10n.t("section.all"))
            Spacer()
            if !trimmedQuery.isEmpty {
                Text(L10n.t("badge.matches", visibleRows.count))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    /// The filter field. Deliberately looks nothing like the name field (a
    /// beveled text box): a flat "search pill" — no bezel, filled rounded
    /// rect, magnifying-glass icon, and a clear button that appears while
    /// filtering. An idle pill shows its ⌘F shortcut.
    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            SearchTextField(
                text: $searchText,
                placeholder: L10n.t("field.searchSpaces"),
                focusRequestToken: searchFocusToken,
                onEditingChanged: { editing in
                    searchActive = editing
                }
            )
            if !trimmedQuery.isEmpty {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .onTapGesture { searchText = "" }
                    .help(L10n.t("hint.clearSearch"))
            } else if !searchActive {
                Text("⌘F")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 26)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(Color.white.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(
                    searchActive ? Color.accentColor.opacity(0.55) : Color.white.opacity(0.12),
                    lineWidth: 1
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 7))
        // Clicking anywhere on the pill (icon, padding) focuses the field;
        // clicks on the field itself already do, and end up here too.
        .onTapGesture { startFind() }
        .help(L10n.t("hint.searchField"))
    }

    /// The filtered list, or a quiet empty state when nothing matches.
    @ViewBuilder
    private var listArea: some View {
        if visibleRows.isEmpty, !trimmedQuery.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .light))
                    .foregroundStyle(.tertiary)
                Text(L10n.t("empty.noMatch"))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 22)
        } else {
            spaceList
        }
    }

    private var spaceList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 1) {
                    ForEach(visibleRows, id: \.id) { row in
                        spaceRow(id: row.id, desktop: row.desktop)
                            .id(row.id)
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

    private func spaceRow(id: UInt64, desktop: Int) -> some View {
        let label = store.labels[id] ?? SpaceLabel(name: "?", colorHex: "#888888")
        let isCurrent = id == monitor.currentSpaceID
        let isSelected = id == selectedID
        let isPendingDelete = id == pendingDeleteID
        return HStack(spacing: 9) {
            Circle()
                .fill(Color(hex: label.colorHex) ?? .gray)
                .frame(width: 10, height: 10)
            Text(highlightedName(label.name))
                .font(.system(size: 13))
            Spacer()
            if isCurrent {
                Text(L10n.t("badge.current"))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            // Live "Desktop N" number (the Ctrl+N shortcut this Space maps
            // to right now). 0 when the numbering API is unavailable —
            // show nothing then.
            if desktop > 0 {
                Text(L10n.t("badge.desktop", desktop))
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

    /// Bolds + tints every case-insensitive occurrence of the search query
    /// in a row name, so the filter's effect is obvious even in a long list.
    private func highlightedName(_ name: String) -> AttributedString {
        var attributed = AttributedString(name)
        let query = trimmedQuery
        guard !query.isEmpty else { return attributed }
        var searchRange = attributed.startIndex..<attributed.endIndex
        while let range = attributed[searchRange].range(of: query, options: [.caseInsensitive]) {
            attributed[range].inlinePresentationIntent = .stronglyEmphasized
            attributed[range].foregroundColor = Color.accentColor
            searchRange = range.upperBound..<attributed.endIndex
        }
        return attributed
    }

    private func rowBackground(isCurrent: Bool, isSelected: Bool, isHovered: Bool, isPendingDelete: Bool) -> Color {
        if isPendingDelete { return Color.red.opacity(0.1) }
        if isCurrent { return Color.accentColor.opacity(0.16) }
        if isSelected { return Color.accentColor.opacity(0.08) }
        if isHovered { return Color.white.opacity(0.05) }
        return Color.clear
    }

    /// ↑/↓ moves the selection through the Space list; ⏎ jumps to the
    /// selected Space. While the search field owns the keyboard, ↑/↓/⏎
    /// keep steering the (filtered) list — launcher-style — and Esc first
    /// clears the filter, then exits the field. ⌘F focuses the search
    /// field from the list. Keys are left alone while an input method is
    /// composing (marked text), and other ⌃ combinations are passed
    /// through (the ^⇧↑ toggle hotkey must reach the app-level monitor).
    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [self] event in
            // A text field (name or search) owns the keyboard right now.
            if let firstResponder = NSApp.keyWindow?.firstResponder, firstResponder is NSTextView {
                switch event.keyCode {
                case 126, 125, 36, 76:  // ↑ / ↓ / ⏎
                    if searchActive, !hasMarkedText() {
                        // Steer the list instead of typing into the field.
                        if event.keyCode == 126, event.modifierFlags.contains(.control) {
                            return event
                        }
                        self.handleListKey(event.keyCode)
                        return nil
                    }
                    return event
                case 53:  // Esc
                    if searchActive {
                        if hasMarkedText() {
                            // First Esc cancels the in-progress IME composition.
                            return event
                        }
                        if !searchText.isEmpty {
                            searchText = ""
                        } else {
                            self.endSearchEditing()
                        }
                        return nil
                    }
                    self.endRenaming()
                    return nil
                case 15:  // R — ⌘R works even while the search field is focused
                    if !event.modifierFlags.contains(.command) { return event }
                    self.startRenaming()
                    return nil
                default:
                    return event
                }
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
            case 3:  // F — ⌘F focuses the search/filter field
                if !event.modifierFlags.contains(.command) { return event }
                self.startFind()
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
    /// becomes key (initial first responder). @FocusState can't override
    /// that once it has happened, so listen for the window becoming key
    /// and steal the focus back — the Space list owns the keyboard by
    /// default, and ↑/↓ + ⏎ work immediately. ⌘F (or clicking the search
    /// bar) moves focus into the search field.
    private func installKeyObserver() {
        guard keyObserver == nil else { return }
        keyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { [self] _ in
            assignInitialFocus()
        }
    }

    private func removeKeyObserver() {
        if let keyObserver {
            NotificationCenter.default.removeObserver(keyObserver)
            self.keyObserver = nil
        }
    }

    private func assignInitialFocus() {
        // One runloop hop: the initial-first-responder assignment (the name
        // field) happens right after the notification, so wait for it.
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
            selectedID = defaultSelectedID
        }
        pendingDeleteID = nil
    }

    /// ↑/↓ moves the selection through the Space list, wrapping around at
    /// both ends: ↑ on the first row lands on the last one, ↓ on the last
    /// row lands on the first one (head-to-tail continuation).
    private func moveSelection(_ delta: Int) {
        guard !sortedIDs.isEmpty else { return }
        guard let current = selectedID, let index = sortedIDs.firstIndex(of: current) else {
            selectedID = defaultSelectedID
            return
        }
        let newIndex = (index + delta + sortedIDs.count) % sortedIDs.count
        selectedID = sortedIDs[newIndex]
    }

    /// Routes list-navigation keys (↑/↓/⏎) while the search field is
    /// focused — the same handlers the list uses when it owns the keyboard.
    private func handleListKey(_ keyCode: UInt16) {
        switch keyCode {
        case 126:
            moveSelection(-1)
        case 125:
            moveSelection(1)
        case 36, 76:
            jumpToSelected()
        default:
            break
        }
    }

    /// Whether the active text field has uncommitted IME text (e.g. pinyin
    /// composition). While it does, navigation keys must reach the input
    /// method instead of being stolen for list movement.
    private func hasMarkedText() -> Bool {
        guard let editor = NSApp.keyWindow?.firstResponder as? NSTextView else { return false }
        return editor.hasMarkedText()
    }

    /// Esc with an empty search: leave the search field so the list owns
    /// the keyboard again (↑/↓/⏎ work without the filter).
    private func endSearchEditing() {
        NSApp.keyWindow?.makeFirstResponder(nil)
    }

    /// After every keystroke in the search bar, keep the ↑/↓ cursor inside
    /// the filtered set: the current Space when it matches (as on open),
    /// otherwise the first match — or nothing when no row matches.
    private func keepSelectionInsideFilter() {
        let ids = visibleRows.map(\.id)
        if ids.isEmpty {
            selectedID = nil
        } else if let sel = selectedID, ids.contains(sel) {
            return
        } else if ids.contains(monitor.currentSpaceID) {
            selectedID = monitor.currentSpaceID
        } else {
            selectedID = ids.first
        }
    }

    private func jumpToSelected() {
        // Only jump when the selection is actually visible — after typing a
        // query the previously selected Space may no longer match.
        guard let id = selectedID,
            visibleRows.contains(where: { $0.id == id })
        else { return }
        jump(to: id)
    }

    /// ⌘R: bump the request token; the name field responds by grabbing focus
    /// and selecting its current contents so typing replaces them right away.
    private func startRenaming() {
        renameRequestToken += 1
    }

    /// ⌘F: bump the request token; the search field responds by grabbing
    /// focus and selecting its current contents, so typing filters right
    /// away.
    private func startFind() {
        searchFocusToken += 1
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

/// Borderless single-line field for the filter bar. No bezel or drawn
/// background — the flat "search pill" around it is SwiftUI. Like
/// `RenameTextField`, the delegate reports every change (IME composition
/// included) so the list filters live while pinyin is still being marked.
private struct SearchTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    /// Increment to request focus (+ select-all), e.g. on popover open.
    var focusRequestToken: Int
    /// Fired when the editing session starts / ends (focus change, Esc).
    var onEditingChanged: (Bool) -> Void = { _ in }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField(string: text)
        field.placeholderString = placeholder
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 12)
        field.lineBreakMode = .byTruncatingTail
        field.delegate = context.coordinator
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        // Compare against the live field-editor string, which includes any
        // uncommitted IME text; never overwrite mid-composition — that would
        // interrupt the input method.
        let current = field.currentEditor()?.string ?? field.stringValue
        if current != text {
            // A binding change while the field is being edited (Esc / ✕
            // clears the filter) must rewrite the field editor itself —
            // setting stringValue alone doesn't rerender a live editor.
            if let editor = field.currentEditor() {
                editor.string = text
            } else {
                field.stringValue = text
            }
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
        var parent: SearchTextField
        var focusToken = 0

        init(_ parent: SearchTextField) {
            self.parent = parent
        }

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
