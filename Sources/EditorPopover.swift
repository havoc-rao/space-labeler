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

    private let palette = ["#FF6B6B", "#4ECDC4", "#FFE66D", "#95E1D3", "#C7B8EA", "#FFA07A"]

    var body: some View {
        Group {
            if showSettings {
                SettingsView(onDone: { showSettings = false })
            } else {
                mainContent
            }
        }
        .frame(width: 290)
        .onAppear { syncBuffer() }
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
        VStack(spacing: 1) {
            ForEach(store.labels.keys.sorted(), id: \.self) { id in
                spaceRow(id: id)
            }
        }
    }

    private func spaceRow(id: UInt64) -> some View {
        let label = store.labels[id] ?? SpaceLabel(name: "?", colorHex: "#888888")
        let isCurrent = id == monitor.currentSpaceID
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
                .fill(isCurrent ? Color.accentColor.opacity(0.16) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture { jump(to: id) }
        .onHover { hovering in
            guard !isCurrent else { return }
            if hovering { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .help(L10n.t(isCurrent ? "help.currentSpace" : "help.clickToSwitch"))
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
