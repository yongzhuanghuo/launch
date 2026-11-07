import AppKit
import Combine
import SwiftUI

// MARK: - 内置卸载器

enum UninstallFileKind: String, CaseIterable, Identifiable {
    case app
    case caches
    case containers
    case preferences
    case appSupport
    case logs
    case savedState
    case webData
    case launchAgents
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .app: return LicenseText.t("应用程序", "Application")
        case .caches: return LicenseText.t("缓存", "Caches")
        case .containers: return LicenseText.t("容器", "Containers")
        case .preferences: return LicenseText.t("偏好设置", "Preferences")
        case .appSupport: return LicenseText.t("支持文件", "Application Support")
        case .logs: return LicenseText.t("日志", "Logs")
        case .savedState: return LicenseText.t("窗口状态", "Saved State")
        case .webData: return LicenseText.t("网页数据", "Web Data")
        case .launchAgents: return LicenseText.t("登录项", "Login Items")
        case .other: return LicenseText.t("其他", "Other")
        }
    }

    var symbol: String {
        switch self {
        case .app: return "app"
        case .caches: return "internaldrive"
        case .containers: return "shippingbox"
        case .preferences: return "slider.horizontal.3"
        case .appSupport: return "folder"
        case .logs: return "doc.text"
        case .savedState: return "macwindow"
        case .webData: return "globe"
        case .launchAgents: return "power"
        case .other: return "questionmark.folder"
        }
    }
}

struct UninstallFileItem: Identifiable {
    let url: URL
    let kind: UninstallFileKind
    let size: Int64
    let fuzzy: Bool
    let appPath: String
    let appName: String
    var selected: Bool = true

    var id: String { appPath + "|" + url.path }

    var displayPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if url.path.hasPrefix(home) {
            return "~" + url.path.dropFirst(home.count)
        }
        return url.path
    }
}

private struct UninstallScanResult {
    var items: [UninstallFileItem]
    var needsFullDiskAccess: Bool
    var errors: [String]
}

@MainActor
final class AppUninstallerModel: ObservableObject {
    let apps: [AppInfo]
    private let appStore: AppStore

    @Published var items: [UninstallFileItem] = []
    @Published var isScanning = true
    @Published var isDeleting = false
    @Published var status = ""
    @Published var errorMessage: String?
    @Published var needsFullDiskAccess = false
    @Published var isRunning = false

    var canUninstall: Bool {
        blockedReason == nil
    }

    var blockedReason: String? {
        for app in apps {
            let path = app.url.standardizedFileURL.path
            if path.hasPrefix("/System/") {
                return LicenseText.t(
                    "\(app.name) 是系统自带应用，不能在这里卸载",
                    "\(app.name) is a system app and cannot be uninstalled here"
                )
            }
            if app.url.standardizedFileURL == Bundle.main.bundleURL.standardizedFileURL {
                return LicenseText.t("不能卸载启动台本身", "启动台 cannot uninstall itself")
            }
        }
        return nil
    }

    init(apps: [AppInfo], appStore: AppStore) {
        self.apps = apps
        self.appStore = appStore
        self.isRunning = apps.contains { Self.runningApplication(for: $0) != nil }
        scan()
    }

    convenience init(app: AppInfo, appStore: AppStore) {
        self.init(apps: [app], appStore: appStore)
    }

    var selectedItems: [UninstallFileItem] { items.filter(\.selected) }
    var selectedSize: Int64 { selectedItems.reduce(0) { $0 + $1.size } }
    var totalSize: Int64 { items.reduce(0) { $0 + $1.size } }

    func scan() {
        isScanning = true
        status = LicenseText.t("正在扫描关联文件…", "Scanning associated files…")
        let apps = self.apps
        Task.detached(priority: .userInitiated) {
            var allItems: [UninstallFileItem] = []
            var needsFDA = false
            var errors: [String] = []
            for app in apps {
                let result = Self.performScan(app: app)
                allItems.append(contentsOf: result.items)
                needsFDA = needsFDA || result.needsFullDiskAccess
                errors.append(contentsOf: result.errors)
            }
            await MainActor.run {
                self.items = allItems
                self.needsFullDiskAccess = needsFDA
                self.errorMessage = errors.first
                self.isScanning = false
                self.status = ""
                self.isRunning = apps.contains { Self.runningApplication(for: $0) != nil }
            }
        }
    }

    func toggleAll(_ selected: Bool) {
        for index in items.indices {
            items[index].selected = selected
        }
    }

