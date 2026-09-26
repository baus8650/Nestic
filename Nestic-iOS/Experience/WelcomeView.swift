import SwiftUI

struct NesticRootView: View {
    @EnvironmentObject private var store: NesticStore
    var body: some View {
        Group {
            if store.isAuthenticated { NesticTabs() }
            else { WelcomeView() }
        }
        .animation(.easeInOut(duration: 0.2), value: store.isAuthenticated)
    }
}

struct WelcomeView: View {
    @EnvironmentObject private var store: NesticStore
    @State private var authMode: AuthMode?
    @State private var showServer = false

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    HStack(spacing: 8) {
                        NestMark().frame(width: 34, height: 36)
                        Text("nestic").font(.system(size: 28, weight: .bold, design: .rounded)).tracking(-1)
                        Spacer()
                        Text("A LITTLE MORE TOGETHER").font(.system(size: 9, weight: .bold)).tracking(1)
                            .foregroundStyle(.secondary)
                    }.padding(.top, 12)
                    ZStack {
                        RoundedRectangle(cornerRadius: 40).fill(NesticTheme.deepForest)
                        Circle().stroke(.white.opacity(0.07), lineWidth: 1).frame(width: 230).offset(x: 90, y: -50)
                        Circle().stroke(.white.opacity(0.07), lineWidth: 1).frame(width: 290).offset(x: 90, y: -50)
                        VStack(spacing: 18) {
                            NestMark(color: NesticTheme.lime).frame(width: 115, height: 110)
                            HStack(spacing: 9) {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(NesticTheme.lime)
                                Text("Milo went for a walk").font(.subheadline.weight(.medium)).foregroundStyle(.white)
                                Text("just now").font(.caption).foregroundStyle(.white.opacity(0.65))
                            }.padding(15).background(.white.opacity(0.10), in: Capsule())
                        }
                    }.frame(height: 260).clipped().accessibilityElement(children: .ignore)
                        .accessibilityLabel("A shared nest for the people and pets you care about")
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Life’s little things.\nAll in one nest.")
                            .font(.system(size: 38, weight: .bold, design: .rounded)).tracking(-1.6)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Who fed the dog? When was the last walk?\nKeep your people in the loop, one little update at a time.")
                            .font(.body).foregroundStyle(.secondary).lineSpacing(4)
                    }
                    VStack(spacing: 14) {
                        PrimaryButton(title: "Create your nest", symbol: "arrow.right") { authMode = .register }
                            .accessibilityIdentifier("welcome.create")
                        Button("I already have an account") { authMode = .login }
                            .font(.subheadline.weight(.semibold)).padding(.vertical, 4)
                        Button {
                            store.enterDemo()
                        } label: {
                            Label("Explore a sample nest", systemImage: "sparkles")
                                .font(.subheadline).foregroundStyle(.secondary)
                        }.padding(.top, 6).accessibilityIdentifier("welcome.demo")
                    }
                    Spacer(minLength: 0)
                    Button("Server settings") { showServer = true }
                        .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                }.padding(24).frame(minHeight: geometry.size.height)
            }.background(NesticTheme.paper)
        }
        .sheet(item: $authMode) { AuthSheet(mode: $0) }
        .sheet(isPresented: $showServer) { ServerSettingsSheet() }
    }
}

enum AuthMode: String, Identifiable {
    case login, register
    var id: String { rawValue }
}

struct AuthSheet: View {
    @EnvironmentObject private var store: NesticStore
    @Environment(\.dismiss) private var dismiss
    let mode: AuthMode
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var busy = false
    @State private var error: String?
    @State private var showServer = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        NestMark().frame(width: 54, height: 54)
                        Text(mode == .register ? "Your people. Your nest." : "Welcome back.")
                            .font(.system(.title, design: .rounded, weight: .bold))
                        Text(mode == .register ? "Create an account, then start a nest or ask someone to add you to theirs." : "Sign in to catch up on your nest.")
                            .foregroundStyle(.secondary)
                    }.padding(.vertical, 14)
                }.listRowBackground(Color.clear).listRowInsets(EdgeInsets())
                Section {
                    if mode == .register {
                        TextField("Your name", text: $name).textContentType(.name).accessibilityIdentifier("auth.name")
                    }
                    TextField("Email address", text: $email)
                        .keyboardType(.emailAddress).textContentType(.emailAddress)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("auth.email")
                    SecureField("Password", text: $password)
                        .textContentType(mode == .register ? .newPassword : .password).accessibilityIdentifier("auth.password")
                } footer: {
                    if mode == .register { Text("Use at least 8 characters for your password.") }
                }
                if let error { Section { Text(error).foregroundStyle(.red).font(.subheadline) } }
                Section {
                    PrimaryButton(title: mode == .register ? "Create account" : "Sign in", busy: busy) { submit() }
                        .disabled(email.isEmpty || password.isEmpty || (mode == .register && name.isEmpty))
                        .accessibilityIdentifier("auth.submit")
                }.listRowBackground(Color.clear).listRowInsets(EdgeInsets())
                Section {
                    Button("Connection settings", systemImage: "network") { showServer = true }
                } footer: { Text("For local testing, start the included Nestic server. You can also use your Railway server address.") }
            }.formStyle().navigationTitle(mode == .register ? "Get started" : "Sign in")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
                .sheet(isPresented: $showServer) { ServerSettingsSheet() }
        }
    }
    private func submit() {
        busy = true; error = nil
        Task {
            defer { busy = false }
            do {
                if mode == .register { try await store.register(name: name, email: email, password: password) }
                else { try await store.signIn(email: email, password: password) }
                dismiss()
            } catch { self.error = error.localizedDescription }
        }
    }
}

struct ServerSettingsSheet: View {
    @EnvironmentObject private var store: NesticStore
    @Environment(\.dismiss) private var dismiss
    @State private var address = ""
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://your-service.up.railway.app", text: $address)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityIdentifier("server.address")
                } header: { Text("Server address") } footer: {
                    Text("Simulator: http://127.0.0.1:8080. On an iPhone, use your Mac’s local IP address on the same Wi-Fi, or your Railway HTTPS address. Changing servers signs you out.")
                }
                if let error { Text(error).foregroundStyle(.red) }
                Section {
                    Text("Your domain can be connected to Railway later. Until then, use the URL Railway provides.")
                        .foregroundStyle(.secondary)
                }
            }.formStyle().navigationTitle("Connection").navigationBarTitleDisplayMode(.inline)
                .onAppear { address = store.serverURL }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            do { try store.configureServer(address); dismiss() }
                            catch { self.error = error.localizedDescription }
                        }.fontWeight(.semibold)
                    }
                }
        }
    }
}
