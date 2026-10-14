import Foundation
import SwiftUI
import WidgetKit
import AppIntents
import UIKit

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
    var photoData: String?
    var metrics: [NesticWidgetMetricData]
    var predictedAt: Date?
    var predictionConfidence: Int?
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
    /// Optional keeps payloads from previous app builds readable.
    var hasPredictionAccess: Bool?
    var quietHours: [NesticWidgetQuietPeriod]? = nil
}

struct NesticWidgetSubjectEntity: AppEntity, Hashable {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Person or thing")

    struct Query: EntityQuery {
        static var persistentIdentifier: String = "NesticWidget.SubjectQuery"

        func entities(for identifiers: [String]) async throws -> [NesticWidgetSubjectEntity] {
            let data = NesticWidgetDataReader.load()
            return data.subjects.filter { identifiers.contains($0.id.uuidString) }.map(Self.entity)
        }

        func suggestedEntities() async throws -> [NesticWidgetSubjectEntity] {
            NesticWidgetDataReader.load().subjects.map(Self.entity)
        }

        private static func entity(_ subject: NesticWidgetSubjectData) -> NesticWidgetSubjectEntity {
            NesticWidgetSubjectEntity(id: subject.id.uuidString, displayString: "\(subject.emoji) \(subject.name)")
        }
    }

    static var defaultQuery = Query()

    var id: String
    var displayString: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(displayString)")
    }

    init(id: String, displayString: String) {
        self.id = id
        self.displayString = displayString
    }
}

struct NesticWidgetMetricEntity: AppEntity, Hashable {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Tracker")

    struct Query: EntityQuery {
        static var persistentIdentifier: String = "NesticWidget.MetricQuery"

        @IntentParameterDependency<NesticWidgetConfigurationIntent>(\.$subject) var intent

        func entities(for identifiers: [String]) async throws -> [NesticWidgetMetricEntity] {
            let data = NesticWidgetDataReader.load()
            return NesticWidgetDataReader.trackers(in: data.subjects)
                .filter { identifiers.contains($0.id.uuidString) }.map(Self.entity)
        }

        func suggestedEntities() async throws -> [NesticWidgetMetricEntity] {
            let data = NesticWidgetDataReader.load()
            let subjectID = UUID(uuidString: intent?.subject.id ?? "")
            let subjects = subjectID.flatMap { id in data.subjects.filter { $0.id == id } } ?? data.subjects
            return NesticWidgetDataReader.trackers(in: subjects).map(Self.entity)
        }

        private static func entity(_ metric: NesticWidgetMetricData) -> NesticWidgetMetricEntity {
            NesticWidgetMetricEntity(id: metric.id.uuidString, displayString: metric.routineID != nil ? "Routine: \(metric.name)" : (metric.isEmoji ? "\(metric.symbol) \(metric.name)" : metric.name), symbol: metric.isEmoji ? nil : metric.symbol)
        }
    }

    static var defaultQuery = Query()

    var id: String
    var displayString: String
    var symbol: String?

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(displayString)", image: symbol.map { .init(systemName: $0) })
    }

    init(id: String, displayString: String, symbol: String? = nil) {
        self.id = id
        self.displayString = displayString
        self.symbol = symbol
    }
}

struct NesticFirstSubjectMetricEntity: AppEntity, Hashable {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Tracker or routine")

    struct Query: EntityQuery {
        static var persistentIdentifier: String = "NesticFirstSubjectMetricEntity.Query"

        @IntentParameterDependency<NesticPairConfigurationIntent>(\.$firstSubject) var intent

        func entities(for identifiers: [String]) async throws -> [NesticFirstSubjectMetricEntity] {
            let data = NesticWidgetDataReader.load()
            return NesticWidgetDataReader.actions(in: data.subjects)
                .filter { identifiers.contains($0.id.uuidString) }.map(Self.entity)
        }

        func suggestedEntities() async throws -> [NesticFirstSubjectMetricEntity] {
            let data = NesticWidgetDataReader.load()
            let subjectID = UUID(uuidString: intent?.firstSubject.id ?? "")
            let subjects = subjectID.flatMap { id in data.subjects.filter { $0.id == id } } ?? data.subjects
            return NesticWidgetDataReader.actions(in: subjects).map(Self.entity)
        }

        private static func entity(_ metric: NesticWidgetMetricData) -> NesticFirstSubjectMetricEntity {
            NesticFirstSubjectMetricEntity(id: metric.id.uuidString, displayString: metric.routineID != nil ? "Routine: \(metric.name)" : (metric.isEmoji ? "\(metric.symbol) \(metric.name)" : metric.name), symbol: metric.isEmoji ? nil : metric.symbol)
        }
    }

    static var defaultQuery = Query()

    var id: String
    var displayString: String
    var symbol: String?

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(displayString)", image: symbol.map { .init(systemName: $0) })
    }

    init(id: String, displayString: String, symbol: String? = nil) {
        self.id = id
        self.displayString = displayString
        self.symbol = symbol
    }
}

struct NesticSecondSubjectMetricEntity: AppEntity, Hashable {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Tracker or routine")

    struct Query: EntityQuery {
        static var persistentIdentifier: String = "NesticSecondSubjectMetricEntity.Query"

        @IntentParameterDependency<NesticPairConfigurationIntent>(\.$secondSubject) var intent

        func entities(for identifiers: [String]) async throws -> [NesticSecondSubjectMetricEntity] {
            let data = NesticWidgetDataReader.load()
            return NesticWidgetDataReader.actions(in: data.subjects)
                .filter { identifiers.contains($0.id.uuidString) }.map(Self.entity)
        }

        func suggestedEntities() async throws -> [NesticSecondSubjectMetricEntity] {
            let data = NesticWidgetDataReader.load()
            let subjectID = UUID(uuidString: intent?.secondSubject.id ?? "")
            let subjects = subjectID.flatMap { id in data.subjects.filter { $0.id == id } } ?? data.subjects
            return NesticWidgetDataReader.actions(in: subjects).map(Self.entity)
        }

        private static func entity(_ metric: NesticWidgetMetricData) -> NesticSecondSubjectMetricEntity {
            NesticSecondSubjectMetricEntity(id: metric.id.uuidString, displayString: metric.routineID != nil ? "Routine: \(metric.name)" : (metric.isEmoji ? "\(metric.symbol) \(metric.name)" : metric.name), symbol: metric.isEmoji ? nil : metric.symbol)
        }
    }

    static var defaultQuery = Query()

    var id: String
    var displayString: String
    var symbol: String?

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(displayString)", image: symbol.map { .init(systemName: $0) })
    }

    init(id: String, displayString: String, symbol: String? = nil) {
        self.id = id
        self.displayString = displayString
        self.symbol = symbol
    }
}

