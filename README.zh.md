# SpaceLabeler

[![Discord](https://img.shields.io/badge/Discord-Join%20Server-7289da?style=flat&logo=discord&logoColor=white)](https://discord.gg/7xsxU4ZG6A)

<p align="center">
  <img src="assets/derived/logo-256.png" width="128" height="128" alt="SpaceLabeler icon">
</p>

一个极简的 macOS 菜单栏应用，用于给你的虚拟桌面（Spaces）命名和配色。

macOS 本身不支持为 Spaces 命名——而 `TotalSpaces2` 又因 Apple 的 SIP 加固而消亡——SpaceLabeler 正好填补了这个让人恼火的小空缺。它会在菜单栏显示一个彩色圆点和当前 Space 的名称，切换 Space 时自动更新，并支持在弹出面板中为每个 Space 重命名、换色。

网站：https://neonwatty.github.io/space-labeler/

## 环境要求

- macOS 13（Ventura）或更高版本
- Xcode 15 或更高版本
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) — `brew install xcodegen`

## 安装

### 直接下载（推荐）

从 [GitHub Releases](https://github.com/havoc-rao/space-labeler/releases/latest) 下载 `SpaceLabeler-<版本>-macos.zip`（通用二进制，同时支持 Apple Silicon 与 Intel），解压后将 `SpaceLabeler.app` 移入 `/Applications`（或 `~/Applications`）并打开。

由于采用 ad-hoc 签名且未经公证，首次启动时 macOS 可能提示「无法验证开发者」——右键点按应用 →「打开」即可（或者终端执行 `xattr -dr com.apple.quarantine /Applications/SpaceLabeler.app`）。之后应用可以自行检查并安装更新（见[更新](#更新)），无需再从源码构建。

### 从源码构建

```sh
git clone https://github.com/neonwatty/space-labeler.git
cd space-labeler
make install
```

该命令会生成 Xcode 工程、构建 Release 版本、把产物拷贝到 `~/Applications/SpaceLabeler.app`，并启动它。

### 开机自启（可选）

```sh
make install-login
```

这会写入 `~/Library/LaunchAgents/com.jeremywatt.SpaceLabeler.plist` 并用 `launchctl load` 加载，重启后菜单栏图标会自动恢复。卸载方式：

```sh
launchctl unload ~/Library/LaunchAgents/com.jeremywatt.SpaceLabeler.plist
rm ~/Library/LaunchAgents/com.jeremywatt.SpaceLabeler.plist
```

如果未执行 `install-login`，应用**不会**随登录自动启动——重启后需通过 `Cmd+Space` → "Space Labeler" → `Enter` 手动启动。

### 为什么用 LaunchAgent 而不是 `SMAppService`？

应用采用 ad-hoc 签名（无开发者 ID）。对 ad-hoc 签名 bundle 调用 `SMAppService.mainApp.register()` 虽然返回 `.enabled` 且无报错，但 macOS 的 BackgroundTaskManagement 守护进程会静默拒绝持久化记录——应用实际上不会在登录时重新启动。LaunchAgent plist 是可行的解决方案。

## 使用说明

看你的菜单栏——会看到一个彩色圆点和当前 Space 的名称（例如 `● Space 1`）。用 `Ctrl+←` / `Ctrl+→` 切换 Space 时标签会同步更新。点击菜单栏图标打开弹出面板，即可重命名或重新着色当前 Space。

点击「All Spaces」列表中的任意 Space 可直接跳转过去。跳转通过合成系统自带的「切换到桌面 N」快捷键（`Ctrl+1` … `Ctrl+9`）实现，因此切换使用 macOS 原生的过渡动画。需要一次性完成两项配置：

1. **授予辅助功能权限** — 设置 → 隐私与安全 → 辅助功能 → 打开 Space Labeler（应用通过它来发送 `Ctrl+N` 键事件）。
2. **开启桌面切换快捷键** — 设置 → 键盘 → 键盘快捷键 → 调度中心 → 勾选「切换到桌面 1/2/3…」。

列表按照调度中心（Mission Control）看到的桌面顺序（1、2、3…）展示，因此映射是自动的。第 9 个桌面之后的 Space 无法直接跳转——请改用 `Ctrl+←` / `Ctrl+→`。如果缺少权限或快捷键，弹出面板会内联显示同样的配置路径（设置 → 隐私与安全 → 辅助功能 → 打开 Space Labeler），而不是静默失败。

### 筛选 Space

打开面板后，焦点默认留在「所有 Space」列表上（↑/↓/⏎ 直接可用）。按 `⌘F`（或点击列表上方的搜索条）将焦点移入筛选框：输入即按名称（或桌面编号，如 `3`）实时过滤列表，匹配片段加粗高亮，右侧显示匹配数量。筛选时 ↑/↓ 仍在过滤后的列表中移动，⏎ 跳转到选中的 Space，`Esc` 先清空筛选、再退出搜索条回到列表。搜索条是扁平圆角胶囊风格（放大镜图标 + 清除 ✕），刻意与「当前 Space」卡片里带边框的「Space 名称」输入框区分开。

### 数字直达（Ctrl+N）

跳转通过发送一次系统「切换到桌面 N」快捷键（`Ctrl+N`）实现。SpaceLabeler 会**自动读取系统实际启用的数字快捷键范围**：如果目标桌面的快捷键未勾选，会给出精确提示（「桌面 N 的快捷键未启用——请在调度中心勾选」），而不是发一个无效按键。

设置界面（**Preferences…**）内置 **环境自检**：实时显示辅助功能授权状态、系统已启用的数字快捷键（如 `1, 2, 3, 4`），并有「请求权限…」按钮直接触发系统授权弹窗。

设置界面还能切换界面语言（**Language**，默认中文，可选 English）——切换后立即生效并持久保存。

标签与颜色在重启后仍会保留，存储在 `UserDefaults` 的 `SpaceLabels.v1` 键下。

### 更新

应用启动时会静默检查一次更新（每天最多一次）。打开 **Preferences…** → **更新** 区块，可随时手动「检查更新…」；发现新版本后点击「下载并重启」，应用会退出、用新版本替换自身并自动重新启动。

注意：每次构建都是新的 ad-hoc 签名，macOS 可能因此重置辅助功能授权——若更新后跳转（Ctrl+N）失效，请到「系统设置 → 隐私与安全性 → 辅助功能」重新开启 Space Labeler。更新源仓库在 `Sources/Updater.swift` 的 `UpdaterConfig.repo` 中配置，仓库迁移时只需改这一处。

## 开发

```sh
make build      # xcodegen + xcodebuild Release
make test       # xcodebuild test
make clean      # 删除生成的 xcodeproj 与 build/
```

或者使用原始命令：

```sh
xcodegen generate
xcodebuild build -project SpaceLabeler.xcodeproj -scheme SpaceLabeler \
  -configuration Release -destination 'platform=macOS' -derivedDataPath build
xcodebuild test  -project SpaceLabeler.xcodeproj -scheme SpaceLabeler \
  -destination 'platform=macOS' -derivedDataPath build
swift-format lint --recursive Sources Tests
```

Xcode 工程文件（`SpaceLabeler.xcodeproj`）已被 gitignore——真正的源头是 `project.yml`。克隆仓库后或修改 `project.yml` 后，务必先运行 `xcodegen generate`（`make build` 会自动执行）。

### 发布新版本

```sh
# 1. 修改 VERSION 文件（如 0.2.0）并提交
# 2. 打 tag 并推送
git tag v0.2.0
git push origin v0.2.0
```

`.github/workflows/release.yml` 会在 macOS 上构建通用（arm64 + x86_64）Release 包、打包成 zip 并发布到 GitHub Release（tag 必须与 VERSION 文件一致，否则 workflow 会报错；也可以在 Actions 页面手动触发同一个 workflow，它会按 VERSION 发布）。应用内置的更新检查即拉取这些 Release。

## 关于私有 API 的说明

`Sources/SkyLight.swift` 在运行时通过 `dlsym` 解析以下未文档化的 CoreGraphics 符号：

- `CGSMainConnectionID` — 窗口服务器的连接 ID
- `CGSGetActiveSpace` — 当前激活的 Space ID
- `CGSCopyManagedDisplayForSpace` — Space 归属的显示器
- `CGSCopyManagedDisplaySpaces` — 某显示器上按调度中心顺序排列的 Spaces

前两个用于读取当前 Space ID；后两个支撑「点击 Space 跳转」功能。注意：旧的枚举符号 `CGSCopySpacesForDisplay`（TotalSpaces/Hammerspoon 时代的用法）在 macOS 26 上已不存在——`CGSCopyManagedDisplaySpaces` 是其现代替代品，返回按显示器组织的字典（`Spaces`、`Current Space`、`Display Identifier`）。

这些符号自 macOS 10.11 左右以来一直保持稳定，但不属于 Apple 的公共 API 契约。如果 Apple 移除它们，`SkyLight.currentSpaceID()` 会返回 `nil`，应用会优雅降级为只显示一个 "Space" 标签，而不会崩溃。测试套件包含冒烟测试（`SkyLightSmokeTests`），一旦新 macOS 版本上符号无法解析，会在 CI 中大声失败。

切换 Space 刻意**不**使用私有的 "move to space" 调用——在现代 macOS 上它们都无法真正触发切换。取而代之的是发送系统自带的 `Ctrl+N` 快捷键，这正是需要辅助功能权限和开启调度中心快捷键的原因（见[使用说明](#使用说明)）。

由于私有符号查找与沙盒不兼容，App Sandbox 和 Hardened Runtime 均已关闭。该应用有意不通过 Mac App Store 分发。

## 许可证

MIT。详见 `LICENSE`。
