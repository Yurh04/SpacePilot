# 当前工作与交接

## Dock 图标尺寸修正（2026-09-25）

- 用户截图显示运行时图标明显偏大：Icon Composer 的紧边 PNG 被直接传给 `applicationIconImage`，没有系统图标画布留白。
- 控制器在加载时将深浅两版居中绘制到 1024×1024 透明画布的 824×824 区域，四周 100；两张结果缓存复用，自动切换不变，原生 Assets.car 不额外缩放。
- 新增两版 alpha 边界回归测试，修复前边界为 0–100% 而失败，修复后约为 9.77–90.23%。外观切换测试继续通过；运行时输出与系统设置图标同画布对比，主体尺寸一致。
- `./script/test_release.sh` 通过：573 项测试、Release 构建、启动、签名结构及 ZIP。已重新启动修正版；Gatekeeper 仍拒绝 ad-hoc 签名。

## 图标自动切换（2026-09-25，替代下方固定图标方案）

- 新增 `ApplicationIconController`，启动时选取图标，并观察 `NSApplication.effectiveAppearance` 实时更新 Dock；终止时释放观察。仅记录图标外观名称。
- `Artwork/AppIcon.icon` 保存深浅色图层，Xcode 26+ 打包生成原生 `Assets.car`，通过 `CFBundleIconName` 接入 Finder 和未运行应用；旧系统保留浅色 ICNS 回退，运行中的 Dock 自动切换支持 macOS 15+。
- 系统“图标与小组件样式”独立于窗口外观；Finder 自动切换需选择“深色 → 自动”。本机验证过程中该设置从自动回到默认，保留用户当前选择，不继续覆盖。运行中 Dock 通过应用外观监听独立更新。
- 新增测试覆盖浅→深→浅、资源实际加载和停止观察。最终 `./script/test_release.sh` 通过：572 项测试、Release 构建、启动、签名结构与 ZIP；Gatekeeper 仍拒绝 ad-hoc 签名。
- 真机通过系统设置执行浅→深→浅，并恢复原“自动”窗口外观；同一 PID 的 AppIcon 日志确认逐次应用 light/dark/light，无需重启。Dock 截图工具超时，未完成 Dock 像素级截图验收；原生图标两种 rendition 均已导出检查，Assets.car 内存在 Aqua/DarkAqua 外观。

## 浅色正式图标（2026-09-25）

- 按用户要求将浅色版设为正式默认图标，更新 `AppIcon/AppIcon-1024.png` 与 `AppIcon.icns` 的 16–1024 px 表示。正式原稿保存为 `output/imagegen/SpacePilot-light-production.png`，深色稿保留。
- 使用满幅浅色原稿，避免透明边缘生成杂点；已检查本机 macOS 26 的 `NSWorkspace.icon(forFile:)` 渲染结果，显示干净的浅色圆角图标。当前为固定浅色图标，不随系统外观自动切换。
- `./script/test_release.sh` 通过：571 项测试、Release 构建、启动、签名结构校验与 ZIP 生成；Gatekeeper 仍拒绝 ad-hoc 签名。已确认打包图标与源码一致，刷新 Launch Services 和 Dock 并重新启动应用。

## 图标替换（2026-09-24）

- 正式应用图标替换为简化的深色容量圆环与领航箭头，更新 `AppIcon/AppIcon-1024.png` 和含 16–1024 px 表示的 `AppIcon.icns`；沿用现有应用包图标加载方式。
- 深浅色生成稿保存在 `output/imagegen/`。浅色稿仍带浅灰背景，未接入应用；当前不按系统外观切换图标。
- `./script/test_release.sh` 通过：571 项测试、Release 构建、应用启动、签名结构校验和 ZIP 生成。Gatekeeper 仍拒绝现有 ad-hoc 开发签名。
- 图标显示跟进：Dock 固定项指向当前 `dist/SpacePilot.app`，包内 ICNS 与源码哈希一致，`NSWorkspace.icon(forFile:)` 返回新版。已 touch 应用包、强制重新注册 Launch Services、重启 Dock 并重新打开应用。Computer Use 检查 Dock 时超时，尚未确认用户屏幕上的最终显示；若仍显示旧图标，需先确认具体显示位置。

最后更新：2026-09-25