struct NesticWidgetConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "Nestic care" }
    static var description: IntentDescription { "Choose who to follow and the two trackers shown by this widget." }

    @Parameter(title: "Who in the nest")
    var subject: NesticWidgetSubjectEntity?

    @Parameter(title: "First tracker")
    var firstMetric: NesticWidgetMetricEntity?

    @Parameter(title: "Second tracker")
    var secondMetric: NesticWidgetMetricEntity?

    init() {}
}

struct NesticWidgetMetricSnapshot {
    var id: UUID
    var name: String
    var symbol: String
    var isEmoji: Bool = false
    var color: String = "#2E6B52"
    var supportsQuickLog: Bool = false
    var routineID: UUID? = nil
    var routineTrackerCount: Int? = nil
    var routineSubjectCount: Int? = nil
    var actionSummary: String {
        guard let count = routineTrackerCount else { return "\(eventDates.count) today" }
        let subjects = routineSubjectCount ?? 1
        return subjects > 1 ? "\(count) trackers · \(subjects) subjects" : "Routine · \(count) trackers"
    }
    var eventDates: [Date]
    var accidentDates: [Date] = []
    var lastEventAt: Date? = nil
    var predictionAt: Date? = nil
    var isForecastOnly: Bool = false
    var predictionConfidence: Int? = nil
}

struct NesticWidgetSnapshot {
    var subjectID: UUID
    var subjectName: String
    var subjectEmoji: String
    var subjectPhotoData: String? = nil
    var firstMetric: NesticWidgetMetricSnapshot?
    var secondMetric: NesticWidgetMetricSnapshot?
    var predictedAt: Date?
    var predictionConfidence: Int?
    var predictionMetricName: String?
    var hasPredictionAccess: Bool = false
    var quietHours: [NesticWidgetQuietPeriod] = []
}

struct NesticWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: NesticWidgetSnapshot?
}

private enum NesticWidgetDataReader {
    private static let appGroup = "group.com.bausch.Nestic-iOS"
    private static let dataKey = "nestic.widget.data.v6"

    static func actions(in subjects: [NesticWidgetSubjectData]) -> [NesticWidgetMetricData] {
        var seen = Set<UUID>()
        return subjects.flatMap(\.metrics).filter { seen.insert($0.id).inserted }
    }

    static func trackers(in subjects: [NesticWidgetSubjectData]) -> [NesticWidgetMetricData] {
        actions(in: subjects).filter { $0.routineID == nil }
    }

    static func load() -> NesticWidgetStoreData {
        guard let data = UserDefaults(suiteName: appGroup)?.data(forKey: dataKey),
              let decoded = try? JSONDecoder().decode(NesticWidgetStoreData.self, from: data) else {
            return NesticWidgetStoreData(defaultSubjectID: nil, subjects: [], events: [], hasPredictionAccess: nil)
        }
        return decoded
    }
}

/// Keep a full day of clock positions ready if WidgetKit delays a reload.
/// Include calendar midnight explicitly so counts and the axis roll over on
/// 23- and 25-hour days too.
enum NesticWidgetTimelineSchedule {
    static func dates(startingAt now: Date, calendar: Calendar = .current) -> [Date] {
        let end = now.addingTimeInterval(24 * 3600)
        var dates = [now]
        var cursor = now
        while cursor < end {
            let midnight = calendar.dateInterval(of: .day, for: cursor)?.end ?? end
            let next = min(cursor.addingTimeInterval(5 * 60), midnight, end)
            guard next > cursor else { break }
            dates.append(next)
            cursor = next
        }
        return dates
    }
}

struct NesticWidgetProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> NesticWidgetEntry {
        let now = Date()
        let first = NesticWidgetMetricSnapshot(id: UUID(), name: "Pee", symbol: "drop.fill", eventDates: [now.addingTimeInterval(-3600)], lastEventAt: now.addingTimeInterval(-3600), predictionAt: now.addingTimeInterval(3600))
        let second = NesticWidgetMetricSnapshot(id: UUID(), name: "Walk", symbol: "figure.walk", eventDates: [now.addingTimeInterval(-7200)], lastEventAt: now.addingTimeInterval(-7200))
        return NesticWidgetEntry(date: now, snapshot: NesticWidgetSnapshot(subjectID: UUID(), subjectName: "Milo", subjectEmoji: "🐶", firstMetric: first, secondMetric: second, predictedAt: now.addingTimeInterval(3600), predictionConfidence: 72, predictionMetricName: "Pee", hasPredictionAccess: true))
    }

    func snapshot(for configuration: NesticWidgetConfigurationIntent, in context: Context) async -> NesticWidgetEntry {
        let now = Date()
        return NesticWidgetEntry(date: now, snapshot: makeSnapshot(configuration: configuration, now: now))
    }

    func timeline(for configuration: NesticWidgetConfigurationIntent, in context: Context) async -> Timeline<NesticWidgetEntry> {
        let now = Date()
        let data = NesticWidgetDataReader.load()
        // Future entries move the clock even when iOS postpones a provider
        // reload. They reuse cached history; they never invent new forecasts.
        struct SnapshotKey: Hashable {
            let day: Date
            let forecastPhase: Int
        }
        let calendar = Calendar.current
        let forecastDates = Array(Set(data.subjects.flatMap { subject in
            subject.metrics.compactMap(\.predictionAt) + [subject.predictedAt].compactMap { $0 }
        })).sorted()
        var snapshots: [SnapshotKey: NesticWidgetSnapshot] = [:]
        let entries = NesticWidgetTimelineSchedule.dates(startingAt: now).map { date in
            // Counts and selected forecasts only change at midnight or when
            // a cached forecast passes. Reuse those snapshots between changes.
            let key = SnapshotKey(day: calendar.startOfDay(for: date),
                                  forecastPhase: forecastDates.prefix { $0 <= date }.count)
            let snapshot = snapshots[key] ?? makeSnapshot(configuration: configuration, now: date, data: data)
            snapshots[key] = snapshot
            return NesticWidgetEntry(date: date, snapshot: snapshot)
        }
        return Timeline(entries: entries, policy: .after(now.addingTimeInterval(5 * 60)))
    }

    func makeSnapshot(configuration: NesticWidgetConfigurationIntent, now: Date, includeRoutines: Bool = false, data cachedData: NesticWidgetStoreData? = nil) -> NesticWidgetSnapshot? {
        let data = cachedData ?? NesticWidgetDataReader.load()
        let subjectID = UUID(uuidString: configuration.subject?.id ?? "") ?? data.defaultSubjectID
        guard let subject = subjectID.flatMap({ id in data.subjects.first { $0.id == id } }) ?? data.subjects.first else { return nil }

        let availableMetrics = includeRoutines ? subject.metrics : subject.metrics.filter { $0.routineID == nil }
        let firstID = UUID(uuidString: configuration.firstMetric?.id ?? "")
        let firstMetric = availableMetrics.first { $0.id == firstID } ?? availableMetrics.first
        let secondID = UUID(uuidString: configuration.secondMetric?.id ?? "")
        let secondMetric = availableMetrics.first { $0.id == secondID && $0.id != firstMetric?.id }
            ?? availableMetrics.first { $0.id != firstMetric?.id }

        func snapshot(for metric: NesticWidgetMetricData?) -> NesticWidgetMetricSnapshot? {
            guard let metric else { return nil }
            let metricEvents = data.events.filter { $0.subjectID == subject.id && $0.metricID == metric.id }
            let allDates = metricEvents.map(\.occurredAt)
            let dates = allDates.filter { Calendar.current.isDate($0, inSameDayAs: now) }.sorted()
            let accidentDates = metricEvents
                .filter { $0.wasAccident == true && Calendar.current.isDate($0.occurredAt, inSameDayAs: now) }
                .map(\.occurredAt)
            return NesticWidgetMetricSnapshot(id: metric.id, name: metric.name, symbol: metric.symbol, isEmoji: metric.isEmoji, color: metric.color, supportsQuickLog: metric.supportsQuickLog ?? false,
                                              routineID: metric.routineID, routineTrackerCount: metric.routineTrackerCount,
                                              routineSubjectCount: metric.routineSubjectCount, eventDates: dates,
                                              accidentDates: accidentDates,
                                              lastEventAt: allDates.max(),
                                              predictionAt: metric.predictionAt,
                                              predictionConfidence: metric.predictionConfidence)
        }

        let selectedMetrics = [snapshot(for: firstMetric), snapshot(for: secondMetric)].compactMap { $0 }
        let nextMetricPrediction = selectedMetrics
            .filter { ($0.predictionAt ?? .distantPast) > now }
            .min { $0.predictionAt! < $1.predictionAt! }

        let subjectForecastIsUpcoming = (subject.predictedAt ?? .distantPast) > now
        let predictedAt = nextMetricPrediction?.predictionAt
            ?? (subjectForecastIsUpcoming ? subject.predictedAt : nil)

        return NesticWidgetSnapshot(
            subjectID: subject.id,
            subjectName: subject.name,
            subjectEmoji: subject.emoji,
            subjectPhotoData: subject.photoData,
            firstMetric: snapshot(for: firstMetric),
            secondMetric: snapshot(for: secondMetric),
            predictedAt: predictedAt,
            predictionConfidence: nextMetricPrediction?.predictionConfidence ?? (subjectForecastIsUpcoming ? subject.predictionConfidence : nil),
            predictionMetricName: nextMetricPrediction?.name ?? (subjectForecastIsUpcoming ? subject.predictionMetricName : nil),
            hasPredictionAccess: data.hasPredictionAccess ?? false,
            quietHours: data.quietHours ?? []
        )
    }
}

