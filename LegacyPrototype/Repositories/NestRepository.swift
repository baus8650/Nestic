//
//  NestRepository.swift
//  Nestic-iOS
//
//  Created by Tim Bausch on 2/28/26.
//

import Foundation
import CoreData

final class NestRepository {
    private let api: APIClient

    init(api: APIClient = APIClient()) {
        self.api = api
    }

    func refreshNests(token: String, context: NSManagedObjectContext) async throws {
        let nests: [NestResponse] = try await api.request("nests", bearerToken: token)

        try await context.perform {
            for n in nests {
                try NestMapper.upsert(n, in: context)
            }
            if context.hasChanges {
                try context.save()
            }
        }
    }
}
