# 发版经验总结（v0.2.5）

> 触发方式：`git push origin main`（触发 CI）+ `git push origin v0.2.5`（触发 Release 工作流）。
> 结论先行：**GitHub 侧构建实际只用了 59 秒，慢感全部来自操作与"确认发完没有"的反馈链路，而不是构建本身。**

## 1. 本次发版实测时间线（本地 +0800，数据来自 Actions API step 级日志）

| 时刻 | 事件 |
|---|---|
| ~12:02 | bump VERSION/project.yml → commit `Release 0.2.5` → push main（`5580aef`） |
| ~12:03:14 | CI 工作流触发（main push） |
| 12:03:18 | Release 工作流触发（tag push） |
| **12:04:11** | **Release v0.2.5 上线、zip 资产可下载** |
| 12:04:17 | Release 工作流完成（总时长 **59 秒**） |
| 12:04:46 | CI 完成（总时长 **92 秒**，build+test+lint 全绿） |
| ~12:05 | 工作流最后一步把 `latest.json`（0.2.5 + 新 SHA256）推回 main（`3ca8c5a`） |
| ~12:06 | 本地 `git fetch` 最终确认元数据已更新（此时才真正确认"发完了"） |

Release 工作流步骤耗时分解（共 59s）：

```
Set up job               1s
actions/checkout         3s
Select latest Xcode      0s
brew install xcodegen    5s   ← 没想象中慢，bottle 秒装
xcodegen generate        0s
Build Release (universal)29s  ← 双架构小项目也就半分钟
Verify/Package/Notes     2s
Create GitHub Release    5s
Publish latest.json      3s
```

## 2. 为什么"感觉慢"——慢在反馈链路，不在构建

1. **没有一键发版**：手动两步 push（main → tag），中间还要惦记 CI 结果，操作步骤多、心智负担大。
2. **监控工具缺失，确认"发完没有"最耗时**（本次比构建本身还久）：
   - 本机没装 `gh`，也没有认证 token；
   - 匿名 GitHub API 在关键时刻撞上**限流 403**（60 次/小时，且共享出口 IP 更容易撞）；
   - Actions 网页是**客户端渲染**，curl 抓不到运行状态；
   - `raw.githubusercontent.com` 有 **CDN 缓存**，`latest.json` 明明已更新，curl 仍返回旧值 0.2.4，造成"怎么还没好"的错觉；
   - 最终靠 `git fetch origin main && git show origin/main:latest.json` 才拿到权威结论——**这一招其实秒级、无缓存、无限流，本应第一优先用**。
3. **反馈等待的绝对值被放大**：整个构建不足 2 分钟，但在我这边的感知是多轮"查一下好了没"，等到第 4 分钟才给出确定性答复。

## 3. 改进清单（下次发版按优先级做）

1. **装 `gh` 并 `gh auth login`** —— 最值得的一笔投资：
   ```bash
   gh run watch        # 实时盯当前/指定 run
   gh run list --limit 5
   gh release view v0.2.6
   ```
2. **权威确认用 git，别用 raw CDN 和匿名 API**：
   ```bash
   git fetch origin main && git show origin/main:latest.json   # 秒级、永远新鲜
   git ls-remote --tags origin | grep v0.2.6                   # 确认 tag 已推
   ```
   `releases.atom`（`https://github.com/<owner>/<repo>/releases.atom`）是服务器渲染的，含精确发布时间，比 Actions 页面更适合脚本确认。
3. **一键发版**：给 `Makefile` 加 `release` target，把「校验 VERSION → commit → push main → tag（v$(VERSION)） → push tag」合成一条命令，消除手动两步和漏 tag 的风险。
4. **GitHub 侧做小优化（可选，收益有限）**：
   - `ci.yml` 里独立的 `Build` 步骤其实冗余 —— `xcodebuild test` 本身就包含编译（可砍约 30s CI 时间）；
   - 缓存 xcodegen（`actions/cache`）或改成直接下载预编译二进制，省掉每次 `brew install`；
   - 两次 push 触发两个工作流是并行的，不是串行，无叠加延迟，不用改。
5. **心态阈值**：小项目 universal Release 整条流水线 1–2 分钟属于正常。**超过 3 分钟没任何进展**才需要怀疑 runner 排队或构建异常（此时去看 `gh run list` 的状态和步骤日志）。

## 4. 本次做对了、值得固化的流程

- VERSION 文件是单一事实源，`release.yml` 里已有「tag 与 VERSION 必须一致」的硬校验 —— 保持。
- 发版 commit 只改两个文件（`VERSION` + `project.yml` 的 `MARKETING_VERSION`），模板化、可脚本化。
- 攒批发版：v0.2.5 一个版本包含 6 个提交（feat/fix/refactor），避免为单 commit 频繁发版 —— 保持这个节奏。
- 发布后校验闭环：下载 zip → 本地 `shasum -a 256` 与 `latest.json` 比对（本次实测一致：`dcd0d733…`）—— 每次发布后都值得做这一步。

## 5. 一句话

> 发版慢是假象：构建 59 秒，慢的是手感和眼睛——**一键脚本省操作，gh/git 看真相，别让 CDN 缓存和匿名限流骗了你。**