import SwiftUI
import UIKit
import UserNotifications
import MTKit

/// Settings → Notifications: system permission, per-event toggles, test send.
struct NotificationSettingsView: View {
    @Environment(AppModel.self) private var app
    @Environment(PushManager.self) private var push
    @State private var preferences: Loadable<[NotificationEvent: Bool]> = .idle
    @State private var testResult: String?
    @State private var sendingTest = false

    var body: some View {
        Form {
            Section {
                permissionRow
            } footer: {
                Text("You get notifications for teams you follow.")
            }
            Section("Notify me about") {
                switch preferences {
                case .loaded(let prefs):
                    ForEach(NotificationEvent.allCases) { event in
                        Toggle(event.title, isOn: Binding(
                            get: { prefs[event] ?? false },
                            set: { enabled in Task { await set(event, enabled) } }
                        ))
                    }
                case .failed(let message):
                    Text(message).foregroundStyle(.secondary)
                    Button("Try Again") { Task { await load() } }
                case .idle, .loading:
                    ProgressView()
                }
            }
            Section {
                Button {
                    Task { await sendTest() }
                } label: {
                    HStack {
                        Text("Send Test Notification")
                        if sendingTest { Spacer(); ProgressView() }
                    }
                }
                .disabled(sendingTest)
            } footer: {
                if let testResult { Text(testResult) }
            }
        }
        .navigationTitle("Notifications")
        .task {
            await push.refreshAuthorization()
            await load()
        }
    }

    @ViewBuilder private var permissionRow: some View {
        switch push.authorization {
        case .authorized, .provisional, .ephemeral:
            Label("Notifications are on", systemImage: "bell.badge.fill")
        case .denied:
            VStack(alignment: .leading, spacing: 8) {
                Label("Notifications are off", systemImage: "bell.slash")
                Button("Open iOS Settings") {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            }
        case .notDetermined:
            Button("Turn On Notifications") { Task { await push.requestAuthorizationIfNeeded() } }
        @unknown default:
            EmptyView()
        }
    }

    private func load() async {
        do {
            preferences = .loaded(try await app.client.notificationPreferences())
        } catch {
            app.handle(error)
            preferences = .failed(error.displayMessage)
        }
    }

    private func set(_ event: NotificationEvent, _ enabled: Bool) async {
        guard var prefs = preferences.value else { return }
        let previous = prefs[event]
        prefs[event] = enabled
        preferences = .loaded(prefs)
        do {
            preferences = .loaded(try await app.client.setNotificationPreferences([event: enabled]))
        } catch {
            prefs[event] = previous
            preferences = .loaded(prefs)
            app.handle(error)
        }
    }

    private func sendTest() async {
        sendingTest = true
        defer { sendingTest = false }
        do {
            let result = try await app.client.sendTestNotification()
            testResult = result.sent > 0 ? "Sent to \(result.sent) device(s)." : "No registered devices received it."
        } catch {
            app.handle(error)
            testResult = error.displayMessage
        }
    }
}
