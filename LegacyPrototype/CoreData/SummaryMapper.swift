//
//  SummaryMapper.swift
//  Nestic-iOS
//
//  Created by Tim Bausch on 2/28/26.
//

import Foundation
import CoreData

enum SummaryMapper {

    static func upsertEntity(_ dto: EntitySummaryDTO, nestId: String, in context: NSManagedObjectContext) throws {
        let idStr = dto.entityId.uuidString

        let fetch = NSFetchRequest<CDEntity>(entityName: "CDEntity")
        fetch.fetchLimit = 1
        fetch.predicate = NSPredicate(format: "id == %@", idStr)

        let existing = try context.fetch(fetch).first
        let obj = existing ?? CDEntity(context: context)

        obj.id = idStr
        obj.nestId = nestId
        obj.name = dto.name
        obj.kindRaw = dto.kind
        obj.birthday = dto.birthday
        obj.imageURL = dto.imageURL
    }

    static func replacePinnedActions(for entityId: String, nestId: String, pinned: [PinnedActionSummaryDTO], in context: NSManagedObjectContext) throws {
        // Delete existing pins for entity
        let delFetch = NSFetchRequest<CDPinnedAction>(entityName: "CDPinnedAction")
        delFetch.predicate = NSPredicate(format: "entityId == %@", entityId)
        let existingPins = try context.fetch(delFetch)
        existingPins.forEach { context.delete($0) }

        // Insert new pins
        for p in pinned {
            let pin = CDPinnedAction(context: context)
            let actionId = p.actionId.uuidString
            pin.id = "\(entityId)|\(actionId)"
            pin.nestId = nestId
            pin.entityId = entityId
            pin.actionId = actionId
            pin.name = p.actionName
            pin.valueTypeRaw = p.valueType
            pin.unit = p.unit
            pin.sortOrder = Int16(p.sortOrder)
        }
    }

    static func upsertLastEvent(entityId: String, nestId: String, actionId: String, last: LastEventSummaryDTO?, in context: NSManagedObjectContext) throws {
        // If no last event, delete any existing last event row for this (entity, action)
        guard let last else {
            let fetch = NSFetchRequest<CDLastEvent>(entityName: "CDLastEvent")
            fetch.predicate = NSPredicate(format: "entityId == %@ AND actionId == %@", entityId, actionId)
            let existing = try context.fetch(fetch)
            existing.forEach { context.delete($0) }
            return
        }

        let fetch = NSFetchRequest<CDLastEvent>(entityName: "CDLastEvent")
        fetch.fetchLimit = 1
        fetch.predicate = NSPredicate(format: "entityId == %@ AND actionId == %@", entityId, actionId)

        let existing = try context.fetch(fetch).first
        let obj = existing ?? CDLastEvent(context: context)

        obj.id = last.eventId.uuidString
        obj.nestId = nestId
        obj.entityId = entityId
        obj.actionId = actionId
        obj.occurredAt = last.occurredAt
        obj.valueNumber = last.valueNumber ?? obj.valueNumber
        obj.valueText = last.valueText
        obj.valueBool = last.valueBool ?? obj.valueBool

        if let dict = last.valueJSON {
            let data = try JSONSerialization.data(withJSONObject: dict, options: [])
            obj.valueJSON = String(data: data, encoding: .utf8)
        } else {
            obj.valueJSON = nil
        }

        obj.note = last.note
    }
}
