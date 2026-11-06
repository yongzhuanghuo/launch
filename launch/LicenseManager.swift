import Combine
import Foundation
import IOKit
import SwiftUI

// MARK: - 配置

enum LicenseConfig {
    /// 先与 Downie6 一样复用现有 HTTP 接口；后续换 HTTPS 只改这一处。
    /// 调试时可设 LAUNCH_API_BASE=http://127.0.0.1:3000 指向本地/测试后端。
    static var apiBase: String {
        ProcessInfo.processInfo.environment["LAUNCH_API_BASE"]
            ?? "http://8.153.99.239:3000"
    }
    static let product = "launch"
    static let supportEmail = "huoyongzhuang@qq.com"
    static let offlineGraceSeconds: TimeInterval = 7 * 24 * 3600
    static let refreshInterval: TimeInterval = 6 * 3600
    static let trialDays = 14
}

/// 授权 UI 的中英双语（其他语言回退英文；不依赖完整 LocalizationKey 表）。
enum LicenseText {
    static var language: AppLanguage {
        if let raw = UserDefaults.standard.string(forKey: "preferredLanguage"),
           let language = AppLanguage(rawValue: raw) {
            return language == .system ? AppLanguage.resolveSystemDefault() : language
        }
        return AppLanguage.resolveSystemDefault()
    }

    static func t(_ zh: String, _ en: String) -> String {
        switch language {
        case .simplifiedChinese, .traditionalChinese:
            return zh
        default:
            return en
        }
    }
}

// MARK: - 本地状态

struct StoredLicenseState: Codable, Equatable {
    /// "trial" | "license"
    var kind: String
    var code: String?
    var email: String?
    /// epoch seconds
    var trialEnd: TimeInterval?
    /// epoch seconds
    var lastVerified: TimeInterval
    var lastServerTime: TimeInterval?
}

// MARK: - 设备标识

private enum DeviceIdentity {
    static var deviceName: String {
        ProcessInfo.processInfo.hostName
    }

    static var fingerprint: String {
        let raw = platformUUID() ?? fallbackInstallID()
        return raw.replacingOccurrences(of: "-", with: "").lowercased()
    }

    private static func platformUUID() -> String? {
        let service = IOServiceGetMatchingService(
            kIOMainPortDefault,
            IOServiceMatching("IOPlatformExpertDevice")
        )
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        guard let value = IORegistryEntryCreateCFProperty(
            service,
            kIOPlatformUUIDKey as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() as? String else {
            return nil
        }
        return value
    }

    private static func fallbackInstallID() -> String {
        let key = "launch.license.installID"
        if let existing = UserDefaults.standard.string(forKey: key), !existing.isEmpty {
            return existing
        }
        let value = UUID().uuidString
        UserDefaults.standard.set(value, forKey: key)
        return value
    }
}

// MARK: - 本地存储（0600 文件）

private enum LicenseStore {
    // 未签名/ad-hoc 发布时 Keychain 会按代码签名校验访问权限，
    // 每次升级都可能弹系统密码框。授权状态不是密码，改用 0600 文件。
    static func load() -> StoredLicenseState? {
        guard let data = fileLoad() else { return nil }
        return try? JSONDecoder().decode(StoredLicenseState.self, from: data)
    }

    static func save(_ state: StoredLicenseState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        fileSave(data)
    }

    static func clear() {
        if let url = fileURL {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private static var fileURL: URL? {
        guard let support = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            return nil
        }
        let dir = support
            .appendingPathComponent("launch", isDirectory: true)
            .appendingPathComponent("License", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("license.json", isDirectory: false)
    }

    private static func fileLoad() -> Data? {
        guard let url = fileURL else { return nil }
        return try? Data(contentsOf: url)
    }

    private static func fileSave(_ data: Data) {
        guard let url = fileURL else { return }
        do {
            try data.write(to: url, options: .atomic)
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: url.path
            )
        } catch {
            // 本地存储失败不阻断使用，下次联网会重新校验
        }
    }
}

// MARK: - API

private struct APIErrorEnvelope: Decodable {
    struct Detail: Decodable {
        let ok: Bool?
        let error: String?
        let message: String?
    }

