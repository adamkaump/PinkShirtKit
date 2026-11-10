import Foundation
import Security
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

extension View {
    /// Counts this install once per day toward the app's daily, weekly and monthly users, with no identifier.
    ///
    ///     ContentView()
    ///         .usageReporting(app: "pinpoint")
    ///
    /// Each report says only whether it's also the install's first of the week and of the month, plus the app
    /// version, platform, device model, system version and language. While the app is on screen it also sends a
    /// heartbeat each minute, holding only the app's name, for sessions, time spent and people using it now.
    /// Debug builds don't report unless launched with `-PSFUsageDebug YES`. People turn it off with
    /// `UsageReporting.isEnabled`.
    public func usageReporting(app: String, isEnabled: Bool = true) -> some View {
        modifier(UsageModifier(app: app, isEnabled: isEnabled))
    }
}

/// The app's switch for anonymous usage reports, announcement views included. On unless turned off.
public enum UsageReporting {
    /// Bind a toggle to this with `@AppStorage(UsageReporting.disabledKey)`, where true means off.
    public static let disabledKey = "PSFUsage.disabled"
    static let lastDayKey = "PSFUsage.lastDay"
    static let lastWeekKey = "PSFUsage.lastWeek"
    static let lastMonthKey = "PSFUsage.lastMonth"
    static let debugKey = "PSFUsageDebug"

    public static var isEnabled: Bool {
        get { !UserDefaults.standard.bool(forKey: disabledKey) }
        set { UserDefaults.standard.set(!newValue, forKey: disabledKey) }
    }

    /// Off in debug builds, simulators and Apple's virtual devices, so testing doesn't count as users.
    static var mayReport: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        #if DEBUG
        guard UserDefaults.standard.bool(forKey: debugKey) else { return false }
        #endif
        return isEnabled && !DeviceContext.isVirtual
        #endif
    }

    /// How often an app on screen says so. The server counts heartbeats this recent as people using it now.
    static let heartbeatInterval: Duration = .seconds(60)
    /// Coming back on screen within this long continues the session, so a quick trip to another app isn't a new one.
    static let sessionGap: TimeInterval = 5 * 60
    @MainActor static var lastOnScreen: Date?
    @MainActor private static var isBeating = false

    /// Sends a heartbeat when the app comes on screen and every minute until it leaves. Each adds a minute of
    /// foreground time, and the first after a break also starts a session. Only the app's name is sent.
    @MainActor static func sendHeartbeats(app: String) async {
        // One loop for the app, even with several windows on screen.
        guard mayReport, !isBeating else { return }
        isBeating = true
        defer { isBeating = false }
        var start = lastOnScreen.map { Date.now.timeIntervalSince($0) > sessionGap } ?? true
        while !Task.isCancelled {
            lastOnScreen = .now
            let body: [String: any Sendable] = ["app": app, "start": start]
            Task.detached { _ = await API.post("v1/heartbeat", body) }
            start = false
            try? await Task.sleep(for: heartbeatInterval)
        }
        lastOnScreen = .now
    }

    /// The periods a report sent at `date` would be the first of, in UTC to match the server's days.
    struct Periods: Equatable, Codable {
        var day: String
        var week: String
        var month: String

        init(day: String, week: String, month: String) {
            self.day = day
            self.week = week
            self.month = month
        }

        init(_ date: Date) {
            var calendar = Calendar(identifier: .iso8601)
            calendar.timeZone = TimeZone(identifier: "UTC")!
            let parts = calendar.dateComponents([.year, .month, .day, .yearForWeekOfYear, .weekOfYear], from: date)
            day = String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
            week = String(format: "%04d-W%02d", parts.yearForWeekOfYear!, parts.weekOfYear!)
            month = String(format: "%04d-%02d", parts.year!, parts.month!)
        }
    }

    @MainActor private static var isSending = false

    /// Sends today's report if this install hasn't yet. A failed send is tried again on the next activation.
    @MainActor static func reportIfNeeded(app: String, now: Date = .now) async {
        guard mayReport, !isSending else { return }
        let periods = Periods(now)
        let last = LastReport.load()
        guard last?.day != periods.day else { return }
        isSending = true
        defer { isSending = false }

        var body = DeviceContext.current(app: app)
        body["firstOfWeek"] = last?.week != periods.week
        body["firstOfMonth"] = last?.month != periods.month
        guard await API.post("v1/ping", body) != nil else { return }
        LastReport.save(periods)
    }

    /// An announcement was shown, or its link was tapped.
    static func recordAnnouncement(_ announcement: ResolvedAnnouncement, kind: String) {
        guard mayReport, let app = announcement.app else { return }
        let body: [String: any Sendable] = ["app": app, "announcement": announcement.id, "kind": kind, "language": announcement.language]
        Task.detached { _ = await API.post("v1/announcement-events", body) }
    }
}

