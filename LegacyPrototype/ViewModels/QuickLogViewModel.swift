//
//  QuickLogViewModel.swift
//  Nestic-iOS
//
//  Created by Tim Bausch on 2/28/26.
//

import Foundation
import Combine
import CoreData

@MainActor
final class QuickLogViewModel: ObservableObject {
    enum ValueType: String {
        case none, number, text, boolean, json
    }

    @Published var valueNumberText: String = ""
    @Published var note: String = ""
    @Published private(set) var isSaving: Bool = false
    @Published private(set) var errorMessage: String?

    let entityId: String
    let actionId: UUID
    let actionName: String
    let valueType: ValueType
    let unit: String?

    private let repo: EventRepository
    private let auth: AuthViewModel
    private let context: NSManagedObjectContext

    init(
        entityId: String,
        actionId: UUID,
        actionName: String,
        valueTypeRaw: String,
        unit: String?,
        auth: AuthViewModel,
        context: NSManagedObjectContext,
        repo: EventRepository = EventRepository()
    ) {
        self.entityId = entityId
        self.actionId = actionId
        self.actionName = actionName
        self.valueType = ValueType(rawValue: valueTypeRaw) ?? .none
        self.unit = unit
        self.auth = auth
        self.context = context
        self.repo = repo
    }

    func save() async -> Bool {
        errorMessage = nil
        guard let token = auth.token else {
            errorMessage = "Not authenticated."
            return false
        }

        var valueNumber: Double? = nil

        if valueType == .number {
            let trimmed = valueNumberText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let parsed = Double(trimmed) else {
                errorMessage = "Enter a valid number."
                return false
            }
            valueNumber = parsed
        }

        isSaving = true
        defer { isSaving = false }

        do {
            let req = CreateEventRequest(
                actionID: actionId,
                occurredAt: nil,
                valueNumber: valueNumber,
                valueText: nil,
                valueBool: nil,
                valueJSON: nil,
                note: note.isEmpty ? nil : note
            )
            _ = try await repo.createEvent(entityId: entityId, request: req, token: token, context: context)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