    let detail: Detail?
    let error: String?
    let message: String?
}

private struct TrialPayload: Decodable {
    let status: String
    let trial_end: Double
    let days_remaining: Int
}

private struct TrialEnvelope: Decodable {
    let ok: Bool
    let trial: TrialPayload?
    let can_download: Bool?
    let product: String?
}

private struct LicensePayload: Decodable {
    let type: String
    let max_devices: Int
    let expire_at: Int64?
}

private struct ActivateEnvelope: Decodable {
    let ok: Bool
    let error: String?
    let message: String?
    let license: LicensePayload?
    let product: String?
}

private struct VerifyEnvelope: Decodable {
    let ok: Bool
    let valid: Bool
    let reason: String?
    let is_pro: Bool?
    let product: String?
}

private struct OkEnvelope: Decodable {
    let ok: Bool
    let error: String?
    let message: String?
}

enum LicenseAPIError: LocalizedError {
    case invalidResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return LicenseText.t("授权服务器响应异常", "Invalid response from the license server")
        case .server(let message):
            return message
        }
    }
}

private enum LicenseAPI {
    static func post<T: Decodable>(_ path: String, body: [String: Any]) async throws -> T {
        guard let url = URL(string: LicenseConfig.apiBase + path) else {
            throw LicenseAPIError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw LicenseAPIError.invalidResponse
        }
        if http.statusCode >= 400 {
            throw serverError(from: data, status: http.statusCode)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private static func serverError(from data: Data, status: Int) -> LicenseAPIError {
        if let envelope = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data) {
            let message = envelope.detail?.message ?? envelope.message
            let error = envelope.detail?.error ?? envelope.error
            if let message, !message.isEmpty { return .server(message) }
            if let error, !error.isEmpty { return .server(error) }
        }
        return .server(LicenseText.t("授权请求失败（HTTP \(status)）", "License request failed (HTTP \(status))"))
    }
}

// MARK: - LicenseManager

@MainActor
final class LicenseManager: ObservableObject {
    static let shared = LicenseManager()

    enum State: Equatable {
        case checking
        case trial(days: Int, end: Date)
        case licensed(email: String?, code: String)
        case locked(String)
    }

    @Published private(set) var state: State = .checking
    @Published private(set) var isBusy = false
    @Published var errorMessage: String?

    private var stored: StoredLicenseState?
    private var hasBootstrapped = false
    private var refreshTask: Task<Void, Never>?
    private static let dailyTrialReminderKey = "launch.license.lastTrialReminderDay"

    private init() {
        stored = LicenseStore.load()
    }

    var isAllowed: Bool {
        switch state {
        case .trial, .licensed:
            return true
        default:
            return false
        }
    }

    var isLocked: Bool {
        if case .locked = state { return true }
        return false
    }

    var isChecking: Bool {
        if case .checking = state { return true }
        return false
    }

    var trialDaysRemaining: Int? {
        if case let .trial(days, _) = state { return days }
        return nil
    }

    /// 14 天试用一旦开始就不能重新开始；到期后只显示激活入口。
    var canStartTrial: Bool {
        guard let end = stored?.trialEnd else { return true }
        return end > Date().timeIntervalSince1970
    }

    var displayStatus: String {
        switch state {
        case .checking:
            return LicenseText.t("正在校验授权…", "Checking license…")
        case .trial(let days, _):
            return LicenseText.t("试用剩余 \(days) 天", "\(days) days of trial left")
        case .licensed(let email, _):
            return email.map {
                LicenseText.t("已授权 · \($0)", "Licensed · \($0)")
            } ?? LicenseText.t("已授权", "Licensed")
        case .locked(let message):
            return message
        }
    }

    /// CLI/headless 没有 UI，只能用本地缓存判断；首次联网试用仍需 GUI。
    var cachedAccessAllowed: Bool {
        guard let stored else { return false }
        let now = Date().timeIntervalSince1970
        if stored.kind == "license" {
            return now - stored.lastVerified <= LicenseConfig.offlineGraceSeconds
        }
        if let end = stored.trialEnd {
            return end > now
        }
        return false
    }

