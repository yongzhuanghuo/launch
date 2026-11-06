import Foundation
import AppKit
import SwiftData
import SQLite3

/// 直接从 macOS 原生 Launchpad 数据库导入布局
class NativeLaunchpadImporter {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    static func nativeLaunchpadDatabasePath() throws -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/getconf")
        task.arguments = ["DARWIN_USER_DIR"]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        try task.run()
        task.waitUntilExit()

        guard task.terminationStatus == 0 else {
            throw ImportError.systemError("Failed to get user directory path")
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let userDir = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        return "/private\(userDir)com.apple.dock.launchpad/db/db"
    }

    static func hasNativeLaunchpadDatabase() -> Bool {
        guard let path = try? nativeLaunchpadDatabasePath() else { return false }
        return FileManager.default.fileExists(atPath: path)
    }

    static func hasImportableNativeLaunchpadDatabase() -> Bool {
        guard let path = try? nativeLaunchpadDatabasePath(),
              FileManager.default.fileExists(atPath: path) else { return false }

        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            return false
        }
        defer { sqlite3_close(db) }

        return schemaTableExists(in: db, name: "apps")
            && schemaTableExists(in: db, name: "groups")
            && schemaTableExists(in: db, name: "items")
    }

    private static func schemaTableExists(in db: OpaquePointer?, name: String) -> Bool {
        let query = "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name = ?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(stmt) }

        name.withCString { cstr in
            let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            _ = sqlite3_bind_text(stmt, 1, cstr, -1, SQLITE_TRANSIENT)
        }

        if sqlite3_step(stmt) == SQLITE_ROW {
            return sqlite3_column_int(stmt, 0) > 0
        }
        return false
    }

    /// 从原生 Launchpad 数据库导入布局
    func importFromNativeLaunchpad() throws -> ImportResult {
        let nativeLaunchpadDB = try getNativeLaunchpadDatabasePath()

        // 检查数据库是否存在和可访问
        guard FileManager.default.fileExists(atPath: nativeLaunchpadDB) else {
            throw ImportError.databaseNotFound("Native Launchpad database not found")
        }

        // 解析数据库
        let launchpadData = try parseLaunchpadDatabase(at: nativeLaunchpadDB)

        // 转换并保存到 launch 格式
        let result = try convertAndSave(launchpadData: launchpadData)

        return result
    }

    /// 从指定的数据库路径导入（适配旧版 apps/groups/items 架构）
    func importFromDatabasePath(_ dbPath: String) throws -> ImportResult {
        guard FileManager.default.fileExists(atPath: dbPath) else {
            throw ImportError.databaseNotFound("Database not found: \(dbPath)")
        }
        let data = try parseLaunchpadDatabase(at: dbPath)
        return try convertAndSave(launchpadData: data)
    }

    /// 从旧版归档（.lmy/.zip）导入：归档中包含名为 db 的 SQLite 文件
    func importFromLegacyArchive(at url: URL) throws -> ImportResult {
        let fm = FileManager.default
        let ext = url.pathExtension.lowercased()

        // 如果直接给的是 SQLite 文件
        if ext == "db" {
            return try importFromDatabasePath(url.path)
        }

        // 仅支持 .lmy/.zip
        guard ext == "lmy" || ext == "zip" else {
            throw ImportError.systemError("Unsupported file type: .\(ext)")
        }

        let tmpDir = fm.temporaryDirectory.appendingPathComponent("LNImport_\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmpDir) }

        // 使用系统 unzip 解压
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        task.arguments = ["-o", url.path, "-d", tmpDir.path]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        try task.run()
        task.waitUntilExit()
        guard task.terminationStatus == 0 else {
            throw ImportError.systemError("Unzip failed")
        }

        let dbPath = tmpDir.appendingPathComponent("db").path
        guard fm.fileExists(atPath: dbPath) else {
            throw ImportError.databaseNotFound("db file not found in archive")
        }

        return try importFromDatabasePath(dbPath)
    }

    // MARK: - 私有方法

    /// 获取原生 Launchpad 数据库路径
    private func getNativeLaunchpadDatabasePath() throws -> String {
        try Self.nativeLaunchpadDatabasePath()
    }

    private func parseLaunchpadDatabase(at dbPath: String) throws -> LaunchpadData {
        var db: OpaquePointer?
        guard sqlite3_open_v2(dbPath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            throw ImportError.databaseError("Failed to open native Launchpad database")
        }
        defer { sqlite3_close(db) }

        // 打印数据库里有哪些表，便于兼容不同 macOS 版本
        logAllTables(in: db)

        // 快速自检：检查我们依赖的三张表是否存在
        let hasLegacySchema =
            tableExists(in: db, name: "apps") &&
            tableExists(in: db, name: "groups") &&
            tableExists(in: db, name: "items")
        guard hasLegacySchema else {
            // Currently only legacy schema supported; provide table list to adapt Z*-based schema
            throw ImportError.databaseError("Non-legacy schema detected. Please provide table list for adaptation.")
        }

        // 解析应用
        let apps = try parseApps(from: db)
        print("📱 Found \(apps.count) apps")

        // 解析文件夹
        let groups = try parseGroups(from: db)
        print("📁 Found \(groups.count) folders")

        // 解析层级结构
        let items = try parseItems(from: db)
        print("🗂 Found \(items.count) layout items")

        return LaunchpadData(apps: apps, groups: groups, items: items)
    }

    // MARK: - 数据库结构探测
    private func logAllTables(in db: OpaquePointer?) {
        let query = "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name;"
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK {
            var names: [String] = []
            defer { sqlite3_finalize(stmt) }
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let cName = sqlite3_column_text(stmt, 0) {
                    names.append(String(cString: cName))
                }
            }
            print("🧩 Tables in native DB: \(names.joined(separator: ", "))")
        }
    }

    private func tableExists(in db: OpaquePointer?, name: String) -> Bool {
        let query = "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name = ?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(stmt) }
        name.withCString { cstr in
            let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            _ = sqlite3_bind_text(stmt, 1, cstr, -1, SQLITE_TRANSIENT)
        }
        if sqlite3_step(stmt) == SQLITE_ROW {
            let count = sqlite3_column_int(stmt, 0)
            return count > 0
        }
        return false
    }

    private func parseApps(from db: OpaquePointer?) throws -> [String: LaunchpadDBApp] {
        var apps: [String: LaunchpadDBApp] = [:]
        let query = "SELECT item_id, title, bundleid, storeid FROM apps"
        var stmt: OpaquePointer?

        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
            throw ImportError.databaseError("Failed to query apps table")
        }
        defer { sqlite3_finalize(stmt) }

        while sqlite3_step(stmt) == SQLITE_ROW {
            let itemId = String(sqlite3_column_int(stmt, 0))

            // 安全获取字符串，处理 NULL 值
            let title = sqlite3_column_text(stmt, 1) != nil
                ? String(cString: sqlite3_column_text(stmt, 1))
                : "Unknown App"

            let bundleId = sqlite3_column_text(stmt, 2) != nil
                ? String(cString: sqlite3_column_text(stmt, 2))
                : ""

            if bundleId == "com.apple.Maps" || bundleId == "com.apple.Music" {
                print("[Importer][Debug] bundleId=\(bundleId) title=\(title)")
            }

            apps[itemId] = LaunchpadDBApp(
                itemId: itemId,
                title: title,
                bundleId: bundleId
            )
        }

        return apps
    }

    private func parseGroups(from db: OpaquePointer?) throws -> [String: LaunchpadGroup] {
        var groups: [String: LaunchpadGroup] = [:]
        let query = "SELECT item_id, title FROM groups"
        var stmt: OpaquePointer?

        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
            throw ImportError.databaseError("Failed to query groups table")
        }
        defer { sqlite3_finalize(stmt) }

        while sqlite3_step(stmt) == SQLITE_ROW {
            let itemId = String(sqlite3_column_int(stmt, 0))
            let title = sqlite3_column_text(stmt, 1) != nil
                ? String(cString: sqlite3_column_text(stmt, 1))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                : "Untitled"

            groups[itemId] = LaunchpadGroup(
                itemId: itemId,
                title: title.isEmpty ? "Untitled" : title
            )
        }

        return groups
    }

    private func parseItems(from db: OpaquePointer?) throws -> [LaunchpadDBItem] {
        var items: [LaunchpadDBItem] = []
        let query = """
            SELECT rowid, uuid, flags, type, parent_id, ordering
            FROM items
            ORDER BY parent_id, ordering
        """
        var stmt: OpaquePointer?

        guard sqlite3_prepare_v2(db, query, -1, &stmt, nil) == SQLITE_OK else {
            throw ImportError.databaseError("Failed to query items table")
        }
        defer { sqlite3_finalize(stmt) }

        while sqlite3_step(stmt) == SQLITE_ROW {
            let rowId = String(sqlite3_column_int(stmt, 0))
            let type = sqlite3_column_int(stmt, 3)
            let parentId = sqlite3_column_int(stmt, 4)
            let ordering = sqlite3_column_int(stmt, 5)

            items.append(LaunchpadDBItem(
                rowId: rowId,
                type: Int(type),
                parentId: Int(parentId),
                ordering: Int(ordering)
            ))
        }

        return items
    }

    private func convertAndSave(launchpadData: LaunchpadData) throws -> ImportResult {
        print("🔄 Start converting data...")

        // 为便于定位，先构建父子索引
        var childrenByParent: [Int: [LaunchpadDBItem]] = [:]
        for item in launchpadData.items { childrenByParent[item.parentId, default: []].append(item) }
        for key in childrenByParent.keys { childrenByParent[key]?.sort { $0.ordering < $1.ordering } }

        // 1) 顶层容器（即顶层页组）：parent_id = 1, type = 3
        let topContainers = launchpadData.items
            .filter { $0.type == 3 && $0.parentId == 1 }
            .sorted { $0.ordering < $1.ordering }

        #if DEBUG
        print("🧭 顶层容器顺序: \(topContainers.map{ $0.rowId }.joined(separator: ", "))")
        #endif

        // 清空现有数据
        try clearExistingData()
        print("🗑 Clearing existing layout data")

        var convertedApps = 0
        var convertedFolders = 0
        var failedApps: [String] = []

        // 2) 逐个顶层容器构建页面
        for (pageIndex, container) in topContainers.enumerated() {
            let containerId = Int(container.rowId) ?? 0
            let direct = (childrenByParent[containerId] ?? [])
            let directApps = direct.filter { $0.type == 4 }
            let folderPages = direct.filter { $0.type == 2 }

            // 本页最大位置 = 两类条目的 ordering 最大值
            let maxPos = max(directApps.map{ $0.ordering }.max() ?? -1,
                             folderPages.map{ $0.ordering }.max() ?? -1)

            print("📄 Page #\(pageIndex + 1): apps=\(directApps.count), folderPages=\(folderPages.count), maxPos=\(maxPos)")

            var occupied = Set<Int>()

            // 2.1) 放置直接应用
            for appItem in directApps {
                if let app = launchpadData.apps[appItem.rowId],
                   let appInfo = findLocalApp(bundleId: app.bundleId, title: app.title) {
                    try saveAppToPosition(appInfo: appInfo, pageIndex: pageIndex, position: appItem.ordering)
                    occupied.insert(appItem.ordering)
                    convertedApps += 1
                } else {
                    try saveEmptySlot(pageIndex: pageIndex, position: appItem.ordering)
                    occupied.insert(appItem.ordering)
                    failedApps.append(launchpadData.apps[appItem.rowId]?.title ?? appItem.rowId)
                }
            }

            // 2.2) 放置文件夹（由子页 type=2 表示）
            for page in folderPages {
                let folderNameRaw = (launchpadData.groups[page.rowId]?.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let pageId = Int(page.rowId) ?? 0
                let slotContainers = (childrenByParent[pageId] ?? []).filter { $0.type == 3 }
                var folderAppInfos: [AppInfo] = []
                for sc in slotContainers {
                    let scId = Int(sc.rowId) ?? 0
                    for child in (childrenByParent[scId] ?? []) where child.type == 4 {
                        if let app = launchpadData.apps[child.rowId],
                           let info = findLocalApp(bundleId: app.bundleId, title: app.title) {
                            folderAppInfos.append(info)
                        }
                    }
                }

                let finalName: String
                if isPlaceholderFolderTitle(folderNameRaw) {
                    // 用 DB 内的应用标题生成
                    var names: [String] = []
                    for sc in slotContainers {
                        let scId = Int(sc.rowId) ?? 0
                        for child in (childrenByParent[scId] ?? []) where child.type == 4 {
                            if let app = launchpadData.apps[child.rowId] {
                                let t = app.title.trimmingCharacters(in: .whitespacesAndNewlines)
                                if !t.isEmpty { names.append(t) }
                            }
                        }
                    }
                    let top = Array(names.prefix(3))
                    if top.isEmpty { finalName = "Untitled" }
                    else if top.count == 1 { finalName = top[0] }
                    else if top.count == 2 { finalName = top[0] + " + " + top[1] }
                    else { finalName = top[0] + " + " + top[1] + " + …" }
                } else {
                    finalName = folderNameRaw
                }

                try saveFolderToPosition(name: finalName, apps: folderAppInfos, pageIndex: pageIndex, position: page.ordering)
                occupied.insert(page.ordering)
                convertedFolders += 1
            }

            // 2.3) 补齐空位
            if maxPos >= 0 {
                for pos in 0...maxPos where !occupied.contains(pos) {
                    try saveEmptySlot(pageIndex: pageIndex, position: pos)
                }
            }
        }

        try modelContext.save()
        print("💾 Save completed")

        let result = ImportResult(convertedApps: convertedApps, convertedFolders: convertedFolders, failedApps: failedApps)
        print("✅ Import finished: \(convertedApps) apps, \(convertedFolders) folders")
        if !failedApps.isEmpty { print("⚠️ \(failedApps.count) apps not found: \(failedApps.prefix(5).joined(separator: ", "))") }
        return result
    }

    private func buildHierarchy(from data: LaunchpadData) -> LaunchpadHierarchy {
        // 说明（旧版 schema 结构）：
        // 层级关系为 Root(type=1) → TopContainers(type=3) → Pages(type=2) → Slots(type=3) → Apps(type=4)
        // 页面顺序应当按：TopContainers 的 ordering，再按各 TopContainer 下 Pages 的 ordering 依次展开。
        // 槽位顺序：按 Page 的直接子项 Slots(type=3) 的 ordering。

        // 构建 parent -> children 的索引，便于快速查找
        var childrenByParent: [Int: [LaunchpadDBItem]] = [:]
        for item in data.items {
            childrenByParent[item.parentId, default: []].append(item)
        }
        for key in childrenByParent.keys {
            childrenByParent[key]?.sort { $0.ordering < $1.ordering }
        }

        // 寻找 Root 节点（可能存在多个 type=1，仅取作父级的那些）
        let roots = data.items.filter { $0.type == 1 }
        let rootIds: [Int]
        if roots.isEmpty {
            rootIds = [1] // 兜底：典型旧库中 root 为 1
        } else {
            // 按 ordering 排序（若无意义，则自然顺序）
            rootIds = roots.sorted { $0.ordering < $1.ordering }.map { intValue($0.rowId) }
        }

        // Top-level 容器（直接隶属于 Root 的 type=3）
        var topContainers: [(rootIndex: Int, container: LaunchpadDBItem)] = []
        for (idx, rootId) in rootIds.enumerated() {
            let containers = (childrenByParent[rootId] ?? []).filter { $0.type == 3 }
            for c in containers { topContainers.append((rootIndex: idx, container: c)) }
        }
        // 仅保留“真正承载页面”的容器（其直接子项包含 type=2）
        topContainers = topContainers.filter { entry in
            let pid = intValue(entry.container.rowId)
            return (childrenByParent[pid] ?? []).contains(where: { $0.type == 2 })
        }
        // 以 (rootIndex, container.ordering) 排序，保持各 Root 内部顺序
        topContainers.sort { lhs, rhs in
            if lhs.rootIndex == rhs.rootIndex { return lhs.container.ordering < rhs.container.ordering }
            return lhs.rootIndex < rhs.rootIndex
        }
        #if DEBUG
        let tcIds = topContainers.map { $0.container.rowId }
        print("🧭 顶层容器顺序: \(tcIds.joined(separator: ", "))")
        #endif

        // 计算页面顺序：每个 topContainer 下的 pages(type=2) 依次追加
        var orderedPages: [LaunchpadDBItem] = []
        for entry in topContainers {
            let parentId = intValue(entry.container.rowId)
            let pagesUnder = (childrenByParent[parentId] ?? []).filter { $0.type == 2 }
            orderedPages.append(contentsOf: pagesUnder)
        }
        #if DEBUG
        let pageIds = orderedPages.map { $0.rowId }
        print("🧭 页面顺序: \(pageIds.joined(separator: ", "))")
        #endif

        // 槽位（每页的直接子项 type=3）
        var pages: [LaunchpadPage] = []
        for page in orderedPages {
            let pid = intValue(page.rowId)
            let slots = (childrenByParent[pid] ?? []).filter { $0.type == 3 }
            pages.append(LaunchpadPage(items: slots))
        }

        // 文件夹映射：任意 containerId(type=3) → 其子应用(type=4)
        var slotIdToApps: [String: [LaunchpadDBItem]] = [:]
        for item in data.items where item.type == 4 {
            slotIdToApps[String(item.parentId), default: []].append(item)
        }
        for key in slotIdToApps.keys {
            slotIdToApps[key]?.sort { $0.ordering < $1.ordering }
        }

        return LaunchpadHierarchy(pages: pages, folderItems: slotIdToApps)
    }

    private func intValue(_ s: String) -> Int {
        return Int(s) ?? 0
    }

    private func findLocalApp(bundleId: String, title: String) -> AppInfo? {
        // 优先使用 NSWorkspace 查找
        if let appPath = NSWorkspace.shared.absolutePathForApplication(withBundleIdentifier: bundleId) {
            return AppInfo.from(url: URL(fileURLWithPath: appPath),
                                preferredName: title,
                                loadIcon: PerformanceMode.current == .full)
        }

        // 备用方案：在常见路径中搜索
        let searchPaths = [
            "/Applications",
            "/System/Applications",
            "/System/Applications/Utilities",
            "/Applications/Utilities"
        ]

        for searchPath in searchPaths {
            if let app = searchAppInDirectory(searchPath, bundleId: bundleId, title: title) {
                return app
            }
        }

        return nil
    }

    private func searchAppInDirectory(_ path: String, bundleId: String, title: String) -> AppInfo? {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(at: URL(fileURLWithPath: path),
                                                      includingPropertiesForKeys: nil,
                                                      options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]) else {
            return nil
        }

        for case let url as URL in enumerator {
            if url.pathExtension == "app" {
                if let bundle = Bundle(url: url) {
                    // 精确匹配 bundle ID
                    if bundle.bundleIdentifier == bundleId {
                        return AppInfo.from(url: url,
                                            preferredName: title,
                                            loadIcon: PerformanceMode.current == .full)
                    }
                    // 备用：名称匹配
                    if let appName = bundle.infoDictionary?["CFBundleName"] as? String,
                       appName == title {
                        return AppInfo.from(url: url,
                                            preferredName: title,
                                            loadIcon: PerformanceMode.current == .full)
                    }
                }
            }
        }

        return nil
    }

    private func findFolderApps(groupId: String, hierarchy: LaunchpadHierarchy, launchpadData: LaunchpadData) -> [AppInfo] {
        let folderItems = hierarchy.folderItems[groupId] ?? []
        var apps: [AppInfo] = []

        for item in folderItems {
            if item.type == 4, // 应用
               let app = launchpadData.apps[item.rowId],
               let appInfo = findLocalApp(bundleId: app.bundleId, title: app.title) {
                apps.append(appInfo)
            }
        }

        return apps
    }

    private func findSingleApp(inContainerId containerId: String, launchpadData: LaunchpadData, hierarchy: LaunchpadHierarchy) -> AppInfo? {
        // 旧版 schema：单个应用的顶层项通常是一个 type=3 的容器，
        // 其下挂着一个 type=4 的应用项。这里取第一个 app 子项。
        if let items = hierarchy.folderItems[containerId] {
            if let appItem = items.first, let app = launchpadData.apps[appItem.rowId] {
                return findLocalApp(bundleId: app.bundleId, title: app.title)
            }
        }
        return nil
    }

    private func computeFolderName(from apps: [AppInfo]) -> String {
        let names = apps.prefix(3).map { $0.name }
        switch names.count {
        case 0: return "Untitled"
        case 1: return names[0]
        case 2: return names[0] + " + " + names[1]
        default: return names[0] + " + " + names[1] + " + …"
        }
    }

    private func isPlaceholderFolderTitle(_ s: String) -> Bool {
        if s.isEmpty { return true }
        let lower = s.lowercased()
        let placeholders: Set<String> = [
            "untitled",
            "untitled folder",
            "folder",
            "new folder",
            "未命名",
            "未命名文件夹"
        ]
        return placeholders.contains(lower)
    }

    private func computeFolderNameFromDB(groupId: String, launchpadData: LaunchpadData, hierarchy: LaunchpadHierarchy) -> String {
        let items = hierarchy.folderItems[groupId] ?? []
        let titles: [String] = items.compactMap { (child: LaunchpadDBItem) -> String? in
            guard child.type == 4, let app = launchpadData.apps[child.rowId] else { return nil }
            let t = app.title.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }
        let top = Array(titles.prefix(3))
        if top.isEmpty { return "" }
        if top.count == 1 { return top[0] }
        if top.count == 2 { return top[0] + " + " + top[1] }
        return top[0] + " + " + top[1] + " + …"
    }

    private func clearExistingData() throws {
        let descriptor = FetchDescriptor<PageEntryData>()
        let existingEntries = try modelContext.fetch(descriptor)
        for entry in existingEntries {
            modelContext.delete(entry)
        }
    }

    private func saveAppToPosition(appInfo: AppInfo, pageIndex: Int, position: Int) throws {
        let slotId = "page-\(pageIndex)-pos-\(position)"
        let entry = PageEntryData(
            slotId: slotId,
            pageIndex: pageIndex,
            position: position,
            kind: "app",
            appPath: appInfo.url.path
        )
        modelContext.insert(entry)
    }

    private func saveFolderToPosition(name: String, apps: [AppInfo], pageIndex: Int, position: Int) throws {
        let slotId = "page-\(pageIndex)-pos-\(position)"
        let folderId = UUID().uuidString
        let appPaths = apps.map { $0.url.path }

        let entry = PageEntryData(
            slotId: slotId,
            pageIndex: pageIndex,
            position: position,
            kind: "folder",
            folderId: folderId,
            folderName: name,
            appPaths: appPaths
        )
        modelContext.insert(entry)
    }

    private func saveEmptySlot(pageIndex: Int, position: Int) throws {
        let slotId = "page-\(pageIndex)-pos-\(position)"
        let entry = PageEntryData(
            slotId: slotId,
            pageIndex: pageIndex,
            position: position,
            kind: "empty"
        )
        modelContext.insert(entry)
    }
}