    func uninstall() {
        guard !isDeleting, canUninstall else { return }
        let selected = selectedItems
        guard !selected.isEmpty else { return }
        isDeleting = true
        errorMessage = nil
        status = LicenseText.t("正在退出应用…", "Quitting app…")

        Task {
            for app in apps {
                guard let running = Self.runningApplication(for: app) else { continue }
                running.terminate()
                for _ in 0..<20 where running.isTerminated == false {
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
                if !running.isTerminated {
                    running.forceTerminate()
                    try? await Task.sleep(nanoseconds: 300_000_000)
                }
            }

            status = LicenseText.t("正在移到废纸篓…", "Moving to Trash…")
            var failures: [String] = []
            // 先删关联文件，最后删 app 本体。
            let ordered = selected.sorted { lhs, rhs in
                let lhsApp = lhs.kind == .app
                let rhsApp = rhs.kind == .app
                if lhsApp != rhsApp { return !lhsApp }
                return lhs.appPath < rhs.appPath
            }
            for item in ordered {
                do {
                    try FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
                } catch {
                    failures.append("\(item.displayPath): \(error.localizedDescription)")
                }
            }

            appStore.forceFullRescan()
            isDeleting = false
            if failures.isEmpty {
                status = LicenseText.t("卸载完成", "Uninstall complete")
                NSApp.keyWindow?.close()
            } else {
                status = ""
                errorMessage = failures.joined(separator: "\n")
            }
        }
    }

    static func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    private static func runningApplication(for app: AppInfo) -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first { running in
            running.bundleURL?.standardizedFileURL == app.url.standardizedFileURL ||
            (running.bundleIdentifier != nil && running.bundleIdentifier == Bundle(url: app.url)?.bundleIdentifier)
        }
    }

    // MARK: - 扫描

    private nonisolated static func performScan(app: AppInfo) -> UninstallScanResult {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let library = home.appendingPathComponent("Library", isDirectory: true)
        let appURL = app.url.standardizedFileURL
        let bundleID = Bundle(url: appURL)?.bundleIdentifier
        let appName = appURL.deletingPathExtension().lastPathComponent

        var candidates: [(URL, UninstallFileKind, Bool)] = [(appURL, .app, false)]
        var needsFDA = false

        func add(_ url: URL, _ kind: UninstallFileKind, fuzzy: Bool = false) {
            candidates.append((url.standardizedFileURL, kind, fuzzy))
        }

        func addIfExists(_ url: URL, _ kind: UninstallFileKind, fuzzy: Bool = false) {
            var isDirectory: ObjCBool = false
            if fm.fileExists(atPath: url.path, isDirectory: &isDirectory) {
                if isDirectory.boolValue && !fm.isReadableFile(atPath: url.path) {
                    needsFDA = true
                }
                add(url, kind, fuzzy: fuzzy)
            }
        }

        if let bundleID {
            addIfExists(library.appendingPathComponent("Caches/\(bundleID)"), .caches)
            addIfExists(library.appendingPathComponent("Caches/\(bundleID).ShipIt"), .caches)
            addIfExists(library.appendingPathComponent("Containers/\(bundleID)"), .containers)
            addIfExists(library.appendingPathComponent("Application Scripts/\(bundleID)"), .appSupport)
            addIfExists(library.appendingPathComponent("Preferences/\(bundleID).plist"), .preferences)
            addIfExists(library.appendingPathComponent("Application Support/\(bundleID)"), .appSupport)
            addIfExists(library.appendingPathComponent("Application Support/\(bundleID).ShipIt"), .appSupport)
            addIfExists(library.appendingPathComponent("Logs/\(bundleID)"), .logs)
            addIfExists(library.appendingPathComponent("Saved Application State/\(bundleID).savedState"), .savedState)
            addIfExists(library.appendingPathComponent("WebKit/\(bundleID)"), .webData)
            addIfExists(library.appendingPathComponent("HTTPStorages/\(bundleID)"), .webData)
            addIfExists(library.appendingPathComponent("Cookies/\(bundleID).binarycookies"), .webData)
            addIfExists(library.appendingPathComponent("LaunchAgents/\(bundleID).plist"), .launchAgents)

            // ByHost 偏好设置
            let byHost = library.appendingPathComponent("Preferences/ByHost", isDirectory: true)
            if let files = try? fm.contentsOfDirectory(at: byHost, includingPropertiesForKeys: nil) {
                for file in files where file.lastPathComponent.hasPrefix(bundleID + ".") {
                    add(file, .preferences)
                }
            }

            // Group Containers：通常以 group.<bundleID> 命名
            let groups = library.appendingPathComponent("Group Containers", isDirectory: true)
            if let dirs = try? fm.contentsOfDirectory(at: groups, includingPropertiesForKeys: nil) {
                for dir in dirs where dir.lastPathComponent.localizedCaseInsensitiveContains(bundleID) {
                    add(dir, .containers)
                }
            }

            // 诊断报告：只匹配完整 bundle id 或应用名
            let diagnostic = library.appendingPathComponent("Logs/DiagnosticReports", isDirectory: true)
            if let files = try? fm.contentsOfDirectory(at: diagnostic, includingPropertiesForKeys: nil) {
                for file in files where file.lastPathComponent.localizedCaseInsensitiveContains(bundleID) {
                    add(file, .logs)
                }
            }

            // 应用别名/应用目录中的同名副本
            let userApps = home.appendingPathComponent("Applications", isDirectory: true)
            let alias = userApps.appendingPathComponent("\(appName).app")
            if alias.standardizedFileURL != appURL {
                addIfExists(alias, .other, fuzzy: true)
            }
        }

        // 名称匹配的支持目录：可能误伤，标为低置信度。
        let nameCandidates: [(URL, UninstallFileKind)] = [
            (library.appendingPathComponent("Caches/\(appName)"), .caches),
            (library.appendingPathComponent("Application Support/\(appName)"), .appSupport),
            (library.appendingPathComponent("Logs/\(appName)"), .logs),
        ]
        for (url, kind) in nameCandidates {
            var isDirectory: ObjCBool = false
            if fm.fileExists(atPath: url.path, isDirectory: &isDirectory) {
                addIfExists(url, kind, fuzzy: true)
            }
        }

        var seen = Set<String>()
        var items: [UninstallFileItem] = []
        for (url, kind, fuzzy) in candidates {
            let key = url.path
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            guard fm.fileExists(atPath: url.path) else { continue }
            items.append(
                UninstallFileItem(
                    url: url,
                    kind: kind,
                    size: directorySize(url),
                    fuzzy: fuzzy,
                    appPath: appURL.path,
                    appName: app.name
                )
            )
        }
        items.sort {
            if $0.kind == $1.kind { return $0.url.path < $1.url.path }
            return UninstallFileKind.allCases.firstIndex(of: $0.kind)! <
                UninstallFileKind.allCases.firstIndex(of: $1.kind)!
        }
        return UninstallScanResult(items: items, needsFullDiskAccess: needsFDA, errors: [])
    }