## 仓库检查点

- 当前分支为 `main`，跟踪 `origin/main`。
- 本轮开始时基线为 `main` 的 `34c2369`（PR #5）；当前批次包含 Xcode 容量口径修复和自适应应用图标。
- 当前预览版本：0.1.3。
- 开始工作前仍必须运行 `git status --short --branch` 检查实时状态，不能只依赖本文档。

## 本轮完成

- 追加修复应用大小显示口径：ApplicationRecord 分别保存可选 logicalSize 与 allocatedSize。应用详情和列表的“总大小”使用 Finder 应用大小加关联项当前占用，Xcode 因此约为 15.8 GB；详情另列“磁盘占用”约 10.65 GB，磁盘分类与清理估算继续只使用 allocatedSize。旧快照缺失 logicalSize 时正常解码，按需分析补齐；应用清单缓存版本升级，快照压缩、后台刷新和清理后的记录复制保留新字段。
- 应用大小读取优先使用 Spotlight 的逻辑/物理大小；无索引时完整遍历应用包，包含隐藏文件与内嵌 bundle，保留硬链接去重和取消检查。旧实现会跳过内嵌 package，现已修正。本机无 Spotlight 大小字段时复算 Xcode：logical=9,450,671,065 字节、allocated=4,311,171,072 字节，界面应分别显示 9.45 GB 与计入总占用的 4.31 GB。
- 当前本机快照中，Xcode 的 35 个关联项物理占用为 6,324,056,064 字节；新的“总大小”为 15,774,727,129 字节（约 15.77 GB），“磁盘占用”为 10,635,227,136 字节（约 10.64 GB）。

- 修复 Xcode 详情漏关联 `Library/Developer/Xcode` 开发数据：知识库 1.9.0 使用精确 `com.apple.dt.Xcode` + `59GAB85EFG` 签名 Team，分别关联 DerivedData、iOS DeviceSupport、Archives、UserData。前两项可重建，后两项敏感且不进入默认重置；不把整个 Developer 或共享 CoreSimulator 目录归为 Xcode 专属。
- 组件发现补充 `Contents/Applications` 与 `Contents/Developer/Applications` 两个有界根目录，覆盖 Instruments、Simulator、Icon Composer 等；保持原有深度、数量与符号链接限制，不扫描整个 SDK/Toolchains。身份缓存 token 升级，旧缓存自动重新解析。
- 差异证据：本机 `mdls` 报告 Xcode 逻辑大小 9,450,863,849 字节、物理大小 4,311,171,072 字节，分别对应 App Cleaner 的 9.45 GB 和 SpacePilot 的 4.31 GB。App Cleaner 实际明细中的 `Library/Developer/Xcode` 为 6.33 GB；缺失主体为 iOS DeviceSupport 6,078,169,088 字节、DerivedData 224,808,960 字节、UserData 24,473,600 字节。
- 2026-09-20 本机只读分析器验证：35 个关联项，总磁盘占用 10,648,133,632 字节（约 10.65 GB）。该结果使用真实身份读取、Spotlight、临时目录与知识库分析，不改写用户快照，不清理用户文件。一次性本机探针测试已移除，保留可移植回归测试。
- 2026-09-20 最终 `swift test`：571 项通过，0 失败。新增测试先在旧代码上复现失败，再验证目录容量、敏感数据重置排除、精确身份匹配、伴随应用发现，以及总大小与磁盘占用分离。
- `./script/test_release.sh`：571 项测试、Release 构建、临时启动、签名结构和 ZIP 生成通过；Gatekeeper 仍按预期拒绝 ad-hoc 签名。
- 界面验收限制：构建启动成功，但应用重启后 Computer Use 持续返回 `Sky Computer Use native pipe closed before response`，重置连接仍未恢复；尚未通过真实界面确认刷新后的 Xcode 数值。下一次可用时重新打开 Xcode 详情触发分析，检查新增开发数据与约 10.65 GB 的磁盘占用（缓存和后续文件变化可能带来小幅差异）。

## 上一轮完成（2026-09-18）