// MARK: - 数据模型 (复用之前的)

struct LaunchpadData {
    let apps: [String: LaunchpadDBApp]
    let groups: [String: LaunchpadGroup]
    let items: [LaunchpadDBItem]
}

struct LaunchpadDBApp {
    let itemId: String
    let title: String
    let bundleId: String
}

struct LaunchpadGroup {
    let itemId: String
    let title: String
}

struct LaunchpadDBItem {
    let rowId: String
    let type: Int  // 1=root, 2=page, 3=folder, 4=app
    let parentId: Int
    let ordering: Int
}

struct LaunchpadHierarchy {
    let pages: [LaunchpadPage]
    let folderItems: [String: [LaunchpadDBItem]]
}

struct LaunchpadPage {
    let items: [LaunchpadDBItem]
}

struct ImportResult {
    let convertedApps: Int
    let convertedFolders: Int
    let failedApps: [String]

    var summary: String {
        var lines = [
            "✅ Import Completed!",
            "📱 Apps: \(convertedApps)",
            "📁 Folders: \(convertedFolders)"
        ]

        if !failedApps.isEmpty {
            lines.append("⚠️ Not found: \(failedApps.count)")
        }
        
        return lines.joined(separator: "\n")
    }
}

enum ImportError: LocalizedError {
    case databaseNotFound(String)
    case databaseError(String)
    case systemError(String)
    case conversionError(String)

    var errorDescription: String? {
        switch self {
        case .databaseNotFound(let msg):
            return "Database not found: \(msg)"
        case .databaseError(let msg):
            return "Database error: \(msg)"
        case .systemError(let msg):
            return "System error: \(msg)"
        case .conversionError(let msg):
            return "Conversion error: \(msg)"
        }
    }
}

// MARK: - 扩展

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