    private nonisolated static func directorySize(_ url: URL) -> Int64 {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return 0 }
        if !isDirectory.boolValue {
            return (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        }
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in enumerator {
            guard let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true else { continue }
            total += Int64(values.fileSize ?? 0)
        }
        return total
    }
}

struct AppUninstallerView: View {
    @ObservedObject var model: AppUninstallerModel
    @State private var showConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(nsImage: model.apps[0].icon)
                    .resizable()
                    .frame(width: 56, height: 56)
                    .overlay(alignment: .bottomTrailing) {
                        if model.apps.count > 1 {
                            Text("\(model.apps.count)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(4)
                                .background(Color.red, in: Circle())
                                .offset(x: 4, y: 4)
                        }
                    }
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.apps.count == 1
                         ? LicenseText.t("卸载 \(model.apps[0].name)", "Uninstall \(model.apps[0].name)")
                         : LicenseText.t("卸载 \(model.apps.count) 个应用", "Uninstall \(model.apps.count) apps"))
                        .font(.system(size: 20, weight: .bold))
                    Text(model.apps.count == 1
                         ? model.apps[0].url.path
                         : model.apps.map(\.name).joined(separator: "、"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    if model.isRunning {
                        Label(
                            LicenseText.t("应用正在运行，卸载前会自动退出", "The app is running and will be quit before uninstalling"),
                            systemImage: "exclamationmark.triangle"
                        )
                        .font(.caption)
                        .foregroundStyle(.orange)
                    }
                }
                Spacer()
            }

