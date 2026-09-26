//
//  AuthViewModel.swift
//  Nestic-iOS
//
//  Created by Tim Bausch on 2/28/26.
//

import Foundation
import Combine

@MainActor
final class AuthViewModel: ObservableObject {
    // Inputs
    @Published var email: String = ""
    @Published var password: String = ""
    @Published var displayName: String = ""
    @Published var imageURL: String = ""

    // UI state
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var token: String? = nil

    var isAuthenticated: Bool { token != nil }

    private let authService: AuthService
    private let tokenStore: TokenStore

    init(authService: AuthService = AuthService(), tokenStore: TokenStore = TokenStore()) {
        self.authService = authService
        self.tokenStore = tokenStore

        // Load token from Keychain on startup
        do {
            self.token = try tokenStore.loadToken()
        } catch {
            self.errorMessage = error.localizedDescription
        }
    }

    func register() {
        errorMessage = nil
        isLoading = true

        Task {
            defer { isLoading = false }
            do {
                let resp = try await authService.register(
                    email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                    password: password,
                    displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
                    imageURL: imageURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : imageURL.trimmingCharacters(in: .whitespacesAndNewlines)
                )
                try tokenStore.saveToken(resp.token)
                token = resp.token
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func login() {
        errorMessage = nil
        isLoading = true

        Task {
            defer { isLoading = false }
            do {
                let resp = try await authService.login(
                    email: email.trimmingCharacters(in: .whitespacesAndNewlines),
                    password: password
                )
                try tokenStore.saveToken(resp.token)
                token = resp.token
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func logout() {
        errorMessage = nil
        do { try tokenStore.deleteToken() } catch { errorMessage = error.localizedDescription }
        token = nil
        password = ""
    }
    
    func logout(selectedNest: SelectedNestStore) {
        do { try tokenStore.deleteToken() } catch { errorMessage = error.localizedDescription }
        token = nil
        selectedNest.selectedNestId = nil
    }
}
