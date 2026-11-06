import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Window

final class ClassicSettingsWindowController: NSWindowController, NSWindowDelegate {
    static let shared = ClassicSettingsWindowController()

    private var panel: NSPanel?

    private init() {
        super.init(window: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show(appStore: AppStore) {
        if let panel {
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = ClassicSettingsView(
            appStore: appStore,
            onClose: { [weak self] in self?.close() },
            onOpenAdvanced: { [weak self] in
                self?.close()
                AppDelegate.shared?.presentAdvancedSettings()
            }
        )

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 684, height: 465),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "Settings"
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 2)
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: view)
        panel.delegate = self
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.panel = panel
        self.window = panel
    }

    override func close() {
        panel?.close()
        panel = nil
        window = nil
    }

    func windowWillClose(_ notification: Notification) {
        panel = nil
        window = nil
    }
}

// MARK: - Settings view

private enum ClassicSettingsSection: String, CaseIterable, Identifiable {
    case general
    case appearance
    case layout
    case appLocations
    case hiddenApps
    case license
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "通用"
        case .appearance: return "外观"
        case .layout: return "布局"
        case .appLocations: return "应用位置"
        case .hiddenApps: return "已隐藏 App"
        case .license: return "授权"
        case .about: return "关于"
        }
    }
}

private enum HotCornerChoice: String, CaseIterable, Identifiable, Hashable {
    case off
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: return "关闭"
        case .topLeft: return "左上角"
        case .topRight: return "右上角"
        case .bottomLeft: return "左下角"
        case .bottomRight: return "右下角"
        }
    }
}

private enum GestureChoice: String, CaseIterable, Identifiable, Hashable {
    case off
    case four
    case five

    var id: String { rawValue }
    var title: String {
        switch self {
        case .off: return "关闭"
        case .four: return "四指捏合"
        case .five: return "五指捏合"
        }
    }
}

private enum BackgroundChoice: String, CaseIterable, Identifiable, Hashable {
    case systemWallpaper
    case color
    case image

    var id: String { rawValue }
    var title: String {
        switch self {
        case .systemWallpaper: return "系统壁纸"
        case .color: return "纯色"
        case .image: return "图片"
        }
    }
}

struct ClassicSettingsView: View {
    @ObservedObject var appStore: AppStore
    let onClose: () -> Void
    let onOpenAdvanced: () -> Void

