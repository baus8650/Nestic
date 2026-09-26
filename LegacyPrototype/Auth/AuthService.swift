//
//  AuthService.swift
//  Nestic-iOS
//
//  Created by Tim Bausch on 2/28/26.
//

import Foundation

final class AuthService {
    private let api: APIClient

    init(api: APIClient = APIClient()) {
        self.api = api
    }

    func register(email: String, password: String, displayName: String, imageURL: String?) async throws -> TokenResponse {
        let body = RegisterRequest(email: email, password: password, displayName: displayName, imageURL: imageURL)
        let resp: TokenResponse = try await api.request("auth/register", method: "POST", body: body)
        return resp
    }

    func login(email: String, password: String) async throws -> TokenResponse {
        let resp: TokenResponse = try await api.request("auth/login", method: "POST", basicAuth: (email, password))
        return resp
    }
}
