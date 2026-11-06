# BuhoLaunchpad 2.0.2 vs LaunchNext：深度对比与调整清单

> 目标：用 REA 可用的原生元数据/资源/AX/截图证据，重新核对 BuhoLaunchpad 的功能与实现线索，
> 找出 LaunchNext Classic 模式还需要调整的地方。
> 说明：本机没有 Ghidra/Hopper/IDA/Kuna 反编译引擎，**没有函数级伪代码**；以下证据来自
> Mach-O/ObjC/Swift 元数据、Assets.car、Localizable.strings、Core Data、AX 树和运行时截图。

---

## 1. 本轮新增证据

### 1.1 Mach-O / 依赖 / 元数据

- `BuhoLaunchpadServer`：universal（arm64/x86_64），主二进制约 17MB，依赖 AppKit、SwiftUI、
  QuartzCore/Core Animation、Core Data、Combine、SQLite3、SnapKit、KeyboardShortcuts、
  CocoaLumberjack、SkyLight（weak）等。
- ObjC 运行时共 **218 个类**、19 个协议、431 个 ivar 记录、1627 个 dispatch slot。
- 关键类：
  `LaunchpadController`、`LaunchpadWindow`、`LaunchpadContentView`、`LaunchpadPagerView`、
  `LaunchpadPageView`、`LaunchpadGroupView`、`LaunchpadIconItemView`、`LaunchpadAppItemView`、
  `LaunchpadItemNameLabel`、`LaunchpadPageIndicatorItem`、`LaunchpadSearchView`、
  `LaunchpadSearchResult(View/Page)`、`LaunchpadBackgroundView`、`LaunchpadBlurView`、
  `LaunchpadBackgroundImageLoader`、`LaunchpadSceneManager`、`LaunchpadScene`、
  `LaunchpadHotCornerMonitor`、`LaunchpadGestureMonitor`、`SettingsWindow`、`DockPreferences`、
  `SystemLaunchpad`、`AppDataMigrator`、`Uninstaller*`。

### 1.2 关键 ivar（直接反映功能）

`LaunchpadController`：
`_numberOfRows`、`_numberOfColumns`、`_isFreeLayout`、`_appearance`、`_hidesDock`、
`_iconScale`、`_paddingScale`、`_itemLayoutProperties`、`_isLockReorderOnOption`、
`_highlight`、`_apps`、`_olderApps`、`_hiddenApps`、`_groups`、`_darkIconStyle`、
`_showsHiddenAppIcons`、`_isEditing`、`_pendingChanges`、`_responder`、`_draggingItem`、
`_cachedItemViews`、`_reusableAppItemViews`、`_reusableGroupItemViews`、`_reusableSpaceItemViews`。

`LaunchpadSceneManager`：
`_scenes`、`__currentScene`、`_rows`、`_columns`、`_iconScale`、`_paddingScale`、`_isFreeLayout`。

`LaunchpadWindow`：
`windowThemeView`、`windowContentView`、`backgroundView`、`launchpadView`、
`hidesDockCancellable`、`mouseDownView`、`mouseClickCount`、`placement`、
`resetPageStateTimeout`、`closeTime`、`limitedDisplayTimer`、`isShow`、`needShowLimited`、
`redisplayActivationAlert`、`pendingTrigger`、`didChangeOcclusionStateObserver`、
`didActivateApplicationObserver`、`didWakeObserver`、`localMouseDownMonitor`、
`globalMouseDownMonitor`、`animationDuraction`、`animationTimingFunction`、`animationCurve`、
`maxAnimationScale`、`displayLink`、`pinchGesture`、`pinchStartTimestamp`。

`LaunchpadBackgroundView`：
`backgoundType`、`backgroundImageInfo`、`backgoundImage`、`backgroundBlur`、
`backgroundBlurView`、`textColor`、`imageLoader`、`imageQueue`、`requestVersion`、
`imageRequest`、`pendingImageRequest`、`screenChangeWorkItem`、`isBackgroundVisible`、
`backgroundRevision`、`brightnessRevision`、`brightness`、`isResolvingBrightness`、
`textColorResolution`、`context`、`memoryPressureSource`、`wallpaperState`。

`LaunchpadIconItemView`：
`openMethod`、`nameLabel`、`selectedBackgroundLayer`、`isEditing`、`isHighlighted`、
`isSelected`、`backgroundRect`、`iconRect`、`dragChecker`、`editModeWorkItem`。

`LaunchpadContentView`：
`contentSafeAreaInsets`、`containerView`、`pagerView`、`searchResultView`、`searchView`、
`groupItemView`、`groupNameEditor`、`preventsClosingGroupWhileDragging`、`isGroupAnimating`、
`recentSearchText`、`recentSearchResultCount`、`progressCancellable`、`observation`、`isKeyDown`。

