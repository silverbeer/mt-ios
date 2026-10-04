import SwiftUI
import MTKit

struct LoginView: View {
    @Environment(AppModel.self) private var app
    @State private var username = ""
    @State private var password = ""
    @State private var error: String?
    @State private var busy = false
    @FocusState private var focus: Field?

    private enum Field { case username, password }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 8) {
                        Image(systemName: "soccerball")
                            .font(.system(size: 48))
                            .foregroundStyle(.tint)
                        Text("Missing Table").font(.title.bold())
                        Text("Tables, scores and live updates for your teams.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }
                Section {
                    TextField("Username", text: $username)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focus, equals: .username)
                        .submitLabel(.next)
                        .onSubmit { focus = .password }
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                        .focused($focus, equals: .password)
                        .submitLabel(.go)
                        .onSubmit { Task { await signIn() } }
                } footer: {
                    if let error {
                        Text(error).foregroundStyle(.red)
                    }
                }
                Section {
                    Button {
                        Task { await signIn() }
                    } label: {
                        HStack {
                            Spacer()
                            if busy { ProgressView() } else { Text("Sign In").bold() }
                            Spacer()
                        }
                    }
                    .disabled(busy || username.isEmpty || password.isEmpty)
                }
                #if DEBUG
                Section("Developer") {
                    EnvironmentPicker()
                }
                #endif
            }
        }
    }

    private func signIn() async {
        guard !username.isEmpty, !password.isEmpty else { return }
        busy = true
        error = nil
        defer { busy = false }
        do {
            try await app.login(username: username.trimmingCharacters(in: .whitespaces), password: password)
        } catch APIError.unauthorized {
            error = "Wrong username or password."
        } catch {
            self.error = error.displayMessage
        }
    }
}

struct EnvironmentPicker: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        Picker("Backend", selection: Binding(
            get: { app.environment },
            set: { env in Task { await app.switchEnvironment(env) } }
        )) {
            ForEach(APIEnvironment.allCases, id: \.self) { env in
                Text(env.rawValue.capitalized).tag(env)
            }
        }
    }
}
