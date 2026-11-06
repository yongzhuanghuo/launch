# BuhoLaunchpad 1:1 复刻方案（主界面 + 核心交互）

> 状态：已确认，开始实施。
> 基线：在 `/Users/Admin/project/Launch` 的 **launch** 上改造，不另起项目。
> 参考对象：`/Applications/BuhoLaunchpad.app`（2.0.2，build 56）。
> 本次范围：**全部功能与 UI 交互（1:1 Buho）**，包括主界面、独立设置窗口、右键菜单、多场景、自由布局、紧凑页面、App 位置、隐藏 App、菜单栏图标、Dock 置留、多屏显示、快捷键、备份/恢复、旧版布局导入等。
> 暂缓到 2.0：**购买/试用/激活/许可证/设备绑定/购买页**。不复制 Buho 的专有代码与素材。

---

## 1. 结论摘要

1. **launch 已具备约 70–80% 的底层能力**：应用扫描、图标缓存、7×5 网格、文件夹、拖拽、分页、搜索、壁纸背景、热区、触控板手势、隐藏 App、旧版 Launchpad 导入、备份等。直接重写不划算。
2. 与 BuhoLaunchpad 的主要差距不在功能数量，而在**默认呈现和交互细节**：
   - 默认是紧凑浮窗；Buho 始终全屏、铺满屏幕。
   - 默认不隐藏菜单栏；Buho 隐藏菜单栏但保留 Dock。
   - 默认没有壁纸背景；Buho 是“壁纸快照 + 强模糊 + 轻微压暗”。
   - 搜索框过宽，菜单按钮在搜索框外；Buho 是窄胶囊搜索框，菜单按钮在框内。
   - 搜索结果按整页网格展示；Buho 是单行结果 + 首项选中高亮。
   - 文件夹面板比例、标题位置/字号、页点尺寸与 Buho 不同。
   - 右键菜单是 launch 的超集；Buho 只有少量固定项，且空白处有独立背景菜单。
3. **推荐做法**：在 launch 内增加一个默认开启的 **Classic（Buho 兼容）呈现模式**，复用现有引擎；关闭该模式可回到 launch 原样式，便于对比和回退。不做新 target，不复制 Buho 的代码/素材。
4. **本次全量范围**：主界面 + 核心交互 + 独立设置窗口（6 分区）+ 多场景/自由布局/紧凑页面 + 菜单栏图标/Dock 置留/多屏显示/快捷键 + App 位置/隐藏 App/备份恢复/旧版导入。先保证功能跑通，再做像素校准。
5. **购买/激活全部移除**：不做购买、试用、许可证、设备绑定、购买页。若后续需要身份标识，只保留一个**本地邮箱输入**（不联网、不校验），2.0 再讨论。
6. **预计工期**：全量功能约 **18–25 个工作日**（先功能、后像素）；如果只求功能跑通、暂不追像素，可压缩到 **10–14 天**。

---

## 2. 本次分析的方法与边界

### 2.1 对 BuhoLaunchpad 做了什么

- Bundle 结构、Info.plist、Mach-O 元数据（REA `inspect_macho`）：外层 Launcher（`LSBackgroundOnly`）+ `BuhoLaunchpadServer.app`（`LSUIElement`，Storyboard 启动）+ `Update.app`（Sparkle）。
- 主逻辑在 `BuhoLaunchpadServer.app` 的 Swift 模块 `Launchpad` 中；依赖 AppKit、SwiftUI、QuartzCore/Core Animation、Core Data、SnapKit、KeyboardShortcuts、CocoaLumberjack。
- 从二进制恢复的源码文件名/类型名（证明架构，未获得源码）：
  `LaunchpadController`、`LaunchpadWindow`、`LaunchpadContentView`、`LaunchpadPagerView`、`LaunchpadPageView`、`LaunchpadGroupView`、`LaunchpadGroupPageView`、`LaunchpadItemView`、`LaunchpadAppItemView`、`LaunchpadGroupItemView`、`LaunchpadSearchView`、`LaunchpadSearchResultView`、`LaunchpadBackgroundView`、`LaunchpadBlurView`、`LaunchpadPageIndicatorItem`、`LaunchpadScene/LaunchpadSceneManager`、`LaunchpadSpace`、`LaunchpadRoot`、`LaunchpadLayout`、`LaunchpadHotCornerMonitor`、`LaunchpadGestureMonitor`、`CoreDataStack`、`AppManager`、`AppDeviceMonitor`、`AppTaskQueue`、`Uninstaller*`。
- Core Data 模型：`LaunchpadRoot/LaunchpadSpace/LaunchpadPage/LaunchpadGroup/LaunchpadItem/LaunchpadItemList`、`HiddenAppList`、`AppDirectoryList`、`CachedAppInfo`。当前用户库约 92 个 item、4 个 item list、90 个缓存 App。
- 设置/字符串/本地化、偏好 plist、Core Data 实库、辅助功能（AX）树、运行时截图。
- 观察到的关键行为与尺寸见第 4 节。

