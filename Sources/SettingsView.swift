import AppKit
import SwiftUI

/// Preferences shown when "Preferences…" is clicked in the main popover.
/// Kept out of the main Space list so it stays compact.
struct SettingsView: View {
    /// Update checks and the download-and-restart flow.
    @ObservedObject var updater: UpdaterState

    /// Called when the user navigates back to the main popover.
    var onDone: () -> Void

    /// UI language; defaults to Chinese. Also acts as the Observation
    /// dependency so the whole settings view re-renders on change.
    @AppStorage(L10n.languageDefaultsKey) private var languageRaw = AppLanguage.zh.rawValue

    // Environment self-check state.
    @State private var axTrusted = SkyLight.isAccessibilityTrusted
    @State private var digits: Set<Int> = []
    /// True while the elevated `tccutil reset` (with its admin password
    /// prompt) is running.
    @State private var isResetting = false

    private var language: AppLanguage {
        AppLanguage(rawValue: languageRaw) ?? .zh
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            Divider()

            languageSection
            updateSection
            statusSection

            Spacer(minLength: 0)
        }
        .padding(13)
        .frame(width: 290, height: 450)
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

    /// Checks GitHub Releases for a newer build, offers Download & Restart.
    private var updateSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L10n.t("settings.updates"))
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(.secondary)
                Spacer()
                if updater.isChecking {
                    ProgressView()
                        .controlSize(.small)
                }
                Button(L10n.t("settings.checkForUpdates")) {
                    Task { await updater.checkForUpdates() }
                }
                .buttonStyle(.plain)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .disabled(updater.isChecking)
            }

            HStack(spacing: 8) {
                Text(L10n.t("settings.currentVersion"))
                    .font(.system(size: 12))
                Spacer()
                Text("v\(UpdaterState.currentVersion)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            updateStatus

            if let latest = updater.latestVersion, latest > UpdaterState.currentVersion {
                HStack {
                    Button {
                        confirmAndDownload(version: latest)
                    } label: {
                        if updater.isDownloading {
                            HStack(spacing: 6) {
                                ProgressView()
                                    .controlSize(.small)
                                Text(L10n.t("settings.downloading", "v\(latest)"))
                            }
                        } else {
                            Text(L10n.t("settings.downloadUpdate"))
                        }
                    }
                    .buttonStyle(.bordered)
                    .font(.system(size: 11))
                    .disabled(updater.isDownloading)
                    Spacer()
                }
                .padding(.top, 2)
            }
        }
        .padding(11)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.white.opacity(0.055))
        )
    }

    @ViewBuilder
    private var updateStatus: some View {
        switch updater.state {
        case .checking:
            Text(L10n.t("settings.checking"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        case .upToDate:
            Text(L10n.t("settings.upToDate"))
                .font(.system(size: 11))
                .foregroundStyle(.green)
        case .updateAvailable(let version):
            Text(L10n.t("settings.updateAvailable", "v\(version)"))
                .font(.system(size: 11))
                .foregroundStyle(.green)
        case .applying:
            Text(L10n.t("settings.applying"))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        case .failed(let message):
            Text(L10n.t("settings.updateFailed", message))
                .font(.system(size: 11))
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
        case .idle:
            EmptyView()
        }
    }

    /// Confirmation before quitting the app to swap in the new build. The ad-hoc
    /// signature changes on every build, so macOS may reset the Accessibility
    /// grant — the message tells the user how to re-enable it if jumping stops
    /// working after the update.
    private func confirmAndDownload(version: AppVersion) {
        let alert = NSAlert()
        alert.messageText = L10n.t("settings.updatePromptTitle")
        alert.informativeText = L10n.t("settings.updatePromptMessage", "v\(version)")
        alert.addButton(withTitle: L10n.t("settings.updatePromptDownload"))
        alert.addButton(withTitle: L10n.t("settings.updatePromptCancel"))
        alert.alertStyle = .informational
        if alert.runModal() == .alertFirstButtonReturn {
            updater.downloadAndInstallLatest()
        }
    }

    /// Confirmation before wiping macOS's stored Accessibility records for
    /// this app (the Makefile's `sudo tccutil reset`). The admin password
    /// prompt comes from the system after this dialog is accepted.
    private func confirmAndResetAccessibility() {
        let alert = NSAlert()
        alert.messageText = L10n.t("settings.resetPromptTitle")
        alert.informativeText = L10n.t("settings.resetPromptMessage")
        alert.addButton(withTitle: L10n.t("settings.resetPromptConfirm"))
        alert.addButton(withTitle: L10n.t("settings.resetPromptCancel"))
        alert.alertStyle = .warning
        if alert.runModal() == .alertFirstButtonReturn {
            performAccessibilityReset()
        }
    }

    /// Runs the elevated `tccutil reset Accessibility`, then re-triggers the
    /// system authorization dialog so the user can re-grant immediately.
    private func performAccessibilityReset() {
        isResetting = true
        let result = SkyLight.resetAccessibilityRecords()
        isResetting = false
        refreshStatus()

        switch result {
        case .success:
            // The table is clean now — pop the system dialog right away so
            // the fresh grant lands in it instead of next to dead entries.
            if !axTrusted {
                SkyLight.promptForAccessibility()
            }
        case .cancelled:
            break
        case .failed(let message):
            let alert = NSAlert()
            alert.messageText = L10n.t("settings.resetFailedTitle")
            alert.informativeText = L10n.t("settings.resetFailedMessage", message)
            alert.addButton(withTitle: L10n.t("settings.ok"))
            alert.alertStyle = .critical
            alert.runModal()
        }
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

            // Clears macOS's stored Accessibility records for this app — the
            // in-app equivalent of `sudo tccutil reset Accessibility` in the
            // Makefile. Ad-hoc installs (zip updates in particular) change
            // the code signature on every build, so dead TCC entries can
            // accumulate under the same bundle id and shadow a fresh grant,
            // leaving the STATUS check stuck on "not granted". The reset
            // wipes them so the user can re-grant cleanly.
            HStack(spacing: 8) {
                Text(L10n.t("settings.resetAccessibility"))
                    .font(.system(size: 12))
                Spacer()
                Button {
                    confirmAndResetAccessibility()
                } label: {
                    if isResetting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text(L10n.t("settings.resetAccessibilityButton"))
                    }
                }
                .buttonStyle(.bordered)
                .font(.system(size: 11))
                .disabled(isResetting)
                .help(L10n.t("settings.resetAccessibilityHint"))
            }

            if !axTrusted {
                Text(L10n.t("settings.resetAccessibilityExplain"))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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