struct NesticWidgetView: View {
    let entry: NesticWidgetEntry
    @Environment(\.widgetFamily) private var family

    private let lime = Color(red: 0.84, green: 0.93, blue: 0.60)
    private let mint = Color(red: 0.55, green: 0.86, blue: 0.74)

    var body: some View {
        Group {
            if let snapshot = entry.snapshot {
                switch family {
                case .systemSmall: small(snapshot)
                case .systemMedium: medium(snapshot)
                case .systemLarge: large(snapshot)
                    
                case
                        .accessoryInline: lockScreenInline(snapshot)
                case .accessoryCircular: lockScreenCircular(snapshot)
                case .accessoryRectangular: lockScreenRectangular(snapshot)
                default: medium(snapshot)
            }
            } else {
                empty
            }
        }
        .containerBackground(for: .widget) {
            LinearGradient(colors: [Color(red: 0.14, green: 0.30, blue: 0.24), Color(red: 0.23, green: 0.42, blue: 0.31)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
        .widgetURL(entry.snapshot.flatMap(subjectURL))
    }

    private func subjectURL(_ snapshot: NesticWidgetSnapshot) -> URL? {
        URL(string: "nestic://subject?subjectID=\(snapshot.subjectID.uuidString)")
    }

    private func small(_ snapshot: NesticWidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                subjectImage(snapshot, size: 29)
                Text(snapshot.subjectName)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }
            if snapshot.firstMetric != nil || snapshot.secondMetric != nil {
                VStack(alignment: .leading, spacing: 4) {
                    smallMetric(snapshot.firstMetric, subjectID: snapshot.subjectID, fallback: lime)
                    smallMetric(snapshot.secondMetric, subjectID: snapshot.subjectID, fallback: mint)
                }
            } else {
                Text("Choose two trackers or routines in widget settings")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.78))
                    .lineLimit(2)
            }
            smallForecast(snapshot)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 0)
        .padding(.vertical, 0)
    }

    @ViewBuilder
    private func smallMetric(_ metric: NesticWidgetMetricSnapshot?, subjectID: UUID, fallback: Color) -> some View {
        if let metric {
            if let routineID = metric.routineID {
                Button(intent: NesticWidgetLogRoutineIntent(subjectID: subjectID, routineID: routineID)) {
                    smallMetricLabel(metric, fallback: fallback)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Log \(metric.name), \(metric.actionSummary)")
            } else {
                smallMetricLabel(metric, fallback: fallback)
            }
        }
    }

    private func smallMetricLabel(_ metric: NesticWidgetMetricSnapshot, fallback: Color) -> some View {
        let tint = metricTint(metric, fallback: fallback)
        return HStack(spacing: 6) {
            metricIcon(metric, tint: tint, font: .subheadline.weight(.semibold)).frame(width: 20)
            Text(metric.name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.88))
                .lineLimit(1)
                .minimumScaleFactor(0.62)
                .layoutPriority(1)
            Spacer(minLength: 2)
            Text(metric.routineID == nil ? "\(metric.eventDates.count)" : "Routine")
                .font(metric.routineID == nil ? .title3.weight(.bold) : .caption.weight(.semibold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.65)
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func smallForecast(_ snapshot: NesticWidgetSnapshot) -> some View {
        Group {
            if snapshot.hasPredictionAccess {
                HStack(spacing: 5) {
                    Image(systemName: "sparkles")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(lime)
                    if let predictedAt = snapshot.predictedAt {
                        Text(snapshot.predictionMetricName ?? "Next event")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.82))
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)
                        Spacer(minLength: 2)
                        Text(smallCompactProjectionLabel(for: predictedAt))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)
                            .layoutPriority(1)
                    } else {
                        Text("No forecast yet")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.white.opacity(0.68))
                            .lineLimit(1)
                    }
                }
            } else {
                recentActivityFooter(snapshot)
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
    }

    private func smallCompactProjectionLabel(for date: Date) -> String {
        let day = smallProjectionDayLabel(for: date)
        let time = date.formatted(.dateTime.hour().minute())
        return day == "Today" ? time : "\(day) \(time)"
    }

    private func smallProjectionDayLabel(for date: Date) -> String {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: entry.date)
        let projectedDay = calendar.startOfDay(for: date)
        let dayDistance = calendar.dateComponents([.day], from: today, to: projectedDay).day ?? 0

        switch dayDistance {
        case ...0: return "Today"
        case 1: return "Tomorrow"
        case 2...7: return date.formatted(.dateTime.weekday(.abbreviated))
        default: return date.formatted(.dateTime.month(.abbreviated).day())
        }
    }

    private func medium(_ snapshot: NesticWidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                subjectImage(snapshot, size: 26)
                Text(snapshot.subjectName).font(.subheadline.bold()).foregroundStyle(.white).lineLimit(1)
                Spacer()
            }
            HStack(spacing: 8) {
                mediumMetric(snapshot.firstMetric, tint: lime, hasPredictionAccess: snapshot.hasPredictionAccess)
                mediumMetric(snapshot.secondMetric, tint: mint, hasPredictionAccess: snapshot.hasPredictionAccess)
            }
            mediumForecast(snapshot)
            HStack(spacing: 6) {
                quickLog(snapshot, metric: snapshot.firstMetric, title: "Log", icon: snapshot.firstMetric?.symbol ?? "plus", compact: true)
                quickLog(snapshot, metric: snapshot.secondMetric, title: "Log", icon: snapshot.secondMetric?.symbol ?? "plus", compact: true)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private func mediumForecast(_ snapshot: NesticWidgetSnapshot) -> some View {
        if snapshot.hasPredictionAccess {
            HStack(spacing: 5) {
                Image(systemName: "sparkles")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(lime)
                Text(snapshot.predictionMetricName.map { "Next \($0)" } ?? "Next predicted event")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 3)
                if let predictedAt = snapshot.predictedAt {
                    Text(projectedDateLabel(for: predictedAt))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                        .layoutPriority(1)
                } else {
                    Text("No forecast yet")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.white.opacity(0.62))
                }
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
        }
    }

    private func projectedDateLabel(for date: Date) -> String {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: entry.date)
        let projectedDay = calendar.startOfDay(for: date)
        let dayDistance = calendar.dateComponents([.day], from: today, to: projectedDay).day ?? 0
        let time = date.formatted(.dateTime.hour().minute())

        switch dayDistance {
        case ...0:
            return "Today \(time)"
        case 1:
            return "Tomorrow \(time)"
        case 2...7:
            return "\(date.formatted(.dateTime.weekday(.abbreviated))) \(time)"
        default:
            return date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
        }
    }

    private func mostRecentMetric(in snapshot: NesticWidgetSnapshot) -> NesticWidgetMetricSnapshot? {
        [snapshot.firstMetric, snapshot.secondMetric]
            .compactMap { $0 }
            .max { ($0.lastEventAt ?? .distantPast) < ($1.lastEventAt ?? .distantPast) }
    }

    private func recentActivityFooter(_ snapshot: NesticWidgetSnapshot) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white.opacity(0.68))
            if let metric = mostRecentMetric(in: snapshot), let date = metric.lastEventAt {
                Text("Last \(metric.name) \(lastRecordedLabel(for: date, compact: true))")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.white.opacity(0.76))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            } else {
                Text("Ready for your first update")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.white.opacity(0.76))
            }
        }
    }

    private func recentActivityCard(_ snapshot: NesticWidgetSnapshot, compact: Bool = false) -> some View {
        HStack(spacing: compact ? 5 : 8) {
            Image(systemName: "clock.arrow.circlepath")
                .font(compact ? .caption2.weight(.bold) : .headline.weight(.bold))
                .foregroundStyle(.white.opacity(0.8))
            VStack(alignment: .leading, spacing: 1) {
                Text("Recent activity")
                    .font(compact ? .caption2.weight(.medium) : .headline.weight(.semibold))
                    .foregroundStyle(.white)
                if let metric = mostRecentMetric(in: snapshot), let date = metric.lastEventAt {
                    Text("Last \(metric.name) · \(lastRecordedLabel(for: date))")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(1)
                } else {
                    Text("Use the buttons below to log an update")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, compact ? 7 : 11)
        .padding(.vertical, compact ? 6 : 9)
        .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: compact ? 10 : 12))
    }

    private func large(_ snapshot: NesticWidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                subjectImage(snapshot, size: 38)
                VStack(alignment: .leading, spacing: 3) {
                    Text(snapshot.subjectName).font(.title3.bold()).foregroundStyle(.white)
                    Text("Today’s care at a glance").font(.caption).foregroundStyle(.white.opacity(0.75))
                }
                Spacer()
            }
            Divider().overlay(.white.opacity(0.25))
            dailyGraph(snapshot)
            if snapshot.hasPredictionAccess, let predictedAt = snapshot.predictedAt {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.white.opacity(0.8))
                        Text(snapshot.predictionMetricName.map { "Next \($0)" } ?? "Next predicted event")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Spacer(minLength: 6)
                        Text(predictedAt, format: .dateTime.weekday(.abbreviated).hour().minute())
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .layoutPriority(1)
                    }
                    if let confidence = snapshot.predictionConfidence {
                        Text("\(confidence)% confidence")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.white.opacity(0.65))
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 9)
                .background(.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
            } else if !snapshot.hasPredictionAccess {
                recentActivityCard(snapshot)
            }
            HStack(spacing: 8) {
                quickLog(snapshot, metric: snapshot.firstMetric, title: "Log", icon: snapshot.firstMetric?.symbol ?? "plus")
                quickLog(snapshot, metric: snapshot.secondMetric, title: "Log", icon: snapshot.secondMetric?.symbol ?? "plus")
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
    }

    private func graphMetrics(_ snapshot: NesticWidgetSnapshot) -> [NesticWidgetMetricSnapshot] {
        var metrics = [snapshot.firstMetric, snapshot.secondMetric].compactMap { $0 }
        // The forecast card can belong to a tracker outside the two selected
        // actions. Give that forecast its own lane rather than losing its dot.
        if snapshot.hasPredictionAccess, let forecast = snapshot.predictedAt,
           let name = snapshot.predictionMetricName {
            if let index = metrics.firstIndex(where: { $0.routineID == nil && $0.name == name }) {
                if metrics[index].predictionAt == nil { metrics[index].predictionAt = forecast }
            } else {
                metrics.append(NesticWidgetMetricSnapshot(id: snapshot.subjectID, name: name,
                                                          symbol: "sparkles", eventDates: [], predictionAt: forecast, isForecastOnly: true))
            }
        }
        return metrics
    }

    private func dailyGraph(_ snapshot: NesticWidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Label("Today", systemImage: "chart.xyaxis.line")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.82))
                Spacer()
                Text(entry.date, format: .dateTime.month(.abbreviated).day()).font(.caption2).foregroundStyle(.white.opacity(0.7))
            }
            VStack(spacing: 10) {
                ForEach(Array(graphMetrics(snapshot).enumerated()), id: \.offset) { index, metric in
                    if metric.isForecastOnly {
                        timelineRow(metric, tint: lime, showsCount: false)
                    } else {
                        actionRow(metric, tint: metricTint(metric, fallback: index == 0 ? lime : mint))
                    }
                }
            }
            if graphMetrics(snapshot).contains(where: { $0.routineID == nil }) {
                timelineAxis
                HStack(spacing: 8) {
                    Rectangle().fill(.white.opacity(0.85)).frame(width: 2, height: 9)
                    Text("As of \(entry.date.formatted(date: .omitted, time: .shortened))")
                    if snapshot.hasPredictionAccess {
                        Circle().fill(.white.opacity(0.25))
                            .overlay(Circle().strokeBorder(.white.opacity(0.65), style: StrokeStyle(lineWidth: 1, dash: [2, 2])))
                            .frame(width: 9, height: 9)
                        Text("Predicted")
                    }
                }
                .font(.system(size: 9)).foregroundStyle(.white.opacity(0.7))
                .lineLimit(1).minimumScaleFactor(0.8)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .background(.black.opacity(0.13), in: RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private func actionRow(_ metric: NesticWidgetMetricSnapshot, tint: Color) -> some View {
        if metric.routineID != nil {
            VStack(alignment: .leading, spacing: 5) {
                Label(metric.name, systemImage: metric.symbol).font(.caption.weight(.semibold))
                Text(metric.actionSummary).font(.caption2).opacity(0.75)
            }.foregroundStyle(.white).frame(maxWidth: .infinity, alignment: .leading)
        } else {
            timelineRow(metric, tint: tint)
        }
    }

    private func timelineRow(_ metric: NesticWidgetMetricSnapshot, tint: Color, showsCount: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                metricIcon(metric, tint: tint, font: .caption)
                Text(metric.name).font(.caption.weight(.semibold)).foregroundStyle(.white).lineLimit(1)
                Spacer(minLength: 8)
                if showsCount {
                    Text("\(metric.eventDates.count)").font(.caption.bold()).foregroundStyle(.white.opacity(0.78))
                }
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.14))
                        .overlay {
                            NesticQuietHoursBands(intervals: timelineQuietIntervals,
                                day: Calendar.current.dateInterval(of: .day, for: entry.date) ?? DateInterval(start: entry.date, duration: 86400))
                                .fill(.white.opacity(0.38))
                                .clipShape(Capsule())
                                .accessibilityHidden(true)
                        }
                    ForEach(1..<4, id: \.self) { index in
                        Rectangle()
                            .fill(.white.opacity(0.17))
                            .frame(width: 1, height: 22)
                            .position(x: proxy.size.width * CGFloat(index) / 4, y: proxy.size.height / 2)
                    }
                    // Show the time represented by this timeline entry, rather
                    // than suggesting that a delayed widget is a live clock.
                    Rectangle()
                        .fill(.white.opacity(0.85))
                        .frame(width: 1.5, height: 22)
                        .position(x: markerPosition(for: entry.date, width: proxy.size.width), y: proxy.size.height / 2)
                        .accessibilityLabel("Time as of \(entry.date.formatted(date: .omitted, time: .shortened))")
                    if entry.snapshot?.hasPredictionAccess == true,
                       let predictedAt = metric.predictionAt,
                       Calendar.current.isDate(predictedAt, inSameDayAs: entry.date) {
                        let isOverdue = predictedAt < entry.date
                        let predictionTint: Color = isOverdue ? .red : tint
                        Circle()
                            .fill(predictionTint.opacity(0.4))
                            .overlay(Circle().strokeBorder(predictionTint.opacity(0.95), style: StrokeStyle(lineWidth: 1.5, dash: [2, 2])))
                            .frame(width: 18, height: 18)
                            .position(x: markerPosition(for: predictedAt, width: proxy.size.width), y: proxy.size.height / 2)
                            .accessibilityLabel("Predicted \(metric.name), \(predictedAt.formatted(date: .abbreviated, time: .shortened))")
                            .accessibilityValue(isOverdue ? "Past predicted time" : "Upcoming prediction")
                    }
                    ForEach(Array(metric.eventDates.enumerated()), id: \.offset) { _, date in
                        Group {
                            if metric.accidentDates.contains(date) {
                                Circle()
                                    .fill(LinearGradient(colors: [.red, tint], startPoint: .leading, endPoint: .trailing))
                            } else {
                                Circle().fill(tint)
                            }
                        }
                        .frame(width: 10, height: 10)
                        .position(x: markerPosition(for: date, width: proxy.size.width), y: proxy.size.height / 2)
                    }
                }
            }
            .frame(height: 22)
        }
        .frame(maxWidth: .infinity)
    }

    private var timelineQuietIntervals: [DateInterval] {
        NesticTimelineQuietHours.intervals(on: entry.date,
            periods: (entry.snapshot?.quietHours ?? []).map { ($0.startMinute, $0.endMinute) })
    }

    private var uses24HourClock: Bool {
        let template = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .autoupdatingCurrent) ?? ""
        return template.contains("H") || template.contains("k")
    }

    private var timelineAxis: some View {
        GeometryReader { proxy in
            ZStack {
                ForEach([0, 6, 12, 18, 24], id: \.self) { hour in
                    Text(axisLabel(for: hour))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.white.opacity(0.55))
                        .fixedSize()
                        .frame(width: proxy.size.width, height: proxy.size.height,
                               alignment: hour == 0 ? .leading : (hour == 24 ? .trailing : .center))
                        .offset(x: hour == 0 || hour == 24
                                ? 0
                                : proxy.size.width * timelineFraction(for: hour) - proxy.size.width / 2)
                }
            }
        }
        .frame(height: 16)
    }

    private func axisLabel(for hour: Int) -> String {
        let date = timelineDate(for: hour)
        if uses24HourClock {
            return date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)))
        }
        return date.formatted(.dateTime.hour(.defaultDigits(amPM: .abbreviated)))
    }

    private func timelineDate(for hour: Int) -> Date {
        let calendar = Calendar.current
        let interval = calendar.dateInterval(of: .day, for: entry.date)
        let start = interval?.start ?? calendar.startOfDay(for: entry.date)
        if hour == 24, let end = interval?.end {
            return end
        }
        return calendar.date(byAdding: .hour, value: hour, to: start) ?? start
    }

    private func timelineFraction(for hour: Int) -> CGFloat {
        let calendar = Calendar.current
        let interval = calendar.dateInterval(of: .day, for: entry.date)
        let start = interval?.start ?? calendar.startOfDay(for: entry.date)
        let duration = interval?.duration ?? 86_400
        let fraction = timelineDate(for: hour).timeIntervalSince(start) / duration
        return CGFloat(min(1, max(0, fraction)))
    }

    private func markerPosition(for date: Date, width: CGFloat) -> CGFloat {
        let interval = Calendar.current.dateInterval(of: .day, for: entry.date)
        let start = interval?.start ?? Calendar.current.startOfDay(for: entry.date)
        let duration = interval?.duration ?? 86_400
        let fraction = min(1, max(0, date.timeIntervalSince(start) / duration))
        return min(max(4, width - 4), max(4, CGFloat(fraction) * width))
    }

    private func lockScreenInline(_ snapshot: NesticWidgetSnapshot) -> some View {
        Text(lockScreenSummary(snapshot))
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .widgetAccentable()
    }

    private func lockScreenCircular(_ snapshot: NesticWidgetSnapshot) -> some View {
        let metric = snapshot.firstMetric

        return VStack(spacing: 1) {
            if let metric {
                metricIcon(metric, tint: .primary, font: .caption)
                    .widgetAccentable()
                Text(metric.routineID == nil ? (metric.lastEventAt.map { lastRecordedLabel(for: $0, compact: true) } ?? "No logs") : "Routine")
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                    .widgetAccentable()
                Text(metric.name)
                    .font(.system(size: 8, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
            } else {
                Image(systemName: "pawprint.fill")
                    .font(.title3)
                    .widgetAccentable()
                Text("Set up")
                    .font(.system(size: 8, weight: .semibold))
            }
        }
        .padding(2)
    }

    private func lockScreenRectangular(_ snapshot: NesticWidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                subjectImage(snapshot, size: 17)
                Text(snapshot.subjectName)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
            if snapshot.firstMetric != nil || snapshot.secondMetric != nil {
                HStack(spacing: 9) {
                    lockScreenMetric(snapshot.firstMetric)
                    lockScreenMetric(snapshot.secondMetric)
                }
            } else {
                Text("Choose metrics in Nestic")
                    .font(.caption2)
                    .lineLimit(1)
            }
        }
        .widgetAccentable()
    }

    private func lockScreenMetric(_ metric: NesticWidgetMetricSnapshot?) -> some View {
        Group {
            if let metric {
                HStack(spacing: 3) {
                    metricIcon(metric, tint: .primary, font: .caption2)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(metric.name)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Text(metric.routineID == nil ? (metric.lastEventAt.map { lastRecordedLabel(for: $0) } ?? "No logs") : metric.actionSummary)
                            .font(.caption2)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                }
            }
        }
    }

    private func lockScreenSummary(_ snapshot: NesticWidgetSnapshot) -> String {
        let metrics = [snapshot.firstMetric, snapshot.secondMetric].compactMap { $0 }
        guard !metrics.isEmpty else { return "Nestic · Set up metrics" }

        let summary = metrics.map { metric in
            metric.routineID == nil ? "\(metric.name) \(metric.lastEventAt.map { lastRecordedLabel(for: $0, compact: true) } ?? "—")" : "\(metric.name) · Routine"
        }.joined(separator: " · ")
        return "\(snapshot.subjectName) · \(summary)"
    }

    private func lastRecordedLabel(for date: Date, compact: Bool = false) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return date.formatted(.dateTime.hour().minute())
        }
        if compact {
            return date.formatted(.dateTime.hour().minute())
        }
        return date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
    }

    private var empty: some View {
        VStack(spacing: 5) {
            Image(systemName: "pawprint.fill").font(.title2).foregroundStyle(lime)
            Text("Open Nestic to choose a subject").font(.caption).multilineTextAlignment(.center).foregroundStyle(.white)
        }.padding(14)
    }

    private func metricCard(_ metric: NesticWidgetMetricSnapshot?, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let metric {
                HStack(spacing: 5) {
                    metricIcon(metric, tint: tint, font: .body)
                    Text(metric.name).font(.caption.weight(.semibold)).foregroundStyle(.white).lineLimit(1)
                }
                Text(metric.routineID == nil ? "\(metric.eventDates.count)" : "Routine").font(.system(.title2, design: .rounded, weight: .bold)).foregroundStyle(.white)
                Text(metric.routineID == nil ? "today" : metric.actionSummary).font(.caption2).foregroundStyle(.white.opacity(0.7))
            } else {
                Text("Choose a metric").font(.caption).foregroundStyle(.white.opacity(0.7))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func mediumMetric(_ metric: NesticWidgetMetricSnapshot?, tint: Color, hasPredictionAccess: Bool) -> some View {
        Group {
            if let metric {
                let accent = metricTint(metric, fallback: tint)
                HStack(spacing: 5) {
                    metricIcon(metric, tint: accent, font: .caption)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(metric.name).font(.subheadline.weight(.semibold)).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.7)
                        if metric.routineID != nil {
                            Text(metric.actionSummary).font(.caption2).foregroundStyle(.white.opacity(0.7))
                        } else {
                            Text(metricForecastSummary(metric, hasPredictionAccess: hasPredictionAccess))
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(hasPredictionAccess ? .white.opacity(0.78) : .white.opacity(0.55))
                                .lineLimit(1)
                                .minimumScaleFactor(0.55)
                        }
                    }
                    Spacer(minLength: 0)
                }
            } else {
                Text("Choose a metric").font(.caption2).foregroundStyle(.white.opacity(0.65))
            }
        }
        .frame(maxWidth: .infinity, minHeight: 32, maxHeight: 32, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background((metric.map { metricTint($0, fallback: tint) } ?? tint).opacity(0.18),
                    in: RoundedRectangle(cornerRadius: 10))
    }

    private func metricForecastSummary(_ metric: NesticWidgetMetricSnapshot, hasPredictionAccess: Bool) -> String {
        let count = metric.eventDates.count == 1 ? "1" : "\(metric.eventDates.count)"
        guard hasPredictionAccess else { return "\(count) today" }
        guard let predictedAt = metric.predictionAt, predictedAt > entry.date else {
            return "\(count) today · No forecast yet"
        }
        return "\(count) today · \(projectedDateLabel(for: predictedAt))"
    }

    @ViewBuilder
    private func quickLog(_ snapshot: NesticWidgetSnapshot, metric: NesticWidgetMetricSnapshot?, title: String, icon: String, compact: Bool = false) -> some View {
        if let metric, let url = URL(string: "nestic://record?subjectID=\(snapshot.subjectID.uuidString)&trackerID=\(metric.id.uuidString)") {
            Group {
                if let routineID = metric.routineID {
                    Button(intent: NesticWidgetLogRoutineIntent(subjectID: snapshot.subjectID, routineID: routineID)) {
                        quickLogLabel(metric, title: title, icon: icon, compact: compact)
                    }.buttonStyle(.plain)
                } else if metric.supportsQuickLog {
                    Button(intent: NesticWidgetLogIntent(subjectID: snapshot.subjectID, trackerID: metric.id)) {
                        quickLogLabel(metric, title: title, icon: icon, compact: compact)
                    }.buttonStyle(.plain)
                } else {
                    Link(destination: url) {
                        quickLogLabel(metric, title: title, icon: icon, compact: compact)
                    }
                }
            }
            .foregroundStyle(.white)
            .accessibilityLabel("\(title) \(metric.name) for \(snapshot.subjectName)")
        }
    }

    private func quickLogLabel(_ metric: NesticWidgetMetricSnapshot, title: String, icon: String, compact: Bool) -> some View {
                Group {
                    if metric.isEmoji {
                        HStack(spacing: 4) {
                            metricIcon(metric, tint: .white, font: .caption2)
                            Text("\(title) \(metric.name)")
                        }
                    } else {
                        Label("\(title) \(metric.name)", systemImage: icon)
                    }
                }
                .font(.caption2.weight(compact ? .medium : .semibold)).lineLimit(1).minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity).padding(.vertical, compact ? 5 : 8)
                 .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))
    }


    @ViewBuilder
    private func subjectImage(_ snapshot: NesticWidgetSnapshot, size: CGFloat) -> some View {
        if let encoded = snapshot.subjectPhotoData,
           let data = Data(base64Encoded: encoded),
           let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.3))
                .overlay {
                    RoundedRectangle(cornerRadius: size * 0.3)
                        .stroke(.white.opacity(0.32), lineWidth: 1)
                }
        } else {
            Text(snapshot.subjectEmoji)
                .font(.system(size: size * 0.56))
                .frame(width: size, height: size)
                .background(.white.opacity(0.13), in: RoundedRectangle(cornerRadius: size * 0.3))
        }
    }

    @ViewBuilder
    private func metricIcon(_ metric: NesticWidgetMetricSnapshot, tint: Color, font: Font) -> some View {
        if metric.isEmoji {
            Text(metric.symbol).font(font)
        } else {
            Image(systemName: metric.symbol).font(font).foregroundStyle(tint)
        }
    }

    private func metricTint(_ metric: NesticWidgetMetricSnapshot, fallback: Color) -> Color {
        color(from: metric.color) ?? fallback
    }

    private func color(from hex: String) -> Color? {
        let clean = hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        guard clean.count == 6, let value = UInt64(clean, radix: 16) else { return nil }
        return Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}

