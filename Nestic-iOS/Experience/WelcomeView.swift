import SwiftUI
import UIKit
import AuthenticationServices

struct NesticRootView: View {
    @EnvironmentObject private var store: NesticStore
    var body: some View {
        ZStack(alignment: .top) {
            Group {
                if store.careLinkSession != nil { CareLinkView() }
                else if store.isAuthenticated { NesticTabs() }
                else { WelcomeView() }
            }
            if store.isLoading && store.isAuthenticated {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Updating your nest…").font(.caption.weight(.medium))
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 8)
                .background(NesticTheme.card, in: Capsule())
                .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
                .padding(.top, 6)
                .transition(.move(edge: .top).combined(with: .opacity))
                .accessibilityLabel("Updating your nest")
            }
        }
        .animation(.easeInOut(duration: 0.2), value: store.isAuthenticated)
        .alert("Couldn’t open caregiver link", isPresented: Binding(
            get: { store.careLinkError != nil },
            set: { if !$0 { store.careLinkError = nil } }
        )) {
            Button("OK") { store.careLinkError = nil }
        } message: {
            Text(store.careLinkError ?? "The link is unavailable.")
        }
        .alert("Account deleted", isPresented: Binding(get: { store.accountDeletionNotice != nil }, set: { if !$0 { store.accountDeletionNotice = nil } })) {
            Button("OK") { store.accountDeletionNotice = nil }
        } message: { Text(store.accountDeletionNotice ?? "") }
    }
}

