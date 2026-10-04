import SwiftUI
import MTKit

/// Season / age group / league / division pickers.
struct FilterSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(LeagueFilter.self) private var filter
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var filter = filter
        NavigationStack {
            Form {
                Picker("Season", selection: $filter.seasonId) {
                    ForEach(filter.seasons) { Text($0.name).tag(Optional($0.id)) }
                }
                Picker("Age Group", selection: $filter.ageGroupId) {
                    ForEach(filter.ageGroups) { Text($0.name).tag(Optional($0.id)) }
                }
                Picker("League", selection: Binding(
                    get: { filter.leagueId },
                    set: { id in Task { try? await filter.selectLeague(id, using: app.client) } }
                )) {
                    ForEach(filter.leagues) { Text($0.name).tag(Optional($0.id)) }
                }
                Picker("Division", selection: $filter.divisionId) {
                    ForEach(filter.divisions) { Text($0.name).tag(Optional($0.id)) }
                }
                .disabled(filter.divisions.isEmpty)
            }
            .navigationTitle("Filter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Toolbar button that opens the filter sheet and shows the current selection.
struct FilterButton: View {
    @Environment(LeagueFilter.self) private var filter
    @State private var showing = false

    var body: some View {
        Button {
            showing = true
        } label: {
            Label(filter.summary.isEmpty ? "Filter" : filter.summary,
                  systemImage: "line.3.horizontal.decrease.circle")
                .labelStyle(.titleAndIcon)
        }
        .sheet(isPresented: $showing) { FilterSheet() }
    }
}