struct NesticWidget: Widget {
    let kind = "NesticWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: NesticWidgetConfigurationIntent.self, provider: NesticWidgetProvider()) { entry in
            NesticWidgetView(entry: entry)
        }
        .configurationDisplayName("Nestic care")
        .description("Choose who to follow and two trackers or routines to log from your widget.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .systemLarge,
            .accessoryInline,
            .accessoryCircular,
            .accessoryRectangular
        ])
    }
}

struct NesticPairConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "Two subjects" }
    static var description: IntentDescription { "Follow two subjects with two trackers or routines each." }
    @Parameter(title: "First subject") var firstSubject: NesticWidgetSubjectEntity?
    @Parameter(title: "First subject · first action") var firstTracker: NesticFirstSubjectMetricEntity?
    @Parameter(title: "First subject · second action") var secondTracker: NesticFirstSubjectMetricEntity?
    @Parameter(title: "Second subject") var secondSubject: NesticWidgetSubjectEntity?
    @Parameter(title: "Second subject · first action") var thirdTracker: NesticSecondSubjectMetricEntity?
    @Parameter(title: "Second subject · second action") var fourthTracker: NesticSecondSubjectMetricEntity?
    init() {}
}

struct NesticPairEntry: TimelineEntry {
    let date: Date
    let first: NesticWidgetSnapshot?
    let second: NesticWidgetSnapshot?
}

