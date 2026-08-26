# SpaceLabeler

[![Discord](https://img.shields.io/badge/Discord-Join%20Server-7289da?style=flat&logo=discord&logoColor=white)](https://discord.gg/7xsxU4ZG6A)

<p align="center">
  <img src="assets/derived/logo-256.png" width="128" height="128" alt="SpaceLabeler icon">
</p>

A minimal macOS menu bar app that lets you name and color-code your virtual desktops (Spaces).

Since macOS doesn't natively let you name your Spaces — and `TotalSpaces2` was killed by Apple's SIP hardening — SpaceLabeler fills a small but annoying gap. It puts a colored dot and a label in your menu bar that updates whenever you switch Spaces, and lets you rename and recolor each one from a popover.

Website: https://neonwatty.github.io/space-labeler/

## Requirements

- macOS 13 (Ventura) or later
- Xcode 15 or later
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) — `brew install xcodegen`

## Install

### Prebuilt downloads (recommended)

Grab `SpaceLabeler-<version>-macos.zip` from [GitHub Releases](https://github.com/havoc-rao/space-labeler/releases/latest) — a universal binary for both Apple Silicon and Intel. Unzip, move `SpaceLabeler.app` into `/Applications` (or `~/Applications`), and open it.

Because builds are ad-hoc signed and not notarized, macOS may warn "cannot verify the developer" on first launch — Control-click the app and choose **Open** (or run `xattr -dr com.apple.quarantine /Applications/SpaceLabeler.app`). From then on the app can check for and install updates on its own (see [Updates](#updates)) — no need to build from source again.

### Build from source

```sh
git clone https://github.com/neonwatty/space-labeler.git
cd space-labeler
make install
```

That generates the Xcode project, builds a Release binary, copies it to `~/Applications/SpaceLabeler.app`, and launches it.

### Launch at login (optional)

```sh
make install-login
```

This writes `~/Library/LaunchAgents/com.jeremywatt.SpaceLabeler.plist` and `launchctl load`s it, so the menu bar item comes back automatically after reboot. To uninstall:

```sh
launchctl unload ~/Library/LaunchAgents/com.jeremywatt.SpaceLabeler.plist
rm ~/Library/LaunchAgents/com.jeremywatt.SpaceLabeler.plist
```

Without `install-login`, the app does **not** auto-launch at login — relaunch it after reboot via `Cmd+Space` → "Space Labeler" → `Enter`.

### Why a LaunchAgent instead of `SMAppService`?

The app is ad-hoc signed (no Developer ID). `SMAppService.mainApp.register()` returns `.enabled` with no error for ad-hoc bundles, but macOS's BackgroundTaskManagement daemon silently refuses to persist the record — the app never actually relaunches at login. A LaunchAgent plist is the supported workaround.

## Usage

Look at your menu bar — you'll see a colored dot and the current Space's name (for example, `● Space 1`). Switch Spaces with `Ctrl+←` / `Ctrl+→` and watch the label update. Click the item to open a popover where you can rename or recolor the current Space.

Click any Space in the "All Spaces" list to jump straight to it. Jumping synthesizes the system's own "Switch to Desktop N" shortcut (`Ctrl+1` … `Ctrl+9`), so the switch uses macOS's normal animation. It needs two one-time setup steps:

1. **Grant Accessibility permission** — 设置 → 隐私与安全 → 辅助功能 → 打开 Space Labeler (this is how the app posts the `Ctrl+N` key events).
2. **Enable the desktop shortcuts** — 设置 → 键盘 → 键盘快捷键 → 调度中心 → 勾选「切换到桌面 1/2/3…」.

The list shows the desktop's order (1, 2, 3…) as Mission Control sees it, so the mapping is automatic. Spaces beyond the 9th desktop can't be jumped to directly — use `Ctrl+←` / `Ctrl+→` for those. If a required permission or shortcut is missing, the popover shows the same path inline (设置 → 隐私与安全 → 辅助功能 → 打开 Space Labeler) instead of failing silently.

### Direct jumps (Ctrl+N)

Jumping posts a single "Switch to Desktop N" shortcut (`Ctrl+N`). SpaceLabeler automatically reads which desktop shortcuts are actually enabled on this machine: if the target desktop's shortcut isn't checked, you get a precise message ("Desktop N's shortcut is not enabled — check it in Mission Control") instead of a dead keystroke.

Open **Preferences…** — a **STATUS** self-check shows the live Accessibility grant state, the system's enabled Ctrl+N shortcuts (e.g. `1, 2, 3, 4`), and a "Request permission…" button that pops the system authorization dialog.

Preferences also includes a **Language** picker (中文 by default, English available) — the UI switches immediately and persists.

Labels and colors persist across reboots in `UserDefaults` under the key `SpaceLabels.v1`.

### Updates

On launch the app silently checks for a new release (at most once per day). Open **Preferences…** → **UPDATES** to run a manual "Check for Updates…" at any time; when a new version is found, hit **Download & Restart** and the app quits, replaces itself in place, and relaunches.

Note: every build carries a fresh ad-hoc signature, so macOS may reset the Accessibility grant — if jumping (Ctrl+N) stops working after an update, re-enable Space Labeler in System Settings → Privacy & Security → Accessibility. The update source repo is configured in one constant, `UpdaterConfig.repo` in `Sources/Updater.swift`, so it's easy to change if the repository moves.

## Development

```sh
make build      # xcodegen + xcodebuild Release
make test       # xcodebuild test
make clean      # remove generated xcodeproj + build/
```

Or the raw commands:

```sh
xcodegen generate
xcodebuild build -project SpaceLabeler.xcodeproj -scheme SpaceLabeler \
  -configuration Release -destination 'platform=macOS' -derivedDataPath build
xcodebuild test  -project SpaceLabeler.xcodeproj -scheme SpaceLabeler \
  -destination 'platform=macOS' -derivedDataPath build
swift-format lint --recursive Sources Tests
```

The Xcode project file (`SpaceLabeler.xcodeproj`) is gitignored — the source of truth is `project.yml`. Always run `xcodegen generate` (or `make build`, which does it for you) after cloning or after editing `project.yml`.

### Cutting a release

```sh
# 1. Bump the VERSION file (e.g. 0.2.0) and commit
# 2. Tag and push
git tag v0.2.0
git push origin v0.2.0
```

`.github/workflows/release.yml` builds a universal (arm64 + x86_64) Release on macOS, packages it as a zip, and publishes it to a GitHub Release (the tag must match the VERSION file or the workflow errors out; the same workflow can also be run manually from the Actions tab, publishing `v$(VERSION)`). The in-app update check pulls from these Releases.

## Notes on the private API

`Sources/SkyLight.swift` resolves a handful of undocumented CoreGraphics symbols at runtime via `dlsym`:

- `CGSMainConnectionID` — connection ID for the window server
- `CGSGetActiveSpace` — the currently-active Space ID
- `CGSCopyManagedDisplayForSpace` — which display owns a Space
- `CGSCopyManagedDisplaySpaces` — a display's Spaces in Mission Control order

The first two read the active Space ID; the last two power the "click a Space to jump to it" feature. Note the older enumeration symbol `CGSCopySpacesForDisplay` (used by TotalSpaces/Hammerspoon-era code) is no longer present on macOS 26 — `CGSCopyManagedDisplaySpaces` is its modern replacement, returning per-display dictionaries (`Spaces`, `Current Space`, `Display Identifier`).

These have been stable since roughly macOS 10.11 but are not part of Apple's public API contract. If Apple ever removes them, `SkyLight.currentSpaceID()` returns `nil` and the app gracefully degrades to showing a single "Space" label rather than crashing. The test suite includes smoke tests (`SkyLightSmokeTests`) that fail loudly in CI if the symbols can no longer be resolved on a new macOS version.

Switching Spaces is intentionally *not* done via a private "move to space" call — none of those actually trigger a real switch on modern macOS. Instead the app posts the system's own `Ctrl+N` shortcut, which is why the Accessibility permission and the enabled Mission Control shortcuts are required (see [Usage](#usage)).

App Sandbox and Hardened Runtime are disabled because private symbol lookup is incompatible with the sandbox. This app is intentionally not distributable via the Mac App Store.

## License

MIT. See `LICENSE`.
