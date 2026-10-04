import SwiftUI
import MTKit

struct SettingsView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        Form {
            Section("Account") {
                if let user = app.user {
                    LabeledContent("Signed in as", value: user.label)
                    if let role = user.role {
                        LabeledContent("Role", value: role.replacingOccurrences(of: "_", with: " ").capitalized)
                    }
                }
                Button("Sign Out", role: .destructive) {
                    Task { await app.logout() }
                }
            }
            #if DEBUG
            Section("Developer") {
                EnvironmentPicker()
                LabeledContent("API", value: app.environment.baseURL.absoluteString)
            }
            #endif
            Section {
                LabeledContent("Version", value: Bundle.main.appVersion)
            }
        }
        .navigationTitle("Settings")
    }
}

extension Bundle {
    var appVersion: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}
