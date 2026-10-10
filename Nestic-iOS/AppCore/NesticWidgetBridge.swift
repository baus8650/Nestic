import Foundation
import WidgetKit

struct NesticWidgetMetricData: Codable, Sendable, Hashable {
    var id: UUID
    var name: String
    var symbol: String
    var isEmoji: Bool
    var color: String
    var supportsQuickLog: Bool? = nil
    /// Routine actions share the widget's action slots, but never tracker counts.
    var routineID: UUID? = nil
    var routineTrackerCount: Int? = nil
    var routineSubjectCount: Int? = nil
    var predictionAt: Date?
    var predictionConfidence: Int?
}

struct NesticWidgetSubjectData: Codable, Sendable, Hashable {
    var id: UUID
    var name: String
    var emoji: String
    /// A small, compressed avatar cache for widget rendering. Widgets cannot
    /// rely on the app or a network connection being available at render time.
    var photoData: String?
    var metrics: [NesticWidgetMetricData]
    var predictedAt: Date?
    var predictionConfidence: Int?
    /// Kept separate from the metrics shown in the widget: the next forecast
    /// may belong to a tracker that is not one of the two selected metrics.
    var predictionMetricName: String?
}

struct NesticWidgetEventData: Codable, Sendable, Hashable {
    var id: UUID
    var subjectID: UUID
    var metricID: UUID
    var occurredAt: Date
    /// Optional keeps widget payloads written by older app versions readable.
    var wasAccident: Bool? = nil
}

struct NesticWidgetQuietPeriod: Codable, Sendable {
    var startMinute: Int
    var endMinute: Int
}

struct NesticWidgetStoreData: Codable, Sendable {
    var defaultSubjectID: UUID?
    var subjects: [NesticWidgetSubjectData]
    var events: [NesticWidgetEventData]
    /// Optional so a widget can still decode data written by older app builds.
    var hasPredictionAccess: Bool?
    var quietHours: [NesticWidgetQuietPeriod]? = nil
}

enum NesticWidgetBridge {
    static let appGroup = "group.com.bausch.Nestic-iOS"
    static let dataKey = "nestic.widget.data.v6"

    @MainActor
    static func refresh(defaultSubject: NestSubject?, subjects: [NestSubject], trackers: [NestTracker], entries: [NestEntry], routines: [NestRoutine] = [], predictions: [UUID: [UUID: EventPrediction]], hasPredictionAccess: Bool, quietHours: [NestQuietHoursPeriod] = []) {
        guard let defaultSubject, let defaults = UserDefaults(suiteName: appGroup) else { return }
        let subjectIDs = Set(subjects.map(\.id))
        let widgetSubjects = subjects.map { subject in
            let subjectTrackers = subject.pinnedActionIDs.compactMap { id in trackers.first { $0.id == id } }
            let subjectPredictions = predictions[subject.id] ?? [:]
            // Do not limit the forecast to the widget's pinned metrics. A
            // user may choose to display two daily metrics while forecasting
            // a different tracker, and that forecast should remain visible.
            let nextPredictedPair = subjectPredictions
                .filter { $0.value.predictedAt > Date() }
                .min { $0.value.predictedAt < $1.value.predictedAt }
            let nearestPrediction = nextPredictedPair?.value
            let predictionTracker = nextPredictedPair.flatMap { pair in
                trackers.first { $0.id == pair.key }
            }
            // Keep saved routines discoverable while StoreKit restores access.
            // Logging still enforces Pro and nest permissions in the app store.
            let routineActions: [NesticWidgetMetricData] = routines
                .filter { $0.targets.contains { $0.entityID == subject.id } }
                .map { routine in
                    NesticWidgetMetricData(id: routine.id, name: routine.name, symbol: "square.stack.3d.up.fill",
                                           isEmoji: false, color: "#8CDBBD", supportsQuickLog: true,
                                           routineID: routine.id,
                                           routineTrackerCount: routine.targets.reduce(0) { $0 + $1.items.count },
                                           routineSubjectCount: routine.targets.count)
                }
            return NesticWidgetSubjectData(
                id: subject.id,
                name: subject.name,
                emoji: subject.emoji,
                photoData: subject.photoData,
                metrics: subjectTrackers.map { tracker in
                    let prediction = subjectPredictions[tracker.id]
                    let icon = trackerIconValue(tracker)
                    return NesticWidgetMetricData(id: tracker.id, name: tracker.name, symbol: icon,
                                                  isEmoji: TrackerIconCatalog.isEmoji(icon),
                                                  color: trackerColorValue(tracker),
                                                  supportsQuickLog: tracker.valueType == .none,
                                                  predictionAt: prediction?.predictedAt,
                                                  predictionConfidence: prediction?.confidencePercent)
                } + routineActions,
                predictedAt: nearestPrediction?.predictedAt,
                predictionConfidence: nearestPrediction?.confidencePercent,
                predictionMetricName: predictionTracker?.name
            )
        }
        let metricIDs = Set(widgetSubjects.flatMap { $0.metrics.map(\.id) })
        let widgetEvents = entries.compactMap { entry -> NesticWidgetEventData? in
            guard subjectIDs.contains(entry.entityId), metricIDs.contains(entry.actionId) else { return nil }
            return NesticWidgetEventData(id: entry.id, subjectID: entry.entityId, metricID: entry.actionId,
                                         occurredAt: entry.occurredAt, wasAccident: entry.isAccident)
        }
        let data = NesticWidgetStoreData(defaultSubjectID: defaultSubject.id,
                                         subjects: widgetSubjects,
                                         events: widgetEvents,
                                         hasPredictionAccess: hasPredictionAccess,
                                         quietHours: quietHours.map { NesticWidgetQuietPeriod(startMinute: $0.startMinute, endMinute: $0.endMinute) })
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        guard let encoded = try? encoder.encode(data), defaults.data(forKey: dataKey) != encoded else { return }
        defaults.set(encoded, forKey: dataKey)
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func clear() {
        UserDefaults(suiteName: appGroup)?.removeObject(forKey: dataKey)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
