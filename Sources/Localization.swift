import Foundation

/// User-facing language for the app UI. Independent of the system locale;
/// defaults to English.
enum AppLanguage: String, CaseIterable, Identifiable {
    case en
    case zh

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .en: return "English"
        case .zh: return "中文"
        }
    }
}

/// Tiny string-table-based localization. Keys are stable identifiers, values
/// come from a zh/en table in code (no .lproj resources needed for a menu bar
/// app). `t()` falls back to the key itself so a missing entry never crashes.
enum L10n {
    static let languageDefaultsKey = "appLanguage"

    /// Read from UserDefaults; defaults to Chinese.
    static func currentLanguage() -> AppLanguage {
        AppLanguage(
            rawValue: UserDefaults.standard.string(forKey: languageDefaultsKey) ?? ""
        ) ?? .zh
    }

    static func t(_ key: String) -> String {
        let table = currentLanguage() == .zh ? zhTable : enTable
        return table[key] ?? key
    }

    /// Localized string with printf-style formatting (`%@`, `%d`, …).
    static func t(_ key: String, _ args: CVarArg...) -> String {
        String(format: t(key), arguments: args)
    }

    private static let enTable: [String: String] = [
        // EditorPopover
        "section.current": "Current Space",
        "section.all": "All Spaces",
        "badge.current": "current",
        "badge.desktop": "Desktop %d",
        "button.preferences": "Preferences…",
        "button.quit": "Quit",
        "field.spaceName": "Space name",
        "hint.deletePending": "Press Delete again to confirm deletion",
        "hint.expandColors": "Show all colors",
        "hint.collapseColors": "Show fewer colors",
        "field.searchSpaces": "Search spaces…",
        "hint.searchField": "Type to filter — ↑/↓ move, ⏎ jumps, Esc clears · ⌘F focuses",
        "hint.clearSearch": "Clear the filter",
        "hint.clearName": "Clear the name",
        "empty.noMatch": "No matching Spaces",
        "badge.matches": "%d matches",
        "help.resetLabel": "Reset current Space label",
        "help.removeLabel": "Remove saved Space label",
        "help.currentSpace": "Current Space",
        "help.clickToSwitch": "Click to switch to this Space",
        "error.notFound": "This Space is not on the current display's desktop sequence and can't be jumped to",
        "error.indexTooHigh": "Space number exceeds %d — not supported by system shortcuts",
        "error.accessibility":
            "Accessibility permission required: System Settings → Privacy & Security → Accessibility → enable Space Labeler (restart the app if you just enabled it)",
        "error.shortcutNotEnabled":
            "Desktop %d's shortcut is not enabled — check “Switch to Desktop %d” in System Settings → Keyboard → Keyboard Shortcuts → Mission Control",
        "error.unavailable":
            "Jump unavailable: private API resolution failed, or the system “Switch to Desktop N” shortcuts are not enabled",

        // Environment self-check (SettingsView)
        "settings.status": "STATUS",
        "settings.accessibility": "Accessibility permission",
        "settings.granted": "Granted",
        "settings.notGranted":
            "Not granted — enable it in Privacy & Security → Accessibility. If you just did, quit and relaunch the app.",
        "settings.shortcutTitle": "Desktop switch shortcuts",
        "settings.shortcutHint":
            "Enable the “Switch to Desktop 1…9” shortcuts you need in System Settings → Keyboard → Keyboard Shortcuts → Mission Control.",
        "settings.refresh": "Refresh",
        "settings.requestPermission": "Request permission…",
        "settings.requestPermissionHint":
            "Triggers the system authorization dialog (only shown when the permission is not granted).",
        "settings.digitsLabel": "Ctrl+N desktop shortcuts",
        "settings.digitsValueNone": "None enabled — enable “Switch to Desktop 1…9”",
        "settings.selfCheckHint":
            "Jumping posts Ctrl+N — the Accessibility permission and the target desktop's “Switch to Desktop N” shortcut must both be enabled, and the target Space must be on the current display.",

        // Accessibility record reset (SettingsView) — mirrors the Makefile's
        // `sudo tccutil reset Accessibility` in the `install` target.
        "settings.resetAccessibility": "Clean stale Accessibility records",
        "settings.resetAccessibilityButton": "Reset…",
        "settings.resetAccessibilityHint":
            "Wipes macOS's stored Accessibility records for Space Labeler (needs your admin password); you'll then re-grant the permission once.",
        "settings.resetAccessibilityExplain":
            "Ad-hoc installs change the app's signature every time — dead records can shadow a fresh grant. Same as `sudo tccutil reset Accessibility` in the Makefile.",
        "settings.resetPromptTitle": "Reset Accessibility records?",
        "settings.resetPromptMessage":
            "This clears macOS's stored Accessibility permission for Space Labeler, including stale entries from older builds. You'll be asked for your admin password, and the system will then ask you to re-grant the permission.",
        "settings.resetPromptConfirm": "Reset & Re-grant",
        "settings.resetPromptCancel": "Cancel",
        "settings.resetFailedTitle": "Reset failed",
        "settings.resetFailedMessage": "Couldn't clear the Accessibility records: %@",
        "settings.ok": "OK",

        // SettingsView
        "settings.back": "Back",
        "settings.title": "SETTINGS",
        "settings.language": "Language",

        // Updates (SettingsView)
        "settings.updates": "UPDATES",
        "settings.currentVersion": "Current version",
        "settings.checkForUpdates": "Check for Updates…",
        "settings.checking": "Checking…",
        "settings.upToDate": "You're on the latest version",
        "settings.updateAvailable": "New version v%@ available",
        "settings.downloadUpdate": "Download & Restart",
        "settings.downloading": "Downloading v%@…",
        "settings.applying": "Applying update…",
        "settings.updateFailed": "Update check failed: %@",
        "settings.updatePromptTitle": "New version available",
        "settings.updatePromptMessage":
            "v%@ is ready to install. The app will quit, replace itself and relaunch.\n\nNote: this build is ad-hoc signed, so macOS may reset the Accessibility permission. If jumping (Ctrl+N) stops working afterwards, re-enable Space Labeler in System Settings → Privacy & Security → Accessibility.",
        "settings.updatePromptDownload": "Download & Restart",
        "settings.updatePromptCancel": "Cancel",
    ]

