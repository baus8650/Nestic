//
//  SyncCoordinator.swift
//  Nestic-iOS
//
//  Created by Tim Bausch on 2/28/26.
//

import Foundation
import CoreData
import Combine

@MainActor
final class SyncCoordinator: ObservableObject {
    private var cancellables = Set<AnyCancellable>()

    private let nestRepo: NestRepository
    private let actionRepo: ActionRepository
    private let summaryRepo: SummaryRepository
    private let context: NSManagedObjectContext
    private let selectedNest: SelectedNestStore
    private let auth: AuthViewModel

    private let realtimeBaseURL: String
    private let realtime: RealtimeClient

    private var lastConnectedToken: String?
    private var lastSubscribedNestId: String?

    init(
        auth: AuthViewModel,
        selectedNest: SelectedNestStore,
        context: NSManagedObjectContext,
        nestRepo: NestRepository = NestRepository(),
        actionRepo: ActionRepository = ActionRepository(),
        summaryRepo: SummaryRepository = SummaryRepository(),
        realtimeBaseURL: String = "http://127.0.0.1:8080",
        realtime: RealtimeClient? = nil
    ) {
        self.auth = auth
        self.selectedNest = selectedNest
        self.context = context
        self.nestRepo = nestRepo
        self.actionRepo = actionRepo
        self.summaryRepo = summaryRepo

        self.realtimeBaseURL = realtimeBaseURL
        self.realtime = realtime ?? RealtimeClient()

        self.realtime.onActionEventCreated = { [weak self] event in
            guard let self else { return }

            guard self.selectedNest.selectedNestId == event.nestId.uuidString else {
                return
            }

            self.applyRealtime(event: event)
        }

        self.realtime.onEntityCreated = { [weak self] entity in
            guard let self else { return }
            guard self.selectedNest.selectedNestId == entity.nestId.uuidString else { return }
            self.refreshSummaryForCurrentNest()
        }

        self.realtime.onEntityUpdated = { [weak self] entity in
            guard let self else { return }
            guard self.selectedNest.selectedNestId == entity.nestId.uuidString else { return }
            self.refreshSummaryForCurrentNest()
        }

        self.realtime.onEntityDeleted = { [weak self] entity in
            guard let self else { return }
            guard self.selectedNest.selectedNestId == entity.nestId.uuidString else { return }
            self.refreshSummaryForCurrentNest()
        }

        self.realtime.onActionCreated = { [weak self] action in
            guard let self else { return }
            guard self.selectedNest.selectedNestId == action.nestId.uuidString else { return }
            self.refreshActionsAndSummaryForCurrentNest()
        }

        self.realtime.onPinnedActionsUpdated = { [weak self] update in
            guard let self else { return }
            guard self.selectedNest.selectedNestId == update.nestId.uuidString else { return }
            self.refreshSummaryForCurrentNest()
        }

        self.realtime.onMemberCreated = { [weak self] member in
            guard let self else { return }
            guard self.selectedNest.selectedNestId != nil else { return }
        }

        self.realtime.onMemberUpdated = { [weak self] member in
            guard let self else { return }
            guard self.selectedNest.selectedNestId != nil else { return }
        }

        self.realtime.onMemberDeleted = { [weak self] member in
            guard let self else { return }
            guard self.selectedNest.selectedNestId != nil else { return }
        }

        bind()
    }