- 修复 Spotlight 名称片段(`nameFragment`)查询的跨应用误归因:`SpotlightApplicationCandidateFinder` 新增 `isTrustworthyNameFragmentLocation` 守卫,只有当 artifact 根目录正下方的一级组件本身包含应用名时才接受低置信度名称匹配。拒绝了深埋于别家应用沙箱目录中、仅因文件名含目标应用名子串而被误匹配的文件(如 Stats 应用误归因 Doubao/TRAE 沙箱里的 `pstats.py`、`_stats`)。
- 真机验证:点开 Stats 详情触发重分析后,关联项从 35 项降至 12 项,总空间从 12.29 GB 降至 36.5 MB,所有跨应用误匹配文件全部消失,仅保留 Stats 真实拥有的路径。
- 新增 `testRejectsCrossApplicationNameFragmentMismatches` 定向测试,覆盖真实的 Stats/pstats.py 场景。
- 2026-09-18 验证:`swift test` 561 项通过;4 项 `SafeCLIVersionProbeTests` 失败为本机全局安装 `codex` npm 包干扰 fnm 隔离测试所致,与本改动无关。

## 上一轮完成

- 补充应用关联知识库规则(`contentVersion` 升至 1.8.0,规则数 18 → 20),覆盖此前仅靠低置信度名称匹配归因的两个字节系大体积应用:
  - `product.bytedance.trae-solo-data.v1`:TRAE SOLO CN(`cn.trae.solo.app` + team `CG2SCM6AV5`),覆盖 `Library/Application Support/TRAE SOLO CN`(约 3.6GB)与 `Library/Caches/TRAE SOLO CN`。
  - `product.bytedance.doubaowork-data.v1`:DoubaoWork(`com.work.pc.doubao` + team `96L78H6LMH`),覆盖 `Library/Application Support/DoubaoWork` 与 `Library/Caches/DoubaoWork`。
- 两条规则均用 bundle id + team id 双重匹配防同名冒充;DoubaoWork 与 Doubao 共享 team id,测试断言两条规则严格互斥。
- 真机验证:TRAE SOLO CN 与 DoubaoWork 的主数据目录归因从 `vendorAndNameMatch`(confidence 60)提升为 `knownRule`(confidence 90, ownership owned)。
- 架构确认:知识库规则仅在 `ApplicationDetailAnalyzer.analyze()`(用户点开应用详情)时执行,全量重新扫描走标准解析器、不触发知识库规则,这是既有的性能权衡而非缺陷。
- 2026-09-17 验证:`swift test` 560 项通过;4 项 `SafeCLIVersionProbeTests` 失败同上。

## 更早完成

- 收敛应用发现层对沙箱环境的处理：`RegisteredApplicationDiscovery` 新增 UUID 目录组件判定，Application Support 下路径若含 UUID 形态（8-4-4-4-12 十六进制）的祖先目录，判定为应用生成的临时/隔离运行环境并排除；语义化版本号与 `current` 命名的稳定安装布局不受影响。此规则用结构信号泛化覆盖各类 UUID 沙箱，替代逐个补字符串片段。
- 修复上一轮记录的 DoubaoWork 沙箱环境 `RPADevLocal.app`（`sandbox_envs_dir/envs/<uuid>/override_dlcs/`）被误列为已安装应用的问题。
- 真机验证：重新扫描后 RPADevLocal 从应用清单消失，三个合法 Application Support 应用（Claude Code `.../2.1.260/`、GoogleUpdater `.../152.0.7933.0/`、JetBrains Toolbox Daemon `.../current/`）保留；应用清单从 36 项降为 35 项。
- 新增 `RegisteredApplicationDiscoveryTests` 的 UUID 沙箱排除定向测试，同时断言版本号/current 布局不被误伤。
- 2026-09-17 验证：`swift test` 557 项通过；4 项 `SafeCLIVersionProbeTests` 失败为本机全局安装 `codex` npm 包干扰 fnm 隔离测试所致，与本改动无关，`main` 干净树同样失败。

## 更早完成