### 2.2 局限（必须说明）

- 本机 **没有可用的反编译引擎**：Ghidra 未配置（`GHIDRA_INSTALL_DIR` 为空）、Hopper 未安装、IDA/Kuna 未配置。REA 的 Mach-O 检查、字符串、符号、Core Data、AX、截图可用，但**没有拿到函数级伪代码**。
- 因此本方案的行为结论来自“发布产物元数据 + 运行时 UI 观察”，足以指导重构，但不能保证动画曲线、模糊半径等算法级完全一致；这些需要在实现阶段用截图/录屏逐项校准。
- 如果后续必须做函数级确认，可安装 Ghidra 12.1.x 并设置 `GHIDRA_INSTALL_DIR`（需要你确认下载与安装），或用 Hopper/IDA。此事项不影响本方案启动。
- **清洁室原则**：不复制 Buho 的源码、Assets.car、AppIcon、专有图片/文案素材；只复刻可观察的行为与布局。launch 是 GPLv3，若对外分发需遵守 GPL。

---

## 3. 两个项目的现状

### 3.1 launch（本仓库）

- 入口：[LaunchpadApp.swift](../launch/LaunchpadApp.swift)，`AppDelegate` 创建无边框浮窗（level `.floating`，`isOpaque=false`），默认紧凑模式，可选全屏模式。
- 主界面：[LaunchpadView.swift](../launch/LaunchpadView.swift)，SwiftUI 布局 + 可选 Core Animation 网格（`CAGridView`）。
- 状态/数据：[AppStore.swift](../launch/AppStore.swift)，SwiftData + UserDefaults；`AppInfo`/`FolderInfo` 模型。
- 文件夹：[FolderView.swift](../launch/FolderView.swift)、[CAFolderPresentation.swift](../launch/CAFolderPresentation.swift)、`CAFolderGridView`。
- 搜索：[Search/LaunchpadSearchEngine.swift](../launch/Search/LaunchpadSearchEngine.swift)、[FuzzyMatcher.swift](../launch/Search/FuzzyMatcher.swift)。
- 右键：[RightClickMenu.swift](../launch/RightClickMenu.swift)、[AppContextMenu.swift](../launch/AppContextMenu.swift)、`launchContextMenuCore`。
- 旧版导入：[NativeLaunchpadImporter.swift](../launch/NativeLaunchpadImporter.swift)。
- 壁纸：[BackgroundImageController.swift](../launch/BackgroundImageController.swift)、`launchWallpaperCore`。
- 设置：[SettingsView.swift](../launch/SettingsView.swift)（单 sheet，13 个分区）。
- 当前默认值（新装）：
  - 非全屏（紧凑浮窗 4:3），`hideDock=false`，`hideMenuBar=false`
  - 不启用壁纸背景；背景样式 `glass`
  - 7 列 × 5 行；图标缩放 0.95；标签 11pt；列/行间距 20/14
  - 页点 8pt、可点击区域 28pt 高；页点偏移 27 / 顶部内边距 12
  - 文件夹全屏比例 0.7 × 0.7；文件夹标题在面板内，字号 `.title`
  - 搜索框最大宽 480，右侧有独立刷新/省略号按钮
  - 右键菜单是 Buho 的超集；没有空白处背景菜单

### 3.2 BuhoLaunchpad（参考应用）

- 外层 Launcher 负责拉起 Server；Server 是后台 Agent（`LSUIElement`），主窗口为无边框全屏浮窗（CGWindow layer 3）。
- 采用 AppKit + Core Animation + SwiftUI 混合；文件夹/网格/翻页有独立控制器；壁纸和模糊独立视图；有 Core Data 持久化。
- 设置窗口是独立的居中面板（约 684×465），6 个分区：通用、外观、布局、应用位置、已隐藏 App、关于。
- 主要功能：全屏 Launchpad、搜索（模糊）、7×5 网格、文件夹、分页、拖拽/分组、右键菜单、热区、触控板手势、快捷键、多场景布局、自由布局、紧凑页面、备份/恢复、旧版 Launchpad 导入、隐藏 App、自定义应用目录、Dock 置留、菜单栏图标、开机启动、多屏显示位置、语言。
- 付费/试用/激活/购买、Sparkle 更新、Sentry/统计也存在，但**本次不复刻**。

### 3.3 能力对照（本次范围相关）

