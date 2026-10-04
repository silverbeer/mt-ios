import SwiftUI

enum AppTab: String, CaseIterable, Hashable {
    case table, matches, settings
}

struct RootView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        switch app.phase {
        case .launching:
            ProgressView().task { await app.bootstrap() }
        case .signedOut:
            LoginView()
        case .signedIn:
            MainTabs()
        }
    }
}

struct MainTabs: View {
    @SceneStorage("tab") private var tab: AppTab = .table

    var body: some View {
        TabView(selection: $tab) {
            Tab("Table", systemImage: "list.number", value: AppTab.table) {
                NavigationStack { Text("Table").navigationTitle("Table") }
            }
            Tab("Matches", systemImage: "sportscourt", value: AppTab.matches) {
                NavigationStack { Text("Matches").navigationTitle("Matches") }
            }
            Tab("Settings", systemImage: "gear", value: AppTab.settings) {
                NavigationStack { SettingsView() }
            }
        }
    }
}