struct WelcomeView: View {
    @EnvironmentObject private var store: NesticStore
    @State private var showTutorial = false
    @State private var authMode: AuthMode?

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    HStack(spacing: 8) {
                        NestMark().frame(width: 34, height: 36)
                        Text("nestic").font(.system(size: 28, weight: .bold, design: .rounded)).tracking(-1)
                        Spacer()
                        Text("YOUR EVERYDAY TRACKER").font(.system(size: 9, weight: .bold)).tracking(1)
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
                        Text("Keep track of\nyour nest.")
                            .font(.system(size: 38, weight: .bold, design: .rounded)).tracking(-1.6)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Track the everyday moments for your people, pets, home, and routines—then see the bigger picture together.")
                            .font(.body).foregroundStyle(.secondary).lineSpacing(4)
                    }
                    VStack(spacing: 14) {
                        PrimaryButton(title: "Create your nest", symbol: "arrow.right") { authMode = .register }
                            .accessibilityIdentifier("welcome.create")
                        Button("How Nestic works") { showTutorial = true }
                            .font(.subheadline.weight(.semibold)).accessibilityIdentifier("welcome.tutorial")
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
                    HStack {
                        Link("Privacy policy", destination: NesticAppLinks.privacyURL)
                        Spacer()
                        Link("Terms of Use", destination: NesticAppLinks.termsURL)
                    }.font(.footnote)
                }.padding(24).frame(minHeight: geometry.size.height)
            }.background(NesticTheme.paper)
        }
        .sheet(isPresented: $showTutorial) { NesticTutorialView() }
        .sheet(item: $authMode) { AuthSheet(mode: $0) }
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
    @State private var confirmPassword = ""
    @State private var busy = false
    @State private var error: String?
    @State private var registrationSent = false
    @State private var showForgotPassword = false
    @State private var acceptedTerms = false
    @State private var pendingAppleCredential: AppleCredentialPayload?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Link("Privacy policy", destination: NesticAppLinks.privacyURL)
                    Link("Read the Terms of Service", destination: NesticAppLinks.termsURL)
                    if mode == .register || pendingAppleCredential != nil {
                        Toggle("I have read and agree to the Terms of Service", isOn: $acceptedTerms)
                            .accessibilityIdentifier("auth.acceptTerms")
                        Text("The Privacy Policy explains how your information is used.")
                            .font(.footnote).foregroundStyle(.secondary)
                        if let credential = pendingAppleCredential {
                            Button("Agree and create account with Apple") { completeApple(credential) }
                                .disabled(busy || !acceptedTerms)
                        }
                    }
                }
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
                    VStack(spacing: 16) {
                        NesticAppleButton(label: .continue, onCredential: completeApple, onError: { error = $0 })
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .layoutPriority(1)
                            .overlay { if busy { ProgressView().tint(.white) } }
                            .disabled(busy || (mode == .register && !acceptedTerms))
                        HStack(spacing: 10) {
                            Rectangle().fill(.secondary.opacity(0.2)).frame(height: 1)
                            Text("or use email").font(.caption).foregroundStyle(.secondary).fixedSize()
                            Rectangle().fill(.secondary.opacity(0.2)).frame(height: 1)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }.listRowBackground(Color.clear).listRowInsets(EdgeInsets())
                Section {
                    if mode == .register {
                        TextField("Your name", text: $name).textContentType(.name).accessibilityIdentifier("auth.name")
                    }
                    TextField("Email address", text: $email)
                        .keyboardType(.emailAddress).textContentType(.emailAddress)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("auth.email")
                    if mode == .register {
                        // SwiftUI's SecureField can still be inferred by UIKit as a
                        // new-password form, even with `.password` as its content type.
                        // These explicit UIKit fields opt out of Password AutoFill so the
                        // Automatic Strong Password cover view cannot sit over the inputs.
                        ManualPasswordField("Password", text: $password, accessibilityIdentifier: "auth.password")
                        ManualPasswordField("Verify password", text: $confirmPassword, accessibilityIdentifier: "auth.confirmPassword")
                    } else {
                        SecureField("Password", text: $password)
                            .textContentType(.password)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .accessibilityIdentifier("auth.password")
                        Button("Forgot password?") { showForgotPassword = true }
                            .font(.subheadline.weight(.semibold)).foregroundStyle(NesticTheme.forest)
                    }
                } footer: {
                    if mode == .register { Text("Use at least 8 characters. We’ll email you a verification link before your first sign-in.") }
                }
                if registrationSent {
                    Section {
                        Label("Check your inbox at \(email) for a verification link. You can sign in after you open it.", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(NesticTheme.forest)
                        Button("Resend verification email") { resendVerification() }
                    }
                }
                if let error { Section { Text(error).foregroundStyle(.red).font(.subheadline) } }
                Section {
                    PrimaryButton(title: registrationSent ? "Done" : (mode == .register ? "Create account" : "Sign in"), busy: busy) { registrationSent ? dismiss() : submit() }
                        .disabled(busy || (!registrationSent && (email.isEmpty || password.isEmpty || (mode == .register && (name.isEmpty || confirmPassword.isEmpty || !acceptedTerms)))))
                        .accessibilityIdentifier("auth.submit")
                }.listRowBackground(Color.clear).listRowInsets(EdgeInsets())
            }.formStyle().navigationTitle(mode == .register ? "Get started" : "Sign in")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
                .sheet(isPresented: $showForgotPassword) { ForgotPasswordSheet() }
        }
    }
    private func submit() {
        busy = true; error = nil
        Task {
            defer { busy = false }
            do {
                if mode == .register {
                    guard password == confirmPassword else { throw NesticError.message("The passwords do not match.") }
                    registrationSent = try await store.register(name: name, email: email, password: password, acceptedTerms: acceptedTerms)
                }
                else { try await store.signIn(email: email, password: password) }
                if mode == .login || !registrationSent { dismiss() }
            } catch { self.error = error.localizedDescription }
        }
    }

    private func resendVerification() {
        busy = true; error = nil
        Task {
            defer { busy = false }
            do { try await store.resendVerification(email: email) }
            catch { self.error = error.localizedDescription }
        }
    }

    private func completeApple(_ credential: AppleCredentialPayload) {
        busy = true; error = nil
        Task {
            defer { busy = false }
            do {
                try await store.signInWithApple(identityToken: credential.identityToken,
                                               user: credential.user,
                                               email: credential.email,
                                               displayName: credential.displayName,
                                               nonce: credential.nonce,
                                               acceptedTerms: acceptedTerms)
                dismiss()
            } catch NesticError.termsAcceptanceRequired {
                pendingAppleCredential = credential
                error = "To create a new account with Apple, read the Terms of Service and select the agreement above."
            } catch { self.error = error.localizedDescription }
        }
    }
}

