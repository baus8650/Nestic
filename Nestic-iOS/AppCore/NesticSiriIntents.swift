import AppIntents
import Foundation

/// The combined tracker/entity value keeps the spoken command natural while
/// using one dynamic App Intents parameter: “Meal for Milo”.
struct NesticSiriTargetEntity: AppEntity, Hashable, Sendable {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Tracker")

    struct Query: EntityQuery {
        static var persistentIdentifier: String = "NesticSiri.TargetQuery"

        func entities(for identifiers: [String]) async throws -> [NesticSiriTargetEntity] {
            let targets = await nesticSiriTargets()
            let requested = Set(identifiers)
            return targets.filter { requested.contains($0.id) }
        }

        func suggestedEntities() async throws -> [NesticSiriTargetEntity] {
            await nesticSiriTargets()
        }
    }

    static var defaultQuery = Query()

    let id: String
    let subjectID: String
    let trackerID: String
    let displayString: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(displayString)")
    }
}

struct NesticSiriRecordTrackerIntent: AppIntent {
    static var title: LocalizedStringResource { "Record Tracker" }
    static var description: IntentDescription {
        "Record a tracker for an entity in Nestic."
    }
    static var openAppWhenRun: Bool { false }

    @Parameter(title: "Tracker for entity")
    var target: NesticSiriTargetEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Record \(\.$target)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let trackerID = UUID(uuidString: target.trackerID),
              let subjectID = UUID(uuidString: target.subjectID) else {
            return .result(dialog: "I couldn’t identify that tracker or entity.")
        }

        let message = await recordNesticSiriTarget(subjectID: subjectID, trackerID: trackerID)
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

struct NesticSiriRoutineEntity: AppEntity, Hashable, Sendable {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Routine")
    static var defaultQuery = Query()
    let id: String
    let name: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
    struct Query: EntityStringQuery {
        func entities(for identifiers: [String]) async throws -> [NesticSiriRoutineEntity] { await siriRoutines().filter { identifiers.contains($0.id) } }
        func suggestedEntities() async throws -> [NesticSiriRoutineEntity] { await siriRoutines() }
        func entities(matching string: String) async throws -> [NesticSiriRoutineEntity] { await siriRoutines().filter { $0.name.localizedCaseInsensitiveContains(string) } }
    }
}
struct NesticSiriRecordRoutineIntent: AppIntent {
    static var title: LocalizedStringResource { "Record Routine" }
    static var description: IntentDescription { "Record every saved tracker in a Nestic routine." }
    static var openAppWhenRun: Bool { false }
    @Parameter(title: "Routine") var routine: NesticSiriRoutineEntity
    @Parameter(title: "Recorded at") var recordedAt: Date?
    static var parameterSummary: some ParameterSummary { Summary("Record \(\.$routine)") { \.$recordedAt } }
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = await recordSiriRoutine(id: routine.id, date: recordedAt ?? Date())
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}
@MainActor private func siriRoutineStore() async -> NesticStore {
    let reminders = NesticReminderStore()
    let store = NesticWidgetActionStore.store ?? NesticStore(reminderStore: reminders)
    await store.start()
    let subscription = NesticSubscriptionStore()
    await subscription.refreshAccessForBackgroundAction(manualPro: store.currentUser?.manualPro == true)
    store.setPredictionAccess(subscription.hasPredictionAccess)
    return store
}
@MainActor private func siriRoutines() async -> [NesticSiriRoutineEntity] {
    let store = await siriRoutineStore()
    guard store.hasRoutineAccess else { return [] }
    return store.routines.map { NesticSiriRoutineEntity(id: $0.id.uuidString, name: $0.name) }
}
@MainActor private func recordSiriRoutine(id: String, date: Date) async -> String {
    let store = await siriRoutineStore()
    guard let id = UUID(uuidString: id), let routine = store.routines.first(where: { $0.id == id }) else { return "I couldn’t find that routine. Open Nestic and refresh your nest." }
    do { try await store.logRoutine(routine, date: date); return "Recorded \(routine.name)." }
    catch { return "I couldn’t record \(routine.name): \(error.localizedDescription)" }
}

struct NesticSiriShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: NesticSiriRecordRoutineIntent(), phrases: ["Run \(\.$routine) in \(.applicationName)", "Record \(\.$routine) in \(.applicationName)", "Log \(\.$routine) in \(.applicationName)"], shortTitle: "Record a routine", systemImageName: "checklist")
        AppShortcut(
            intent: NesticSiriRecordTrackerIntent(),
            phrases: [
                "Record \(\.$target) in \(.applicationName)",
                "Log \(\.$target) in \(.applicationName)"
            ],
            shortTitle: "Record a tracker",
            systemImageName: "checkmark.circle"
        )
    }
}

@MainActor
private func nesticSiriTargets() async -> [NesticSiriTargetEntity] {
    let store = NesticStore()
    await store.start()

    return store.subjects.flatMap { subject in
        store.trackers(for: subject).map { tracker in
            NesticSiriTargetEntity(
                id: "\(subject.id.uuidString)|\(tracker.id.uuidString)",
                subjectID: subject.id.uuidString,
                trackerID: tracker.id.uuidString,
                displayString: "\(tracker.name) for \(subject.name)"
            )
        }
    }
}

@MainActor
private func recordNesticSiriTarget(subjectID: UUID, trackerID: UUID) async -> String {
    let reminders = NesticReminderStore()
    let store = NesticStore(reminderStore: reminders)
    await store.start()
    guard let subject = store.subjects.first(where: { $0.id == subjectID }),
          let tracker = store.trackers.first(where: { $0.id == trackerID }),
          subject.pinnedActionIDs.contains(trackerID) else {
        return "I couldn’t find that tracker for the selected entity. Open Nestic on your iPhone and refresh your nest."
    }

    do {
        switch tracker.valueType {
        case .none:
            try await store.log(subjectID: subjectID, trackerID: trackerID)
        case .number:
            // The spoken command has no amount, so record one unit.
            try await store.log(subjectID: subjectID, trackerID: trackerID, number: 1)
        case .boolean:
            try await store.log(subjectID: subjectID, trackerID: trackerID, bool: true)
        case .text:
            try await store.log(subjectID: subjectID, trackerID: trackerID, text: "Recorded by Siri")
        case .json:
            return "\(tracker.name) needs more details. Open Nestic to record it."
        case .photo:
            return "\(tracker.name) needs a photo. Open Nestic on your iPhone to record it."
        case .health:
            return "\(tracker.name) needs onset details and possibly a photo. Open Nestic on your iPhone to record it."
        }
        return "Recorded \(tracker.name) for \(subject.name)."
    } catch {
        return "I couldn’t record \(tracker.name) for \(subject.name): \(error.localizedDescription)"
    }
}