| 能力 | Buho 行为 | launch 现状 | 处理 |
|---|---|---|---|
| 窗口形态 | 始终全屏、铺满屏幕（含菜单栏区域） | 默认紧凑浮窗；全屏可选 | Classic 模式默认全屏、无圆角、无外边距 |
| 菜单栏 | 隐藏 | 默认显示；且隐藏菜单栏时会连带隐藏 Dock | 修 `updateSystemUIVisibility`，Classic 模式只隐藏菜单栏、保留 Dock |
| Dock | 默认显示（设置可隐藏） | 默认显示；隐藏菜单栏时被连带隐藏 | 同上；`hideDock=false` |
| 背景 | 壁纸快照 + 强模糊 + 轻微压暗 | 默认无壁纸；样式 glass | 默认启用壁纸/静态预览 + blur；校准模糊/压暗 |
| 搜索框 | 顶部居中，约 252×32pt 胶囊；菜单按钮在框内右侧 | 最大 480pt；刷新/省略号在框外右上 | 新建 Classic 搜索条；隐藏独立按钮 |
| 搜索结果 | 单行最多 7 项，首项选中高亮，无页点 | 过滤后按整页网格展示；仅键盘导航时高亮 | 新增 Classic 搜索结果视图 |
| 网格 | 7×5；图标约 84pt；列距约 193、行距约 178 | 7×5；图标缩放 0.95；间距 20/14；全屏内边距 4%/3.5%/6% | 统一到 `ClassicMetrics` 并校准 |
| 页点 | 底部居中，约 6–8pt，激活白色/未激活半透明 | 8pt，命中区 28pt；偏移/内边距可调 | 收窄视觉尺寸，按截图定位 |
| 文件夹 | 面板约 80% 宽 × 78.8% 高；标题在面板上方约 22pt；7×5 | 全屏 0.7×0.7；标题在面板内 `.title`；支持 paged/vertical | 全屏比例、标题位置/字号、默认 paged |
| App 右键 | 在 Finder 中显示 / 隐藏 App / 移动到分组 ▸ | 超集（复制路径、隔离、卸载、批量、Quick Launch 等） | Classic 模式只显示 3 项；新增“移动到分组”子菜单 |
| 空白右键 | 设置 / 立即购买 / 激活 / 检查更新 / 重启 / 退出 | 无 | 新增背景菜单；去掉购买/激活，保留设置/检查更新/重启/退出 |
| 显示/关闭 | 重新打开切换；App 切换/点击外部/快捷键关闭 | 已有 reopen 切换、resignMain 自动隐藏、热区/手势/快捷键 | 补齐“点击外部 mouse-up 关闭”，回归验证 |
| 设置 | 独立 6 分区窗口 | 单 sheet，13 分区 | 新建 Buho 风格独立设置窗口（通用/外观/布局/应用位置/已隐藏 App/关于）；launch 额外能力收进“高级…”入口 |
| 多场景/自由布局/紧凑页面 | 有 | 无（只有一次性经典预设） | 新增场景模型与切换、自由位置布局、紧凑页面算法 |
| 菜单栏图标/Dock 置留/多屏显示位置 | 有 | 部分缺失 | 新增 NSStatusItem、Dock 置留、主屏/光标屏/Dock 屏选择 |
| 上一页/下一页快捷键、Option 分组 | 有 | 部分缺失 | 新增可配置快捷键；补齐 Option 拖动分组语义 |
| 购买/试用/激活/许可证 | 有 | 无 | **全部移除，不做**；如后续需要身份，只保留本地邮箱输入 |

---

## 4. 主界面与核心交互的实测基线

以下尺寸来自 1728×1117 逻辑分辨率下的截图（截图 1600px 宽，按 1.08 换算，允许 1–2pt 误差）。实现时以 `ClassicMetrics` 集中管理，不散落魔法数字。

### 4.1 主窗口/背景

- 窗口：全屏 1728×1117，覆盖菜单栏；菜单栏不可见；Dock 默认可见（高约 80pt）。
- 背景：桌面壁纸快照，强高斯模糊，轻微压暗/去饱和；没有明显的窗口圆角或外阴影。
- 页面内容在背景之上，无独立卡片边框。

### 4.2 搜索区

- 胶囊搜索框：约 252×32pt，中心 `(864, 80)`；水平居中。
- 左侧放大镜，右侧框内圆形按钮（菜单/清除，随状态切换）；无外部刷新/省略号按钮。
- 占位符“搜索”；输入后左侧出现清除按钮。
- 搜索时页面切换到结果视图，页点隐藏。

### 4.3 网格/图标/标签

- 7 列 × 5 行（默认 35 项/页）。
- 图标边长约 84pt；首列中心 x≈286，末列中心 x≈1442，列距≈193。
- 行中心 y≈173、351、524、697、875，行距≈178。
- 左右安全边距约 286pt；首行距顶部约 130pt（搜索框下方）。
- 标签 11–12pt，白色，居中，单行截断，带轻微阴影。
- 页点：底部居中，y≈1064；圆点约 6–8pt；激活白色，未激活约 55% 白色；页点间距约 15–16pt。

### 4.4 文件夹

- 面板：约 1382×880pt（80% 屏宽 × 78.8% 屏高），圆角约 30pt，居中，玻璃/模糊材质。
- 标题：面板上方居中，约 22pt 半粗，白色带阴影；不是面板内部的大标题。
- 内容：7 列 × 5 行，图标/标签与主网格一致；34 项时无页点，超过 35 项才分页（待用大文件夹验证）。
- 打开方式：单击文件夹图标；Esc 关闭；点击面板外关闭。
- Dock 保持可见。

