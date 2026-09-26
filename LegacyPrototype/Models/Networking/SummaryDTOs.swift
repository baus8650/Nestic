//
//  SummaryDTOs.swift
//  Nestic-iOS
//
//  Created by Tim Bausch on 2/28/26.
//

import Foundation

struct EntitySummaryDTO: Codable {
    let entityId: UUID
    let name: String
    let kind: String
    let birthday: Date?
    let imageURL: String?
    let pinned: [PinnedActionSummaryDTO]
}

struct PinnedActionSummaryDTO: Codable {
    let actionId: UUID
    let actionName: String
    let valueType: String
    let unit: String?
    let sortOrder: Int
    let last: LastEventSummaryDTO?
}

struct LastEventSummaryDTO: Codable {
    let eventId: UUID
    let occurredAt: Date
    let valueNumber: Double?
    let valueText: String?
    let valueBool: Bool?
    let valueJSON: [String: String]?
    let note: String?
}