- 修复应用发现层把其他应用内嵌工具链里的 `.app` 误当作已安装应用的问题：`RegisteredApplicationDiscovery` 新增两类排除——嵌套在 `.framework`/`.xpc`/`.plugin`/`.appex`/`.bundle` 等 macOS bundle 容器内的 `.app`（如 Python.framework 自带的 Python.app），以及位于 Homebrew 工具链 `/opt/`、`/cellar/` 布局下的 `.app`（如内嵌 Homebrew 环境里的 IDLE、Python Launcher）。
- 真机验证：重新扫描后 TRAE SOLO CN 内嵌 Python 工具链的三个幻影应用（Python、IDLE、Python Launcher）全部从应用清单消失，`org.python.python` 等 owner 及其误归因记录清零；应用清单从 37 项降为 36 项。
- 新增 `RegisteredApplicationDiscoveryTests` 的 bundle 容器嵌套与 Homebrew 工具链两项定向测试。
- 2026-09-16 验证：`swift test` 557 项通过；4 项 `SafeCLIVersionProbeTests` 失败为本机全局安装 `codex` npm 包干扰 fnm 隔离测试所致，与本改动无关，`main` 干净树同样失败。

## 更早完成

- 修复应用深度关联结果被后台“开发与 AI”增量刷新覆盖的问题：非应用范围刷新会按应用路径、Bundle ID、版本和包大小保留最新已保存的关联项与索引项目，不再把 Chrome 等应用退回基础解析器的少量旧数据。
- 应用详情分析与自动刷新改为串行协调；分析期间到达的刷新请求会排队，若用户分析时已有后台旧刷新在运行，则取消旧任务并在分析保存后重跑，避免旧快照后写覆盖新快照。
- 2026-09-13 验证：完整 `swift test` 558 项通过、0 项失败；`./script/test_release.sh` 的 558 项测试、Release 构建、临时启动、应用包、签名结构和 ZIP 检查通过。Gatekeeper 仍按预期拒绝 ad-hoc 签名。

- 开发与 AI 工作区改为单一稳定侧边栏，统一容纳 Agent、MCP、全局 Skill、Plugin、CLI 和其他 AI 工具；Agent 详情补充 MCP、Hook、全局指令、模型与凭据存在性等只读配置能力。
- 新增 AI 健康诊断和确定性分类：识别重复 Skill、异常/失效软链接、大体积占用、外部 Hook 接管和未引用 Skill，并区分普通 CLI、MCP Server、配置管理器、Hook Provider 等辅助工具及安装来源。
- AI 配置扫描与目录发现改为同一后台任务原子发布，取消或过期结果不会覆盖新快照；本地化目录合并为 402 个中英文键。
- 2026-09-09 验证：完整 `swift test` 556 项通过、0 项失败；`./script/test_release.sh` 的 556 项测试、Release 构建、临时启动、应用包、签名结构和 ZIP 检查通过。Gatekeeper 仍按预期拒绝 ad-hoc 签名。

- 扩大已安装应用发现范围：`/Applications` 与当前用户 `Applications` 目录改为有界递归，能够识别 `TeX`、`Python 3.12` 等套件文件夹中的独立 `.app`，但不会进入已有应用包的 `Contents` 把 helper 重复列为应用。
- 新增 Spotlight 注册应用补充来源，覆盖 Application Support 中真实注册的更新器、Agent 和工具链应用；排除构建产物、Script Editor 模板、卸载器和嵌套 helper，并按 Bundle ID 优先保留正式安装位置。
- 应用清单缓存令牌同步纳入套件子目录，向已有套件文件夹新增或删除应用后不会继续命中旧清单；空 Bundle 显示名会回退到 `.app` 文件名。
- 本机重新扫描后应用清单从旧快照的 75 项增加到 93 项，新增识别包括 TeXShop、BibDesk、LaTeXiT、IDLE、GoogleUpdater、Microsoft AutoUpdate、Anaconda Navigator、ApifoxAppAgent、Pulse 工具和 TRAE Computer Use 等。
- 2026-09-09 验证：应用发现定向测试 8 项通过；完整 `swift test` 508 项通过、0 项失败；`./script/test_release.sh` 的 508 项测试、Release 构建、临时启动、应用包、签名结构和 ZIP 检查通过。Gatekeeper 仍按预期拒绝 ad-hoc 签名。