### 4.5 搜索结果

- 结果只占顶部一行，7 列位置与主网格对齐；不显示页点。
- 首项默认选中，带圆角矩形高亮（浅色玻璃/描边，覆盖图标+标签）。
- 方向键移动选中；Enter 打开；Esc 清空/关闭。
- 搜索基于英文名/别名/模糊匹配；UI 显示本地化名称。
- 超过 7 个结果的分页/滚动行为待补测（用单字母查询验证）。

### 4.6 右键菜单

- App：在 Finder 中显示、隐藏 App、移动到分组 ▸。
- 文件夹（待补测顺序/完整项）：重命名、解散分组等。
- 空白背景：设置、立即购买、激活、检查更新…、重启、退出。
- 菜单为指针附近的浅色玻璃菜单。

### 4.7 显示/关闭生命周期

- 触发：Dock/应用图标重新打开、全局快捷键、热区、触控板手势。
- 关闭：激活了其他 App、点击窗口外部（mouse-up）、Esc（文件夹/搜索）、再次触发热键。
- 再次 `open -a` 是“切换”语义：显示时再开会关闭。

---

## 5. 实现方案

### 5.1 总体策略

在 launch 中新增 **Classic 呈现模式**，默认开启：

- 复用现有 `AppStore`、`AppInfo`、`FolderInfo`、图标缓存、扫描、搜索、拖拽、导入、壁纸、热区/手势。
- 只替换“呈现层 + 部分交互策略”，不重写数据层。
- 保留 launch 原样式作为可切换模式，便于回归对比；额外能力继续留在设置中。
- 所有 Buho 相关常量集中到 `ClassicMetrics`，避免散落。

新增状态建议：

```swift
enum LaunchpadPresentationMode: String, Codable {
    case classic   // Buho 1:1 主界面
    case modern    // launch 原样式
}
```

在 `AppStore` 中持久化 `presentationMode`，新装默认 `.classic`；已有安装通过一次性的 `classicPresentationMigrationV1` 标记应用默认值，**不覆盖用户已经改过的设置**（或由用户在设置中手动切换）。

### 5.2 文件级改动

| 文件 | 改动 |
|---|---|
| [AppStore.swift](../launch/AppStore.swift) | 新增 `presentationMode`、`ClassicMetrics` 默认值/迁移；新装默认全屏、隐藏菜单栏、保留 Dock、启用壁纸 blur、关闭快速刷新、文件夹 paged |
| [LaunchpadApp.swift](../launch/LaunchpadApp.swift) | Classic 模式窗口全屏/无圆角；修复 `updateSystemUIVisibility` 的“隐藏菜单栏连带隐藏 Dock”；对齐 show/hide 关闭触发 |
| [LaunchpadView.swift](../launch/LaunchpadView.swift) | Classic 头部（窄搜索条、框内菜单按钮）、背景压暗/模糊、页点样式、网格指标、搜索结果分支 |
| **新增** `ClassicSearchResultsView.swift` | 单行结果、首项高亮、方向键/Enter/Esc |
| [FolderView.swift](../launch/FolderView.swift) | Classic 文件夹标题在面板上方、22pt；7×5；>35 项才显示页点 |
| [CAFolderPresentation.swift](../launch/CAFolderPresentation.swift) | 全屏比例 0.8×0.788，圆角 30；标题与网格的 inset 对齐 Buho |
| [CAGridView.swift](../launch/CAGridView.swift) / `CAGridView+Layout.swift` | CA 引擎使用同一套 `ClassicMetrics`，保证 SwiftUI/CA 两条路径一致 |
| [RightClickMenu.swift](../launch/RightClickMenu.swift) | Classic 菜单条目过滤；新增空白背景菜单 |
| [AppContextMenu.swift](../launch/AppContextMenu.swift) + `launchContextMenuCore/AppContextMenuModel.swift` | 新增 `.moveToGroup` 动作/标题/路由；Classic 只暴露 3 项 |
| [LaunchpadView.swift](../launch/LaunchpadView.swift) / [CAGridView+Input.swift](../launch/CAGridView+Input.swift) | Option 拖动分组语义；文件夹打开/关闭；点击外部关闭；翻页手势 |
| [SettingsView.swift](../launch/SettingsView.swift) | 只补必要项：Classic/Modern 切换、菜单栏/ Dock 默认行为、背景模糊强度（若没有）；设置结构不重建 |
| `launchTests/*` | 新增 ClassicMetrics、菜单过滤、presentation mode 迁移的单元测试 |

### 5.3 关键实现点

