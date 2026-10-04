import Foundation
import Observation
import UIKit
import UserNotifications
import MTKit

/// Notification permission, APNs device registration and notification taps.
///
/// Permission is asked after the first follow, not at launch. Once granted the
/// device token is sent to the backend on every launch (tokens can change).
@MainActor @Observable
final class PushManager: NSObject {
    private(set) var authorization: UNAuthorizationStatus = .notDetermined
    /// Match to open, set when the user taps a score notification.
    var pendingMatchId: Int?
    private(set) var lastError: String?

    private weak var app: AppModel?
    private var deviceToken: Data?

    /// Debug builds talk to the APNs sandbox, release (TestFlight/App Store) to production.
    nonisolated static var apnsEnvironment: APNsEnvironment {
        #if DEBUG
        .sandbox
        #else
        .production
        #endif
    }

    func attach(_ app: AppModel) {
        self.app = app
        UNUserNotificationCenter.current().delegate = self
    }

    func refreshAuthorization() async {
        authorization = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        if authorization == .authorized || authorization == .provisional {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    /// Ask once; afterwards the user changes it in iOS Settings.
    func requestAuthorizationIfNeeded() async {
        await refreshAuthorization()
        guard authorization == .notDetermined else { return }
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        await refreshAuthorization()
    }

    func didRegister(deviceToken: Data) async {
        self.deviceToken = deviceToken
        await uploadToken()
    }

    /// Send the token to the backend. Needs a session, so it is retried after sign-in.
    func uploadToken() async {
        guard let app, app.user != nil, let deviceToken else { return }
        do {
            try await app.client.registerDevice(
                token: deviceToken, environment: Self.apnsEnvironment,
                label: UIDevice.current.name, appVersion: Bundle.main.appVersion)
            lastError = nil
        } catch {
            app.handle(error)
            lastError = error.displayMessage
        }
    }

    func didFailToRegister(_ error: any Error) {
        lastError = error.localizedDescription
    }

    /// `matchId` from a push payload (top-level, as sent by the backend APNs sender).
    nonisolated static func matchId(from userInfo: [AnyHashable: Any]) -> Int? {
        if let id = userInfo["matchId"] as? Int { return id }
        if let id = userInfo["matchId"] as? String { return Int(id) }
        if let id = userInfo["matchId"] as? NSNumber { return id.intValue }
        return nil
    }
}

extension PushManager: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification)
        async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        guard let id = Self.matchId(from: response.notification.request.content.userInfo) else { return }
        await MainActor.run { self.pendingMatchId = id }
    }
}

/// Bridges UIKit's remote-notification callbacks to PushManager.
@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {
    var push: PushManager?

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        guard let push else { return }
        Task { await push.didRegister(deviceToken: deviceToken) }
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: any Error) {
        push?.didFailToRegister(error)
    }
}