struct NesticPairProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> NesticPairEntry {
        let sample = NesticWidgetProvider().placeholder(in: context)
        var second = sample.snapshot
        second?.subjectName = "Luna"
        second?.subjectEmoji = "🐱"
        return NesticPairEntry(date: sample.date, first: sample.snapshot, second: second)
    }

    func snapshot(for configuration: NesticPairConfigurationIntent, in context: Context) async -> NesticPairEntry {
        makeEntry(configuration, at: Date())
    }

    func timeline(for configuration: NesticPairConfigurationIntent, in context: Context) async -> Timeline<NesticPairEntry> {
        let now = Date()
        let midnight = Calendar.current.dateInterval(of: .day, for: now)!.end
        return Timeline(entries: [makeEntry(configuration, at: now), makeEntry(configuration, at: midnight)],
                        policy: .after(now.addingTimeInterval(5 * 60)))
    }

    private func makeEntry(_ configuration: NesticPairConfigurationIntent, at date: Date) -> NesticPairEntry {
        let data = NesticWidgetDataReader.load()
        let firstID = UUID(uuidString: configuration.firstSubject?.id ?? "") ?? data.defaultSubjectID
        let first = data.subjects.first { $0.id == firstID } ?? data.subjects.first
        let secondID = UUID(uuidString: configuration.secondSubject?.id ?? "")
        let second = data.subjects.first { $0.id == secondID && $0.id != first?.id }
            ?? data.subjects.first { $0.id != first?.id }
        func snapshot(_ subject: NesticWidgetSubjectData?, _ metric1: NesticWidgetMetricEntity?, _ metric2: NesticWidgetMetricEntity?) -> NesticWidgetSnapshot? {
            guard let subject else { return nil }
            var selection = NesticWidgetConfigurationIntent()
            selection.subject = NesticWidgetSubjectEntity(id: subject.id.uuidString, displayString: subject.name)
            selection.firstMetric = metric1
            selection.secondMetric = metric2
            return NesticWidgetProvider().makeSnapshot(configuration: selection, now: date, includeRoutines: true)
        }
        return NesticPairEntry(date: date, first: snapshot(first, configuration.firstTracker.map { NesticWidgetMetricEntity(id: $0.id, displayString: $0.displayString) }, configuration.secondTracker.map { NesticWidgetMetricEntity(id: $0.id, displayString: $0.displayString) }),
                              second: snapshot(second, configuration.thirdTracker.map { NesticWidgetMetricEntity(id: $0.id, displayString: $0.displayString) }, configuration.fourthTracker.map { NesticWidgetMetricEntity(id: $0.id, displayString: $0.displayString) }))
    }
}