1. **窗口/系统 UI**
   - Classic 模式强制 `isFullscreenMode=true`，窗口 frame 为 `screen.frame`，`cornerRadius=0`。
   - `hideMenuBar=true`、`hideDock=false`：先做 spike 验证 `NSApp.presentationOptions = [.hideMenuBar]` 是否单独生效；若 macOS 强制连带隐藏 Dock，则改为“窗口层级高于菜单栏 + 拦截顶部鼠标”的方案，确保 Dock 仍可见。
   - 关闭逻辑对齐：`applicationShouldHandleReopen` 切换；`windowDidResignMain`/App 激活切换；背景 mouse-up 关闭；Esc 关闭文件夹/搜索。

2. **背景**
   - Classic 默认：`backgroundImageEnabled=true`，`backgroundImageSource=.desktopPreview`（静态预览，不要求屏幕录制权限），`launchpadBackgroundStyle=.blur`，压暗约 0.30–0.35（浅色/深色分别校准）。
   - 若用户允许屏幕录制，可保留桌面实时壁纸源作为可选增强；默认不请求权限。
   - 模糊半径/压暗/饱和度用截图迭代校准，目标与 Buho 截图在缩略图尺寸下肉眼一致。

3. **搜索**
   - 新建窄胶囊搜索条（约 252×32），位置 `(centerX, 80)`；右侧框内按钮：有文字时显示清除，无文字时显示菜单。
   - 菜单按钮弹出 `NSMenu`：设置、检查更新…、重启、退出（不含购买/激活）。
   - 搜索结果使用独立视图：单行 7 列、首项选中、键盘导航、Enter 打开、Esc 清空；不显示页点。
   - 复用 `LaunchpadSearchEngine`，确保英文名/别名/模糊匹配行为与 Buho 接近；补测多结果（>7）行为。

4. **网格/页点**
   - `ClassicMetrics` 提供：列/行、图标尺寸、列距、行距、左右/顶部/底部边距、标签字号、页点尺寸/位置。
   - 先按 4.3 的实测值实现，再用截图叠加对比微调。
   - 页点视觉 6–8pt、命中区可保留 16–28pt；激活/未激活透明度按截图。
   - SwiftUI 与 CA 引擎必须读取同一 metrics；若 CA 引擎难以像素级对齐，Classic 模式默认强制 `useCAGridRenderer`，并只维护该路径。

5. **文件夹**
   - 全屏文件夹面板 0.8×0.788，圆角 30；标题移到面板上方，22pt semibold，白色阴影；面板内 7×5。
   - 默认 `folderLayoutMode=.paged`；>35 项时页点/翻页；<=35 项不显示页点。
   - 保留现有拖拽/重命名/解散逻辑，只改呈现与命中区域。

6. **右键菜单**
   - App：在 Finder 中显示、隐藏 App、移动到分组 ▸（子菜单列出所有文件夹 + “新建分组…”如可行）。
   - 文件夹：重命名、解散分组（按 Buho 补测顺序）。
   - 空白：设置、检查更新…、重启、退出；去掉购买/激活。
   - 用 `AppContextMenuBuilder` 的 capability/profile 过滤，保留现有现代模式菜单。
   - 新增空白背景 `NSMenu`，在 `LaunchpadView` 背景/`CAGridView` 空白区域处理 rightMouseDown。

7. **交互**
   - Option 拖动分组：如果现有拖拽逻辑没有“按住 Option 不挤动其他图标”的语义，新增修饰键分支。
   - 点击面板外 mouse-up 关闭（现有背景点击关闭逻辑改为与 Buho 一致）。
   - 页面翻页：保留现有滚轮/触控板/键盘；确认 ⌘←/⌘→ 或现有导航键行为（Buho 默认 ⌘←/⌘→，本次核心交互可先复用 launch 的键盘导航，快捷键自定义列为后续）。
   - 搜索与文件夹打开时禁用主网格滚动/拖拽，避免状态冲突。

### 5.4 本次明确不做（只保留以下例外）

- **购买/试用/激活/许可证/设备绑定/购买页/统计上报**：全部移除，2.0 再讨论。若后续需要身份标识，只保留本地邮箱输入，不联网、不校验。
- **不复制 Buho 的专有代码、图片、AppIcon、Assets.car 或文案素材**：只复刻可观察的布局与行为；launch 保持 GPLv3。
- 其余功能与 UI 交互**全部纳入本次范围**，包括 5.2 之外的新增项：独立设置窗口、多场景、自由布局、紧凑页面、App 位置、隐藏 App、菜单栏图标、Dock 置留、多屏显示、上一页/下一页快捷键、Option 分组、备份/恢复、旧版布局导入。

---

## 6. 实施计划与排期

