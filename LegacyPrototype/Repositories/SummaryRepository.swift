//
//  SummaryRepository.swift
//  Nestic-iOS
//
//  Created by Tim Bausch on 2/28/26.
//

import Foundation
import CoreData

final class SummaryRepository {
    private let api: APIClient

    init(api: APIClient = APIClient()) {
        self.api = api
    }

    func refreshSummary(nestId: String, token: String, context: NSManagedObjectContext) async throws {
        let dtos: [EntitySummaryDTO] = try await api.request("nests/\(nestId)/entities/summary", bearerToken: token)

        try await context.perform {
            // Upsert entities + replace pins + upsert last events
            for e in dtos {
                let entityId = e.entityId.uuidString
                try SummaryMapper.upsertEntity(e, nestId: nestId, in: context)
                try SummaryMapper.replacePinnedActions(for: entityId, nestId: nestId, pinned: e.pinned, in: context)

                for p in e.pinned {
                    try SummaryMapper.upsertLastEvent(
                        entityId: entityId,
                        nestId: nestId,
                        actionId: p.actionId.uuidString,
                        last: p.last,
                        in: context
                    )
                }
            }

            if context.hasChanges {
                try context.save()
            }
        }
    }
}