- 扩展应用关联发现：Chrome 使用精确 `com.google.Chrome` 与 `EQHXZ8M8AV` Team 规则补齐 `Library/Application Support/Google/Chrome`、`Library/Caches/Google/Chrome`、产品激活标记和品牌偏好文件；共享 `GoogleUpdater` 主目录不会被声明为 Chrome 独占。
- 新增当前用户临时区候选发现器，只浅层检查 macOS `C/T/X` 根目录，并只接受主应用或已签名组件 Bundle ID 命名空间，可识别 `com.google.Chrome.code_sign_clone`、helper 缓存和带随机后缀的临时目录。
- 临时区结果只通过现有详情分析器进入关联列表，标记为可重新生成；任何重置或卸载仍必须经过已有的选择、确认、路径保护、身份复核和移到废纸篓流程。
- 真实启动后重新分析本机 Chrome：总空间从旧结果 `2.22 GB / 6 项` 更新为 `14.4 GB / 16 项`，与对照工具显示的 `14.39 GB` 基本一致；其中应用支持 `7.43 GB`、常规缓存 `2.47 GB`、代码签名副本 `2.21 GB`，另包含 helper 临时缓存。
- 2026-09-08 验证：`swift test` 503 项通过、0 项失败；`./script/test_release.sh` 的 503 项测试、Release 构建、临时启动、应用包、签名结构和 ZIP 检查通过。Gatekeeper 仍按预期拒绝 ad-hoc 签名。

- 完成 0.1.3 内测稳定阶段：概览新增最近 7 天空间变化摘要，展示新增、变大、已释放、可用空间变化和可安全清理空间，并复用现有最近变化历史，不增加扫描成本。
- 概览在覆盖范围不足时显示不可访问文件夹数量，并提供“打开完全磁盘访问设置”恢复入口；仍保持只报告已验证数据。
- 最近变化的时间范围、变化类型和可清理性筛选增加可见标题与无障碍标识，多个“全部”不再依赖位置猜测含义。
- 应用详情分析改为行内进度与本次运行的完成时间，加载期间保留现有关联列表，不再用居中转圈遮挡内容。
- 新增最近变化摘要计算、应用分析状态、本地化一致性、默认/窄窗口概览边界和控件稳定性回归。
- 2026-09-08 验证：`swift test` 503 项通过、0 项失败；1200×760 与 806×760 AppKit 运行时布局回归通过；`./script/test_release.sh` 的测试、Release 构建、临时启动、应用包、签名结构和 ZIP 检查通过。Gatekeeper 仍按预期拒绝 ad-hoc 签名。

- 概览布局改为响应式双栏工作台：宽窗口左侧为优先清理建议和最近清理，右侧为持续可见的空间详情，两张卡片等宽等高；窄窗口自动回落为上下布局。
- 概览最多预览 4 条优先清理建议，仍保留全部项目数和总可清理空间；最近清理并入左栏，避免空间详情较高时留下大块空白。
- 快捷操作新增“查看最近变化”，直接进入储存空间的最近变化模式；宽窗口保持单行，窄窗口自动使用两列网格。
- 磁盘容量图改为带可用空间中心值和已用/可用/总容量直读数值的紧凑圆环；分类图改为正文级名称、容量与无坐标轴比例条，并将较小类别合并为“其他已分析”。
- 2026-09-03 验证：1180×760、806×760 概览和 1328×965 最近变化跳转状态实际启动检查通过；`swift test` 495 项通过、0 项失败；`./script/test_release.sh` 的测试、Release 构建、启动、应用包、签名结构和 ZIP 检查通过。

