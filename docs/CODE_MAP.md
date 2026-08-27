# 代码地图

使用本地图只打开当前任务需要的文件。读取大文件前，先使用有针对性的 `rg` 搜索入口、调用方和测试。

## 应用入口和状态

| 用途 | 主要文件 |
| --- | --- |
| 应用入口和窗口 | `Sources/SpacePilot/App/SpacePilotApp.swift` |
| 全局可观察状态和任务协调 | `Sources/SpacePilot/App/AppModel.swift` |
| 导航、全局工具栏和搜索 | `Sources/SpacePilot/Views/AppRootView.swift`、`SidebarView.swift` |
| 导航模型 | `Sources/SpacePilotCore/Models/NavigationDestination.swift` |
| 本地化 API 和资源 | `Sources/SpacePilot/Localization/L10n.swift`、`Sources/SpacePilot/Resources/Localizable.xcstrings` |

## 储存引擎

| 用途 | 主要文件 | 对应测试 |
| --- | --- | --- |
| 运行时依赖组装 | `Sources/SpacePilotCore/Scanning/SpacePilotRuntime.swift` | `PackageSmokeTests.swift` |
| 扫描范围和管线 | `Sources/SpacePilotCore/Scanning/ScanCoordinator.swift` | `ScanCoordinatorTests.swift`、`ScanScopeArchitectureTests.swift` |
| 有数量限制的目录遍历 | `Sources/SpacePilotCore/Scanning/DirectoryScanner.swift` | `DirectoryScannerTests.swift` |
| 磁盘和开发工具目录 | `VolumeScanner.swift`、`DeveloperStorageScanner.swift` | 同名扫描器测试 |
| FSEvents 和变化合并 | `FileSystemChangeMonitor.swift`、`FileSystemChangeReconciler.swift` | `FileSystemChangeMonitorTests.swift` |
| SQLite 快照、索引和统计 | `Sources/SpacePilotCore/Persistence/SQLiteIndexStore.swift`、`IndexSchema.swift` | `SQLiteIndexStoreTests.swift` |
| 快照和所有权核心模型 | `Models/ScanSnapshot.swift`、`ScannedItem.swift`、`StorageIntelligence.swift` | `ModelAggregationTests.swift` |
| 界面投影和数量限制 | `Models/AppSnapshotProjection.swift`、`ViewProjections.swift` | `ViewProjectionTests.swift` |
| 概览和储存界面 | `Views/Overview/`、`Views/Storage/StorageView.swift` | `OverviewDashboardStateTests.swift`、`OverviewChartArchitectureTests.swift`、储存界面架构测试 |

## 应用程序

| 用途 | 主要文件 | 对应测试 |
| --- | --- | --- |
| 已安装应用清单 | `Applications/ApplicationScanner.swift` | `ApplicationScannerTests.swift` |
| Bundle、签名和组件身份 | `ApplicationIdentity.swift`、`ApplicationIdentityReader.swift` | `ApplicationIdentityReaderTests.swift` |
| 候选路径和关联证据 | `ApplicationArtifactResolver.swift`、`ApplicationRule.swift` | `ApplicationArtifactResolverTests.swift` |
| 版本化特殊规则 | `ApplicationAssociationKnowledgeBase.swift` | `ApplicationAssociationKnowledgeBaseTests.swift` |
| Spotlight 加速 | `SpotlightApplicationCandidateDiscovery.swift` | `SpotlightApplicationCandidateDiscoveryTests.swift` |
| 按需计算大小和详情 | `ApplicationDetailAnalyzer.swift`、`ApplicationArtifactSizeResolver.swift` | 对应分析器测试 |
| 重置和卸载选择 | `ApplicationUninstallPlanner.swift` | `ApplicationUninstallPlannerTests.swift` |
| 应用界面和分组行 | `Sources/SpacePilot/Views/Applications/ApplicationsView.swift` | `ApplicationAssociationGroupingTests.swift`、`FinderRevealTests.swift` |
| 原生双击和 Finder 定位 | `Views/Shared/NativeTableDoubleClick.swift`、`FinderReveal.swift` | `FinderRevealTests.swift` |

