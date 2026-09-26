//
//  DTOs.swift
//  Nestic-iOS
//
//  Created by Tim Bausch on 2/28/26.
//

import Foundation

struct TokenResponse: Codable {
    let token: String
}

struct RegisterRequest: Codable {
    let email: String
    let password: String
    let displayName: String
    let imageURL: String?
}