    /// CLI 进程不会走 bootstrap，直接根据本地缓存给出状态。
    var cachedDisplayStatus: String {
        guard let stored else {
            return LicenseText.t("未授权，请打开启动台开始试用或输入激活码", "Not licensed. Open Launchpad to start a trial or enter an activation code.")
        }
        let now = Date().timeIntervalSince1970
        if stored.kind == "license" {
            guard now - stored.lastVerified <= LicenseConfig.offlineGraceSeconds else {
                return LicenseText.t("离线时间过长，请联网校验授权", "Offline for too long. Connect to the internet to verify your license.")
            }
            return stored.email.map {
                LicenseText.t("已授权 · \($0)", "Licensed · \($0)")
            } ?? LicenseText.t("已授权", "Licensed")
        }
        if let end = stored.trialEnd, end > now {
            let days = max(1, Int(ceil((end - now) / 86400)))
            return LicenseText.t("试用剩余 \(days) 天", "\(days) days of trial left")
        }
        return LicenseText.t("14 天试用已结束，请输入激活码继续使用", "The 14-day trial has ended. Enter an activation code to continue.")
    }

    func bootstrap(force: Bool = false) async {
        if !force && hasBootstrapped { return }
        hasBootstrapped = true
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }

        let now = Date()

        // 已有授权：先联网 verify；失败时在离线宽限内继续用
        if let saved = stored, saved.kind == "license", let code = saved.code, !code.isEmpty {
            do {
                let result: VerifyEnvelope = try await LicenseAPI.post(
                    "/api/license/verify",
                    body: [
                        "product": LicenseConfig.product,
                        "code": code,
                        "device_fp": DeviceIdentity.fingerprint,
                    ]
                )
                if result.valid {
                    var updated = saved
                    updated.lastVerified = now.timeIntervalSince1970
                    stored = updated
                    LicenseStore.save(updated)
                    state = .licensed(email: updated.email, code: code)
                    startRefreshLoop()
                    await heartbeat(code: code)
                    return
                }
                LicenseStore.clear()
                stored = nil
                state = .locked(lockedMessage(for: result.reason))
                return
            } catch {
                if now.timeIntervalSince1970 - saved.lastVerified <= LicenseConfig.offlineGraceSeconds {
                    state = .licensed(email: saved.email, code: code)
                    startRefreshLoop()
                    return
                }
                state = .locked(LicenseText.t("无法连接授权服务器，请检查网络后重试", "Cannot reach the license server. Check your network and try again."))
                errorMessage = error.localizedDescription
                return
            }
        }

        // 没有授权：走试用（服务端按 product + 设备指纹记录，不会重置）
        do {
            let trial: TrialEnvelope = try await LicenseAPI.post(
                "/api/license/trial/start",
                body: [
                    "product": LicenseConfig.product,
                    "device_fp": DeviceIdentity.fingerprint,
                    "device_name": DeviceIdentity.deviceName,
                    "platform": "macos",
                ]
            )
            try applyTrial(trial, now: now)
        } catch {
            if let saved = stored, let end = saved.trialEnd, end > now.timeIntervalSince1970 {
                let days = max(0, Int(ceil((end - now.timeIntervalSince1970) / 86400)))
                state = .trial(days: days, end: Date(timeIntervalSince1970: end))
                startRefreshLoop()
            } else if stored?.trialEnd != nil {
                // 本地已有试用记录且已到期：不能重新开始试用，直接锁到激活页。
                state = .locked(LicenseText.t(
                    "14 天试用已结束，请输入激活码继续使用",
                    "The 14-day trial has ended. Enter an activation code to continue."
                ))
            } else {
                state = .locked(LicenseText.t(
                    "需要联网开始 \(LicenseConfig.trialDays) 天试用，或输入激活码",
                    "Connect to the internet to start the \(LicenseConfig.trialDays)-day trial, or enter an activation code."
                ))
                errorMessage = error.localizedDescription
            }
        }
    }

