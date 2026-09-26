//
//  ActionMapper.swift
//  Nestic-iOS
//
//  Created by Tim Bausch on 2/28/26.
//

import Foundation
import CoreData

enum ActionMapper {
    static func upsert(_ dto: ActionDTO, in context: NSManagedObjectContext) throws {
        let idStr = dto.id.uuidString

        let fetch = NSFetchRequest<CDAction>(entityName: "CDAction")
        fetch.fetchLimit = 1
        fetch.predicate = NSPredicate(format: "id == %@", idStr)

        let existing = try context.fetch(fetch).first
        let obj = existing ?? CDAction(context: context)

        obj.id = idStr
        obj.nestId = dto.nestId.uuidString
        obj.name = dto.name
        obj.valueTypeRaw = dto.valueType
        obj.unit = dto.unit
        obj.createdAt = dto.createdAt
        obj.updatedAt = dto.updatedAt
    }

    static func deleteMissing(nestId: String, keeping idsToKeep: Set<String>, in context: NSManagedObjectContext) throws {
        // Optional cleanup: delete actions for this nest that are no longer returned by server
        let fetch = NSFetchRequest<CDAction>(entityName: "CDAction")
        fetch.predicate = NSPredicate(format: "nestId == %@", nestId)
        let existing = try context.fetch(fetch)

        for a in existing {
            if let id = a.id, !idsToKeep.contains(id) {
                context.delete(a)
            }
        }
    }
}
