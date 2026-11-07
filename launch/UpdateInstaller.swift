import AppKit
import Combine
import CryptoKit
import Foundation
import SwiftUI

// MARK: - 应用内更新（与 Downie6 一致：下载 → 就地替换 → 重启）

enum UpdateInstallError: LocalizedError {
    case download(String)
    case checksum
    case archive(String)
    case bundleMissing
    case bundleMismatch
    case permission
    case install(String)

    var errorDescription: String? {
        switch self {
        case .download(let message):
            return LicenseText.t("下载失败：\(message)", "Download failed: \(message)")
        case .checksum:
            return LicenseText.t("安装包校验失败：SHA-256 不匹配", "Checksum failed: SHA-256 mismatch")
        case .archive(let message):
            return LicenseText.t("解压失败：\(message)", "Extraction failed: \(message)")
        case .bundleMissing:
            return LicenseText.t("安装包里没有找到启动台.app", "The update archive does not contain 启动台.app")
        case .bundleMismatch:
            return LicenseText.t("安装包不是启动台，已取消安装", "The update is not 启动台; installation cancelled")
        case .permission:
            return LicenseText.t(
                "没有写入权限，请把启动台放到「应用程序」目录后再更新",
                "No write permission. Move 启动台 to /Applications and try again."
            )
        case .install(let message):
            return LicenseText.t("安装失败：\(message)", "Installation failed: \(message)")
        }
    }
}

private final class ZipDownloader: NSObject, URLSessionDownloadDelegate {
    private let url: URL
    private let destination: URL
    private let onProgress: (Double) -> Void
    private var continuation: CheckedContinuation<URL, Error>?
    private var session: URLSession?
    private var finished = false

    init(url: URL, destination: URL, onProgress: @escaping (Double) -> Void) {
        self.url = url
        self.destination = destination
        self.onProgress = onProgress
    }

    func start() async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let configuration = URLSessionConfiguration.default
            configuration.timeoutIntervalForRequest = 30
            let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
            self.session = session
            session.downloadTask(with: url).resume()
        }
    }

    private func finish(_ result: Result<URL, Error>) {
        guard !finished else { return }
        finished = true
        continuation?.resume(with: result)
        continuation = nil
        session?.invalidateAndCancel()
        session = nil
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        onProgress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        if let http = downloadTask.response as? HTTPURLResponse, http.statusCode != 200 {
            finish(.failure(UpdateInstallError.download("HTTP \(http.statusCode)")))
            return
        }
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
            finish(.success(destination))
        } catch {
            finish(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            finish(.failure(error))
        }
    }
}

final class UpdateInstaller {
    static let shared = UpdateInstaller()

    private init() {}

    func download(
        from url: URL,
        expectedSHA256: String,
        onProgress: @escaping (Double) -> Void
    ) async throws -> URL {
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("启动台-\(UUID().uuidString).zip")
        let downloader = ZipDownloader(url: url, destination: destination, onProgress: onProgress)
        let file = try await downloader.start()

        let expected = expectedSHA256.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !expected.isEmpty {
            let data = try Data(contentsOf: file, options: .mappedIfSafe)
            let actual = SHA256.hash(data: data)
                .map { String(format: "%02x", $0) }
                .joined()
            guard actual == expected else {
                try? FileManager.default.removeItem(at: file)
                throw UpdateInstallError.checksum
            }
        }
        return file
    }

    /// 解压并把新 app 复制到当前 app 同级目录，返回待替换的 app 路径和新 app 路径。
    func prepareInstall(zip: URL) throws -> (appPath: String, stagedApp: URL) {
        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent("启动台-update-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)

        let extract = try run("/usr/bin/ditto", ["-x", "-k", zip.path, staging.path])
        guard extract == 0 else {
            throw UpdateInstallError.archive("ditto exited \(extract)")
        }

        guard let newApp = try findAppBundle(in: staging) else {
            throw UpdateInstallError.bundleMissing
        }
        let infoURL = newApp.appendingPathComponent("Contents/Info.plist")
        let info = try? NSDictionary(contentsOf: infoURL)
        guard info?["CFBundleIdentifier"] as? String == Bundle.main.bundleIdentifier else {
            throw UpdateInstallError.bundleMismatch
        }

        let appPath = Bundle.main.bundlePath
        let parent = URL(fileURLWithPath: appPath).deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: parent.path) else {
            throw UpdateInstallError.permission
        }

        let stagedApp = parent.appendingPathComponent(".启动台-update-\(UUID().uuidString).app")
        try? FileManager.default.removeItem(at: stagedApp)
        guard try run("/usr/bin/ditto", [newApp.path, stagedApp.path]) == 0 else {
            throw UpdateInstallError.install("ditto exited non-zero")
        }
        _ = try? run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", stagedApp.path])
        return (appPath, stagedApp)
    }

