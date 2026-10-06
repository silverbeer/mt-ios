import SwiftUI
import MTKit

/// Season and age group (single), divisions (multi-select, grouped by league).
struct MatchesFilterSheet: View {
    @Environment(LeagueFilter.self) private var filter
    @Environment(MatchesFilterStore.self) private var store
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var filter = filter
        NavigationStack {
            Form {
                Section {
                    Picker("Season", selection: $filter.seasonId) {
                        ForEach(filter.seasons) { Text($0.name).tag(Optional($0.id)) }
                    }
                    Picker("Age Group", selection: $filter.ageGroupId) {
                        ForEach(filter.ageGroups) { Text($0.name).tag(Optional($0.id)) }
                    }
                }
                if let profile = app.profile, profile.primaryTeam != nil {
                    Section {
                        Button("Reset to My Team", systemImage: "person.crop.circle.badge.checkmark") {
                            Task { try? await store.applyHome(for: profile, filter: filter, using: app.client) }
                        }
                    } footer: {
                        Text(profile.primaryTeam?.subtitle ?? "")
                    }
                }
                Section {
                    CheckRow(title: "All divisions", checked: store.divisionIds.isEmpty) {
                        store.divisionIds = []
                    }
                }
                ForEach(store.groups) { group in
                    Section {
                        ForEach(group.divisions) { division in
                            CheckRow(title: division.name, checked: store.divisionIds.contains(division.id)) {
                                store.toggle(division.id)
                            }
                        }
                    } header: {
                        HStack {
                            Text(group.title)
                            Spacer()
                            Button(store.isWholeLeagueSelected(group) ? "None" : "All") {
                                store.toggleLeague(group)
                            }
                            .font(.caption.bold())
                            .textCase(nil)
                        }
                    }
                }
            }
            .navigationTitle("Filter Matches")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct CheckRow: View {
    let title: String
    let checked: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title).foregroundStyle(.primary)
                Spacer()
                if checked { Image(systemName: "checkmark").foregroundStyle(.tint).bold() }
            }
            .contentShape(Rectangle())
        }
        .accessibilityAddTraits(checked ? .isSelected : [])
    }
}

struct MatchesFilterButton: View {
    @Environment(LeagueFilter.self) private var filter
    @Environment(MatchesFilterStore.self) private var store
    @State private var showing = false

    var body: some View {
        Button {
            showing = true
        } label: {
            Label([filter.ageGroup?.name, store.summary].compactMap { $0 }.joined(separator: " · "),
                  systemImage: "line.3.horizontal.decrease.circle")
        }
        .sheet(isPresented: $showing) { MatchesFilterSheet() }
        #if DEBUG
        // `-MTMatchesFilter YES` opens the filter sheet on launch (simulator screenshots).
        .onAppear { if UserDefaults.standard.bool(forKey: "MTMatchesFilter") { showing = true } }
        #endif
    }
}
