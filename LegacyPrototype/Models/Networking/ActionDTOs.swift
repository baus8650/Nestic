//
//  ActionDTOs.swift
//  Nestic-iOS
//
//  Created by Tim Bausch on 2/28/26.
//

import Foundation

struct ActionDTO: Codable {
    let id: UUID
    let nestId: UUID
    let name: String
    let valueType: String
    let unit: String?
    let createdAt: Date?
    let updatedAt: Date?
}
