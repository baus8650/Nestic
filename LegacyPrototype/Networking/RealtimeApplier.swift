//
//  RealtimeApplier.swift
//  Nestic-iOS
//
//  Created by Tim Bausch on 2/28/26.
//

import Foundation
import CoreData

enum RealtimeApplier {
    static func apply(actionEvent: ActionEventResponse, context: NSManagedObjectContext) {
        let entityId = actionEvent.entityId.uuidString
        let actionId = actionEvent.actionId.uuidString

        context.perform {
            let fetch = NSFetchRequest<CDLastEvent>(entityName: "CDLastEvent")
            fetch.fetchLimit = 1
            fetch.predicate = NSPredicate(format: "entityId == %@ AND actionId == %@", entityId, actionId)

            do {
                let existing = try context.fetch(fetch).first
                let obj = existing ?? CDLastEvent(context: context)

                // Out-of-order protection: ignore if existing is newer
                if let existingDate = obj.occurredAt, existingDate > actionEvent.occurredAt {
                    return
                }

                obj.id = actionEvent.id.uuidString
                obj.nestId = actionEvent.nestId.uuidString
                obj.entityId = entityId
                obj.actionId = actionId
                obj.occurredAt = actionEvent.occurredAt
                obj.valueNumber = actionEvent.valueNumber ?? obj.valueNumber
                obj.note = actionEvent.note

                if context.hasChanges {
                    try context.save()
                }
            } catch {
                // ignore best-effort
            }
        }
    }
}