### 1.3 Assets.car

BuhoLaunchpadServer 的 Assets.car 很少：
- `AppIcon`、`MenuBarIcon`
- `logo`、`close`、`icon_code`、`icon_copy`、`icon_user`
- 少量 `ZZZZPackedAsset`（激活/购买/引导相关）
- 没有背景壁纸、文件夹图标等大图资源；这些是运行时用系统图标/壁纸/玻璃材质生成的。

说明：我们的 Classic 背景也应优先使用系统壁纸 + 模糊，而不是内置图片；目前已经这样处理。

### 1.4 设置窗口（AX 实测）

Buho 设置窗口为独立面板，6 个分区：
通用、外观、布局、应用位置、已隐藏 App、关于。

通用：
- 开机时自动启动
- 在菜单栏显示图标
- 将 BuhoLaunchpad 保留在 Dock 中 / 添加到 Dock
- 在以下位置显示：Dock 所在屏幕 / 光标所在屏幕 / 主屏幕
- 返回首页 / 保留上次状态
- 快捷键：前一页 ⌘←、后一页 ⌘→
- 使用 Option 键分组
- 触发角
- 触控板手势
- 语言

外观：
- 隐藏程序坞
- 背景：系统壁纸 / 纯色 / 图片
- 模糊
- 文字颜色：自动 / 浅色 / 深色
- 隐藏搜索栏中的菜单按钮

布局：
- 多场景（新建/复制/切换）
- 行数、列数、图标大小、App 区域边距
- 自由布局
- 紧凑页面
- 重置布局
- 备份布局 / 恢复布局
- 导入旧版启动台布局

应用位置：默认 /Applications、~/Applications、/Users/Shared/Applications + 自定义目录。
已隐藏 App：列表 + 取消隐藏。
关于：版本、检查更新。

---

## 2. 当前差距矩阵

| 能力 | Buho 证据 | LaunchNext Classic 现状 | 结论 |
|---|---|---|---|
| 窗口形态/激活 | LSUIElement + 外层 Launcher；窗口 layer 3；激活后全屏 | 显示时切 `.regular` 并激活，隐藏时 `.accessory`；全屏 | 已对齐 |
| 菜单栏隐藏/Dock 保留 | 隐藏菜单栏，Dock 可见 | `NSMenu.setMenuBarVisible` + 不设 hideDock | 已对齐（需实机验证） |
| 背景 | 壁纸快照 + blur + brightness/textColor | 背景控制器 + 壁纸 URL fallback + blur + 压暗 | 已实现，亮度自动文字色仍可增强 |
| 搜索栏 | 窄胶囊、框内菜单按钮、NSSearchField | SwiftUI 窄胶囊、框内菜单、深色玻璃 | 视觉接近，NSSearchField 原生行为未完全复刻 |
| 搜索结果 | 单行 + 选中背景 + 分页 | 单行 + 选中背景 + 分页 | 已实现 |
| 网格 | 7×5、可调行列/图标/边距 | ClassicMetrics 7×5、128pt 图标、可调 | 已实现；像素按系统默认校准 |
| 页点 | 底部居中，选中态 | Classic 6pt 点、居中 | 已实现；位置略高，待微调 |
| 文件夹 | 0.8×0.788 面板、外置标题、7×5 | 比例/标题已有 | 已实现，需实机验收 |
| App 右键 | 显示 Finder / 隐藏 / 移动到分组 | 三项 + Move to Group 子菜单 | 已实现 |
| 空白右键 | 设置/更新/重启/退出 + 场景 | 已有（无购买/激活） | 已实现 |
| 设置窗口 | 独立 684×465、6 分区 | 独立无标题栏 684×465、6 分区 | 已实现，视觉待调 |
| 场景 | SceneManager 保存 rows/cols/iconScale/padding/freeLayout | ClassicScene 已保存这些字段并切换 | 已实现 |
| 自由布局 | `_isFreeLayout` + itemLayoutProperties | 关闭自动补位/压缩，保留空位 | 部分实现；任意坐标未做 |
| Option 分组 | `_isLockReorderOnOption` | Option 拖动只合并、不挤动其他图标 | 已实现 |
| 菜单栏图标 | MenuBarIcon 资源 | NSStatusItem + SF Symbol | 已实现，图标样式可换 |
| Dock 置留 | DockPreferences | 修改 com.apple.dock + killall Dock | 已实现，未实机验证 |
| 多屏显示 | placement: main/cursor/dock | 主屏/光标屏/Dock 屏 | 已实现 |
| 快捷键 | ⌘←/⌘→、Page Up/Down | 已支持 | 已实现；自定义录制未做 |
| 选中背景 | `selectedBackgroundLayer` | 搜索有；主网格键盘选中只放大 | **待补** |
| 编辑态/删除按钮 | `isEditing`、`deleteButton`、`editModeWorkItem` | 无主网格编辑态 | **待确认是否属于可见功能** |
| 亮度/文字色 | `brightness`、`textColorResolution` | 文字色手动切换 + 背景对比度采样 | 部分；自动亮度算法未复刻 |
| 内存压力 | `memoryPressureSource` | 有缓存/性能模式，未专门监听 | 可补 |
| 壁纸变化 | `wallpaperChanged`、`screenChangeWorkItem` | 监听屏幕/空间变化 | 已补 |
| 触控板捏合关闭 | `pinchGesture`、`gestureCloseOnPinchOut` | LaunchNext 有对应开关 | 已具备 |
| 购买/激活 | 激活/购买/试用资源与窗口 | 已移除，只留本地邮箱 | 按约定不做 |