- 储存空间借鉴 macOS 系统设置改为整盘分段容量卡，使用颜色图例展示主要已分析分类，并单列已分析、未分析/系统占用和可用空间。
- 修正 `StorageProjection` 的口径：分类列表只保留真实扫描数据，应用包计入容量分类，整盘差额不再注入 `.system` 造成“0 项系统分类”的误导。
- 分类侧栏改为更紧凑的原生图标行，并保留最大项目、旧项目、最近变化、搜索和安全清理工作流。
- 已分析分类栏固定为稳定的 260 pt，避免切换到包含额外筛选器的“最近变化”时被 `HSplitView` 压缩。
- 储存模式导航提到最大项目、旧项目和最近变化共用的常驻父层，并为右侧操作保留固定宽度；切换最近变化时模式导航不再横向跳动，三个筛选器在下方独立响应式排列。
- 最大项目、旧项目和最近变化表格使用原生 `Table` 排序，点击名称、位置、风险/类型、时间或空间列头可切换升序和降序。
- 储存空间加入“最近变化”模式，并提供 24 小时、7 天、30 天以及全部、新增、变大、已删除筛选。
- 单文件新增、增长或删除达到 100 MiB 后单独展示；较小变化在同一事件批次内按目录和类型聚合，达到 100 MiB 后展示；1 GiB 以上变化高亮。
- SQLite schema 升级到 v4，保存变化基线、31 天事件历史、磁盘空间采样和覆盖缺口；10 分钟内同路径同类型事件合并，空间采样限制为最密 15 分钟一次。
- FSEvents 游标与变化记录原子保存，应用关闭期间的事件可在下次启动回放；丢失事件会显示覆盖不足，完整扫描会重新校准基线并关闭开放缺口。
- 最近变化界面继续支持类别和全局搜索过滤、系统文件图标、Finder 定位和中英文界面。
- 最近变化保存可验证的风险级别，并用绿色标记展示可安全清理的当前单项；新增“仅可安全清理”筛选。已删除、聚合或风险未知的记录不会被标为安全。
- 2026-09-05 验证：1433×985 实际运行中用真实鼠标从旧项目切换到最近变化，模式导航前后位置和尺寸均保持 `{x: 1055, y: 323, w: 268, h: 24}`；`swift test` 496 项通过、0 项失败；`./script/test_release.sh` 的测试、Release 构建、启动、应用包、签名结构和 ZIP 检查通过。
- 2026-08-28 验证：`swift test` 491 项通过、0 项失败；`./script/test_release.sh` 的测试、Release 构建、启动、应用包、签名结构和 ZIP 检查通过。

- 概览从图表优先的长列表改为操作仪表盘，顶部展示磁盘状态、可用空间、安全清理建议和本地已分析空间。
- 新增检查安全清理、查看最大项目、查看应用占用和重新扫描快捷操作；复用现有导航与清理确认流程，没有新增数据库或后台服务。
- 安全清理建议提升到主内容区，最近一次清理展示已移动项目数和已验证释放空间，并可跳转清理历史。
- 磁盘容量和类别图表移到次级“空间详情”区域；类别横轴改为可读的 GB/TB 单位。
- 概览使用响应式网格；实际在 806 pt 窗口验证，快捷操作自动两列显示，指标、清理建议和侧边栏没有横向裁切。
- 2026-08-26 验证：`./script/test_release.sh` 完成 366 项测试、Release 构建、临时签名、启动、应用包结构和 ZIP 检查；Gatekeeper 因 ad-hoc 签名拒绝仍属预期。
- 储存空间表格的名称列复用 `FileSystemItemIcon`，显示系统文件夹图标以及可解析的应用图标；图标缓存继续由现有 `NSCache` 管理。
- 开发与 AI 工作区改为本地/远程 Agent 双列表，并保留原生双击 Finder 定位；全局 Skill 和 Plugin 按所有者、范围与项目分组。
- 新增用户批准项目目录的持久化与边界校验，只扫描固定描述文件下的 AI 资产。
- 新增可信安装证据、版本检查、选择计划、确认界面和受控更新执行；不支持、未检查或证据冲突的项目不会进入执行计划。
- 2026-08-28 验证：合并结果完整 `swift test` 481 项通过、0 项失败；`./script/test_release.sh` 的测试、Release 构建、启动、应用包、签名结构和 ZIP 检查通过。

## 建议的下一项任务

在多台真实 Mac 上回归完全磁盘访问授权前后、最近变化的 FSEvents 跨启动回放、删除/重命名、大文件增长和小文件目录聚合，并测量冷启动、应用分析耗时和内存峰值。

## 外部阻塞项

公开分发仍需要项目所有者的 Apple Developer 凭据，用于 Developer ID 签名和公证。不能把只有 ad-hoc 签名的 ZIP 描述为适合普通用户公开安装的版本。

## 交接模板

暂停未完成工作时，用实际内容替换以下模板：

```text
目标：
分支和基础提交：
修改文件：
已经完成的行为：
运行的测试和结果：
已知失败场景或阻塞项：
下一步准确操作：
```

本文档应保持简短和最新。已经完成的详细记录写入 Git 提交；长期架构原因写入 `docs/DECISIONS.md`。
