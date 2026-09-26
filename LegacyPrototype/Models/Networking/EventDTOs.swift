//
//  EventDTOs.swift
//  Nestic-iOS
//
//  Created by Tim Bausch on 2/28/26.
//

import Foundation

struct CreateEventRequest: Codable {
    let actionID: UUID
    let occurredAt: Date?
    let valueNumber: Double?
    let valueText: String?
    let valueBool: Bool?
    let valueJSON: [String: String]?
    let note: String?
}

struct ActionEventResponse: Codable {
    let id: UUID
    let actorUserId: UUID?
    let valueNumber: Double?
    let actionId: UUID
    let nestId: UUID
    let note: String?
    let occurredAt: Date
    let entityId: UUID
}