/// A secure entry field for account creation that intentionally opts out of
/// Password AutoFill. iOS can otherwise infer a sign-up form from two SwiftUI
/// `SecureField`s and overlay their editable area with its generated-password UI.
struct ManualPasswordField: UIViewRepresentable {
    let placeholder: String
    @Binding var text: String
    let accessibilityIdentifier: String

    init(_ placeholder: String, text: Binding<String>, accessibilityIdentifier: String) {
        self.placeholder = placeholder
        _text = text
        self.accessibilityIdentifier = accessibilityIdentifier
    }

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.placeholder = placeholder
        field.isSecureTextEntry = true
        field.textContentType = nil
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.spellCheckingType = .no
        field.keyboardType = .asciiCapable
        field.accessibilityLabel = placeholder
        field.accessibilityIdentifier = accessibilityIdentifier
        field.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        guard field.text != text else { return }
        field.text = text
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    final class Coordinator: NSObject {
        private var text: Binding<String>

        init(text: Binding<String>) { self.text = text }

        @objc func changed(_ field: UITextField) {
            text.wrappedValue = field.text ?? ""
        }
    }
}

struct ForgotPasswordSheet: View {
    @EnvironmentObject private var store: NesticStore
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var busy = false
    @State private var sent = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        NestMark().frame(width: 54, height: 54)
                        Text("Reset your password").font(.system(.title, design: .rounded, weight: .bold))
                        Text(sent ? "If an account exists for that email, a secure reset link is on its way." : "Enter your email and we’ll send a secure reset link.")
                            .foregroundStyle(.secondary)
                    }.padding(.vertical, 14)
                }.listRowBackground(Color.clear).listRowInsets(EdgeInsets())
                if !sent {
                    Section {
                        TextField("Email address", text: $email)
                            .keyboardType(.emailAddress).textContentType(.emailAddress)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                        if let error { Text(error).foregroundStyle(.red).font(.subheadline) }
                    }
                    Section {
                        PrimaryButton(title: "Send reset link", busy: busy) { submit() }
                            .disabled(busy || email.isEmpty)
                    }.listRowBackground(Color.clear).listRowInsets(EdgeInsets())
                } else {
                    Section { Label("Check your inbox and follow the link to choose a new password.", systemImage: "envelope.badge.fill").foregroundStyle(NesticTheme.forest) }
                    Section { PrimaryButton(title: "Done") { dismiss() } }
                        .listRowBackground(Color.clear).listRowInsets(EdgeInsets())
                }
            }.formStyle().navigationTitle("Forgot password")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }

    private func submit() {
        busy = true; error = nil
        Task {
            defer { busy = false }
            do { try await store.requestPasswordReset(email: email); sent = true }
            catch { self.error = error.localizedDescription }
        }
    }
}

struct AppleCredentialPayload: Sendable {
    let identityToken: String
    let user: String
    let email: String?
    let displayName: String?
    let nonce: String
    let authorizationCode: String?
}

struct NesticAppleButton: View {
    let label: SignInWithAppleButton.Label
    let onCredential: (AppleCredentialPayload) -> Void
    let onError: (String) -> Void
    @State private var nonce: String?

    var body: some View {
        SignInWithAppleButton(label, onRequest: { request in
            let value = UUID().uuidString.replacingOccurrences(of: "-", with: "")
            nonce = value
            request.requestedScopes = [.email, .fullName]
            request.nonce = value
        }, onCompletion: { result in
            switch result {
            case .success(let authorization):
                guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                      let tokenData = credential.identityToken,
                      let identityToken = String(data: tokenData, encoding: .utf8),
                      let nonce else {
                    onError("Apple sign-in did not return the information Nestic needs. Please try again.")
                    return
                }
                let name = [credential.fullName?.givenName, credential.fullName?.familyName]
                    .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
                onCredential(AppleCredentialPayload(identityToken: identityToken,
                                                     user: credential.user,
                                                     email: credential.email,
                                                     displayName: name.isEmpty ? nil : name,
                                                     nonce: nonce,
                                                     authorizationCode: credential.authorizationCode.flatMap { String(data: $0, encoding: .utf8) }))
            case .failure(let error):
                if (error as? ASAuthorizationError)?.code != .canceled {
                    onError(error.localizedDescription)
                }
            }
        })
        .signInWithAppleButtonStyle(.black)
    }
}