struct NesticPairView: View {
    let entry: NesticPairEntry
    @Environment(\.widgetFamily) private var family

    private let forest = Color(red: 0.12, green: 0.27, blue: 0.22)
    private let sage = Color(red: 0.73, green: 0.88, blue: 0.63)
    private let sky = Color(red: 0.62, green: 0.84, blue: 0.96)

    var body: some View {
        VStack(alignment: .leading, spacing: family == .systemLarge ? 10 : 8) {
            subject(entry.first)
            Divider().overlay(.white.opacity(0.25))
            subject(entry.second)
        }
        .padding(family == .systemLarge ? 4 : 4)
        .containerBackground(for: .widget) {
            ZStack {
                LinearGradient(colors: [forest, Color(red: 0.23, green: 0.46, blue: 0.36)], startPoint: .topLeading, endPoint: .bottomTrailing)
                Circle()
                    .fill(sage.opacity(0.12))
                    .frame(width: 180, height: 180)
                    .blur(radius: 24)
                    .offset(x: family == .systemLarge ? 120 : 70, y: -100)
            }
        }
    }

    @ViewBuilder
    private func subject(_ snapshot: NesticWidgetSnapshot?) -> some View {
        if let snapshot {
            VStack(alignment: .leading, spacing: family == .systemLarge ? 10 : 7) {
                Link(destination: URL(string: "nestic://subject?subjectID=\(snapshot.subjectID.uuidString)")!) {
                    HStack(spacing: 6) {
                        subjectAvatar(snapshot)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(snapshot.subjectName)
                                .font(family == .systemLarge ? .title3.bold() : .subheadline.bold())
                                .lineLimit(1)
                                .minimumScaleFactor(0.65)
                            Text(subjectSummary(snapshot))
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.white.opacity(0.72))
                                .lineLimit(1)
                                .minimumScaleFactor(0.55)
                        }
                    }
                }
                if family == .systemLarge {
                    HStack(alignment: .center, spacing: 6) {
                        metric(snapshot.firstMetric, subject: snapshot, compact: false)
                        metric(snapshot.secondMetric, subject: snapshot, compact: false)
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    // Medium has one full-width action per subject so both
                    // rows stay readable without crowding four cards into
                    // the available height.
                    metric(snapshot.firstMetric ?? snapshot.secondMetric, subject: snapshot, compact: true)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(family == .systemLarge ? 10 : 6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "person.2.badge.plus")
                    .font(.title2)
                    .foregroundStyle(sage)
                Text("Add a second subject in Nestic")
                    .font(.caption.weight(.medium))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(12)
        }
    }

    @ViewBuilder
    private func metric(_ metric: NesticWidgetMetricSnapshot?, subject: NesticWidgetSnapshot, compact: Bool) -> some View {
        if let metric {
            let activityText = metric.routineID == nil
                ? (metric.lastEventAt.map { "Last " + recordedDateLabel($0) } ?? "No logs yet")
                : metric.actionSummary
            let forecastText = metric.routineID == nil ? forecastLabel(metric, subject: subject) : ""
            Group {
                if let routineID = metric.routineID {
                    Button(intent: NesticWidgetLogRoutineIntent(subjectID: subject.subjectID, routineID: routineID)) { label(metric, subject: subject, compact: compact) }
                        .buttonStyle(.plain)
                } else if metric.supportsQuickLog {
                    Button(intent: NesticWidgetLogIntent(subjectID: subject.subjectID, trackerID: metric.id)) { label(metric, subject: subject, compact: compact) }
                        .buttonStyle(.plain)
                } else {
                    Link(destination: URL(string: "nestic://record?subjectID=\(subject.subjectID.uuidString)&trackerID=\(metric.id.uuidString)")!) { label(metric, subject: subject, compact: compact) }
                }
            }
            .accessibilityLabel("Log \(metric.name) for \(subject.subjectName), \(metric.actionSummary)")
            .accessibilityValue(forecastText.isEmpty ? activityText : "\(activityText), \(forecastText)")
        } else {
            Text("Choose an action")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.58))
        }
    }

    private func subjectSummary(_ snapshot: NesticWidgetSnapshot) -> String {
        let metrics = [snapshot.firstMetric, snapshot.secondMetric].compactMap { $0 }
        let count = metrics.filter { $0.routineID == nil }.reduce(0) { $0 + $1.eventDates.count }
        return count == 1 ? "1 update today" : "\(count) updates today"
    }

    @ViewBuilder
    private func subjectAvatar(_ snapshot: NesticWidgetSnapshot) -> some View {
        let size: CGFloat = family == .systemLarge ? 48 : 32
        Group {
            if let encoded = snapshot.subjectPhotoData,
               let data = Data(base64Encoded: encoded), let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Text(snapshot.subjectEmoji).font(.system(size: size * 0.6))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.white.opacity(0.13))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.3))
        .overlay { RoundedRectangle(cornerRadius: size * 0.3).stroke(.white.opacity(0.25), lineWidth: 1) }
        .accessibilityHidden(true)
    }

    private func recordedDateLabel(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: entry.date) {
            return date.formatted(.dateTime.hour().minute())
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: entry.date),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return "Yesterday " + date.formatted(.dateTime.hour().minute())
        }
        return date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
    }

    private func forecastLabel(_ metric: NesticWidgetMetricSnapshot, subject: NesticWidgetSnapshot) -> String {
        guard subject.hasPredictionAccess else { return "" }
        guard let date = metric.predictionAt, date > entry.date else { return "No forecast yet" }
        let calendar = Calendar.current
        let time = date.formatted(.dateTime.hour().minute())
        if calendar.isDate(date, inSameDayAs: entry.date) { return "Next " + time }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: entry.date),
           calendar.isDate(date, inSameDayAs: tomorrow) { return "Tomorrow " + time }
        return "Next " + date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
    }

    private func label(_ metric: NesticWidgetMetricSnapshot, subject: NesticWidgetSnapshot, compact: Bool) -> some View {
        let tint = metricTint(metric, fallback: metric.routineID == nil ? sage : sky)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                if metric.isEmoji { Text(metric.symbol) }
                else { Image(systemName: metric.symbol).foregroundStyle(tint) }
                Text(metric.name)
                    .font(compact ? .caption2.weight(.semibold) : .caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Spacer(minLength: 0)
                if metric.routineID == nil {
                    Text("\(metric.eventDates.count)")
                        .font(compact ? .caption.weight(.bold) : .subheadline.weight(.bold))
                        .foregroundStyle(tint)
                        .monospacedDigit()
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(tint)
                }
            }
            if metric.routineID != nil {
                Text(metric.actionSummary).font(.caption2).opacity(0.75)
            } else {
                Text(metric.lastEventAt.map { "Last \(recordedDateLabel($0))" } ?? "No logs yet")
                    .font(.system(size: compact ? 11 : 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.90))
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
                    .monospacedDigit()
                    .layoutPriority(1)
            }
            if metric.routineID == nil, !forecastLabel(metric, subject: subject).isEmpty {
                Label(forecastLabel(metric, subject: subject), systemImage: "sparkles")
                    .font(.caption2)
                    .foregroundStyle(sage)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, compact ? 7 : 10)
        .padding(.vertical, compact ? 7 : 10)
        .background(tint.opacity(compact ? 0.14 : 0.18), in: RoundedRectangle(cornerRadius: compact ? 11 : 14))
        .overlay {
            RoundedRectangle(cornerRadius: compact ? 11 : 14)
                .stroke(tint.opacity(0.24), lineWidth: 1)
        }
    }

    private func metricTint(_ metric: NesticWidgetMetricSnapshot, fallback: Color) -> Color {
        let clean = metric.color.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
        guard clean.count == 6, let value = UInt64(clean, radix: 16) else { return fallback }
        return Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

}

struct NesticPairWidget: Widget {
    let kind = "NesticPairWidget"
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: NesticPairConfigurationIntent.self, provider: NesticPairProvider()) { entry in
            NesticPairView(entry: entry).foregroundStyle(.white)
        }
        .configurationDisplayName("Nestic · Two subjects")
        .description("See both subjects with two actions each in a large widget.")
        .supportedFamilies([.systemLarge])
    }
}

@main
struct NesticWidgetBundle: WidgetBundle {
    var body: some Widget {
        NesticWidget()
        NesticPairWidget()
    }
}