    func startTrial() async {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            let trial: TrialEnvelope = try await LicenseAPI.post(
                "/api/license/trial/start",
                body: [
                    "product": LicenseConfig.product,
                    "device_fp": DeviceIdentity.fingerprint,
                    "device_name": DeviceIdentity.deviceName,
                    "platform": "macos",
                ]
            )
            try applyTrial(trial, now: Date())
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func activate(code: String, email: String) async -> Bool {
        let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCode.isEmpty else {
            errorMessage = LicenseText.t("请输入激活码", "Enter an activation code")
            return false
        }
        guard trimmedEmail.range(of: #"^[^@\s]+@[^@\s]+\.[^@\s]+$"#, options: .regularExpression) != nil else {
            errorMessage = LicenseText.t("请输入正确的邮箱", "Enter a valid email address")
            return false
        }

        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            let result: ActivateEnvelope = try await LicenseAPI.post(
                "/api/license/activate",
                body: [
                    "product": LicenseConfig.product,
                    "code": trimmedCode,
                    "device_fp": DeviceIdentity.fingerprint,
                    "device_name": DeviceIdentity.deviceName,
                    "email": trimmedEmail,
                ]
            )
            guard result.ok, result.license != nil else {
                errorMessage = result.message ?? result.error
                    ?? LicenseText.t("激活失败", "Activation failed")
                return false
            }
            let now = Date().timeIntervalSince1970
            let saved = StoredLicenseState(
                kind: "license",
                code: trimmedCode,
                email: trimmedEmail,
                trialEnd: nil,
                lastVerified: now,
                lastServerTime: now
            )
            stored = saved
            LicenseStore.save(saved)
            state = .licensed(email: trimmedEmail, code: trimmedCode)
            startRefreshLoop()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func refresh() async {
        guard !isBusy else { return }
        switch state {
        case .licensed(let email, let code):
            do {
                let result: VerifyEnvelope = try await LicenseAPI.post(
                    "/api/license/verify",
                    body: [
                        "product": LicenseConfig.product,
                        "code": code,
                        "device_fp": DeviceIdentity.fingerprint,
                    ]
                )
                if result.valid {
                    var updated = stored ?? StoredLicenseState(
                        kind: "license", code: code, email: email, trialEnd: nil,
                        lastVerified: Date().timeIntervalSince1970
                    )
                    updated.lastVerified = Date().timeIntervalSince1970
                    stored = updated
                    LicenseStore.save(updated)
                    await heartbeat(code: code)
                } else {
                    LicenseStore.clear()
                    stored = nil
                    state = .locked(lockedMessage(for: result.reason))
                }
            } catch {
                // 网络失败：超过离线宽限就锁，否则保留现有授权继续用
                if let saved = stored,
                   Date().timeIntervalSince1970 - saved.lastVerified > LicenseConfig.offlineGraceSeconds {
                    LicenseStore.clear()
                    stored = nil
                    state = .locked(LicenseText.t("离线时间过长，请联网校验授权", "Offline for too long. Connect to the internet to verify your license."))
                }
            }
        case .trial(_, let end):
            do {
                let trial: TrialEnvelope = try await LicenseAPI.post(
                    "/api/license/trial/start",
                    body: [
                        "product": LicenseConfig.product,
                        "device_fp": DeviceIdentity.fingerprint,
                        "device_name": DeviceIdentity.deviceName,
                        "platform": "macos",
                    ]
                )
                try applyTrial(trial, now: Date())
                presentDailyTrialReminderIfNeeded()
            } catch {
                if end <= Date() {
                    state = .locked(LicenseText.t("14 天试用已结束，请输入激活码继续使用", "The 14-day trial has ended. Enter an activation code to continue."))
                }
            }
        case .checking, .locked:
            break
        }
    }

    func deactivate() async {
        guard case let .licensed(_, code) = state else { return }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            let _: OkEnvelope = try await LicenseAPI.post(
                "/api/license/unbind",
                body: [
                    "product": LicenseConfig.product,
                    "code": code,
                    "device_fp": DeviceIdentity.fingerprint,
                ]
            )
        } catch {
            errorMessage = error.localizedDescription
        }
        LicenseStore.clear()
        stored = nil
        state = .locked(LicenseText.t("已停用当前设备，可在其他设备激活", "This device has been deactivated. You can activate it on another device."))
    }

    func recoverByEmail() {
        let email = stored?.email ?? ""
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = LicenseConfig.supportEmail
        components.queryItems = [
            URLQueryItem(name: "subject", value: "launch 许可证代码找回"),
            URLQueryItem(
                name: "body",
                value: "我的许可证代码丢失了，请协助找回。\n购买邮箱：\(email)"
            ),
        ]
        if let url = components.url {
            NSWorkspace.shared.open(url)
        }
    }

    private func applyTrial(_ trial: TrialEnvelope, now: Date) throws {
        guard let payload = trial.trial else {
            throw LicenseAPIError.invalidResponse
        }
        let isFirstTrialRecord = stored?.trialEnd == nil
        let end = Date(timeIntervalSince1970: payload.trial_end / 1000.0)
        let saved = StoredLicenseState(
            kind: "trial",
            code: nil,
            email: stored?.email,
            trialEnd: end.timeIntervalSince1970,
            lastVerified: now.timeIntervalSince1970,
            lastServerTime: now.timeIntervalSince1970
        )
        if isFirstTrialRecord {
            // 开始试用当天已经在授权页展示过剩余天数，不再额外弹一次。
            markTrialReminderShown(on: now)
        }
        stored = saved
        LicenseStore.save(saved)
        if trial.can_download == true, end > now {
            let days = max(0, Int(ceil(end.timeIntervalSince(now) / 86400)))
            state = .trial(days: days, end: end)
            startRefreshLoop()
        } else {
            state = .locked(LicenseText.t("14 天试用已结束，请输入激活码继续使用", "The 14-day trial has ended. Enter an activation code to continue."))
        }
    }

    private func heartbeat(code: String) async {
        let _: OkEnvelope? = try? await LicenseAPI.post(
            "/api/license/heartbeat",
            body: [
                "product": LicenseConfig.product,
                "code": code,
                "device_fp": DeviceIdentity.fingerprint,
                "device_name": DeviceIdentity.deviceName,
            ]
        )
    }

    private func lockedMessage(for reason: String?) -> String {
        switch reason {
        case "LICENSE_REVOKED":
            return LicenseText.t("该激活码已被吊销", "This activation code has been revoked.")
        case "LICENSE_EXPIRED":
            return LicenseText.t("该激活码已过期", "This activation code has expired.")
        case "DEVICE_NOT_BOUND":
            return LicenseText.t("当前设备未绑定，请输入激活码", "This device is not bound. Enter an activation code.")
        default:
            return LicenseText.t("授权无效，请输入激活码", "License invalid. Enter an activation code.")
        }
    }

    /// 试用期内每天首次打开时提醒一次剩余天数。
    func presentDailyTrialReminderIfNeeded() {
        guard case let .trial(days, _) = state else { return }
        let now = Date()
        guard UserDefaults.standard.string(forKey: Self.dailyTrialReminderKey) != Self.dayString(now) else {
            return
        }
        markTrialReminderShown(on: now)

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = LicenseText.t("启动台试用提醒", "Launchpad trial reminder")
        alert.informativeText = LicenseText.t(
            "14 天试用还剩 \(days) 天。试用结束后需要输入激活码才能继续使用。",
            "\(days) days remain in your 14-day trial. An activation code is required when it ends."
        )
        alert.addButton(withTitle: LicenseText.t("继续试用", "Continue trial"))
        alert.addButton(withTitle: LicenseText.t("输入激活码", "Enter activation code"))
        if alert.runModal() == .alertSecondButtonReturn {
            LicenseWindowController.shared.show()
        }
    }

    private func markTrialReminderShown(on date: Date) {
        UserDefaults.standard.set(Self.dayString(date), forKey: Self.dailyTrialReminderKey)
    }

    private static func dayString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func startRefreshLoop() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(
                    nanoseconds: UInt64(LicenseConfig.refreshInterval * 1_000_000_000)
                )
                guard !Task.isCancelled else { return }
                await self?.refresh()
            }
        }
    }
}

