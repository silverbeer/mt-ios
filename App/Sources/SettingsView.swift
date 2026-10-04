import SwiftUI
import MTKit

struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @Environment(FollowStore.self) private var follows

    var body: some View {
        Form {
            Section {
                if follows.teams.isEmpty {
                    Text("Tap ☆ on a team page to follow it and get score updates.")
                        .foregroundStyle(.secondary)
                }
                ForEach(follows.teams) { team in
                    NavigationLink(value: TeamRoute(id: team.teamId, name: team.name)) {
                        VStack(alignment: .leading) {
                            Text(team.name)
                            if !team.subtitle.isEmpty {
                                Text(team.subtitle).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .onDelete { offsets in
                    let removed = offsets.map { follows.teams[$0] }
                    Task {
                        for team in removed {
                            try? await follows.toggle(TeamRoute(id: team.teamId, name: team.name), using: app.client)
                        }
                    }
                }
            } header: {
                Text("My Teams")
            }
            Section {
                NavigationLink {
                    NotificationSettingsView()
                } label: {
                    Label("Notifications", systemImage: "bell")
                }
            }
            Section("Account") {
                if let user = app.user {
                    LabeledContent("Signed in as", value: user.label)
                    if let role = user.role {
                        LabeledContent("Role", value: role.replacingOccurrences(of: "_", with: " ").capitalized)
                    }
                }
                Button("Sign Out", role: .destructive) {
                    Task {
                        await app.logout()
                        follows.reset()
                    }
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
        .task { try? await follows.load(using: app.client) }
    }
}

extension Bundle {
    var appVersion: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}