/// When this device last reported. Kept in the Keychain, which on iPhone and iPad survives deleting and
/// reinstalling the app, so a reinstall the same day or week isn't counted as another person. It holds only the
/// dates, never anything sent anywhere. UserDefaults is the fallback if the Keychain refuses.
enum LastReport {
    private static var query: [CFString: Any] { [
        kSecClass: kSecClassGenericPassword,
        kSecAttrService: "PSFUsage",
        kSecAttrAccount: "lastReport",
        kSecUseDataProtectionKeychain: true,
    ] }

    static func load() -> UsageReporting.Periods? {
        var request = query
        request[kSecReturnData] = true
        var result: CFTypeRef?
        if SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess, let data = result as? Data,
           let periods = try? JSONDecoder().decode(UsageReporting.Periods.self, from: data) {
            return periods
        }
        let defaults = UserDefaults.standard
        guard let day = defaults.string(forKey: UsageReporting.lastDayKey) else { return nil }
        return .init(day: day, week: defaults.string(forKey: UsageReporting.lastWeekKey) ?? "",
                     month: defaults.string(forKey: UsageReporting.lastMonthKey) ?? "")
    }

    static func save(_ periods: UsageReporting.Periods) {
        let defaults = UserDefaults.standard
        defaults.set(periods.day, forKey: UsageReporting.lastDayKey)
        defaults.set(periods.week, forKey: UsageReporting.lastWeekKey)
        defaults.set(periods.month, forKey: UsageReporting.lastMonthKey)
        guard let data = try? JSONEncoder().encode(periods) else { return }
        if SecItemUpdate(query as CFDictionary, [kSecValueData: data] as CFDictionary) == errSecItemNotFound {
            var item = query
            item[kSecValueData] = data
            item[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(item as CFDictionary, nil)
        }
    }
}

struct UsageModifier: ViewModifier {
    let app: String
    let isEnabled: Bool
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            // Apps stay open for days, so a new day's activation counts too, not just launch.
            .task(id: scenePhase) {
                guard isEnabled, scenePhase == .active else { return }
                await UsageReporting.reportIfNeeded(app: app)
            }
            // Cancelled when the app leaves the screen, which ends the heartbeats.
            .task(id: scenePhase) {
                guard isEnabled, scenePhase == .active else { return }
                await UsageReporting.sendHeartbeats(app: app)
            }
    }
}

/// What every report and feedback message says about where it came from.
enum DeviceContext {
    @MainActor static func current(app: String) -> [String: any Sendable] {
        let info = Bundle.main.infoDictionary ?? [:]
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return [
            "app": app,
            "platform": platform,
            "device": model,
            "os": "\(os.majorVersion).\(os.minorVersion)",
            "version": info["CFBundleShortVersionString"] as? String ?? "?",
            "build": info["CFBundleVersion"] as? String ?? "?",
            "language": Locale.preferredLanguages.first ?? "?",
        ]
    }

    @MainActor static var platform: String {
        #if os(macOS)
        "macOS"
        #elseif os(visionOS)
        "visionOS"
        #elseif os(tvOS)
        "tvOS"
        #else
        ProcessInfo.processInfo.isiOSAppOnMac ? "macOS" : UIDevice.current.userInterfaceIdiom == .pad ? "iPadOS" : "iOS"
        #endif
    }

    /// Apple's virtual iPhones and Macs (iPhone99,10, VirtualMac2,1), which launch each uploaded build for
    /// App Store Connect.
    static var isVirtual: Bool {
        model.contains("99,") || model.hasPrefix("Virtual")
    }

    /// The hardware model, such as iPhone16,2 or Mac14,3.
    static var model: String {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] { return simulated }
        #if os(macOS)
        return sysctlString("hw.model") ?? "Mac"
        #else
        var system = utsname()
        uname(&system)
        return withUnsafeBytes(of: &system.machine) { String(decoding: $0.prefix(while: { $0 != 0 }), as: UTF8.self) }
        #endif
    }

    #if os(macOS)
    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(decoding: buffer.prefix(while: { $0 != 0 }), as: UTF8.self)
    }
    #endif
}

/// Pink Shirt Friday's backend, the pinkshirtfriday-api Worker.
enum API {
    static let baseURL = URL(string: "https://pinkshirtfriday-api.pinkshirtfriday-api.workers.dev/")!

    enum Failure: Error {
        case offline
        case tooManyRequests
        case rejected(String)
    }

    /// The response body, or nil on any failure. For callers that don't need to say why.
    static func post(_ path: String, _ body: [String: any Sendable]) async -> Data? {
        try? await send(path, body)
    }

    static func send(_ path: String, _ body: [String: any Sendable]) async throws(Failure) -> Data {
        var request = URLRequest(url: baseURL.appending(path: path), timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let status = (response as? HTTPURLResponse)?.statusCode
        else { throw .offline }
        switch status {
        case 200..<300: return data
        case 429: throw .tooManyRequests
        default:
            struct Message: Decodable { var error: String }
            throw .rejected((try? JSONDecoder().decode(Message.self, from: data))?.error ?? "HTTP \(status)")
        }
    }
}
