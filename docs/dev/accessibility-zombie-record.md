# 跳转失效排查：辅助功能权限「僵尸记录」诊断记录

- **日期**: 2026-08-21
- **现象**: 用户已开启辅助功能权限，反复 toggle、重启应用后跳转仍无法使用；`AXIsProcessTrusted()` 恒为 false。
- **结论**: TCC 授权记录（csreq）绑定的代码签名指纹对应一个**已被覆盖删除的旧构建**；开关操作只翻转 auth_value，不重写 csreq（且 toggle 时应用未在运行，系统无法抓取当前签名）。记录永远匹配不上磁盘上任何实际二进制 → 权限形同虚设。

---

## 1. 排查证据链

### 1.1 运行态与磁盘副本

```sh
ps aux | grep -i [S]paceLabeler          # 无任何运行中的实例
find ~/Applications build -name "SpaceLabeler.app" -type d
# /Users/havoc420/Applications/SpaceLabeler.app
# .../space-labeler/build/Build/Products/Release/SpaceLabeler.app
# .../space-labeler/build/Build/Products/Debug/SpaceLabeler.app
```

### 1.2 各副本签名指纹（ad-hoc，每次构建都变）

| 文件 | CDHash |
|---|---|
| `~/Applications/SpaceLabeler.app`（最新 `make install`） | `509020408364dfa12c4518bf204231dfbdef4913` |
| `build/Release`（同一次构建） | `509020408364dfa12c4518bf204231dfbdef4913` |
| `build/Debug`（测试产物） | `a92ea0b7a7556d1c3ed7025daa81bcd48a72174c` |
| **TCC csreq 绑定**（读系统库） | **`C03F2E6AA597086E9092982F4FCE6CDF462A79B3`** |

> 磁盘上没有任何二进制的指纹 == TCC 绑定指纹。

### 1.3 TCC 记录查询

授权记录在**系统级** TCC 库（用户级库里没有辅助功能记录，之前误查用户库为空是正常的）：

```sh
sqlite3 "/Library/Application Support/com.apple.TCC/TCC.db" \
  "SELECT service, auth_value, datetime(last_modified,'unixepoch','localtime'), length(csreq) \
   FROM access WHERE client='com.jeremywatt.SpaceLabeler';"
# kTCCServiceAccessibility | 2 | 2026-08-21 10:57:41 | 40
```

- `auth_value = 2`（已授权）
- `last_modified` 随用户在系统设置的 toggle（10:57:41）更新——说明操作生效，但 **csreq 字节依旧指向旧指纹**
- 全库 `com.jeremywatt.SpaceLabeler` 只有这一条记录：**只申请过辅助功能权限**（无屏幕录制/输入监控等）

csreq 十六进制解包：`FADE 0C00 00000028 00000001 00000008 00000014 <CDHash 0x14=20字节>`。

### 1.4 根因机制

macOS 辅助功能授权 = **bundle id + 代码签名指纹（CDHash）** 二元匹配：

1. 本项目 ad-hoc 签名（`CODE_SIGN_IDENTITY: "-"`），每次构建 CDHash 都不同；
2. `make install` 整包覆盖 `~/Applications/SpaceLabeler.app`，旧二进制被删除；
3. TCC 记录仍指向旧指纹 → 任何新二进制都无法匹配 → `AXIsProcessTrusted()` 恒 false；
4. 系统设置里 toggle 开关：
   - 若授权时**应用未在运行**，系统无法抓取「当前进程」的签名，csreq 保持旧值；
   - toggle 只更新 `auth_value`/`last_modified`，**不重写 csreq** —— 这就是「关了再开也没用」「重启也没用」的机制。

---

## 2. 排除的其他可能（均已验证）

