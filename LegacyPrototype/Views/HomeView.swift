//
//  HomeView.swift
//  Nestic-iOS
//
//  Created by Tim Bausch on 2/28/26.
//

import SwiftUI
import CoreData

struct HomeView: View {
    @EnvironmentObject var selectedNest: SelectedNestStore

    @FetchRequest private var entities: FetchedResults<CDEntity>

    init(nestId: String) {
        _entities = FetchRequest(
            entity: CDEntity.entity(),
            sortDescriptors: [NSSortDescriptor(key: "name", ascending: true)],
            predicate: NSPredicate(format: "nestId == %@", nestId)
        )
    }

    var body: some View {
        List {
            ForEach(entities, id: \.id) { entity in
                EntityRow(entity: entity)
            }
        }
        .navigationTitle("Home")
    }
}

private struct EntityRow: View {
    @ObservedObject var entity: CDEntity

    @EnvironmentObject var auth: AuthViewModel
    @Environment(\.managedObjectContext) private var context

    @State private var selectedAction: SelectedAction?

    struct SelectedAction: Identifiable {
        let id = UUID()
        let entityId: String
        let actionId: UUID
        let actionName: String
        let valueTypeRaw: String
        let unit: String?
    }

    private func selectAction(from pin: CDPinnedAction) {
        guard let entityId = entity.id,
              let actionIdStr = pin.actionId,
              let actionUUID = UUID(uuidString: actionIdStr) else { return }

        selectedAction = SelectedAction(
            entityId: entityId,
            actionId: actionUUID,
            actionName: pin.name ?? "Action",
            valueTypeRaw: pin.valueTypeRaw ?? "none",
            unit: pin.unit
        )
    }

    private func selectAction(from action: CDAction) {
        guard let entityId = entity.id,
              let actionIdStr = action.id,
              let actionUUID = UUID(uuidString: actionIdStr) else { return }

        selectedAction = SelectedAction(
            entityId: entityId,
            actionId: actionUUID,
            actionName: action.name ?? "Action",
            valueTypeRaw: action.valueTypeRaw ?? "none",
            unit: action.unit
        )
    }

    @FetchRequest private var pins: FetchedResults<CDPinnedAction>
    @FetchRequest private var lastEvents: FetchedResults<CDLastEvent>
    @FetchRequest private var allActions: FetchedResults<CDAction>

    init(entity: CDEntity) {
        self.entity = entity

        let entityId = entity.id ?? ""
        let nestId = entity.nestId ?? ""

        _pins = FetchRequest(
            entity: CDPinnedAction.entity(),
            sortDescriptors: [
                NSSortDescriptor(key: "sortOrder", ascending: true),
                NSSortDescriptor(key: "name", ascending: true)
            ],
            predicate: NSPredicate(format: "entityId == %@", entityId)
        )

        _lastEvents = FetchRequest(
            entity: CDLastEvent.entity(),
            sortDescriptors: [NSSortDescriptor(key: "occurredAt", ascending: false)],
            predicate: NSPredicate(format: "entityId == %@", entityId)
        )

        _allActions = FetchRequest(
            entity: CDAction.entity(),
            sortDescriptors: [NSSortDescriptor(key: "name", ascending: true)],
            predicate: NSPredicate(format: "nestId == %@", nestId)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(entity.name ?? "Unnamed")
                    .font(.headline)
                Spacer()
                Text(entity.kindRaw ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .contextMenu {
                if allActions.isEmpty {
                    Button("No actions available") {}
                        .disabled(true)
                } else {
                    // Long-press the entity header to log ANY action for this entity
                    ForEach(allActions, id: \.id) { action in
                        Button(action.name ?? "Action") {
                            selectAction(from: action)
                        }
                    }
                }
            }

            ForEach(pins, id: \.id) { pin in
                if let last = lastEvent(for: pin) {
                    PinnedActionRowWithLast(
                        pin: pin,
                        last: last,
                        onTap: { selectAction(from: pin) },
                        valueText: { lastValueText(pin: pin, last: last) },
                        relativeDateText: { relativeDate(last.occurredAt) }
                    )
                } else {
                    PinnedActionRowEmpty(
                        pin: pin,
                        onTap: { selectAction(from: pin) }
                    )
                }
            }
        }
        .padding(.vertical, 6)
        .sheet(item: $selectedAction) { sel in
            QuickLogView(
                vm: QuickLogViewModel(
                    entityId: sel.entityId,
                    actionId: sel.actionId,
                    actionName: sel.actionName,
                    valueTypeRaw: sel.valueTypeRaw,
                    unit: sel.unit,
                    auth: auth,
                    context: context
                )
            )
        }
    }

    private struct PinnedActionRowEmpty: View {
        @ObservedObject var pin: CDPinnedAction
        let onTap: () -> Void

        var body: some View {
            Button(action: onTap) {
                HStack {
                    Text(pin.name ?? "Action")
                        .font(.subheadline)
                    Spacer()
                    Text("—")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private struct PinnedActionRowWithLast: View {
        @ObservedObject var pin: CDPinnedAction
        @ObservedObject var last: CDLastEvent

        let onTap: () -> Void
        let valueText: () -> String?
        let relativeDateText: () -> String

        var body: some View {
            Button(action: onTap) {
                HStack {
                    Text(pin.name ?? "Action")
                        .font(.subheadline)
                    Spacer()

                    let vt = valueText()
                    VStack(alignment: .trailing, spacing: 2) {
                        if let vt {
                            Text(vt)
                                .font(.caption)
                        }
                        Text(relativeDateText())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

    private func lastEvent(for pin: CDPinnedAction) -> CDLastEvent? {
        guard
            let pinActionIdStr = pin.actionId,
            let pinActionId = UUID(uuidString: pinActionIdStr)
        else { return nil }

        return lastEvents.first(where: {
            guard let evActionIdStr = $0.actionId, let evActionId = UUID(uuidString: evActionIdStr) else { return false }
            return evActionId == pinActionId
        })
    }

    private func lastValueText(pin: CDPinnedAction, last: CDLastEvent?) -> String? {
        guard let last else { return nil }

        let valueType = (pin.valueTypeRaw ?? "none").lowercased()

        switch valueType {
        case "number":
            // Core Data optional doubles can be tricky; prefer checking via KVC for nil
            let raw = last.value(forKey: "valueNumber") as? Double
            guard let number = raw else { return nil }
            let formatted = formatNumber(number)
            if let unit = pin.unit, !unit.isEmpty {
                return "\(formatted) \(unit)"
            }
            return formatted

        case "text":
            if let text = last.valueText, !text.isEmpty { return text }
            return nil

        case "boolean", "bool":
            // If your model stores valueBool as non-optional, we still render it.
            let raw = last.value(forKey: "valueBool") as? Bool
            guard let b = raw else { return nil }
            return b ? "Yes" : "No"

        case "none":
            return nil

        default:
            // json or unknown types
            return nil
        }
    }

    private func formatNumber(_ value: Double) -> String {
        let nf = NumberFormatter()
        nf.numberStyle = .decimal
        nf.maximumFractionDigits = 2
        nf.minimumFractionDigits = 0
        return nf.string(from: NSNumber(value: value)) ?? String(value)
    }

    private func relativeDate(_ date: Date?) -> String {
        guard let date else { return "—" }
        return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
    }
}
