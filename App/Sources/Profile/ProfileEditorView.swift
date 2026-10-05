import SwiftUI
import UIKit
import MTKit

/// Player profile editor (web PlayerProfileEditor): positions (first = primary),
/// card style and colours, social handles. Jersey number is set by the team manager.
struct ProfileEditorView: View {
    let profile: MyProfile
    let onSaved: () async -> Void
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var draft: ProfileCustomization
    @State private var options: [PositionOption] = []
    @State private var saving = false
    @State private var error: String?

    init(profile: MyProfile, onSaved: @escaping () async -> Void) {
        self.profile = profile
        self.onSaved = onSaved
        _draft = State(initialValue: ProfileCustomization(from: profile))
    }

    private var handlesValid: Bool {
        [draft.instagramHandle, draft.snapchatHandle, draft.tiktokHandle]
            .map { $0?.trimmingCharacters(in: CharacterSet(charactersIn: "@ ")) }
            .allSatisfy(ProfileCustomization.isValidHandle)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Player Information") {
                    LabeledContent("Jersey Number", value: profile.playerNumber.map { "#\($0)" } ?? "—")
                    Text("Set by your team manager").font(.caption).foregroundStyle(.secondary)
                }
                Section {
                    PositionPicker(options: options, selection: Binding(
                        get: { draft.positions ?? [] }, set: { draft.positions = $0 }))
                } header: {
                    Text("Positions")
                } footer: {
                    Text("Tap in order. The first position is your primary.")
                }
                Section("Card Style") {
                    Picker("Overlay", selection: Binding(
                        get: { draft.overlayStyle ?? "badge" }, set: { draft.overlayStyle = $0 })) {
                        ForEach(ProfileCustomization.overlayStyles, id: \.self) { Text($0.capitalized).tag($0) }
                    }
                    HexColorPicker(title: "Primary Color", hex: $draft.primaryColor, fallback: .blue)
                    HexColorPicker(title: "Secondary Color", hex: $draft.accentColor, fallback: .orange)
                    HexColorPicker(title: "Text Color", hex: $draft.textColor, fallback: .white)
                }
                Section {
                    handleField("Instagram", text: $draft.instagramHandle)
                    handleField("Snapchat", text: $draft.snapchatHandle)
                    handleField("TikTok", text: $draft.tiktokHandle)
                } header: {
                    Text("Social")
                } footer: {
                    if !handlesValid {
                        Text("Handles can use letters, numbers, _ and . (30 max).").foregroundStyle(.red)
                    }
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Saving…" : "Save") { Task { await save() } }
                        .disabled(saving || !handlesValid || draft == ProfileCustomization(from: profile))
                }
            }
            .task { options = (try? await app.client.positions()) ?? [] }
        }
    }

    private func handleField(_ title: String, text: Binding<String?>) -> some View {
        TextField(title, text: Binding(get: { text.wrappedValue ?? "" }, set: { text.wrappedValue = $0 }),
                  prompt: Text("@handle"))
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
    }

    private func save() async {
        saving = true
        error = nil
        defer { saving = false }
        do {
            try await app.client.updateCustomization(draft)
            await onSaved()
            dismiss()
        } catch {
            app.handle(error)
            self.error = error.displayMessage
        }
    }
}

/// Ordered multi-select: chips in tap order, grouped choices below.
private struct PositionPicker: View {
    let options: [PositionOption]
    @Binding var selection: [String]

    var body: some View {
        if !selection.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(selection.enumerated()), id: \.element) { index, code in
                        Button {
                            selection.removeAll { $0 == code }
                        } label: {
                            Label(code, systemImage: "xmark.circle.fill")
                                .font(.subheadline.weight(index == 0 ? .bold : .regular))
                        }
                        .buttonStyle(.bordered)
                        .tint(index == 0 ? .accentColor : .secondary)
                    }
                }
            }
        }
        if options.isEmpty {
            ProgressView()
        }
        ForEach(groups, id: \.0) { group, members in
            DisclosureGroup(group) {
                ForEach(members) { option in
                    Button {
                        if selection.contains(option.abbreviation) {
                            selection.removeAll { $0 == option.abbreviation }
                        } else {
                            selection.append(option.abbreviation)
                        }
                    } label: {
                        HStack {
                            Text("\(option.abbreviation) · \(option.fullName)").foregroundStyle(.primary)
                            Spacer()
                            if let index = selection.firstIndex(of: option.abbreviation) {
                                Text(index == 0 ? "Primary" : "\(index + 1)").font(.caption.bold()).foregroundStyle(.tint)
                            }
                        }
                    }
                }
            }
        }
    }

    private var groups: [(String, [PositionOption])] {
        var order: [String] = []
        var byGroup: [String: [PositionOption]] = [:]
        for option in options {
            if byGroup[option.group] == nil { order.append(option.group) }
            byGroup[option.group, default: []].append(option)
        }
        return order.map { ($0, byGroup[$0]!) }
    }
}

/// ColorPicker bound to a `#RRGGBB` string.
private struct HexColorPicker: View {
    let title: String
    @Binding var hex: String?
    let fallback: Color

    var body: some View {
        ColorPicker(title, selection: Binding(
            get: { Color(hex: hex) ?? fallback },
            set: { hex = $0.hexString }
        ), supportsOpacity: false)
    }
}

extension Color {
    /// `#RRGGBB` for the backend.
    var hexString: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        func byte(_ v: CGFloat) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(r), byte(g), byte(b))
    }
}