// MARK: - 授权窗口 UI

struct LicenseGateView: View {
    @ObservedObject var manager: LicenseManager
    @State private var email = ""
    @State private var code = ""
    @State private var showActivation = false
    @State private var didAppear = false

    var body: some View {
        VStack(spacing: 18) {
            if let icon = NSApp.applicationIconImage {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 84, height: 84)
            }
            Text("启动台")
                .font(.system(size: 30, weight: .bold, design: .rounded))

            switch manager.state {
            case .checking:
                ProgressView(LicenseText.t("正在校验授权…", "Checking license…"))
                    .controlSize(.large)
            case .licensed(let licensedEmail, let licensedCode):
                licensedView(email: licensedEmail, code: licensedCode)
            case .trial(let days, _):
                trialView(days: days)
            case .locked(let message):
                lockedView(message: message)
            }

            if let error = manager.errorMessage, !error.isEmpty {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(36)
        .frame(width: 460)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
        .onAppear {
            guard !didAppear else { return }
            didAppear = true
            email = LicenseManager.shared.storedEmailForUI
            Task {
                await manager.bootstrap()
                manager.presentDailyTrialReminderIfNeeded()
            }
        }
    }

    @ViewBuilder
    private func trialView(days: Int) -> some View {
        VStack(spacing: 8) {
            Text(LicenseText.t("试用进行中", "Trial active"))
                .font(.headline)
            Text(LicenseText.t(
                "剩余 \(days) 天。试用结束后需要激活码才能继续使用。",
                "\(days) days left. An activation code is required after the trial."
            ))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }

        if showActivation {
            activationFields
        } else {
            Button(LicenseText.t("输入激活码", "Enter activation code")) { showActivation = true }
                .buttonStyle(.borderedProminent)
        }
        Button(LicenseText.t("找回许可证", "Recover license")) { manager.recoverByEmail() }
            .buttonStyle(.link)
            .font(.caption)
    }

    @ViewBuilder
    private func lockedView(message: String) -> some View {
        Text(message)
            .font(.headline)
            .multilineTextAlignment(.center)
            .foregroundStyle(.primary)

        if showActivation {
            activationFields
        } else {
            HStack(spacing: 12) {
                Button(LicenseText.t("输入激活码", "Enter activation code")) { showActivation = true }
                    .buttonStyle(.borderedProminent)
                if manager.canStartTrial {
                    Button(LicenseText.t("开始 14 天试用", "Start 14-day trial")) {
                        Task { await manager.startTrial() }
                    }
                    .disabled(manager.isBusy)
                }
            }
        }

        HStack(spacing: 16) {
            Button(LicenseText.t("找回许可证", "Recover license")) { manager.recoverByEmail() }
                .buttonStyle(.link)
            Button(LicenseText.t("退出启动台", "Quit launch")) { NSApp.terminate(nil) }
                .buttonStyle(.link)
        }
        .font(.caption)
    }

    @ViewBuilder
    private var activationFields: some View {
        VStack(spacing: 10) {
            TextField(LicenseText.t("购买邮箱", "Purchase email"), text: $email)
                .textFieldStyle(.roundedBorder)
            TextField(LicenseText.t("激活码", "Activation code"), text: $code)
                .textFieldStyle(.roundedBorder)
            Button(manager.isBusy
                   ? LicenseText.t("激活中…", "Activating…")
                   : LicenseText.t("激活", "Activate")) {
                Task { _ = await manager.activate(code: code, email: email) }
            }
            .buttonStyle(.borderedProminent)
            .disabled(manager.isBusy)
        }
        .frame(maxWidth: 340)
    }

    @ViewBuilder
    private func licensedView(email: String?, code: String) -> some View {
        VStack(spacing: 10) {
            Label(LicenseText.t("已授权", "Licensed"), systemImage: "checkmark.seal.fill")
                .font(.headline)
                .foregroundStyle(.green)
            Text(maskedEmail(email))
                .foregroundStyle(.secondary)
            Text(LicenseText.t("激活码：\(maskedCode(code))", "Code: \(maskedCode(code))"))
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 16) {
                Button(LicenseText.t("刷新状态", "Refresh")) { Task { await manager.refresh() } }
                Button(LicenseText.t("停用当前设备", "Deactivate this device")) {
                    Task { await manager.deactivate() }
                }
                    .foregroundStyle(.red)
            }
            .font(.caption)
        }
    }