| 阶段 | 内容 | 交付物 | 预计 |
|---|---|---|---|
| P0 基线 | 保留 Buho 参考截图/测量；确认构建链；建立截图对比脚本 | 可重复的构建/运行/截图流程 | 0.5 天 |
| P1 窗口/背景/头部 | Classic 模式、全屏铺满、菜单栏/Dock 行为、壁纸 blur/压暗、窄搜索条 | 首屏功能可跑通 | 2 天 |
| P2 网格/页点/文件夹 | ClassicMetrics、7×5 布局、图标/标签/页点、文件夹面板与标题 | 主网格 + 文件夹功能/视觉 | 1.5 天 |
| P3 搜索结果/右键 | 单行搜索结果、首项高亮、键盘；App/文件夹/空白菜单 | 搜索与菜单功能 | 1.5 天 |
| P4 核心交互 | Option 分组、点击外部关闭、翻页、显示/隐藏生命周期 | 核心交互对齐 | 2 天 |
| P5 独立设置窗口 | 6 分区：通用/外观/布局/应用位置/已隐藏 App/关于；“高级…”入口保留额外能力 | 设置窗口可用 | 3–4 天 |
| P6 高级布局 | 场景模型/新建/复制/切换；自由布局；紧凑页面；App 区域边距；布局备份/恢复/导入 | 高级布局功能 | 4–6 天 |
| P7 系统集成 | 菜单栏图标、Dock 置留、主屏/光标屏/Dock 屏选择、上一页/下一页快捷键 | 系统级能力 | 2 天 |
| P8 数据/内容 | App 位置增删、隐藏 App 管理、旧版 Launchpad 导入 UI、背景类型/文字颜色 | 数据与内容管理 | 2 天 |
| P9 默认值/验收 | 新装默认 profile、迁移、截图 diff、性能、回归、多分辨率 | 可验收版本 | 2–3 天 |

**合计：约 18–25 个工作日**（先功能跑通，再做像素校准）。如果只求功能跑通、暂不追像素，可压缩到 **10–14 天**；购买/激活不在其中，2.0 另做。

---

## 7. 如何启动/构建这个项目（已实测）

### 7.1 前置

- macOS 26（当前机器 26.6.2），Xcode 27.2（README 写 Xcode 26；当前版本可用）。
- 不需要付费开发者账号；本地签名即可。

### 7.2 先构建 SwiftUpdater（关键）

直接 `xcodebuild` 会在 `Run Script (Updater)` 阶段失败：

```
error: SwiftUpdater binary not found. Run 'swift build --configuration release --arch arm64 --arch x86_64 --product SwiftUpdater' in UpdaterScripts/SwiftUpdater
```

先执行：

```bash
cd /Users/Admin/project/Launch/UpdaterScripts/SwiftUpdater
swift build --configuration release --arch arm64 --arch x86_64 --product SwiftUpdater
```

### 7.3 Xcode 运行

```bash
open /Users/Admin/project/Launch/launch.xcodeproj
```

1. 选择 scheme `launch`。
2. 运行目标选 **My Mac**，不要选 Any Mac。
3. Signing & Capabilities：Team = None，证书 = Sign to Run Locally（README 的本地签名说明）。
4. `⌘R`。

### 7.4 命令行构建/运行

```bash
cd /Users/Admin/project/Launch

xcodebuild -project launch.xcodeproj \
  -scheme launch \
  -configuration Debug \
  -derivedDataPath /tmp/launch-dd \
  CODE_SIGNING_ALLOWED=NO \
  build

open /tmp/launch-dd/Build/Products/Debug/launch.app
```

- 首次启动会扫描应用并显示 4 步引导；点“跳过引导”或“开始”。
- 扫描/首次构建后窗口可能出现得稍晚，属正常。
- 重建：重复 `xcodebuild` 命令即可。
- 测试：`xcodebuild test -project launch.xcodeproj -scheme launch -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`（若测试宿主需要签名，改用 Xcode 本地签名运行）。
- 常见问题：
  - `SwiftUpdater binary not found` → 先执行 7.2。
  - 窗口不出现 → 看是否有引导页/扫描中；检查 Console 是否被系统 UI 遮挡；用 Dock 图标重新打开。
  - 权限弹窗（屏幕录制/辅助功能）→ Classic 模式默认用静态壁纸预览，尽量避免依赖屏幕录制。

### 7.5 与 Buho 对照

- `open -a /Applications/BuhoLaunchpad.app` 是“重新打开”语义：显示时再执行会关闭。
- 设置：激活 Buho 后使用应用菜单 `BuhoLaunchpadServer > Preferences…`，或背景右键 → 设置。
- 对照时固定分辨率/外观（浅色/深色各一组），截取同尺寸截图叠加比较。

---

## 8. 验收标准

### 8.1 视觉

- [ ] 主窗口铺满屏幕，菜单栏不可见，Dock 默认可见（`hideDock=false`）。
- [ ] 背景为壁纸快照的强模糊 + 压暗，无浮窗圆角/外阴影。
- [ ] 搜索框约 252×32pt、居中 y≈80；菜单按钮在框内右侧；无外部刷新/省略号。
- [ ] 7×5 网格；图标约 84pt；列距≈193、行距≈178；首行 y≈173、末行 y≈875；左右边距≈286。
- [ ] 标签 11–12pt 白色带阴影；页点 y≈1064、6–8pt、激活白色/未激活半透明。
- [ ] 文件夹面板约 80%×78.8%、圆角 30；标题在面板上方约 22pt；7×5；34 项无页点。
- [ ] 搜索结果单行、首项高亮、无页点。
- [ ] App 右键仅 3 项；空白右键为设置/检查更新/重启/退出。

