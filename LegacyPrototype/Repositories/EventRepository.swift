//
//  EventRepository.swift
//  Nestic-iOS
//
//  Created by Tim Bausch on 2/28/26.
//

import Foundation
import CoreData

final class EventRepository {
    private let api: APIClient

    init(api: APIClient = APIClient()) {
        self.api = api
    }

    func createEvent(
        entityId: String,
        request: CreateEventRequest,
        token: String,
        context: NSManagedObjectContext
    ) async throws -> ActionEventResponse {

        let resp: ActionEventResponse = try await api.request(
            "entities/\(entityId)/events",
            method: "POST",
            bearerToken: token,
            body: request
        )

        // Update CDLastEvent for (entityId, actionId)
        try await context.perform {
            let actionIdStr = resp.actionId.uuidString

            let fetch = NSFetchRequest<CDLastEvent>(entityName: "CDLastEvent")
            fetch.fetchLimit = 1
            fetch.predicate = NSPredicate(format: "entityId == %@ AND actionId == %@", entityId, actionIdStr)

            let existing = try context.fetch(fetch).first
            let obj = existing ?? CDLastEvent(context: context)

            obj.id = resp.id.uuidString
            obj.nestId = resp.nestId.uuidString
            obj.entityId = resp.entityId.uuidString
            obj.actionId = actionIdStr
            obj.occurredAt = resp.occurredAt
            obj.valueNumber = resp.valueNumber ?? obj.valueNumber
            obj.valueText = nil
            obj.valueBool = false // will be ignored if unused; optional is better if your model supports it
            obj.valueJSON = nil
            obj.note = resp.note

            if context.hasChanges {
                try context.save()
            }
        }

        return resp
    }
}