    private func bind() {
        // When token appears/disappears: refresh nests
        auth.$token
            .removeDuplicates()
            .sink { [weak self] token in
                guard let self else { return }

                guard let token else {
                    self.selectedNest.selectedNestId = nil

                    // Realtime teardown
                    self.lastConnectedToken = nil
                    self.lastSubscribedNestId = nil
                    self.realtime.disconnect()
                    return
                }

                Task {
                    try? await self.nestRepo.refreshNests(token: token, context: self.context)
                    await self.autoSelectNestIfPossible()
                }
            }
            .store(in: &cancellables)

        // When selected nest changes: refresh summary
        Publishers.CombineLatest(auth.$token.removeDuplicates(), selectedNest.$selectedNestId.removeDuplicates())
            .sink { [weak self] token, nestId in
                guard let self else { return }
                guard let token, let nestId else { return }

                Task {
                    // 1) Connect/reconnect realtime for the active token + selected nest
                    if (self.lastConnectedToken != token || self.lastSubscribedNestId != nestId),
                       let uuid = UUID(uuidString: nestId) {
                        self.lastConnectedToken = token
                        self.lastSubscribedNestId = nestId
                        self.realtime.connect(
                            baseURL: self.realtimeBaseURL,
                            token: token,
                            nestId: uuid
                        )
                    }

                    await self.refreshActionsAndSummary(nestId: nestId, token: token)
                }
            }
            .store(in: &cancellables)
    }

    private func applyRealtime(event: ActionEventResponse) {
        // Upsert CDLastEvent for (entityId, actionId). Ignore out-of-order events.
        let entityId = event.entityId.uuidString
        let actionId = event.actionId.uuidString

        context.perform {
            let fetch = NSFetchRequest<CDLastEvent>(entityName: "CDLastEvent")
            fetch.fetchLimit = 1
            fetch.predicate = NSPredicate(format: "entityId == %@ AND actionId == %@", entityId, actionId)

            do {
                let existing = try self.context.fetch(fetch).first
                let obj = existing ?? CDLastEvent(context: self.context)

                if let existingDate = obj.occurredAt, existingDate > event.occurredAt {
                    return
                }

                obj.id = event.id.uuidString
                obj.nestId = event.nestId.uuidString
                obj.entityId = entityId
                obj.actionId = actionId
                obj.occurredAt = event.occurredAt
                obj.valueNumber = event.valueNumber ?? obj.valueNumber
                obj.note = event.note

                if self.context.hasChanges {
                    try self.context.save()
                }

                self.refreshSummaryForCurrentNest()
            } catch {
                // best-effort
            }
        }
    }

    private func refreshActionsAndSummary(nestId: String, token: String) async {
        // 1) Refresh actions catalog (for long-press menu)
        try? await self.actionRepo.refreshActions(nestId: nestId, token: token, context: self.context)

        // 2) Refresh entity summary (home screen)
        try? await self.summaryRepo.refreshSummary(nestId: nestId, token: token, context: self.context)
    }

    private func refreshActionsAndSummaryForCurrentNest() {
        guard let token = auth.token,
              let nestId = selectedNest.selectedNestId else {
            return
        }

        Task {
            await self.refreshActionsAndSummary(nestId: nestId, token: token)
        }
    }

    private func refreshSummaryForCurrentNest() {
        guard let token = auth.token,
              let nestId = selectedNest.selectedNestId else {
            return
        }

        Task {
            try? await self.summaryRepo.refreshSummary(nestId: nestId, token: token, context: self.context)
        }
    }

    private func autoSelectNestIfPossible() async {
        // 1) default nest if it exists
        if let defaultId = selectedNest.defaultNestId,
           await nestExists(id: defaultId) {
            selectedNest.selectedNestId = defaultId
            return
        }

        // 2) if only one nest, auto-select it
        let ids = await fetchNestIds()
        if ids.count == 1 {
            selectedNest.selectedNestId = ids.first
        }
        // else: user picks in UI
    }

    private func nestExists(id: String) async -> Bool {
        await self.context.perform {
            let fetch = NSFetchRequest<CDNest>(entityName: "CDNest")
            fetch.fetchLimit = 1
            fetch.predicate = NSPredicate(format: "id == %@", id)
            return (try? self.context.fetch(fetch).first) != nil
        }
    }

    private func fetchNestIds() async -> [String] {
        await self.context.perform {
            let fetch = NSFetchRequest<CDNest>(entityName: "CDNest")
            fetch.propertiesToFetch = ["id"]
            let results = (try? self.context.fetch(fetch)) ?? []
            return results.compactMap { $0.id }
        }
    }
}