---

## 3. 建议的下一步调整（按优先级）

1. **主网格选中背景层**：在 CA 网格为键盘选中项绘制圆角背景（白色 10–14% + 细边框），
   与 Buho 的 `selectedBackgroundLayer` 对齐。
2. **页点/网格像素校准**：当前页点略高、行距略紧；按 1728×1117 截图继续微调。
3. **文件夹外部标题验收**：CA 面板上方标题的字号/位置与 Buho 截图对齐。
4. **设置窗口视觉验收**：6 分区、控件间距、深/浅色材质、Done 按钮位置。
5. **自由布局**：从“保留空位”升级为可保存每个 item 的自定义坐标（`itemLayoutProperties`）。
6. **NSSearchField 行为**：如需完全 1:1，替换 SwiftUI TextField 为 NSSearchField 包装，
   获得原生清除按钮、焦点环、右键菜单和键盘编辑行为。
7. **亮度自动文字色**：根据壁纸亮度自动选择白/黑文字，而不是只依赖手动设置。
8. **内存压力/壁纸变化**：监听内存压力释放图标缓存；壁纸变化时刷新背景。
9. **菜单栏图标资源**：用 Buho 风格的网格图标替换 SF Symbol（自绘模板图）。
10. **主网格编辑态**：确认 Buho 的删除按钮/编辑态是否用户可见；如是，再补。

---

## 4. 验证方式

- 构建：`xcodebuild -project LaunchNext.xcodeproj -scheme LaunchNext -configuration Debug -derivedDataPath /tmp/launchnext-dd CODE_SIGNING_ALLOWED=NO build`
- 运行：`open -n /tmp/launchnext-dd/Build/Products/Debug/LaunchNext.app`
- 截图：ScreenCaptureKit 按窗口 ID 捕获；或用户提供屏幕照片。
- 对照：同分辨率 1728×1117、浅色/深色各一组；重点看网格、搜索、文件夹、设置窗口。
- 回归：`xcodebuild test -scheme LaunchNext -destination 'platform=macOS'`（本地签名）。

---

## 5. 本轮已调整（2026-11-04）

- 主网格选中背景层：CA 网格现在会在键盘选中项后面绘制圆角半透明底板，
  已通过直接向进程发送方向键 + ScreenCaptureKit 截图验证。
- 图标尺寸：Classic 基准从 84pt 提升到 96pt，并保留设置里的图标大小滑块。
- 搜索：加入 type-to-search（直接键入字母自动进入搜索并聚焦搜索框），为后续 NSSearchField 对齐做准备。
- 场景：保存/恢复 rows、columns、iconScale、padding、freeLayout。
- 背景：新增纯色背景与 ColorPicker；文字颜色设置应用到 CA 网格和搜索结果标签。
- 多屏：Dock 屏选择通过 CGWindowList 定位 Dock 窗口所在屏幕。
- 页键：Page Up / Page Down 翻页；Command+←/→ 保留。
- 壁纸变化/空间切换时重新加载背景兜底。

## 6. 仍需调整

1. 自由布局的任意坐标摆放（当前为网格槽位 + 保留空位）。
2. 文件夹外部标题的字号/位置实机验收。
3. 设置窗口 6 分区的视觉微调（间距、材质、Dock/菜单栏图标资源）。
4. 自动亮度文字色（Buho 的 brightness/textColorResolution 算法）。
5. NSSearchField 原生行为（清除按钮、焦点环、右键菜单）。
6. 主网格编辑态/删除按钮是否属于可见功能待确认。
7. 菜单栏图标使用 Buho 风格的自绘模板图（当前 SF Symbol）。

### 2026-11-04 视觉微调