### 8.2 交互

- [ ] 打开：Dock/应用图标 reopen、全局快捷键、热区、手势。
- [ ] 关闭：App 切换、点击外部 mouse-up、Esc（文件夹/搜索）、再次热键。
- [ ] reopen 是切换语义；显示时再开会关闭。
- [ ] 文件夹单击打开、Esc/外部点击关闭；拖入/拖出/重命名/解散正常。
- [ ] Option 拖动分组不挤动其他图标。
- [ ] 搜索：输入即筛选、方向键/Enter/Esc、清空恢复页面。
- [ ] 翻页：滚轮/触控板/键盘；页点点击。
- [ ] 旧版 Launchpad 布局导入后，页面/文件夹/顺序与 Buho 参考一致。

### 8.3 性能/稳定性

- [ ] 翻页/文件夹动画 60fps（或显示器刷新率）；无明显掉帧。
- [ ] 图标/文件夹预览无明显闪烁；内存稳定。
- [ ] 连续开关 50 次无泄漏/卡死；多显示器切换正常。
- [ ] `xcodebuild test` 通过；现有 launch 功能（隐藏 App、导入、备份、卸载器、CLI）无回归。

---

## 9. 风险与限制

| 风险 | 说明 | 对策 |
|---|---|---|
| 菜单栏隐藏 vs Dock 可见 | launch 现有实现隐藏菜单栏时会连带隐藏 Dock；Buho 保留 Dock | 先做 `presentationOptions` spike；必要时改用窗口层级覆盖菜单栏 |
| 壁纸捕获权限 | 实时桌面壁纸需要屏幕录制权限；Buho 可能用私有 API 取壁纸 | 默认静态预览 + 自定义图片；实时壁纸作为可选增强 |
| 像素级动画/模糊 | 没有函数级反编译，模糊半径/动画曲线只能观察 | 截图/录屏迭代校准；把参数集中到 `ClassicMetrics`/外观配置 |
| 双渲染引擎 | SwiftUI 和 CA 网格两套路径可能出现差异 | Classic 模式强制 CA 引擎；或两套共用 metrics 并加截图测试 |
| 文件夹动画交接 | launch 的 CA 玻璃交接逻辑复杂，改比例可能影响动画 | 先改 geometry，再校动画；保留现代模式回退 |
| 商业参考的版权/许可 | Buho 为商业软件；launch 为 GPLv3 | 只复刻行为/布局，不复制代码/素材；对外分发遵守 GPL，不使用 Buho 商标 |
| Buho 版本变化 | 参考为 2.0.2 (56)，后续版本可能改 UI | 以本次截图/尺寸为基线；必要时重新采样 |
| REA 引擎缺失 | 无法函数级反编译 | 需要时安装 Ghidra 12.1.x（需确认），或继续用 UI/字符串证据 |

---

## 10. 已确认范围与实施约定

已确认：

- 基线：**改造 launch**，Classic 模式默认开启，保留 Modern 切换用于回退/对比。
- 范围：**全部功能与 UI 交互**（见第 5 节），先功能跑通，再做像素校准。
- 额外能力：保留在“高级…”入口，不干扰 Buho 风格主界面。
- **购买/试用/激活/许可证/购买页全部移除**；2.0 再讨论。若后续需要身份标识，只用**本地邮箱输入**（不联网、不校验）。
- 实施过程中允许临时修改本机 `UserDefaults` 做校准；不把个人配置写入仓库。

实施顺序按 P0 → P9；每个阶段结束都要求 `xcodebuild` 通过并做一次实机截图/交互检查。P1–P2 先交付可运行的主界面，然后继续设置窗口和高级布局。

---

## 11. 实施进度（本轮）

### 已完成并通过编译

