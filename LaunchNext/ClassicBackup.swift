import Foundation
import AppKit

enum ClassicBackupError: LocalizedError {
    case supportDirectoryUnavailable
    case invalidBackup
    case copyFailed(String)

    var errorDescription: String? {
        switch self {
        case .supportDirectoryUnavailable:
            return "无法访问 LaunchNext 数据目录。"
        case .invalidBackup:
            return "所选文件夹不是有效的 LaunchNext 备份。"
        case .copyFailed(let message):
            return "备份操作失败：\(message)"
        }
    }
}

enum ClassicBackup {
    static func supportDirectory() throws -> URL {
        let fm = FileManager.default
        guard let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw ClassicBackupError.supportDirectoryUnavailable
        }
        let dir = appSupport.appendingPathComponent("LaunchNext", isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    @discardableResult
    static func createBackup(to parent: URL) throws -> URL {
        let source = try supportDirectory()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let destination = parent.appendingPathComponent("LaunchNext_\(formatter.string(from: Date())).launchnext",
                                                        isDirectory: true)
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: destination, withIntermediateDirectories: true)
            for item in try fm.contentsOfDirectory(at: source, includingPropertiesForKeys: nil) {
                let name = item.lastPathComponent
                guard name != "LaunchNext.restore" else { continue }
                try fm.copyItem(at: item, to: destination.appendingPathComponent(name))
            }
        } catch {
            try? fm.removeItem(at: destination)
            throw ClassicBackupError.copyFailed(error.localizedDescription)
        }
        return destination
    }

    static func restore(from source: URL) throws {
        let fm = FileManager.default
        let destination = try supportDirectory()
        let contents = try fm.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)
        guard contents.contains(where: { $0.lastPathComponent.hasSuffix(".store") || $0.lastPathComponent == "default.store" }) ||
              contents.contains(where: { $0.pathExtension == "sqlite" }) else {
            throw ClassicBackupError.invalidBackup
        }
        do {
            for existing in try fm.contentsOfDirectory(at: destination, includingPropertiesForKeys: nil) {
                try? fm.removeItem(at: existing)
            }
            for item in contents {
                try fm.copyItem(at: item, to: destination.appendingPathComponent(item.lastPathComponent))
            }
        } catch {
            throw ClassicBackupError.copyFailed(error.localizedDescription)
        }
    }

    static func relaunch() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-n", Bundle.main.bundlePath]
        try? process.run()
        NSApp.terminate(nil)
    }
}