- 图标基准从 96pt 提升到 **108pt**。
- Classic 顶部留白从 8% 提升到 **13%**，页点上方间距从 89 降到 30，
  网格整体下移，5 行网格更接近 Buho 的垂直位置。
- 通过窗口级 ScreenCaptureKit 截图确认：7 列居中、5 行完整、图标增大、
  背景为当前壁纸模糊、页点在底部。
- 下一轮继续：页点最终位置、文件夹外部标题、设置窗口视觉、自由布局坐标。

### 2026-11-04 文字与图标最终微调

- Classic 图标基准 108pt；网格顶部留白 13%、页点上方间距 30，整体下移。
- 图标标签默认改为**白色**（ClassicTextColor 默认 light），字号 13、字重 semibold。
- 搜索结果标签同步使用 13/semibold/白色。
- 修复 type-to-search 误吞 Page Up/Page Down 等功能键的问题：过滤 0xF700–0xF8FF 功能键区。
- 自测确认：Page Down 能切到下一页；窗口截图确认 7 列居中、5 行、白色加粗标签、108pt 图标。

### 2026-11-04 字号继续放大

- Classic 图标基准 **128pt**。
- 图标标签 **18pt / semibold / 白色**；搜索结果标签同步。
- 修复 `CAGridViewRepresentable.updateNSView` 在每次 SwiftUI 更新时把 Classic 标签字号
  重置成设置里的 11pt 的问题；现在 make/update 两条路径都使用 Classic 的
  `effectiveLabelFontSize` / `effectiveLabelFontWeight`。
- 修复后重新截图确认：7 列居中、5 行完整，图标 128pt，标签实际以 18pt semibold 渲染，
  不再被回退成 11pt。

### 2026-11-05 分组（文件夹）对齐 Buho

通过 BuhoLaunchpadServer 的 `Localizable.strings`、Core Data 分组数据和用户截图核对：

- Buho 新建分组的默认标题是 `Untitled`，简体中文直接显示 **“未命名”**。
  Classic 新建分组现在使用同一套本地化默认名；旧的 `Untitled` 默认名在加载时迁移为当前语言。
- Buho 的 `LaunchpadGroupNameEditor` 支持在分组打开时点击标题直接改名。
  Classic 分组标题现在也是可点击的 `NSTextField`：单击进入编辑，回车提交，Esc 取消。
  之前不可点击的原因是 `CAFolderPresentationHost.hitTest` 只把命中限制在玻璃卡片内，标题在卡片外，
  所以点击被 Host 吞掉了；现在标题区域会优先返回标题控件。
- Buho 分组是**内容自适应高度**的宽卡片，不是接近全屏的卡片；Classic 现在按 7 列、最多 5 行计算行数，
  1 行时最小 340pt，之后每行增加一个图标单元高度。
- 分组内部使用 **7 列**，与主网格一致。
- 打开分组时搜索栏、主网格、页点完全隐藏（之前是 0.1 透明度，仍会透出搜索框的白色胶囊）。
- 关闭分组后不再把分组设置为键盘选中项；之前鼠标关闭分组会留下选中背景卡片，Buho 关闭后回到无选中网格。
- 分组标题与卡片顶部保持约 30pt 间距；之前错误地固定到屏幕顶部搜索栏位置，离卡片过远。

### 2026-11-04 系统 Launchpad 默认尺寸（Dock.app 证据）

通过 `/System/Library/CoreServices/Dock.app/Contents/MacOS/Dock` 的 arm64e 元数据和反汇编确认：

- 默认网格：**7 列 × 5 行**。
- 标签字体：`-[ECSBEnvironment init]` 直接把 `_labelFontSize` 设为 **13pt**
  （`str x8, [x19, #0x18]`，`x8 = 0xd`），`_labelFontType = 105`；
  `-_rebuildLabelFont` 用这个字号创建 CTFont。
- 图标尺寸：不是固定常量，而是
  `+[ECSBGridLayer calculateIconSize:miniIconSize:forBounds:andScaleFactor:withNumberOfRows:andColumns:]`
  按可用区域、行数、列数动态计算；`+[ECSBItemLayer ...]` 先减去标签行高和上下留白，
  再把结果向下取整到 8 的倍数，**下限为 128pt**，最后乘以屏幕 scale。
  在 1728×1117、7×5 的布局下落在 **128pt** 档，因此 Classic 采用 128pt。
- 结论：图标已按系统默认值 **128pt**；标签的系统默认值虽然是 13pt，但用户明确反馈
  13/15/17pt 都偏小，因此 Classic 保留 **18pt semibold**，作为“可读性优先”的覆盖值。
- 上述默认值来自系统 Dock 的 Launchpad/ECSB 代码路径，而非社区猜测的
  `springboard-icon-size` 64px 值。
