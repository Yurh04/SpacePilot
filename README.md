# SpacePilot

SpacePilot 是一款面向 Apple Silicon、macOS 15 及以上版本的本地储存空间分析与应用管理工具。它兼顾普通用户的清晰体验，同时重点解释开发工具和 AI 应用占用。

## 当前能力

- 分析 Mac 内置磁盘与用户目录，显示分类、最大项目和扫描覆盖范围。
- 启动时直接加载本地索引；文件变化会经过静默合并，并按应用或开发与 AI 范围增量刷新。
- 识别应用本体及高可信度关联文件，提供完整卸载预览。
- 将 ChatGPT 与 Codex 识别为同一产品族，统一展示应用本体、对话、日志、缓存、插件和技能占用；同时深度分析 Claude，并对 Ollama、OpenCode 提供基础占用统计。
- 识别 Xcode、Simulator、Homebrew、npm、Gradle 和 pip 的常见开发空间，并解释风险与重建成本。
- 在 AI 应用内部展示 Plugin 和 Skill，不把它们作为独立主导航。
- 区分共享 Skill、Codex 专属 Skill、Claude 专属 Skill、Plugin 提供的 Skill 和系统管理 Skill。
- 检测 Skill 重复、同名冲突和 Agent 覆盖关系；不提供 Skill 跨目录移动功能。
- 所有清理先展示精确路径与风险，再重新核验文件身份并移到废纸篓。
- 应用支持高可信关联文件预览、Reset 和完整卸载；用户文档与中低可信文件不会被预选。
- Plugin 提供和系统管理的内容只读，不直接修改 Plugin 缓存。

## 隐私与安全

SpacePilot 完全在本机分析。SQLite 索引只保存路径、大小、分类、风险和操作历史等元数据，不保存对话或日志正文。没有完全磁盘访问权限时，应用会继续扫描可访问内容并明确显示覆盖不足。

清理分为 Safe、Rebuildable、Sensitive 和 Managed 四类。敏感内容必须单独确认，Managed 内容禁止直接修改。应用不提供永久删除，第一版统一使用 macOS 废纸篓。

## 开发与运行

要求：

- Apple Silicon Mac
- macOS 15+
- Xcode 16+ 和 Swift 6

运行应用：

```bash
./script/build_and_run.sh
```

也可以在 Xcode 中打开 `Package.swift`，选择 `SpacePilot` scheme 后运行；macOS 应用不需要模拟器，直接在当前 Mac 上测试。

运行测试：

```bash
swift test
```

完整发布前检查：

```bash
./script/test_release.sh
```

## 分发状态

发布检查会生成 `dist/SpacePilot.app` 和 `dist/SpacePilot.zip`，使用本机 ad-hoc Hardened Runtime 签名，仅用于开发和测试。通过网站、Homebrew Cask 或其他渠道公开分发时，不必上架 Mac App Store，但需要使用所有者的 Apple Developer 账号完成 Developer ID 签名和 Apple 公证。

产品规格位于 `docs/superpowers/specs/2026-07-22-spacepilot-design.md`，实施计划位于 `docs/superpowers/plans/2026-07-22-spacepilot-implementation.md`。