| 假设 | 验证结果 |
|---|---|
| 系统「切换到桌面 N」快捷键未勾选 | 部分存在但**不是主因**：当时误将 79–82 当作「桌面 1–4」启用——实为调度中心方向键导航（Ctrl+←/→ 等），真正的「切换到桌面 1–9」是 ID 118–126（2026-08 勘误，见 §6）；代码已改为读取真实启用集合 + 精确报错 |
| 上一/下一空间（Ctrl+←/→）未启用导致组合跳转失败 | 已按用户要求**移除箭头组合逻辑**，跳转只发单次 Ctrl+N |
| yabai 等窗口管理器抢快捷键 | 已卸载 yabai；检查时其并未运行，非干扰源 |
| 应用运行中覆盖 bundle | 已加入 `pkill` 先退实例再覆盖；本次诊断时本机确实无运行实例 |
| 显示名（CFBundleDisplayName）问题 | TCC 按 bundle id + 签名匹配，改显示名无效 |

---

## 3. 修复步骤（已给用户）

```sh
# 1) 删除僵尸记录（需 sudo；会清掉所有该 app 的辅助功能授权）
sudo tccutil reset Accessibility com.jeremywatt.SpaceLabeler

# 2) 先启动 app —— 授权时进程必须在运行，否则 csreq 又不会刷新
open ~/Applications/SpaceLabeler.app

# 3) 触发授权：点任意 Space 跳转（失败会自动弹窗）或 Preferences… → 请求权限…
#    系统设置 → 辅助功能 出现新条目 → 勾选

# 4) Preferences… → STATUS → 刷新，变绿即可用
```

---

## 4. 同类问题防复发

- 每次 `make install` / 重装后，**若跳转失效先看 STATUS 面板**（环境自检实时显示授权状态与启用的数字快捷键），不要再盲 toggle。
- ad-hoc 签名决定「每次构建指纹必变」是根因；若想一劳永逸，改用 **Developer ID 证书签名**（TCC 按签名匹配，内容更新不影响授权），见 README 相关讨论。
- 兜底终极手段（仅确认重置流程走不通时）：改 bundle id 强制重置，代价是 Space 标签数据与 LaunchAgent 需同步迁移。

---

## 5. 代码中的配套改动（本次排查期间）

- `SkyLight.enabledDesktopShortcuts()`：读取 `com.apple.symbolichotkeys` 实际启用的「切换到桌面 N」集合，未启用时返回 `.shortcutNotEnabled(desktop:)` 精确报错，不再发无效按键。
- `SkyLight.promptForAccessibility()`：`AXIsProcessTrustedWithOptions(prompt)` 触发系统授权弹窗；SettingsView 提供「请求权限…」按钮，跳转失败时自动弹出。
- `SkyLight.isAccessibilityTrusted`：实时查询 TCC 状态供 STATUS 自检。
- SettingsView STATUS 面板：辅助功能授权（绿/红 + 请求权限）+ 已启用数字快捷键列表 + 刷新。
- 移除 Ctrl+←/→ 组合跳转（Direction/SwitchStep/composedSteps/异步多步发送），删除 `ComposedSwitchTests.swift`；设置页移除 Quick Switch 上限配置（改自动检测）。

---

## 6. 勘误（2026-08-23）：「切换到桌面 N」的符号化热键 ID

此前 §2 认为 79–87 是「切换到桌面 1–9」，**错误**。实测本机
`defaults read com.apple.symbolichotkeys AppleSymbolicHotKeys`：

- **118–126 = 「切换到桌面 1–9」**（parameters 键码 18/19/20/21/23/22/26/28/25 对应数字键 1–9，flags 262144 = Ctrl）；
- 79–82 = 调度中心方向键导航（键码 123/124 = ←/→，即 Ctrl+←/→ 上一/下一空间）；
- 该错误还导致「桌面 5/6」按键发送错位（'5' 键码是 23，'6' 是 22，线性公式 17+n 在第 5、6 项颠倒）。

配套修复（`SkyLight.swift`）：
- `desktopShortcutIDs` 改用 118–126；
- `desktopShortcuts()` 直接读取已启用条目的**真实键码 + 修饰键**再发送，用户自定义绑定同样生效；
- 仅在配置完全不可读时退回默认 Ctrl+1…9 键码表（已修正 5/6 次序）。