## 开发与 AI

| 用途 | 主要文件 | 对应测试 |
| --- | --- | --- |
| 产品专属储存适配器 | `SpacePilotCore/AI/CodexAdapter.swift`、`ClaudeAdapter.swift`、`RuleBasedAIAdapter.swift` | `AIAdapterTests.swift` |
| ChatGPT/Codex 产品族合并 | `AI/AIApplicationProductFamilyMerger.swift` | `AIApplicationProductFamilyMergerTests.swift` |
| 已知工具注册和发现 | `AI/Discovery/AIToolRegistry.swift`、`KnownAIToolDefinitions.swift` | `AIToolRegistryTests.swift` |
| AI 应用/CLI 合并和安全版本探测 | `AIApplicationJoin.swift`、`SafeCLIVersionProbe.swift` | 对应测试 |
| Agent 投影、详情和资产分组 | `AIAgentProjection.swift`、`AIAgentDetailProjection.swift`、`AIAssetGroupingProjection.swift` | 对应投影测试 |
| 用户批准项目和项目 AI 资产 | `ApprovedProjectRoot.swift`、`ProjectRootApprovalPolicy.swift`、`ProjectAIAssetScanner.swift` | 对应批准策略和扫描测试 |
| 版本检查、选择计划和受控更新 | `AIUpdateChecking.swift`、`AIUpdateSelectionPlan.swift`、`AIUpdateExecutor.swift` | `AIUpdateCheckingTests.swift`、`AIUpdateExecutionTests.swift` |
| Plugin 目录、清单和组件 | `Sources/SpacePilotCore/Plugins/` | `PluginRootDiscoveryTests.swift`、`PluginScannerTests.swift` |
| Skill 目录、清单和冲突 | `Sources/SpacePilotCore/Skills/` | `SkillScannerTests.swift`、`SkillConflictDetectorTests.swift` |
| 开发与 AI 界面 | `Sources/SpacePilot/Views/DeveloperAI/` | `DeveloperAIArchitectureTests.swift`、AI 管理测试 |

## 清理与安全

| 用途 | 主要文件 | 对应测试 |
| --- | --- | --- |
| 路径安全策略 | `SpacePilotCore/Cleanup/PathSafetyPolicy.swift` | `PathSafetyPolicyTests.swift` |
| 从选择生成不可变计划 | `CleanupPlanner.swift`、`CleanupModels.swift` | `CleanupPlannerTests.swift` |
| 身份复核和移到废纸篓 | `CleanupExecutor.swift`、`TrashMoving.swift`、`CleanupVerifier.swift` | `CleanupExecutorTests.swift` |
| 清理确认界面 | `Views/Shared/CleanupConfirmationView.swift`、`CleanupSelection.swift` | 清理选择测试 |
| 清理历史界面 | `Views/History/CleanupHistoryView.swift` | 清理架构测试 |

## 构建与发布

| 用途 | 文件 |
| --- | --- |
| Package 定义 | `Package.swift` |
| 应用包信息和版本 | `script/Info.plist` |
| 开发构建和启动 | `script/build_and_run.sh` |
| 发布检查和 ZIP | `script/test_release.sh` |
| 分发说明 | `README.md`、`docs/PROJECT_STATUS.md` |

## 快速调查命令

```bash
rg -n "符号或文本" Sources Tests
rg --files Sources/SpacePilotCore/Applications Tests/SpacePilotCoreTests
swift test --filter ApplicationArtifactResolverTests
swift test --filter SQLiteIndexStoreTests
```

不要一开始就完整阅读 `AppModel.swift` 或 `ScanCoordinator.swift`。先定位相关方法，阅读它的直接调用方和测试；只有数据流仍不清楚时再扩大范围。
