//
//  NestDTOs.swift
//  Nestic-iOS
//
//  Created by Tim Bausch on 2/28/26.
//

import Foundation

struct NestResponse: Codable, Identifiable {
    let id: UUID
    let name: String
    let createdAt: Date?
    let updatedAt: Date?
}