    private func maskedEmail(_ email: String?) -> String {
        guard let email, !email.isEmpty else {
            return LicenseText.t("未绑定邮箱", "No email bound")
        }
        let parts = email.split(separator: "@", maxSplits: 1)
        guard parts.count == 2 else { return email }
        let name = String(parts[0])
        let prefix = name.prefix(1)
        return "\(prefix)***@\(parts[1])"
    }

    private func maskedCode(_ code: String) -> String {
        guard code.count > 8 else { return code }
        return "\(code.prefix(4))…\(code.suffix(4))"
    }
}

private extension LicenseManager {
    var storedEmailForUI: String {
        // Keychain/file 已在 init 时读取；这里只暴露给 UI 预填
        (try? LicenseStore.load())?.email ?? ""
    }
}

// MARK: - 设置页授权区

struct LicenseSettingsView: View {
    @ObservedObject var manager = LicenseManager.shared
    @State private var email = ""
    @State private var code = ""
    @State private var showActivation = false
    @State private var didAppear = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(manager.displayStatus)
                    .font(.headline)
                Text(LicenseText.t(
                    "支持邮箱：\(LicenseConfig.supportEmail)",
                    "Support: \(LicenseConfig.supportEmail)"
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))

            switch manager.state {
            case .checking:
                ProgressView("正在校验授权…")
            case .licensed(let licensedEmail, let licensedCode):
                VStack(alignment: .leading, spacing: 6) {
                    Text(LicenseText.t(
                        "邮箱：\(licensedEmail ?? "未绑定")",
                        "Email: \(licensedEmail ?? "not bound")"
                    ))
                    Text(LicenseText.t(
                        "激活码：\(maskedCode(licensedCode))",
                        "Code: \(maskedCode(licensedCode))"
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        Button(LicenseText.t("刷新状态", "Refresh")) {
                            Task { await manager.refresh() }
                        }
                        Button(LicenseText.t("停用当前设备", "Deactivate this device")) {
                            Task { await manager.deactivate() }
                        }
                        .foregroundStyle(.red)
                    }
                    .font(.caption)
                }
            case .trial(let days, _):
                VStack(alignment: .leading, spacing: 8) {
                    Text(LicenseText.t(
                        "14 天试用剩余 \(days) 天",
                        "\(days) days of the 14-day trial left"
                    ))
                    .foregroundStyle(.secondary)
                    if showActivation {
                        activationFields
                    } else {
                        HStack(spacing: 12) {
                            Button(LicenseText.t("输入激活码", "Enter activation code")) {
                                showActivation = true
                            }
                            Button(LicenseText.t("找回许可证", "Recover license")) {
                                manager.recoverByEmail()
                            }
                            .buttonStyle(.link)
                        }
                    }
                }
            case .locked(let message):
                VStack(alignment: .leading, spacing: 8) {
                    Text(message)
                        .foregroundStyle(.secondary)
                    if showActivation {
                        activationFields
                    } else {
                        HStack(spacing: 12) {
                            Button(LicenseText.t("输入激活码", "Enter activation code")) {
                                showActivation = true
                            }
                            if manager.canStartTrial {
                                Button(LicenseText.t("开始 14 天试用", "Start 14-day trial")) {
                                    Task { await manager.startTrial() }
                                }
                            }
                            Button(LicenseText.t("找回许可证", "Recover license")) {
                                manager.recoverByEmail()
                            }
                            .buttonStyle(.link)
                        }
                    }
                }
            }

            if let error = manager.errorMessage, !error.isEmpty {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .onAppear {
            guard !didAppear else { return }
            didAppear = true
            email = manager.storedEmailForUI
            Task { await manager.bootstrap() }
        }
    }

    @ViewBuilder
    private var activationFields: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField(LicenseText.t("购买邮箱", "Purchase email"), text: $email)
                .textFieldStyle(.roundedBorder)
            TextField(LicenseText.t("激活码", "Activation code"), text: $code)
                .textFieldStyle(.roundedBorder)
            Button(manager.isBusy
                   ? LicenseText.t("激活中…", "Activating…")
                   : LicenseText.t("激活", "Activate")) {
                Task { _ = await manager.activate(code: code, email: email) }
            }
            .buttonStyle(.borderedProminent)
            .disabled(manager.isBusy)
        }
        .frame(maxWidth: 360)
    }

    private func maskedCode(_ code: String) -> String {
        guard code.count > 8 else { return code }
        return "\(code.prefix(4))…\(code.suffix(4))"
    }
}

// MARK: - 独立授权窗口（菜单栏/设置入口）

@MainActor
final class LicenseWindowController: NSWindowController, NSWindowDelegate {
    static let shared = LicenseWindowController()

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 560),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = LicenseText.t("启动台 授权", "launch License")
        window.isReleasedWhenClosed = false
        window.center()
        window.contentView = NSHostingView(
            rootView: LicenseGateView(manager: LicenseManager.shared)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))
        )
        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        NSApp.setActivationPolicy(.regular)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

}
