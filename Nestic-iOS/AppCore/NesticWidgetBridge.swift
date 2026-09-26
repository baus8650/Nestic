import Foundation
import WidgetKit

struct NesticWidgetSnapshot: Codable, Sendable {
    var subjectID: UUID
    var subjectName: String
    var subjectEmoji: String
    var peeTrackerID: UUID?
    var poopTrackerID: UUID?
    var peeTrackerName: String?
    var poopTrackerName: String?
    var lastPee: Date?
    var lastPoop: Date?
    var todayPeeCount: Int
    var todayPoopCount: Int
    var predictedAt: Date?
    var predictionConfidence: Int?
}

enum NesticWidgetBridge {
    static let appGroup = "group.com.bausch.Nestic-iOS"
    static let snapshotKey = "nestic.widget.snapshot.v1"

    @MainActor
    static func refresh(subject: NestSubject?, trackers: [NestTracker], entries: [NestEntry], prediction: BathroomPrediction?) {
        guard let subject, let defaults = UserDefaults(suiteName: appGroup) else { return }
        let subjectEntries = entries.filter { $0.entityId == subject.id }
        let pee = subject.pinnedActionIDs.compactMap { id in trackers.first { $0.id == id } }.first { tracker in
            let name = tracker.name.lowercased()
            return name.contains("pee") || name.contains("potty") || name.contains("bathroom")
        }
        let poop = subject.pinnedActionIDs.compactMap { id in trackers.first { $0.id == id } }.first { tracker in
            tracker.name.lowercased().contains("poop")
        }
        let latestPee = pee.flatMap { tracker in
            subjectEntries.filter { entry in entry.actionId == tracker.id }.max { $0.occurredAt < $1.occurredAt }?.occurredAt
        }
        let latestPoop = poop.flatMap { tracker in
            subjectEntries.filter { entry in entry.actionId == tracker.id }.max { $0.occurredAt < $1.occurredAt }?.occurredAt
        }
        let today = Calendar.current
        let snapshot = NesticWidgetSnapshot(
            subjectID: subject.id,
            subjectName: subject.name,
            subjectEmoji: subject.emoji,
            peeTrackerID: pee?.id,
            poopTrackerID: poop?.id,
            peeTrackerName: pee?.name,
            poopTrackerName: poop?.name,
            lastPee: latestPee,
            lastPoop: latestPoop,
            todayPeeCount: pee.map { tracker in subjectEntries.filter { $0.actionId == tracker.id && today.isDateInToday($0.occurredAt) }.count } ?? 0,
            todayPoopCount: poop.map { tracker in subjectEntries.filter { $0.actionId == tracker.id && today.isDateInToday($0.occurredAt) }.count } ?? 0,
            predictedAt: prediction?.predictedAt,
            predictionConfidence: prediction?.confidencePercent
        )
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: snapshotKey)
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func clear() {
        UserDefaults(suiteName: appGroup)?.removeObject(forKey: snapshotKey)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