    /// 启动脱离当前进程的替换脚本；调用方应在稍后退出应用。
    func launchInstallScript(appPath: String, stagedApp: URL) throws {
        let script = FileManager.default.temporaryDirectory
            .appendingPathComponent("启动台-安装-\(UUID().uuidString).sh")
        let content = """
        #!/bin/sh
        set -e
        APP="$1"
        NEW="$2"
        PID="$3"
        while kill -0 "$PID" 2>/dev/null; do sleep 0.5; done
        rm -rf "$APP"
        mv "$NEW" "$APP"
        xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true
        open "$APP"
        """
        try content.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [script.path, appPath, stagedApp.path, String(ProcessInfo.processInfo.processIdentifier)]
        do {
            try process.run()
        } catch {
            throw UpdateInstallError.install(error.localizedDescription)
        }
    }

    private func findAppBundle(in directory: URL) throws -> URL? {
        let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        while let element = enumerator?.nextObject() as? URL {
            if element.pathExtension == "app" {
                return element
            }
        }
        return nil
    }

    @discardableResult
    private func run(_ executable: String, _ arguments: [String]) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }
}

// MARK: - 更新窗口

@MainActor
final class UpdateViewModel: ObservableObject {
    let release: AppStore.UpdateRelease
    let currentVersion: String

    @Published var isInstalling = false
    @Published var progress: Double?
    @Published var status = ""
    @Published var error: String?

    init(release: AppStore.UpdateRelease) {
        self.release = release
        self.currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    func install() {
        guard !isInstalling else { return }
        isInstalling = true
        error = nil
        progress = nil
        status = LicenseText.t("正在下载…", "Downloading…")

        Task {
            do {
                let zip = try await UpdateInstaller.shared.download(
                    from: release.url,
                    expectedSHA256: release.sha256
                ) { value in
                    Task { @MainActor in
                        self.progress = value
                    }
                }
                progress = nil
                status = LicenseText.t("下载完成，正在安装…", "Downloaded. Installing…")

                let prepared = try UpdateInstaller.shared.prepareInstall(zip: zip)
                status = LicenseText.t("安装完成，正在重启…", "Installed. Restarting…")
                try UpdateInstaller.shared.launchInstallScript(
                    appPath: prepared.appPath,
                    stagedApp: prepared.stagedApp
                )
                // 更新脚本会等待本进程退出后替换 app；直接 exit 避免
                // applicationShouldTerminate 的淡出流程卡住更新。
                try await Task.sleep(nanoseconds: 500_000_000)
                exit(0)
            } catch {
                self.error = error.localizedDescription
                self.status = ""
                self.progress = nil
                self.isInstalling = false
            }
        }
    }
}

struct UpdateDialogView: View {
    @ObservedObject var model: UpdateViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(LicenseText.t("发现新版本 v\(model.release.version)", "Update available v\(model.release.version)"))
                .font(.system(size: 20, weight: .bold))
            Text(LicenseText.t(
                "当前版本 \(model.currentVersion) → 新版本 \(model.release.version)",
                "Current \(model.currentVersion) → new \(model.release.version)"
            ))
            .font(.caption)
            .foregroundStyle(.secondary)

            ScrollView {
                Text(model.release.notes?.isEmpty == false ? model.release.notes! : LicenseText.t("有新版本可用。", "A new version is available."))
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 80, maxHeight: 150)

            if model.isInstalling {
                ProgressView(value: model.progress)
                Text(model.status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let error = model.error {
                Text(LicenseText.t("应用内更新失败：\(error)", "Update failed: \(error)"))
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button(LicenseText.t("稍后", "Later")) {
                    NSApp.keyWindow?.close()
                }
                .disabled(model.isInstalling)
                Button(model.isInstalling
                       ? LicenseText.t("正在更新…", "Updating…")
                       : LicenseText.t("下载并安装", "Download and install")) {
                    model.install()
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isInstalling)
            }
        }
        .padding(24)
        .frame(width: 480)
    }
}

@MainActor
final class UpdateWindowController: NSWindowController {
    static let shared = UpdateWindowController()

    private init() {
        super.init(window: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(release: AppStore.UpdateRelease) {
        close()
        let model = UpdateViewModel(release: release)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 340),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = LicenseText.t("发现新版本", "Update available")
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: UpdateDialogView(model: model))
        // launchpad 窗口可能是 mainMenu+1 层级，更新窗口必须再高一层。
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