            if let blocked = model.blockedReason {
                Label(blocked, systemImage: "nosign")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.red)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            }

            if model.needsFullDiskAccess {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "lock.shield")
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(LicenseText.t("部分系统文件需要“完全磁盘访问权限”", "Some system files require Full Disk Access"))
                            .font(.subheadline.weight(.semibold))
                        Text(LicenseText.t("如果关联文件列表不完整，请在系统设置中给启动台开启完全磁盘访问权限后重新扫描。", "If the related file list looks incomplete, grant launch Full Disk Access and rescan."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(LicenseText.t("打开设置", "Open Settings")) {
                        AppUninstallerModel.openFullDiskAccessSettings()
                    }
                }
                .padding(12)
                .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            }

            if model.isScanning {
                VStack(spacing: 12) {
                    ProgressView()
                    Text(LicenseText.t("正在扫描关联文件…", "Scanning associated files…"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(model.apps) { app in
                            let groups = UninstallFileKind.allCases.compactMap { kind -> (UninstallFileKind, [UninstallFileItem])? in
                                let items = model.items.filter { $0.appPath == app.url.path && $0.kind == kind }
                                return items.isEmpty ? nil : (kind, items)
                            }
                            if !groups.isEmpty {
                                if model.apps.count > 1 {
                                    Text(app.name)
                                        .font(.system(size: 13, weight: .semibold))
                                }
                                ForEach(groups, id: \.0) { kind, items in
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(kind.title)
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(.secondary)
                                        ForEach(items) { item in
                                            fileRow(item)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: .infinity)
            }

            if let error = model.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(4)
            }

            HStack(spacing: 12) {
                Text(LicenseText.t(
                    "已选 \(model.selectedItems.count) 项，共 \(formatBytes(model.selectedSize))",
                    "\(model.selectedItems.count) selected, \(formatBytes(model.selectedSize))"
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
                Spacer()
                Button(LicenseText.t("全选", "Select All")) { model.toggleAll(true) }
                Button(LicenseText.t("全不选", "Select None")) { model.toggleAll(false) }
                Button(LicenseText.t("取消", "Cancel")) { NSApp.keyWindow?.close() }
                Button(model.isDeleting
                       ? LicenseText.t("正在卸载…", "Uninstalling…")
                       : LicenseText.t("移到废纸篓", "Move to Trash")) {
                    showConfirm = true
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(model.isDeleting || model.selectedItems.isEmpty || !model.canUninstall)
            }

            if model.isDeleting {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(20)
        .frame(width: 620, height: 560)
        .alert(model.apps.count == 1
               ? LicenseText.t("确认卸载 \(model.apps[0].name)？", "Uninstall \(model.apps[0].name)?")
               : LicenseText.t("确认卸载 \(model.apps.count) 个应用？", "Uninstall \(model.apps.count) apps?"),
               isPresented: $showConfirm) {
            Button(LicenseText.t("取消", "Cancel"), role: .cancel) {}
            Button(LicenseText.t("移到废纸篓", "Move to Trash"), role: .destructive) {
                model.uninstall()
            }
        } message: {
            Text(LicenseText.t(
                "选中的 \(model.selectedItems.count) 项会移到废纸篓，共 \(formatBytes(model.selectedSize))。此操作可以撤销。",
                "\(model.selectedItems.count) selected items (\(formatBytes(model.selectedSize))) will be moved to the Trash. You can undo this."
            ))
        }
    }

    @ViewBuilder
    private func fileRow(_ item: UninstallFileItem) -> some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(
                get: { item.selected },
                set: { newValue in
                    guard let index = model.items.firstIndex(where: { $0.id == item.id }) else { return }
                    model.items[index].selected = newValue
                }
            ))
            .labelsHidden()
            Image(systemName: item.kind.symbol)
                .frame(width: 16)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.url.lastPathComponent)
                    .font(.system(size: 12))
                Text(item.displayPath)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if item.fuzzy {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help(LicenseText.t("按名称匹配，可能不属于此应用，请确认后再删除", "Matched by name; verify before deleting"))
            }
            Spacer()
            Text(formatBytes(item.size))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

@MainActor
final class AppUninstallerWindowController: NSWindowController {
    static let shared = AppUninstallerWindowController()
    private var model: AppUninstallerModel?

    private init() {
        super.init(window: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(app: AppInfo, appStore: AppStore) {
        show(apps: [app], appStore: appStore)
    }

    func show(apps: [AppInfo], appStore: AppStore) {
        close()
        guard !apps.isEmpty else { return }
        let model = AppUninstallerModel(apps: apps, appStore: appStore)
        self.model = model
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: apps.count > 1 ? 620 : 560),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = apps.count == 1
            ? LicenseText.t("卸载 \(apps[0].name)", "Uninstall \(apps[0].name)")
            : LicenseText.t("卸载 \(apps.count) 个应用", "Uninstall \(apps.count) apps")
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: AppUninstallerView(model: model))
        window.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 2)
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.center()
        self.window = window
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }
}
