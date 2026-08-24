# SpacePilot Agent 指南

这是开发 Agent 进入项目时首先阅读的文件。目标是在尽量少占用上下文的前提下理解项目，只读取当前任务真正相关的源码。

## 一句话介绍产品

SpacePilot 是一款完全在本地运行的 macOS 储存空间分析与应用管理工具，支持 Apple Silicon 和 macOS 15 及以上版本。它不仅展示文件大小，还会解释空间属于哪个应用、开发工具或 AI Agent，说明文件为什么与其关联、能否安全删除，并在统一工作区中管理 AI 应用、插件、技能和 CLI 工具。

## 推荐阅读顺序

1. `docs/PROJECT_STATUS.md`：当前版本、完成情况、缺口和下一步。
2. `docs/CODE_MAP.md`：根据任务选择需要读取的源码。
3. `docs/ARCHITECTURE.md`：仅在修改系统边界或数据流时阅读。
4. `docs/FEATURE_MATRIX.md`：确认产品范围和功能状态。
5. `docs/DECISIONS.md`：避免无意中推翻已经确定的决策。
6. `docs/CURRENT_WORK.md`：查看正在进行的工作和交接信息。

`docs/superpowers/` 保存历史设计和实施计划，可用于了解背景，但不是当前开发进度的事实来源。

## 技术栈与常用命令

- Swift 6、SwiftUI、少量 AppKit 互操作、Swift Package Manager。
- `SpacePilotCore` 保存模型和业务逻辑；`SpacePilot` 保存应用状态、本地化和界面。
- SQLite 保存元数据快照、所有权信息、目录统计和清理历史。
- FSEvents 负责标记变化路径并触发小范围后台刷新。
- Spotlight 只负责快速寻找应用关联候选项，不作为完整文件索引。

```bash
./script/build_and_run.sh   # 构建并启动应用
swift test                  # 运行全部测试
./script/test_release.sh   # 发布构建、启动、应用包和签名检查
```

必须选择完整的 Xcode 16 或更高版本。应用直接在真实 Apple Silicon Mac 上运行，不需要 macOS 模拟器。

## 不可破坏的产品规则

- 禁止写死 `/Users/yurunhao` 或其他用户名。使用 `FileManager.default.homeDirectoryForCurrentUser` 或测试注入的根目录。
- 不读取、不索引、不记录、不持久化对话和日志正文，只保存元数据。
- 不永久删除用户数据，清理操作统一移动到废纸篓。
- 执行清理前必须重新校验路径安全性和文件身份。
- Plugin 管理内容和系统管理内容只读。
- 不在全局、Codex、Claude 或 Plugin 管理目录之间移动 Skill。
- 中低置信度、共享或敏感的关联项默认不选中。
- 权限不足时必须明确展示覆盖范围不足，不能把局部结果描述为完整结果。
- 扫描、投影和发现等耗时操作不能阻塞 MainActor。
- 页面切换和普通启动不能重新引入整个用户目录的递归扫描。

## 按任务定位代码

- 应用发现、关联文件、重置和卸载：先看 `Sources/SpacePilotCore/Applications/` 和 `Sources/SpacePilot/Views/Applications/ApplicationsView.swift`。
- 储存扫描、索引和性能：先看 `Sources/SpacePilotCore/Scanning/`、`Sources/SpacePilotCore/Persistence/` 和 `Sources/SpacePilot/App/AppModel.swift`。
- AI 应用、Plugin、Skill 和 CLI 工具：先看 `Sources/SpacePilotCore/AI/`、`Sources/SpacePilotCore/Plugins/`、`Sources/SpacePilotCore/Skills/` 和 `Sources/SpacePilot/Views/DeveloperAI/`。
- 清理安全和历史：先看 `Sources/SpacePilotCore/Cleanup/` 和 `Sources/SpacePilot/Views/Shared/CleanupConfirmationView.swift`。
- 导航、布局和本地化：先看 `Sources/SpacePilot/Views/`、`Sources/SpacePilot/Localization/L10n.swift` 和本地化资源。

更精确的源码与测试对应关系见 `docs/CODE_MAP.md`。

## 修改代码时的规则

- 工作树不干净时，保留用户不相关的修改。
- 行为发生变化时，增加或更新对应测试。
- 原生分组表格的点击行不能直接映射到扁平数据：必须计算分组标题和折叠状态。
- 异步加载期间保持界面列宽稳定，新的大小计算结果不能改变分栏约束。
- 优先使用明确的证据和置信度规则，避免宽泛的名称模糊匹配。
- 项目事实变化时，同步更新 `docs/PROJECT_STATUS.md`、`docs/FEATURE_MATRIX.md` 或 `docs/CURRENT_WORK.md`。

## 完成标准

只有相关测试和 `swift test` 均通过，才能称实现已完成。涉及启动、资源、应用包、权限、签名或分发时，还要运行 `./script/test_release.sh`。未完成或受外部条件阻塞的工作必须写入 `docs/CURRENT_WORK.md`，不能只留在对话中。