- [x] Classic 模式开关（`isClassicLaunchpad`，默认开启；保留 Modern 回退）
- [x] 全屏铺满、无圆角/外边距；菜单栏隐藏但保留 Dock 的代码路径
- [x] 壁纸背景启用、模糊 + 压暗；窄胶囊搜索框、框内菜单按钮
- [x] 7×5 网格、ClassicMetrics、图标尺寸滑块、App 区域边距滑块
- [x] 页点 Classic 尺寸/位置；搜索时隐藏页点
- [x] 单行搜索结果视图（首项高亮、最多 7 项、鼠标/键盘打开）
- [x] 文件夹面板 0.80×0.788、圆角 30、标题移到面板上方（CA 路径）
- [x] App 右键 Classic 三项：在 Finder 中显示 / 隐藏 App / 移动到分组 ▸
- [x] 空白右键菜单：场景 / 设置 / 检查更新 / 重启 / 退出（无购买/激活）
- [x] 多场景基础模型：保存当前布局、复制、切换、删除；设置页和右键菜单可切换
- [x] 独立 Classic 设置窗口：通用 / 外观 / 布局 / 应用位置 / 已隐藏 App / 关于
- [x] 设置项：开机启动、菜单栏图标、添加到 Dock、显示屏幕、返回首页/保留状态、
      Option 分组开关、触发角、触控板手势、语言、隐藏程序坞、背景类型、模糊、
      文字颜色、隐藏搜索菜单按钮、行列数、图标大小、App 区域边距、自由布局、
      紧凑页面、重置、导入旧版布局、App 位置增删、隐藏 App 管理、检查更新、邮箱
- [x] NSStatusItem 菜单栏图标（显示 Launchpad / 设置 / 检查更新 / 退出）
- [x] Command+←/→ 翻页快捷键
- [x] 自由布局开关会阻止自动补位/压缩（保留空位）
- [x] 构建通过（Xcode 27.2，Debug，CODE_SIGNING_ALLOWED=NO）

### 部分完成 / 待继续

- [ ] Option 拖动“分组但不移动其他图标”的完整交互语义（目前只有设置开关）
- [ ] 自由布局的任意坐标摆放（目前只保留空位，仍按网格槽位排列）
- [ ] 场景的菜单栏图标子菜单/背景菜单完整联动（已有基础切换）
- [ ] 备份/恢复的 Classic 版 UI（当前按钮进入高级设置里的备份面板）
- [ ] 菜单栏隐藏时 Dock 仍可见的实机验证（依赖解锁后的视觉测试）
- [ ] 搜索超过 7 个结果的分页/横向滚动
- [ ] 像素级校准（模糊半径、图标/标签/页点/文件夹标题位置）
- [ ] 多显示器、深浅色、不同分辨率回归

### 当前阻塞

- 分析机屏幕处于锁定状态（锁屏界面），无法进行截图视觉自测；编译与进程级冒烟测试已通过。
  解锁后可以直接运行：
  ```bash
  open /tmp/launch-dd/Build/Products/Debug/launch.app
  ```
  如窗口未出现，使用菜单栏图标或再次 `open` 切换显示。

### 2026-11-03 追加修复

- 修复主网格“看起来有 8 列/不居中”：CA 网格容器未裁剪，左右会露出相邻页图标。
  已在 `CAGridView` 与 `CAFolderBackdropView` 开启 `clipsToBounds`，现在固定 7 列并居中。
- 调整 Classic 垂直布局：去掉网格内部重复的 top/bottom inset；按 Buho 的实测值设置
  页点顶部间距 89、底部偏移 27、底部留白 16，使 5 行网格和页点位置更接近参考。
- 保留 `Command+←/→` 翻页；继续校准背景、文件夹和设置窗口。

### 2026-11-03 继续完成

- 主网格居中：开启 CA 网格裁剪，修复相邻页图标外露导致的“假 8 列/偏移”。
- 垂直布局：Classic 模式按 Buho 实测值重新计算网格与页点间距。
- 背景：当背景控制器没有图像时，直接读取当前桌面壁纸并做模糊，避免出现纯灰背景。
- 搜索结果：超过 7 项时按页展示，首项高亮，页点可点击/键盘切换。
- Option 分组：按住 Option 拖动时只允许合并到目标 App/文件夹，不再挤动其他图标。
- 备份/恢复：Classic 布局页新增原生“备份…/恢复…”（复制 launch 数据目录，恢复后自动重启）。
- 独立 Classic 设置窗口已验证可打开（层 26，684×465，6 个分区）。

待继续：自由布局的任意坐标摆放、搜索/页面像素级校准、文件夹面板与设置窗口的视觉微调、跨 Space/锁屏场景回归。

### 2026-11-03 最终自测补充

- 修复打开时窗口不聚焦/被系统缩成 90% 的问题：显示时切换为 `.regular` 激活策略并激活应用，
  隐藏时切回 `.accessory`。现在启动后 launch 会成为前台全屏窗口。
- 修复背景纯灰：当背景控制器没有图时，直接读取当前桌面壁纸并模糊渲染。
- 搜索框改为深色玻璃胶囊、白色文字/图标，贴近 Buho 的顶部搜索条。
- 设置窗口改为无标题栏 684×465 圆角面板（与 Buho 的独立设置窗口一致）。
- 已完成并通过编译：搜索结果分页、Option 拖动分组、原生备份/恢复、场景切换、菜单栏图标、
  添加到 Dock、显示屏幕选择、Command+←/→ 翻页。

仍需做：自由布局的任意坐标微调、文件夹外部标题在真实窗口中的验收、设置窗口各分区视觉微调、
跨 Space/锁屏/多显示器回归。