    @State private var selected: ClassicSettingsSection = .general
    @State private var alertMessage: String?
    @State private var showResetConfirm = false

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 168)
            Divider()
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 684, height: 465)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
        )
        .alert("提示", isPresented: Binding(
            get: { alertMessage != nil },
            set: { if !$0 { alertMessage = nil } }
        )) {
            Button("好") { alertMessage = nil }
        } message: {
            Text(alertMessage ?? "")
        }
        .confirmationDialog("重置布局？", isPresented: $showResetConfirm, titleVisibility: .visible) {
            Button("重置布局", role: .destructive) { appStore.resetLayout() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将应用顺序和分组恢复默认。")
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(ClassicSettingsSection.allCases) { section in
                Button {
                    selected = section
                } label: {
                    Text(section.title)
                        .font(.system(size: 13))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(selected == section ? Color.accentColor : Color.clear)
                        )
                        .foregroundStyle(selected == section ? Color.white : Color.primary)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.top, 22)
        .padding(.horizontal, 10)
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(selected.title)
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 10)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    detailContent
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button("完成") { onClose() }
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.regular)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        switch selected {
        case .general:
            generalSection
        case .appearance:
            appearanceSection
        case .layout:
            layoutSection
        case .appLocations:
            appLocationsSection
        case .hiddenApps:
            hiddenAppsSection
        case .license:
            licenseSection
        case .about:
            aboutSection
        }
    }

    private var licenseSection: some View {
        LicenseSettingsView()
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
    }

    // MARK: General

    private var generalSection: some View {
        VStack(spacing: 0) {
            settingsRow("开机时自动启动") {
                Toggle("", isOn: $appStore.isStartOnLogin).labelsHidden().toggleStyle(.switch)
            }
            settingsRow("在菜单栏显示图标") {
                Toggle("", isOn: $appStore.showMenuBarIcon).labelsHidden().toggleStyle(.switch)
            }
            settingsRow("将启动台保留在 Dock 中", subtitle: "将启动台保留在 Dock 中，方便快速启动。") {
                Button("添加到 Dock") {
                    if !appStore.addToDock() {
                        alertMessage = "无法自动添加到 Dock。请将 launch.app 拖入 Dock，并选择“保留在 Dock 中”。"
                    }
                }
            }
            settingsRow("在以下位置显示 launch：") {
                picker(appStore.showOnScreenTarget, options: AppStore.ShowOnScreenTarget.allCases) { target in
                    switch target {
                    case .mainScreen: return "主屏幕"
                    case .cursorScreen: return "光标所在屏幕"
                    case .dockScreen: return "Dock 所在屏幕"
                    }
                } onChange: { appStore.showOnScreenTarget = $0 }
            }
            settingsRow("返回首页", subtitle: "选择打开应用时返回首页，还是继续上次的浏览状态。") {
                boolPicker(appStore.rememberLastPage,
                           trueTitle: "保留上次状态",
                           falseTitle: "返回首页") { appStore.rememberLastPage = $0 }
            }
            sectionHeader("快捷键")
            settingsRow("前一页") {
                shortcutField("⌘←")
            }
            settingsRow("后一页") {
                shortcutField("⌘→")
            }
            settingsRow("使用 Option 键轻松分组 App", subtitle: "按住 Option 键拖动 App 进行分组，避免自动排列干扰操作。") {
                Toggle("", isOn: $appStore.optionGroupingEnabled).labelsHidden().toggleStyle(.switch)
            }
            sectionHeader("触发角")
            settingsRow("触发角") {
                picker(hotCornerChoice, options: HotCornerChoice.allCases) { $0.title } onChange: { choice in
                    if choice == .off {
                        appStore.hotCornerEnabled = false
                    } else {
                        appStore.hotCornerEnabled = true
                        switch choice {
                        case .topLeft: appStore.hotCornerPosition = .topLeft
                        case .topRight: appStore.hotCornerPosition = .topRight
                        case .bottomLeft: appStore.hotCornerPosition = .bottomLeft
                        case .bottomRight: appStore.hotCornerPosition = .bottomRight
                        case .off: break
                        }
                    }
                }
            }
            sectionHeader("触控板手势")
            settingsRow("触控板手势") {
                picker(gestureChoice, options: GestureChoice.allCases) { $0.title } onChange: { choice in
                    switch choice {
                    case .off: appStore.gestureEnabled = false
                    case .four:
                        appStore.gestureEnabled = true
                        appStore.gestureFingerCount = .four
                    case .five:
                        appStore.gestureEnabled = true
                        appStore.gestureFingerCount = .five
                    }
                }
            }
            sectionHeader("语言")
            settingsRow("语言") {
                Picker("", selection: $appStore.preferredLanguage) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(appStore.localizedLanguageName(for: language)).tag(language)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 150)
            }
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var hotCornerChoice: HotCornerChoice {
        guard appStore.hotCornerEnabled else { return .off }
        switch appStore.hotCornerPosition {
        case .topLeft: return .topLeft
        case .topRight: return .topRight
        case .bottomLeft: return .bottomLeft
        case .bottomRight: return .bottomRight
        }
    }

    private var gestureChoice: GestureChoice {
        guard appStore.gestureEnabled else { return .off }
        return appStore.gestureFingerCount == .five ? .five : .four
    }

    // MARK: Appearance

    private var appearanceSection: some View {
        VStack(spacing: 0) {
            settingsRow("隐藏程序坞") {
                Toggle("", isOn: $appStore.hideDock).labelsHidden().toggleStyle(.switch)
            }
            settingsRow("背景") {
                picker(backgroundChoice, options: BackgroundChoice.allCases) { $0.title } onChange: { choice in
                    switch choice {
                    case .systemWallpaper:
                        appStore.classicSolidColorEnabled = false
                        appStore.backgroundImageEnabled = true
                        appStore.backgroundImageSource = .desktopPreview
                        appStore.launchpadBackgroundStyle = .blur
                    case .color:
                        appStore.backgroundImageEnabled = false
                        appStore.classicSolidColorEnabled = true
                        appStore.launchpadBackgroundStyle = .glass
                    case .image:
                        appStore.classicSolidColorEnabled = false
                        appStore.backgroundImageEnabled = true
                        appStore.backgroundImageSource = .customImage
                        chooseBackgroundImage()
                    }
                }
            }
            if appStore.classicSolidColorEnabled {
                settingsRow("颜色") {
                    ColorPicker("", selection: Binding(
                        get: {
                            Color(.sRGB,
                                  red: appStore.classicSolidColor.red,
                                  green: appStore.classicSolidColor.green,
                                  blue: appStore.classicSolidColor.blue,
                                  opacity: appStore.classicSolidColor.alpha)
                        },
                        set: { appStore.classicSolidColor = AppStore.RGBAColor($0) }
                    ), supportsOpacity: false)
                    .labelsHidden()
                }
            }
            if appStore.backgroundImageEnabled {
                settingsRow("模糊") {
                    Slider(value: Binding(
                        get: { appStore.classicBackgroundBlur },
                        set: { appStore.classicBackgroundBlur = $0 }
                    ), in: 0...1)
                    .frame(width: 140)
                }
            }
            settingsRow("文字颜色") {
                Picker("", selection: $appStore.classicTextColor) {
                    Text("自动").tag(AppStore.ClassicTextColor.auto)
                    Text("浅色").tag(AppStore.ClassicTextColor.light)
                    Text("深色").tag(AppStore.ClassicTextColor.dark)
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 130)
            }
            settingsRow("隐藏搜索栏中的菜单按钮", subtitle: "可随时通过右键访问菜单") {
                Toggle("", isOn: $appStore.hideSearchMenuButton).labelsHidden().toggleStyle(.switch)
            }
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var backgroundChoice: BackgroundChoice {
        if appStore.classicSolidColorEnabled { return .color }
        if !appStore.backgroundImageEnabled { return .color }
        return appStore.backgroundImageSource == .customImage ? .image : .systemWallpaper
    }

    private func chooseBackgroundImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            appStore.customBackgroundImagePath = url.path
            appStore.backgroundImageEnabled = true
            appStore.backgroundImageSource = .customImage
        }
    }

    // MARK: Layout

    private var layoutSection: some View {
        VStack(spacing: 0) {
            Text("场景用于管理不同的布局方案。你可以创建多个场景，并通过右键菜单快速切换。")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
            if appStore.classicScenes.isEmpty {
                settingsRow("当前布局") {
                    HStack(spacing: 8) {
                        Button("创建默认布局") {
                            appStore.resetLayout()
                            appStore.createClassicScene(named: "默认")
                        }
                        Button("保存为场景") {
                            appStore.createClassicScene(named: "场景 1")
                        }
                    }
                }
            } else {
                ForEach(appStore.classicScenes) { scene in
                    settingsRow(scene.name) {
                        HStack(spacing: 8) {
                            Button(appStore.activeClassicSceneID == scene.id ? "当前" : "切换") {
                                appStore.applyClassicScene(id: scene.id)
                            }
                            .disabled(appStore.activeClassicSceneID == scene.id)
                            Button("删除", role: .destructive) {
                                appStore.deleteClassicScene(id: scene.id)
                            }
                        }
                    }
                }
                settingsRow("场景") {
                    HStack(spacing: 8) {
                        Button("新建场景") {
                            appStore.createClassicScene(named: "场景 \(appStore.classicScenes.count + 1)")
                        }
                        Button("复制当前布局") { appStore.duplicateActiveClassicScene() }
                    }
                }
            }
            settingsRow("行数") {
                sliderInt(value: $appStore.gridRowsPerPage, range: 3...8)
            }
            settingsRow("列数") {
                sliderInt(value: $appStore.gridColumnsPerPage, range: 4...10)
            }
            settingsRow("图标大小") {
                Slider(value: $appStore.classicIconScale, in: 0...1).frame(width: 160)
            }
            settingsRow("App 区域边距", subtitle: "调整 App 区域与屏幕边缘之间的距离，并自动优化整体布局。") {
                Slider(value: $appStore.classicAppAreaPadding, in: 0...1).frame(width: 160)
            }
            settingsRow("自由布局", subtitle: "自由摆放 App 并保留空白位置。关闭后将恢复自动排列。") {
                Toggle("", isOn: $appStore.freeLayoutEnabled).labelsHidden().toggleStyle(.switch)
            }
            settingsRow("紧凑页面", subtitle: "重新排列 App 以填满页面并删除空白页面，从而减少页数。") {
                Button("整理") {
                    appStore.compactItemsWithinPages()
                    appStore.removeEmptyPages()
                    appStore.saveAllOrder()
                }
            }
            settingsRow("重置布局", subtitle: "将应用顺序和分组恢复默认") {
                Button("重置…") { showResetConfirm = true }
            }
            settingsRow("备份布局", subtitle: "将当前布局保存到文件") {
                Button("备份…") { backupLayout() }
            }
            settingsRow("恢复布局", subtitle: "从文件中恢复已保存的布局") {
                Button("恢复…") { restoreLayout() }
            }
            settingsRow("导入旧版启动台布局") {
                Button("导入…") {
                    Task {
                        let result = await appStore.importFromNativeLaunchpad()
                        await MainActor.run { alertMessage = result.message }
                    }
                }
            }
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func backupLayout() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "备份"
        panel.message = "选择备份存放的文件夹。"
        guard panel.runModal() == .OK, let parent = panel.url else { return }
        do {
            let destination = try ClassicBackup.createBackup(to: parent)
            alertMessage = "布局已备份到：\n\(destination.path)"
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    private func restoreLayout() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "恢复"
        panel.message = "选择 launch 备份文件夹。"
        guard panel.runModal() == .OK, let source = panel.url else { return }

        let alert = NSAlert()
        alert.messageText = "恢复布局？"
        alert.informativeText = "当前布局会被备份覆盖，应用随后会自动重启。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "恢复")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try ClassicBackup.restore(from: source)
            alertMessage = "恢复完成，应用将重启。"
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                ClassicBackup.relaunch()
            }
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    private func sliderInt(value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        HStack(spacing: 8) {
            Slider(value: Binding(
                get: { Double(value.wrappedValue) },
                set: { value.wrappedValue = Int($0.rounded()) }
            ), in: Double(range.lowerBound)...Double(range.upperBound), step: 1)
            .frame(width: 120)
            Text("\(value.wrappedValue)")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 22)
        }
    }

    // MARK: App locations

    private var appLocationsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            card(title: "默认应用位置", subtitle: "macOS 安装应用的默认文件夹。") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("/Applications/")
                    Text("~/Applications/")
                    Text("/Users/Shared/Applications/")
                }
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
            }

            card(title: "其他应用位置", subtitle: "添加自定义文件夹，以包含安装在其他位置的应用，例如外置硬盘或自定义目录。") {
                VStack(alignment: .leading, spacing: 8) {
                    if appStore.customAppSourcePaths.isEmpty {
                        Text("暂无文件夹").foregroundStyle(.secondary).font(.system(size: 12))
                    } else {
                        ForEach(Array(appStore.customAppSourcePaths.enumerated()), id: \.offset) { index, path in
                            HStack {
                                Text(path).font(.system(size: 12, design: .monospaced)).lineLimit(1)
                                Spacer()
                                Button("移除") { appStore.removeCustomAppSource(at: index) }
                                    .controlSize(.small)
                            }
                        }
                    }
                    HStack {
                        Button("添加") { chooseAppLocation() }
                        Button("移除") { appStore.resetCustomAppSources() }
                            .disabled(appStore.customAppSourcePaths.isEmpty)
                    }
                    .controlSize(.small)
                }
            }
        }
    }

    private func chooseAppLocation() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            _ = appStore.addCustomAppSource(path: url.path)
        }
    }

    // MARK: Hidden apps

    private var hiddenAppsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            if appStore.hiddenAppPaths.isEmpty {
                Text("暂无隐藏的 App")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 30)
            } else {
                ForEach(Array(appStore.hiddenAppPaths).sorted(), id: \.self) { path in
                    HStack(spacing: 10) {
                        Image(systemName: "app.dashed")
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent)
                                .font(.system(size: 13))
                            Text(path)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Button("取消隐藏") { appStore.unhideApp(path: path) }
                            .controlSize(.small)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    // MARK: About

    private var aboutSection: some View {
        VStack(spacing: 0) {
            settingsRow("版本") {
                Text(versionString)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            settingsRow("检查更新") {
                Button("检查更新…") { appStore.checkForUpdates() }
            }
            settingsRow("高级设置", subtitle: "启动台的 CLI、卸载器、音效、手柄、性能、备份等选项。") {
                Button("高级…") { onOpenAdvanced() }
            }
            settingsRow("邮箱") {
                TextField("name@example.com", text: Binding(
                    get: { appStore.localAccountEmail },
                    set: { appStore.localAccountEmail = $0 }
                ))
                .textFieldStyle(.roundedBorder)
                .frame(width: 190)
            }
        }
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var versionString: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.0.2"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "56"
        return "\(version) (\(build))"
    }

    // MARK: Building blocks

    private func settingsRow<Content: View>(_ title: String,
                                            subtitle: String? = nil,
                                            @ViewBuilder control: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 12.5))
                Spacer(minLength: 12)
                control()
            }
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) {
            Divider().opacity(0.35)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 2)
    }

    private func shortcutField(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, design: .monospaced))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 5))
    }

    private func picker<T: Hashable & Identifiable>(_ value: T,
                                                    options: [T],
                                                    title: @escaping (T) -> String,
                                                    onChange: @escaping (T) -> Void) -> some View {
        Picker("", selection: Binding(get: { value }, set: { onChange($0) })) {
            ForEach(options) { option in
                Text(title(option)).tag(option)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(width: 150)
    }

    private func boolPicker(_ value: Bool,
                            trueTitle: String,
                            falseTitle: String,
                            onChange: @escaping (Bool) -> Void) -> some View {
        Picker("", selection: Binding(get: { value }, set: { onChange($0) })) {
            Text(trueTitle).tag(true)
            Text(falseTitle).tag(false)
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(width: 150)
    }

    private func card<Content: View>(title: String,
                                     subtitle: String? = nil,
                                     @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 12.5, weight: .medium))
            if let subtitle {
                Text(subtitle).font(.system(size: 10.5)).foregroundStyle(.secondary)
            }
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}
