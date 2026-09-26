//
//  NestMapper.swift
//  Nestic-iOS
//
//  Created by Tim Bausch on 2/28/26.
//

import Foundation
import CoreData

enum NestMapper {
    static func upsert(_ dto: NestResponse, in context: NSManagedObjectContext) throws {
        let idString = dto.id.uuidString

        let fetch = NSFetchRequest<CDNest>(entityName: "CDNest")
        fetch.fetchLimit = 1
        fetch.predicate = NSPredicate(format: "id == %@", idString)

        let existing = try context.fetch(fetch).first
        let obj = existing ?? CDNest(context: context)

        obj.id = idString
        obj.name = dto.name
        obj.createdAt = dto.createdAt
        obj.updatedAt = dto.updatedAt
    }
}