    private static let zhTable: [String: String] = [
        // EditorPopover
        "section.current": "当前 Space",
        "section.all": "所有 Space",
        "badge.current": "当前",
        "badge.desktop": "桌面 %d",
        "button.preferences": "偏好设置…",
        "button.quit": "退出",
        "field.spaceName": "Space 名称",
        "hint.deletePending": "再次按 Delete 确认删除",
        "hint.expandColors": "展开全部颜色",
        "hint.collapseColors": "收起颜色",
        "field.searchSpaces": "搜索 Space…",
        "hint.searchField": "输入即筛选 —— ↑/↓ 移动选择，⏎ 跳转，Esc 清除（⌘F 聚焦）",
        "hint.clearSearch": "清除筛选",
        "hint.clearName": "清除名称",
        "empty.noMatch": "没有匹配的 Space",
        "badge.matches": "%d 个匹配",
        "help.resetLabel": "重置当前 Space 标签",
        "help.removeLabel": "移除已保存的 Space 标签",
        "help.currentSpace": "当前 Space",
        "help.clickToSwitch": "点击切换到该 Space",
        "error.notFound": "这个 Space 不在当前屏幕的桌面序列中，无法跳转",
        "error.indexTooHigh": "Space 序号超过 %d，系统快捷键不支持跳转",
        "error.accessibility": "需要辅助功能权限：设置 → 隐私与安全性 → 辅助功能 → 打开 Space Labeler（若刚开启请退出并重新启动应用）",
        "error.shortcutNotEnabled": "桌面 %d 的快捷键未启用——请在系统设置 → 键盘 → 键盘快捷键 → 调度中心勾选「切换到桌面 %d」",
        "error.unavailable": "跳转不可用：私有 API 解析失败，或系统「切换到桌面 N」快捷键未开启",

        // Environment self-check (SettingsView)
        "settings.status": "环境自检",
        "settings.accessibility": "辅助功能权限",
        "settings.granted": "已授权",
        "settings.notGranted": "未授权 — 请在「隐私与安全性 → 辅助功能」中打开。若刚开启，请退出并重新启动应用。",
        "settings.shortcutTitle": "桌面切换快捷键",
        "settings.shortcutHint": "请在「系统设置 → 键盘 → 键盘快捷键 → 调度中心」勾选需要的「切换到桌面 1…9」。",
        "settings.refresh": "刷新",
        "settings.requestPermission": "请求权限…",
        "settings.requestPermissionHint": "触发系统授权弹窗（仅在权限未授权时显示）。",
        "settings.digitsLabel": "数字桌面快捷键",
        "settings.digitsValueNone": "未启用任何数字快捷键——请勾选「切换到桌面 1…9」",
        "settings.selfCheckHint": "跳转通过发送 Ctrl+N 实现：需要辅助功能权限已授权、目标桌面的「切换到桌面 N」快捷键已勾选、目标 Space 在当前屏幕。",

        // 清理辅助功能权限记录（SettingsView）——与 Makefile `install` 目标中的
        // `sudo tccutil reset Accessibility` 等价。
        "settings.resetAccessibility": "清理旧的辅助功能权限记录",
        "settings.resetAccessibilityButton": "重置…",
        "settings.resetAccessibilityHint":
            "清除 macOS 中存储的 Space Labeler 辅助功能权限记录（需要输入管理员密码），之后需重新授权一次。",
        "settings.resetAccessibilityExplain":
            "每次安装都会改变 ad-hoc 签名，旧记录可能遮挡新授权。等价于 Makefile 中的 `sudo tccutil reset Accessibility`。",
        "settings.resetPromptTitle": "重置辅助功能权限记录？",
        "settings.resetPromptMessage":
            "这会清除 macOS 中存储的 Space Labeler 辅助功能权限（包括旧版本遗留的失效记录）。系统会要求输入管理员密码，随后会弹出授权窗口，请重新授权。",
        "settings.resetPromptConfirm": "重置并重新授权",
        "settings.resetPromptCancel": "取消",
        "settings.resetFailedTitle": "重置失败",
        "settings.resetFailedMessage": "无法清除辅助功能权限记录：%@",
        "settings.ok": "好",

        // SettingsView
        "settings.back": "返回",
        "settings.title": "设置",
        "settings.language": "语言",

        // Updates (SettingsView)
        "settings.updates": "更新",
        "settings.currentVersion": "当前版本",
        "settings.checkForUpdates": "检查更新…",
        "settings.checking": "正在检查…",
        "settings.upToDate": "已是最新版本",
        "settings.updateAvailable": "发现新版本 v%@",
        "settings.downloadUpdate": "下载并重启",
        "settings.downloading": "正在下载 v%@…",
        "settings.applying": "正在应用更新…",
        "settings.updateFailed": "检查更新失败：%@",
        "settings.updatePromptTitle": "发现新版本",
        "settings.updatePromptMessage":
            "v%@ 已就绪，应用将退出、替换自身并重新启动。\n\n注意：本应用为 ad-hoc 签名，更新后 macOS 可能重置辅助功能权限。若跳转（Ctrl+N）失效，请重新在「系统设置 → 隐私与安全性 → 辅助功能」中开启 Space Labeler。",
        "settings.updatePromptDownload": "下载并重启",
        "settings.updatePromptCancel": "取消",
    ]
}
