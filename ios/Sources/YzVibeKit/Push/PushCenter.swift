import UIKit
import UserNotifications

/// 推送里带回来的上下文（连接器放在 payload 的 `yz` 字段里）。
public struct PushPayload: Sendable, Equatable {
    public enum Kind: String, Sendable { case approval, reply, approvalResolved = "approval.resolved", test, unknown }
    public var kind: Kind
    public var sessionId: String?
    public var approvalId: String?
    public var connector: String?

    public init(userInfo: [AnyHashable: Any]) {
        let yz = userInfo["yz"] as? [String: Any] ?? [:]
        kind = Kind(rawValue: yz["kind"] as? String ?? "") ?? .unknown
        sessionId = yz["sessionId"] as? String
        approvalId = yz["approvalId"] as? String
        connector = yz["connector"] as? String
    }
}

/// 远程推送的注册与回调。
/// App 被 iOS 挂起后 WebSocket 一定会断，只有 APNs 能把「有操作等你批准」送到锁屏上——
/// 没有这一条，「离开电脑也能盯住会话」就不成立。
@MainActor
public final class PushCenter: NSObject, UNUserNotificationCenterDelegate {
    public static let shared = PushCenter()

    public private(set) var token: String?
    public private(set) var lastError: String?
    public private(set) var authorized = false
    /// APNs 环境：Xcode 直接装的开发版是 sandbox，TestFlight / App Store 是 production。
    public let environment: String = PushCenter.detectEnvironment()

    /// 拿到 device token 时回调（AppStore 用它去连接器注册）。
    public var onToken: ((String, String) -> Void)?
    /// 用户点了通知。
    public var onOpen: ((PushPayload) -> Void)?
    /// 收到静默推送，趁机在后台补一次数据。
    public var onSilent: (() async -> Void)?

    private override init() { super.init() }

    /// 请求权限并向 APNs 注册。没授权时不注册，避免拿到一个用不上的 token。
    public func start() async {
        UNUserNotificationCenter.current().delegate = self
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            authorized = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        } else {
            authorized = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
        }
        guard authorized else { lastError = "系统通知权限未开启"; return }
        UIApplication.shared.registerForRemoteNotifications()
    }

    public func didRegister(token hex: String) {
        self.token = hex
        lastError = nil
        onToken?(hex, environment)
    }

    public func didFail(_ error: Error) {
        lastError = error.localizedDescription
    }

    public func handleSilent(_ userInfo: [AnyHashable: Any]) async -> UIBackgroundFetchResult {
        if let badge = (userInfo["aps"] as? [String: Any])?["badge"] as? Int { setBadge(badge) }
        await onSilent?()
        return .newData
    }

    public func setBadge(_ count: Int) {
        UNUserNotificationCenter.current().setBadgeCount(count)
    }

    // MARK: UNUserNotificationCenterDelegate

    /// App 在前台时也把审批横幅显示出来——正在看别的会话时，别的会话的审批同样要能看见。
    nonisolated public func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    nonisolated public func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let payload = PushPayload(userInfo: response.notification.request.content.userInfo)
        await MainActor.run { self.onOpen?(payload) }
    }

    /// 从内嵌的描述文件判断 APNs 环境；App Store 包没有描述文件，按 production 处理。
    /// 猜错也没关系：连接器发现 token 不匹配会自动换另一个环境重试。
    private static func detectEnvironment() -> String {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .isoLatin1),
              let range = text.range(of: "<key>aps-environment</key>") else { return "production" }
        return text[range.upperBound...].prefix(120).contains("development") ? "sandbox" : "production"
    }
}

/// App 的 UIApplicationDelegate：只负责把系统回调转交给 PushCenter。
public final class YzVibeAppDelegate: NSObject, UIApplicationDelegate {
    public func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        MainActor.assumeIsolated { UNUserNotificationCenter.current().delegate = PushCenter.shared }
        return true
    }

    public func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        MainActor.assumeIsolated { PushCenter.shared.didRegister(token: hex) }
    }

    public func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        MainActor.assumeIsolated { PushCenter.shared.didFail(error) }
    }

    public func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any]) async -> UIBackgroundFetchResult {
        await PushCenter.shared.handleSilent(userInfo)
    }
}
