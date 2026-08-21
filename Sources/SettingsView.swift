import SwiftUI

/// Preferences shown when "Preferences…" is clicked in the main popover.
/// Kept out of the main Space list so it stays compact.
struct SettingsView: View {
    /// Called when the user navigates back to the main popover.
    var onDone: () -> Void

    /// UI language; defaults to Chinese. Also acts as the Observation
    /// dependency so the whole settings view re-renders on change.
    @AppStorage(L10n.languageDefaultsKey) private var languageRaw = AppLanguage.zh.rawValue

    // Environment self-check state.
    @State private var axTrusted = SkyLight.isAccessibilityTrusted
    @State private var digits: Set<Int> = []

    private var language: AppLanguage {
        AppLanguage(rawValue: languageRaw) ?? .zh
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            Divider()

            languageSection
            statusSection

            Spacer(minLength: 0)
        }
        .padding(13)
        .frame(width: 290, height: 430)
        .onAppear { refreshStatus() }
        .onChange(of: languageRaw) { _ in refreshStatus() }
    }

    /// Re-reads the Accessibility trust state and the system's enabled
    /// "Switch to Desktop N" shortcuts (queries TCC / symbolic hotkeys
    /// preferences live).
    private func refreshStatus() {
        axTrusted = SkyLight.isAccessibilityTrusted
        digits = SkyLight.enabledDesktopShortcuts()
    }

    /// "1, 2, 3, 4" or the localized no-digits message.
    private var digitsValueText: String {
        if digits.isEmpty {
            return L10n.t("settings.digitsValueNone")
        }
        return digits.sorted().map(String.init).joined(separator: ", ")
    }

    private var header: some View {
        HStack {
            Button {
                onDone()
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "chevron.left")
                    Text(L10n.t("settings.back"))
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)

            Spacer()

            Text(L10n.t("settings.title"))
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
        }
    }

    private var languageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(L10n.t("settings.language"))
                    .font(.system(size: 12))
                Picker("", selection: $languageRaw) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(lang.displayName).tag(lang.rawValue)
                    }
                }
                .labelsHidden()
                .frame(width: 110)
                Spacer()
            }
        }
        .padding(11)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.055))
        )
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L10n.t("settings.status"))
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(L10n.t("settings.refresh")) { refreshStatus() }
                    .buttonStyle(.plain)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Text(L10n.t("settings.accessibility"))
                    .font(.system(size: 12))
                Spacer()
                HStack(spacing: 5) {
                    Circle()
                        .fill(axTrusted ? Color.green : Color.red)
                        .frame(width: 7, height: 7)
                    Text(L10n.t(axTrusted ? "settings.granted" : "settings.notGranted"))
                        .font(.system(size: 11))
                        .foregroundStyle(axTrusted ? .green : .red)
                }
            }

            if !axTrusted {
                HStack {
                    Button {
                        SkyLight.promptForAccessibility()
                    } label: {
                        Text(L10n.t("settings.requestPermission"))
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.bordered)
                    .help(L10n.t("settings.requestPermissionHint"))
                    Spacer()
                }
            }

            Text(L10n.t("settings.shortcutTitle"))
                .font(.system(size: 12))
                .padding(.top, 2)

            HStack(spacing: 8) {
                Text(L10n.t("settings.digitsLabel"))
                    .font(.system(size: 12))
                Spacer()
                Text(digitsValueText)
                    .font(.system(size: 11))
                    .foregroundStyle(digits.isEmpty ? .red : .green)
            }

            // Troubleshooting tips only appear while there is a problem to
            // fix; a fully working setup keeps this card compact.
            if !axTrusted {
                Text(L10n.t("settings.selfCheckHint"))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if digits.isEmpty {
                Text(L10n.t("settings.shortcutHint"))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(11)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.055))
        )
    }
}