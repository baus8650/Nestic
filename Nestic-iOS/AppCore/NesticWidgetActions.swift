import AppIntents
import Foundation
import WidgetKit

/// LiveActivityIntent routes widget actions to the containing app process,
/// where the existing authenticated store and keychain are available.
struct NesticWidgetLogIntent: LiveActivityIntent {
    static var title: LocalizedStringResource { "Log tracker" }
    static var openAppWhenRun: Bool { false }
    @Parameter(title: "Subject ID") var subjectID: String
    @Parameter(title: "Tracker ID") var trackerID: String

    init() {}
    init(subjectID: UUID, trackerID: UUID) {
        self.subjectID = subjectID.uuidString
        self.trackerID = trackerID.uuidString
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !NESTIC_WIDGET_EXTENSION
        guard let subject = UUID(uuidString: subjectID), let tracker = UUID(uuidString: trackerID) else {
            throw NesticError.message("This tracker is no longer available.")
        }
        let cachedPredictionAccess = UserDefaults(suiteName: NesticWidgetBridge.appGroup)?
            .data(forKey: NesticWidgetBridge.dataKey)
            .flatMap { try? JSONDecoder().decode(NesticWidgetStoreData.self, from: $0) }?.hasPredictionAccess ?? false
        let store = NesticWidgetActionStore.store ?? NesticStore(reminderStore: NesticReminderStore())
        store.setPredictionAccess(cachedPredictionAccess)
        guard let metric = store.trackers.first(where: { $0.id == tracker }), metric.valueType == .none else {
            throw NesticError.message("Open Nestic to enter the details for this tracker.")
        }
        try await store.log(subjectID: subject, trackerID: tracker)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
        return .result()
    }
}

struct NesticWidgetLogRoutineIntent: LiveActivityIntent {
    static var title: LocalizedStringResource { "Log routine" }
    static var openAppWhenRun: Bool { false }
    @Parameter(title: "Subject ID") var subjectID: String
    @Parameter(title: "Routine ID") var routineID: String

    init() {}
    init(subjectID: UUID, routineID: UUID) {
        self.subjectID = subjectID.uuidString
        self.routineID = routineID.uuidString
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !NESTIC_WIDGET_EXTENSION
        guard let subject = UUID(uuidString: subjectID), let id = UUID(uuidString: routineID) else {
            throw NesticError.message("This routine is no longer available.")
        }
        let cachedPredictionAccess = UserDefaults(suiteName: NesticWidgetBridge.appGroup)?
            .data(forKey: NesticWidgetBridge.dataKey)
            .flatMap { try? JSONDecoder().decode(NesticWidgetStoreData.self, from: $0) }?.hasPredictionAccess ?? false
        let store = NesticWidgetActionStore.store ?? NesticStore(reminderStore: NesticReminderStore())
        store.setPredictionAccess(cachedPredictionAccess)
        guard let routine = store.routines.first(where: { $0.id == id }),
              routine.targets.contains(where: { $0.entityID == subject }) else {
            throw NesticError.message("This routine is no longer available for this subject. Refresh your widget.")
        }
        // The store validates membership, Pro access, and every saved item,
        // and the server logs the complete routine in one request.
        try await store.logRoutine(routine)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
        return .result()
    }
}

struct NesticWidgetRefreshIntent: LiveActivityIntent {
    static var title: LocalizedStringResource { "Refresh widgets" }
    static var openAppWhenRun: Bool { false }

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !NESTIC_WIDGET_EXTENSION
        let cachedPredictionAccess = UserDefaults(suiteName: NesticWidgetBridge.appGroup)?
            .data(forKey: NesticWidgetBridge.dataKey)
            .flatMap { try? JSONDecoder().decode(NesticWidgetStoreData.self, from: $0) }?.hasPredictionAccess ?? false
        let store = NesticWidgetActionStore.store ?? NesticStore(reminderStore: NesticReminderStore())
        store.setPredictionAccess(cachedPredictionAccess)
        try await store.refresh(presentConnectionError: false, force: true)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
        return .result()
    }
}

#if !NESTIC_WIDGET_EXTENSION
@MainActor
enum NesticWidgetActionStore {
    static weak var store: NesticStore?
}
#endif
