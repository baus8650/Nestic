//
//  ActionRepository.swift
//  Nestic-iOS
//
//  Created by Tim Bausch on 2/28/26.
//

import Foundation
import CoreData

final class ActionRepository {
    private let api: APIClient

    init(api: APIClient = APIClient()) {
        self.api = api
    }

    func refreshActions(nestId: String, token: String, context: NSManagedObjectContext) async throws {
        let actions: [ActionDTO] = try await api.request("nests/\(nestId)/actions", bearerToken: token)

        try await context.perform {
            let keep = Set(actions.map { $0.id.uuidString })

            for a in actions {
                try ActionMapper.upsert(a, in: context)
            }

            // Optional cleanup so menu doesn't show deleted actions
            try ActionMapper.deleteMissing(nestId: nestId, keeping: keep, in: context)

            if context.hasChanges {
                try context.save()
            }
        }
    }
}
