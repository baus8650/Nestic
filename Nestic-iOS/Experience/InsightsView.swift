import Charts
import SwiftUI

struct AnalyticsPoint: Identifiable {
    let id: String
    let date: Date
    let trackerID: UUID
    let trackerName: String
    let count: Int
}

struct AnalyticsView: View {
    @EnvironmentObject private var store: NesticStore
    @EnvironmentObject private var subscription: NesticSubscriptionStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Binding private var requestedSubjectID: UUID?
    private let embeddedSubjectID: UUID?
    @State private var selectedSubjectID: UUID?
    @State private var range: NesticAnalyticsRange = .today
    @State private var historyMonth = Date()
    @State private var historyError: String?
    @State private var selectedHistoryDay: Date?
    @State private var showPredictionSettings = false
    @State private var showProPaywall = false

    init(requestedSubjectID: Binding<UUID?> = .constant(nil), embeddedSubjectID: UUID? = nil) {
        _requestedSubjectID = requestedSubjectID
        self.embeddedSubjectID = embeddedSubjectID
    }

    private var subject: NestSubject? {
        let targetID = embeddedSubjectID ?? selectedSubjectID
        if let targetID, let subject = store.subjects.first(where: { $0.id == targetID }) { return subject }
        return store.subjects.first
    }

    private var subjectTrackers: [NestTracker] {
        guard let subject else { return [] }
        return store.trackers(for: subject)
    }

    private var calendar: Calendar { .current }
    private var isWideLayout: Bool { horizontalSizeClass == .regular }

    /// The graph can be pinned to a historical calendar day without changing
    /// the calendar window a person is browsing below it.
    private var activeDay: Date {
        calendar.startOfDay(for: selectedHistoryDay ?? Date())
    }

    private var rangeStart: Date {
        if range == .today { return activeDay }
        return calendar.date(byAdding: .day, value: -(range.dayCount - 1), to: calendar.startOfDay(for: Date())) ?? Date()
    }

    private var rangeEnd: Date {
        calendar.date(byAdding: .day, value: 1, to: range == .today ? activeDay : calendar.startOfDay(for: Date())) ?? Date()
    }

    private var rangeDetail: String {
        if range == .today, let selectedHistoryDay {
            return selectedHistoryDay.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()).uppercased()
        }
        return range.title.uppercased()
    }

    private var points: [AnalyticsPoint] {
        guard let subject else { return [] }
        let trackerMap = Dictionary(uniqueKeysWithValues: subjectTrackers.map { ($0.id, $0) })
        var counts: [AnalyticsPointKey: Int] = [:]
        for entry in store.entries where entry.entityId == subject.id && entry.occurredAt >= rangeStart && entry.occurredAt < rangeEnd {
            guard let tracker = trackerMap[entry.actionId] else { continue }
            let bucket: Date
            if range == .today {
                bucket = calendar.dateInterval(of: .hour, for: entry.occurredAt)?.start ?? entry.occurredAt
            } else {
                bucket = calendar.startOfDay(for: entry.occurredAt)
            }
            counts[AnalyticsPointKey(date: bucket, trackerID: tracker.id)] = (counts[AnalyticsPointKey(date: bucket, trackerID: tracker.id)] ?? 0) + 1
        }
        return counts.map { key, count in
            AnalyticsPoint(id: "\(key.trackerID.uuidString)-\(key.date.timeIntervalSince1970)", date: key.date,
                           trackerID: key.trackerID, trackerName: trackerMap[key.trackerID]?.name ?? "Update", count: count)
        }.sorted { $0.date < $1.date }
    }

    private var totals: [(tracker: NestTracker, count: Int)] {
        let counts = points.reduce(into: [UUID: Int]()) { $0[$1.trackerID, default: 0] += $1.count }
        return subjectTrackers.map { ($0, counts[$0.id] ?? 0) }.filter { $0.1 > 0 }
    }

    private var historyDays: [Date] {
        guard let month = calendar.dateInterval(of: .month, for: historyMonth),
              let days = calendar.range(of: .day, in: .month, for: month.start) else { return [] }
        return days.compactMap { calendar.date(byAdding: .day, value: $0 - 1, to: month.start) }
    }

    private func selectRange(_ option: NesticAnalyticsRange) {
        if option == .month && !subscription.hasPredictionAccess {
            showProPaywall = true
            return
        }
        range = option
        if option == .today {
            selectedHistoryDay = nil
        } else {
            selectedHistoryDay = nil
        }
    }

    private func applyRequestedSubject() {
        guard embeddedSubjectID == nil else { return }
        guard let requestedSubjectID,
              store.subjects.contains(where: { $0.id == requestedSubjectID }) else { return }
        selectedSubjectID = requestedSubjectID
        self.requestedSubjectID = nil
        selectedHistoryDay = nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if embeddedSubjectID == nil {
                    header
                }
                if store.subjects.isEmpty {
                    EmptyNestView(symbol: "chart.xyaxis.line", title: "Your trends will live here", message: "Add a subject and start logging updates to see Daily Scoop-style history and patterns.")
                        .nesticCard()
                } else if let subject {
                    if embeddedSubjectID == nil {
                        subjectCarousel
                    }
                    rangePicker
                    if isWideLayout {
                        trendCard(for: subject)
                        HStack(alignment: .top, spacing: 20) {
                            summaryCard
                                .frame(maxWidth: .infinity, alignment: .top)
                            EventPredictionCard(subject: subject, showSettings: { showPredictionSettings = true })
                                .frame(maxWidth: .infinity, alignment: .top)
                        }
                        historyCard(for: subject)
                    } else {
                        trendCard(for: subject)
                        summaryCard
                        EventPredictionCard(subject: subject, showSettings: { showPredictionSettings = true })
                        historyCard(for: subject)
                    }
                }
            }
            .frame(maxWidth: isWideLayout ? 1400 : .infinity)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, isWideLayout ? 34 : 22)
            .padding(.top, isWideLayout ? 28 : 22)
            .padding(.bottom, 20)
        }
        .background(NesticTheme.paper)
        .toolbar(embeddedSubjectID == nil ? .hidden : .automatic, for: .navigationBar)
        .onAppear {
            selectedSubjectID = embeddedSubjectID ?? selectedSubjectID ?? store.subjects.first?.id
            applyRequestedSubject()
        }
        .onChange(of: requestedSubjectID) { _, _ in applyRequestedSubject() }
        .onChange(of: store.selectedNestID) { _, _ in
            selectedSubjectID = embeddedSubjectID ?? store.subjects.first?.id
            selectedHistoryDay = nil
            range = .today
            historyMonth = Date()
        }
        .onChange(of: store.subjects) { _, subjects in
            if let selectedSubjectID, subjects.contains(where: { $0.id == selectedSubjectID }) == false {
                self.selectedSubjectID = subjects.first?.id
            }
        }
        .onChange(of: selectedSubjectID) { _, _ in
            selectedHistoryDay = nil
        }
        .sheet(isPresented: $showPredictionSettings) {
            if let subject { PredictionSettingsSheet(subject: subject, initial: store.preferences(for: subject)) }
        }
        .sheet(isPresented: $showProPaywall) { NesticProPaywall() }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Insights").font(.system(.largeTitle, design: .rounded, weight: .bold))
                Text("Patterns that make shared updates easier.").font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chart.xyaxis.line").font(.title2).foregroundStyle(NesticTheme.forest)
        }
    }

    private var subjectCarousel: some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionHeading(title: "Insights for", detail: "SWIPE TO CHANGE")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(store.subjects) { item in
                        let isSelected = selectedSubjectID == item.id
                        Button {
                            selectedSubjectID = item.id
                        } label: {
                            VStack(spacing: 8) {
                                SubjectAvatar(emoji: item.emoji, photoData: item.photoData, size: isWideLayout ? 76 : 60)
                                Text(item.name)
                                    .font(.headline)
                                    .foregroundStyle(NesticTheme.ink)
                                    .lineLimit(1)
                                Text(item.kind.title)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(width: isWideLayout ? 142 : 116)
                            .padding(.vertical, 10)
                            .background(isSelected ? NesticTheme.lime.opacity(0.6) : NesticTheme.card,
                                        in: RoundedRectangle(cornerRadius: 18))
                            .overlay {
                                RoundedRectangle(cornerRadius: 18)
                                    .stroke(isSelected ? NesticTheme.forest.opacity(0.45) : Color.clear, lineWidth: 1)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Insights for \(item.name)")
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                }
            }
        }
    }

    private var rangePicker: some View {
        HStack(spacing: 6) {
            ForEach(NesticAnalyticsRange.allCases) { option in
                Button {
                    selectRange(option)
                } label: {
                    HStack(spacing: 4) {
                        Text(option.title)
                        if option == .month && !subscription.hasPredictionAccess {
                            Image(systemName: "lock.fill").font(.caption2)
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(range == option ? NesticTheme.ink : .secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(range == option ? NesticTheme.lime.opacity(0.65) : Color.clear, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(NesticTheme.card, in: Capsule())
    }

    private func trendCard(for subject: NestSubject) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeading(title: "At a glance", detail: rangeDetail)
            if range == .today, let selectedHistoryDay {
                HStack(spacing: 7) {
                    Image(systemName: "calendar")
                    Text("Showing \(selectedHistoryDay.formatted(date: .abbreviated, time: .omitted)) hour by hour")
                    Spacer()
                    Button("Today") { selectRange(.today) }
                        .font(.caption.weight(.semibold))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            if points.isEmpty && graphPredictions.isEmpty {
                Text(range == .today
                     ? "No updates were logged for \(activeDay.formatted(date: .abbreviated, time: .omitted))."
                     : "Log a few updates for \(subject.name) and the shape of the day will appear here.")
                    .font(.subheadline).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 22)
            } else if range == .today {
                todayTimelineGraph
            } else {
                TrackerTrendChart(series: trendSeries, range: range, start: rangeStart, end: rangeEnd, predictions: graphPredictions)
            }
        }
        .nesticCard()
    }

    private var graphPredictions: [EventPrediction] {
        guard subscription.hasPredictionAccess, let subject else { return [] }
        return store.predictions(for: subject).filter { $0.predictedAt >= rangeStart && $0.predictedAt < rangeEnd }
    }

    private var trendSeries: [TrackerTrendSeries] {
        let counts = Dictionary(uniqueKeysWithValues: points.map { (AnalyticsPointKey(date: $0.date, trackerID: $0.trackerID), $0.count) })
        let buckets = (0..<range.dayCount).compactMap { calendar.date(byAdding: .day, value: $0, to: rangeStart) }
        return subjectTrackers.map { tracker in
            let trackerPoints = buckets.map { bucket in
                TrackerTrendPoint(
                    id: "\(tracker.id.uuidString)-\(bucket.timeIntervalSince1970)",
                    date: bucket,
                    count: counts[AnalyticsPointKey(date: bucket, trackerID: tracker.id)] ?? 0
                )
            }
            return TrackerTrendSeries(tracker: tracker, points: trackerPoints)
        }
    }

    private var todayTimelineGraph: some View {
        let forecasts = Dictionary(uniqueKeysWithValues: graphPredictions.compactMap { prediction -> (UUID, EventPrediction)? in
            prediction.targetTrackerID.map { ($0, prediction) }
        })
        let dayEntries = subject.map { store.entries(for: $0) } ?? []
        let quietIntervals = timelineQuietIntervals
        let datesByTracker = Dictionary(grouping: dayEntries.filter { $0.occurredAt >= rangeStart && $0.occurredAt < rangeEnd }, by: \.actionId)
        return VStack(alignment: .leading, spacing: 9) {
            HStack {
                Label("Today", systemImage: "chart.xyaxis.line")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(NesticTheme.ink.opacity(0.82))
                Spacer()
                Text(activeDay, format: .dateTime.month(.abbreviated).day())
                    .font(.caption2)
                    .foregroundStyle(NesticTheme.ink.opacity(0.68))
            }
            VStack(spacing: 10) {
                ForEach(subjectTrackers) { tracker in
                    todayTimelineRow(tracker, dates: Array((datesByTracker[tracker.id] ?? []).map(\.occurredAt).reversed()), prediction: forecasts[tracker.id], quietIntervals: quietIntervals)
                }
            }
            todayTimelineAxis
            if !quietIntervals.isEmpty {
                Label("Shaded bands show quiet hours.", systemImage: "moon.zzz.fill")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Label("Translucent dots show predicted times; solid dots are logged updates.", systemImage: "circle.dotted")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .background(NesticTheme.card, in: RoundedRectangle(cornerRadius: 16))
    }

    private func todayTimelineRow(_ tracker: NestTracker, dates: [Date], prediction: EventPrediction?, quietIntervals: [DateInterval]) -> some View {
        let tint = trackerColor(tracker)

        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                TrackerIconView(tracker: tracker, size: .caption).foregroundStyle(tint)
                Text(tracker.name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(NesticTheme.ink)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text("\(dates.count)")
                    .font(.caption.bold())
                    .foregroundStyle(NesticTheme.ink.opacity(0.78))
            }
            if let prediction {
                Text("Predicted \(prediction.predictedAt.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2).foregroundStyle(tint)
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(NesticTheme.ink.opacity(0.12))
                        .overlay {
                            ZStack(alignment: .leading) {
                                ForEach(quietIntervals, id: \.start) { interval in
                                    let day = calendar.dateInterval(of: .day, for: activeDay) ?? DateInterval(start: rangeStart, end: rangeEnd)
                                    let start = CGFloat(interval.start.timeIntervalSince(day.start) / day.duration)
                                    let end = CGFloat(interval.end.timeIntervalSince(day.start) / day.duration)
                                    Rectangle()
                                        .fill(NesticTheme.ink.opacity(0.16))
                                        .frame(width: proxy.size.width * (end - start), height: proxy.size.height)
                                        .offset(x: proxy.size.width * start)
                                        .accessibilityHidden(true)
                                }
                            }
                            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .leading)
                            .clipShape(Capsule())
                        }
                    ForEach(1..<4, id: \.self) { index in
                        Rectangle()
                            .fill(NesticTheme.ink.opacity(0.18))
                            .frame(width: 1, height: isWideLayout ? 30 : 22)
                            .position(x: proxy.size.width * CGFloat(index) / 4, y: proxy.size.height / 2)
                    }
                    if let prediction {
                        Circle()
                            .fill(tint.opacity(0.25))
                            .overlay(Circle().strokeBorder(tint.opacity(0.65), style: StrokeStyle(lineWidth: 1.5, dash: [2, 2])))
                            .frame(width: isWideLayout ? 20 : 16, height: isWideLayout ? 20 : 16)
                            .position(x: todayMarkerPosition(for: prediction.predictedAt, width: proxy.size.width), y: proxy.size.height / 2)
                            .accessibilityLabel("Predicted \(tracker.name), \(prediction.predictedAt.formatted(date: .abbreviated, time: .shortened))")
                    }
                    ForEach(Array(dates.enumerated()), id: \.offset) { _, date in
                        Circle()
                            .fill(tint)
                            .frame(width: isWideLayout ? 14 : 10, height: isWideLayout ? 14 : 10)
                            .position(x: todayMarkerPosition(for: date, width: proxy.size.width), y: proxy.size.height / 2)
                    }
                }
            }
            .frame(height: isWideLayout ? 30 : 22)
        }
        .frame(maxWidth: .infinity)
    }

    // Walk actual minutes so overnight periods and daylight-saving transitions
    // use the same local wall-clock times as the quiet-hours settings.
    private var timelineQuietIntervals: [DateInterval] {
        guard let day = calendar.dateInterval(of: .day, for: activeDay),
              !store.quietHoursPreferences.periods.isEmpty else { return [] }
        var intervals: [DateInterval] = []
        var beginning: Date?
        var cursor = day.start
        while cursor < day.end {
            let quiet = store.quietHoursPreferences.periods.contains { $0.contains(cursor, calendar: calendar) }
            if quiet, beginning == nil { beginning = cursor }
            if !quiet, let start = beginning {
                intervals.append(DateInterval(start: start, end: cursor))
                beginning = nil
            }
            cursor = min(day.end, cursor.addingTimeInterval(60))
        }
        if let start = beginning { intervals.append(DateInterval(start: start, end: day.end)) }
        return intervals
    }

    private var uses24HourClock: Bool {
        let template = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .autoupdatingCurrent) ?? ""
        return template.contains("H") || template.contains("k")
    }

    private var todayTimelineAxis: some View {
        GeometryReader { proxy in
            ZStack {
                ForEach([0, 6, 12, 18, 24], id: \.self) { hour in
                    Text(todayAxisLabel(for: hour))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(NesticTheme.ink.opacity(0.58))
                        .fixedSize()
                        .frame(width: proxy.size.width, height: proxy.size.height,
                               alignment: hour == 0 ? .leading : (hour == 24 ? .trailing : .center))
                        .offset(x: hour == 0 || hour == 24
                                ? 0
                                : proxy.size.width * todayTimelineFraction(for: hour) - proxy.size.width / 2)
                }
            }
        }
        .frame(height: isWideLayout ? 22 : 16)
    }

    private func todayAxisLabel(for hour: Int) -> String {
        let date = todayTimelineDate(for: hour)
        if uses24HourClock {
            return date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)))
        }
        return date.formatted(.dateTime.hour(.defaultDigits(amPM: .abbreviated)))
    }

    private func todayTimelineDate(for hour: Int) -> Date {
        let interval = calendar.dateInterval(of: .day, for: activeDay)
        let start = interval?.start ?? activeDay
        if hour == 24, let end = interval?.end {
            return end
        }
        return calendar.date(byAdding: .hour, value: hour, to: start) ?? start
    }

    private func todayTimelineFraction(for hour: Int) -> CGFloat {
        let interval = calendar.dateInterval(of: .day, for: activeDay)
        let start = interval?.start ?? activeDay
        let duration = interval?.duration ?? 86_400
        let fraction = todayTimelineDate(for: hour).timeIntervalSince(start) / duration
        return CGFloat(min(1, max(0, fraction)))
    }

    private func todayMarkerPosition(for date: Date, width: CGFloat) -> CGFloat {
        let interval = calendar.dateInterval(of: .day, for: activeDay)
        let start = interval?.start ?? activeDay
        let duration = interval?.duration ?? 86_400
        let fraction = min(1, max(0, date.timeIntervalSince(start) / duration))
        return min(max(4, width - 4), max(4, CGFloat(fraction) * width))
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 15) {
            SectionHeading(title: "Totals", detail: rangeDetail)
            if totals.isEmpty {
                Text("No updates in this range.").font(.subheadline).foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(totals, id: \.tracker.id) { item in
                        HStack(spacing: 10) {
                            TrackerIconView(tracker: item.tracker).foregroundStyle(trackerColor(item.tracker))
                                .frame(width: 30, height: 30).background(trackerColor(item.tracker).opacity(0.18), in: Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(item.count)").font(.system(.title3, design: .rounded, weight: .bold))
                                Text(item.tracker.name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
        }
        .nesticCard()
    }

    private func historyCard(for subject: NestSubject) -> some View {
        let trackerIDs = Set(subjectTrackers.map(\.id))
        let counts = store.entries(for: subject).reduce(into: [Date: Int]()) { counts, entry in
            if trackerIDs.contains(entry.actionId) { counts[calendar.startOfDay(for: entry.occurredAt), default: 0] += 1 }
        }
        return VStack(alignment: .leading, spacing: 14) {
            SectionHeading(title: "History", detail: "CALENDAR")
            HStack {
                Button { historyMonth = calendar.date(byAdding: .month, value: -1, to: calendar.dateInterval(of: .month, for: historyMonth)?.start ?? historyMonth) ?? historyMonth } label: { Image(systemName: "chevron.left") }
                    .accessibilityLabel("Previous month")
                Spacer()
                Text(historyMonth, format: .dateTime.month(.wide).year()).font(.subheadline.weight(.semibold))
                Spacer()
                Button { historyMonth = calendar.date(byAdding: .month, value: 1, to: calendar.dateInterval(of: .month, for: historyMonth)?.start ?? historyMonth) ?? historyMonth } label: { Image(systemName: "chevron.right") }
                    .disabled(calendar.isDate(historyMonth, equalTo: Date(), toGranularity: .month) || historyMonth > Date())
                    .accessibilityLabel("Next month")
            }
            .buttonStyle(.bordered)
            HStack(spacing: 6) {
                ForEach(0..<7, id: \.self) { index in
                    let day = calendar.shortWeekdaySymbols[(index + calendar.firstWeekday - 1) % 7]
                    Text(String(day.prefix(1))).font(.caption2.weight(.semibold)).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                }
            }
            let leadingBlanks = (calendar.component(.weekday, from: historyDays.first ?? Date()) - calendar.firstWeekday + 7) % 7
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 7), spacing: 8) {
                ForEach(0..<leadingBlanks, id: \.self) { _ in Color.clear.frame(height: isWideLayout ? 52 : 37) }
                ForEach(historyDays, id: \.self) { day in
                    let count = counts[day] ?? 0
                    let isSelected = calendar.isDate(activeDay, inSameDayAs: day)
                    Button {
                        selectedHistoryDay = calendar.startOfDay(for: day)
                        range = .today
                    } label: {
                        VStack(spacing: 4) {
                            Text(day, format: .dateTime.day()).font(.caption.weight(.semibold))
                            Circle().fill(count == 0 ? NesticTheme.paper : NesticTheme.forest.opacity(min(1, 0.18 + Double(count) * 0.15)))
                                .frame(width: 9 + min(CGFloat(count), 4) * 3, height: 9 + min(CGFloat(count), 4) * 3)
                        }
                        .frame(maxWidth: .infinity).frame(height: isWideLayout ? 52 : 37)
                        .background(isSelected ? NesticTheme.lime.opacity(0.65) : Color.clear, in: RoundedRectangle(cornerRadius: 10))
                        .overlay {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 10).stroke(NesticTheme.forest.opacity(0.45), lineWidth: 1)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(day > calendar.startOfDay(for: Date()))
                    .opacity(day > calendar.startOfDay(for: Date()) ? 0.35 : 1)
                    .accessibilityLabel("\(day.formatted(date: .abbreviated, time: .omitted)), \(count) updates")
                    .accessibilityHint("Shows the hour-by-hour graph for this day")
                }
            }
            if store.hasMoreEntries {
                Button("Load older history") {
                    Task { do { try await store.loadOlderEntries() } catch { historyError = error.localizedDescription } }
                }.disabled(store.isLoadingMoreEntries)
            }
            if let historyError { Text(historyError).font(.caption).foregroundStyle(.red) }
            Text("Counts reflect loaded history.").font(.caption2).foregroundStyle(.secondary)
            Text(selectedHistoryDay == nil
                 ? "Tap a day to see its hour-by-hour story."
                 : "Showing \(activeDay.formatted(date: .abbreviated, time: .omitted)) above. Tap another day or choose Today.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .nesticCard()
    }

}

private struct AnalyticsPointKey: Hashable {
    let date: Date
    let trackerID: UUID
}

struct TrackerTrendPoint: Identifiable {
    let id: String
    let date: Date
    let count: Int
}

struct TrackerTrendSeries: Identifiable {
    let tracker: NestTracker
    let points: [TrackerTrendPoint]

    var id: UUID { tracker.id }
    var total: Int { points.reduce(0) { $0 + $1.count } }
}

struct TrackerTrendChart: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let series: [TrackerTrendSeries]
    let range: NesticAnalyticsRange
    let start: Date
    let end: Date
    var predictions: [EventPrediction] = []
    @State private var visibleTrackerIDs: Set<UUID> = []

    private var visibleSeries: [TrackerTrendSeries] {
        visibleTrackerIDs.isEmpty
            ? series
            : series.filter { visibleTrackerIDs.contains($0.id) }
    }

    private var chartHeight: CGFloat {
        horizontalSizeClass == .regular ? 330 : 230
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(series) { trackerSeries in
                        metricChip(for: trackerSeries)
                    }
                }
            }
            .accessibilityLabel("Metrics shown on the graph. Tap a metric to show or hide it.")

            GeometryReader { proxy in
                ScrollView(.horizontal, showsIndicators: true) {
                    Chart {
                        ForEach(visibleSeries) { trackerSeries in
                            ForEach(predictions.filter { $0.targetTrackerID == trackerSeries.id && $0.predictedAt >= start && $0.predictedAt < end }, id: \.targetTrackerID) { prediction in
                                PointMark(
                                    x: .value("Predicted time", prediction.predictedAt),
                                    y: .value("Updates", trackerSeries.points.first { Calendar.current.isDate($0.date, inSameDayAs: prediction.predictedAt) }?.count ?? 0)
                                )
                                .symbolSize(140)
                                .foregroundStyle(trackerColor(trackerSeries.tracker).opacity(0.3))
                                .annotation(position: .top) {
                                    Text("Predicted \(trackerSeries.tracker.name) · \(prediction.predictedAt.formatted(date: .omitted, time: .shortened))")
                                        .font(.caption2).foregroundStyle(trackerColor(trackerSeries.tracker))
                                }
                                .accessibilityLabel("Predicted \(trackerSeries.tracker.name)")
                                .accessibilityValue(prediction.predictedAt.formatted(date: .abbreviated, time: .shortened))
                            }
                            ForEach(trackerSeries.points) { point in
                                BarMark(
                                    x: .value("Day", point.date, unit: .day),
                                    y: .value("Updates", point.count)
                                )
                                .foregroundStyle(by: .value("Metric", trackerSeries.id.uuidString))
                                .position(by: .value("Metric", trackerSeries.id.uuidString))
                                .cornerRadius(4)
                            }
                        }
                    }
                    .chartForegroundStyleScale(
                        domain: series.map { $0.id.uuidString },
                        range: series.map { trackerColor($0.tracker) }
                    )
                    .chartXScale(domain: start...end)
                    .chartYAxis { AxisMarks(preset: .extended, position: .leading) }
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .day, count: range == .month ? 5 : 1)) { _ in
                            AxisGridLine().foregroundStyle(.secondary.opacity(0.15))
                            AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                        }
                    }
                    .chartLegend(.hidden)
                    .frame(
                        width: max(proxy.size.width, CGFloat(range.dayCount) * CGFloat(max(80, visibleSeries.count * 20))),
                        height: chartHeight
                    )
                }
            }
            .frame(height: chartHeight)
            Text("Translucent dots mark predicted times. Their height follows that day's logged count; predictions do not add to totals.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .onAppear {
            visibleTrackerIDs = Set(series.map(\.id))
        }
        .onChange(of: series.map(\.id)) { _, ids in
            let remaining = visibleTrackerIDs.intersection(ids)
            visibleTrackerIDs = remaining.isEmpty ? Set(ids) : remaining
        }
    }

    private func metricChip(for trackerSeries: TrackerTrendSeries) -> some View {
        let isVisible = visibleTrackerIDs.isEmpty || visibleTrackerIDs.contains(trackerSeries.id)
        let tint = trackerColor(trackerSeries.tracker)
        return Button {
            guard visibleTrackerIDs.count > 1 || !isVisible else { return }
            if isVisible {
                visibleTrackerIDs.remove(trackerSeries.id)
            } else {
                visibleTrackerIDs.insert(trackerSeries.id)
            }
        } label: {
            HStack(spacing: 5) {
                TrackerIconView(tracker: trackerSeries.tracker, size: .caption)
                    .foregroundStyle(tint)
                Text(trackerSeries.tracker.name)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                Text("\(trackerSeries.total)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(isVisible ? NesticTheme.ink : .secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isVisible ? tint.opacity(0.14) : NesticTheme.card, in: Capsule())
            .overlay {
                Capsule().stroke(isVisible ? tint.opacity(0.45) : NesticTheme.ink.opacity(0.12), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(trackerSeries.tracker.name), \(trackerSeries.total) updates")
        .accessibilityValue(isVisible ? "Shown" : "Hidden")
    }
}

struct EventPredictionCard: View {
    @EnvironmentObject private var store: NesticStore
    @EnvironmentObject private var subscription: NesticSubscriptionStore
    let subject: NestSubject
    let showSettings: () -> Void
    @State private var statisticsPrediction: EventPrediction?
    @State private var expandedLearningTargetIDs: Set<UUID> = []

    private var predictions: [EventPrediction] {
        store.predictions(for: subject)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Label(predictions.count == 1 ? "Activity forecast" : "Activity forecasts", systemImage: "wand.and.stars")
                    .font(.system(.title3, design: .rounded, weight: .bold))
                Spacer()
                Image(systemName: subscription.hasPredictionAccess ? "checkmark.seal.fill" : "lock.fill")
                    .foregroundStyle(subscription.hasPredictionAccess ? NesticTheme.forest : .secondary)
            }
            if subscription.hasPredictionAccess {
                if predictions.isEmpty {
                    Text("Choose an event to predict, then log at least two updates for it to start a baseline. More history makes each forecast more useful.")
                        .font(.subheadline).foregroundStyle(.secondary)
                } else {
                    ForEach(predictions, id: \.targetTrackerID) { prediction in
                        forecastDetails(for: prediction)
                    }
                }
                Button("Tune what Nestic learns") { showSettings() }.font(.subheadline.weight(.semibold))
            } else {
                Text("Unlock a private, on-device pattern model that estimates when \(subject.name) may next log a selected event. Choose the events and data points it learns from.")
                    .font(.subheadline).foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Button(subscription.isLoading ? "Preparing…" : (store.isDemo ? "Preview sample forecast" : "Unlock Pro · \(subscription.priceDescription)")) {
                        Task {
                            if store.isDemo { subscription.enableSamplePreview() }
                            else { await subscription.purchase() }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(subscription.isLoading)
                    Button(subscription.isLoading ? "Working…" : "Restore") { Task { await subscription.restorePurchases() } }
                        .buttonStyle(.bordered)
                        .disabled(subscription.isLoading)
                }
                if let error = subscription.errorMessage {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
                Text("Pattern estimates are not health or professional advice.").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .nesticCard()
        .sheet(isPresented: Binding(get: { statisticsPrediction != nil }, set: { if !$0 { statisticsPrediction = nil } })) {
            if let prediction = statisticsPrediction {
                ForecastStatisticsView(prediction: prediction)
            }
        }
        .onAppear { store.recordForecasts(for: subject) }
        .onChange(of: store.entries.count) { _, _ in
            store.recordForecasts(for: subject)
        }
    }

    private func forecastDetails(for prediction: EventPrediction) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Next \(prediction.targetNames.first ?? "event")")
                .font(.subheadline.weight(.semibold))
            Text(prediction.predictedAt, format: .dateTime.weekday(.wide).hour().minute())
                .font(.system(.title2, design: .rounded, weight: .bold)).foregroundStyle(NesticTheme.forest)
            HStack(spacing: 8) {
                Text(prediction.model == .contextual
                     ? (prediction.validationSampleCount >= 3 ? "validated context model" : "context model")
                     : "baseline model")
                Text("·")
                Text("~\(prediction.confidencePercent)% confidence")
                Text("·")
                Text("last update \(prediction.lastEventAt, format: .relative(presentation: .named))")
            }
            .font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Image(systemName: "calendar.badge.clock")
                Text("Expected window ±\(forecastHours(prediction.predictionWindowHours))")
                if prediction.validationSampleCount > 0 {
                    Text("·")
                    Text("\(prediction.validationSampleCount) forecast\(prediction.validationSampleCount == 1 ? "" : "s") scored")
                }
            }
            .font(.caption.weight(.medium)).foregroundStyle(NesticTheme.forest)
            Text(prediction.explanation).font(.caption).foregroundStyle(.secondary)
            Text("Estimates come from recorded history, not health or professional advice. Follow the guidance appropriate for your care situation.")
                .font(.caption).foregroundStyle(.secondary)
            if !prediction.inputNames.isEmpty {
                Text("Using: \(prediction.inputNames.joined(separator: ", "))")
                    .font(.caption.weight(.medium)).foregroundStyle(NesticTheme.ink)
            }
            Button {
                statisticsPrediction = prediction
            } label: {
                Label("Forecast statistics", systemImage: "chart.bar.xaxis")
                    .font(.subheadline.weight(.semibold))
            }
            learningDetails(for: prediction)
        }
        .padding(12)
        .background(NesticTheme.paper.opacity(0.78), in: RoundedRectangle(cornerRadius: 14))
    }

    private func forecastHours(_ hours: Double) -> String {
        hours < 1 ? "under 1h" : "\(Int(hours.rounded()))h"
    }

    private func learningDetails(for prediction: EventPrediction) -> some View {
        DisclosureGroup(isExpanded: learningExpansion(for: prediction)) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    learningMetric("Target intervals", value: "\(prediction.sampleCount)")
                    learningMetric("Calendar pattern", value: "Time + weekday")
                }

                if prediction.learningSignals.isEmpty {
                    Text("Nestic is currently learning from the target-event intervals and the time and day they happened.")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(prediction.learningSignals) { signal in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(signal.trackerName).font(.subheadline.weight(.semibold))
                                Spacer()
                                Text(signal.hoursSinceLastUpdate < 1
                                     ? "Updated recently"
                                     : "\(Int(signal.hoursSinceLastUpdate.rounded()))h ago")
                                    .font(.caption.weight(.medium)).foregroundStyle(NesticTheme.forest)
                            }
                            Text("\(signal.updatesInLast24Hours) update\(signal.updatesInLast24Hours == 1 ? "" : "s") in 24h · \(signal.updatesInLast72Hours) in 72h")
                                .font(.caption).foregroundStyle(.secondary)
                            if let latestLearnedValue = signal.latestLearnedValue {
                                Text("Latest learned value: \(latestLearnedValue)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .padding(10)
                        .background(NesticTheme.paper.opacity(0.8), in: RoundedRectangle(cornerRadius: 10))
                    }
                }

                Label("Nestic uses event timing, recent update frequency, time of day, and number or yes/no values when available. It does not read notes or text values, and this model stays on device.", systemImage: "lock.privacy")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .padding(.top, 8)
        } label: {
            Label("What this forecast learned from", systemImage: "slider.horizontal.3")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(NesticTheme.forest)
        }
        .tint(NesticTheme.forest)
    }

    private func learningExpansion(for prediction: EventPrediction) -> Binding<Bool> {
        Binding(
            get: {
                guard let targetID = prediction.targetTrackerID else { return false }
                return expandedLearningTargetIDs.contains(targetID)
            },
            set: { isExpanded in
                guard let targetID = prediction.targetTrackerID else { return }
                if isExpanded {
                    expandedLearningTargetIDs.insert(targetID)
                } else {
                    expandedLearningTargetIDs.remove(targetID)
                }
            }
        )
    }

    private func learningMetric(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.caption.weight(.bold)).foregroundStyle(NesticTheme.ink)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(NesticTheme.paper.opacity(0.8), in: RoundedRectangle(cornerRadius: 10))
    }
}

/// Uses the displayed forecast's diagnostics rather than recomputing a different
/// local estimate when another nest member supplied the shared forecast.
struct ForecastStatisticsView: View {
    @Environment(\.dismiss) private var dismiss
    let prediction: EventPrediction

    private func hours(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(2)))) h"
    }

    private func timestamp(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    private var selectedEstimate: Date {
        prediction.model == .contextual
            ? prediction.contextualPredictedAt ?? prediction.baselinePredictedAt
            : prediction.baselinePredictedAt
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("The displayed forecast") {
                    LabeledContent("Tracker", value: prediction.targetNames.joined(separator: ", "))
                    LabeledContent("Predicted time", value: timestamp(prediction.predictedAt))
                    LabeledContent("Selected model", value: prediction.model.title.capitalized)
                    LabeledContent("Estimated interval", value: hours(prediction.intervalHours))
                    LabeledContent("Last included update", value: timestamp(prediction.lastEventAt))
                    Text("Each target tracker has its own model. Other selected target trackers are excluded from its context inputs.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Why this time?") {
                    LabeledContent("Median baseline estimate", value: timestamp(prediction.baselinePredictedAt))
                    if let contextual = prediction.contextualPredictedAt {
                        LabeledContent("Context estimate", value: timestamp(contextual))
                        LabeledContent("Context shift from baseline", value: hours(contextual.timeIntervalSince(prediction.baselinePredictedAt) / 3600))
                    }
                    Text("The baseline uses the median gap between included target updates. The context model uses ridge regression (regularization 0.12) to fit those gaps from recorded activity and calendar patterns. Intervals are limited to 15 minutes–72 hours.")
                    Text("The selected interval is added to the last included update. If that time has passed or is less than 15 minutes away, the estimate moves to 15 minutes after computation.")
                    if abs(prediction.predictedAt.timeIntervalSince(selectedEstimate)) > 1 {
                        LabeledContent("Before quiet hours", value: timestamp(selectedEstimate))
                        Text("Quiet-hour preferences moved the displayed time forward from the selected model's estimate.")
                    }
                    if let diagnostics = prediction.diagnostics {
                        Text(diagnostics.selectionReason)
                        LabeledContent("Computed", value: timestamp(diagnostics.computedAt))
                    }
                }
                Section("History and variation") {
                    LabeledContent("Usable intervals", value: "\(prediction.sampleCount)")
                    if let diagnostics = prediction.diagnostics {
                        LabeledContent("Median", value: hours(diagnostics.medianHours))
                        LabeledContent("Mean", value: hours(diagnostics.meanHours))
                        LabeledContent("Standard deviation", value: hours(diagnostics.standardDeviationHours))
                        LabeledContent("Shortest gap", value: hours(diagnostics.minimumHours))
                        LabeledContent("Longest gap", value: hours(diagnostics.maximumHours))
                        LabeledContent("Filtered gaps", value: "\(diagnostics.excludedIntervalCount)")
                        Text("Gaps of 9 minutes or less and 72 hours or more are excluded. Updates excluded from predictions are removed before gaps are calculated. Standard deviation describes the spread of the included history, using the population formula.")
                    } else {
                        Text("This forecast was synced from another device. Its summary is available here; detailed interval statistics and model contributions were not included in the synced result.")
                    }
                }
                if let diagnostics = prediction.diagnostics, let raw = diagnostics.rawContextHours {
                    Section("What contributes to the context estimate?") {
                        ForEach(diagnostics.contributions) { contribution in
                            LabeledContent(contribution.name, value: "\(contribution.hours >= 0 ? "+" : "")\(hours(contribution.hours))")
                        }
                        LabeledContent("Sum before interval limits", value: hours(raw))
                        Text("These terms add up to the raw context interval. Each tracker groups its learned coefficients × current feature values; calendar terms and the intercept are shown separately. Positive terms lengthen the fitted interval and negative terms shorten it. They describe associations in this model, not proof that a tracker causes an event or the change from the median baseline.")
                        if prediction.model == .baseline {
                            Text("The context estimate is shown for comparison. These terms do not affect the selected baseline forecast.")
                        }
                    }
                }
                Section("Inputs the context model uses") {
                    if prediction.inputNames.isEmpty {
                        Text("No recorded context trackers are included. Calendar patterns are still available to the context model.")
                    } else {
                        Text(prediction.inputNames.joined(separator: ", "))
                    }
                    Text("For each input: time since its latest update, latest numeric or yes/no value, activity in 6/12/24/72-hour windows since the last target event, numeric average and total within that interval (up to seven days), and the latest input's time of day. Numeric values are scaled to their recorded magnitude. Time of day and weekday use cyclical features.")
                    ForEach(prediction.learningSignals) { signal in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(signal.trackerName).font(.headline)
                            Text("Last update: \(timestamp(signal.lastLoggedAt))")
                            Text("\(signal.updatesInLast24Hours) updates in 24h · \(signal.updatesInLast72Hours) in 72h")
                            if let value = signal.latestLearnedValue { Text("Latest value: \(value)") }
                        }.font(.subheadline)
                    }
                    Text("The activity counts above summarize recorded history; model frequency features only count updates after the last target event and are capped and scaled. Notes and free-form text are not used.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("How much trust to place in it") {
                    LabeledContent("Confidence score", value: "\(prediction.confidencePercent)%")
                    LabeledContent("Scored outcomes", value: "\(prediction.validationSampleCount)")
                    if let error = prediction.expectedErrorHours {
                        LabeledContent(prediction.validationSampleCount > 0 ? "Weighted absolute timing error" : "Historical interval deviation", value: hours(error))
                    }
                    LabeledContent("Timing window", value: "±\(hours(prediction.predictionWindowHours))")
                    Text("Error comes from recorded forecast outcomes when available, weighted by exp(−age in days / 45), so recent results count more. Without outcomes, it is the mean absolute difference between historical gaps and the selected interval, not measured future accuracy.")
                    Text("Confidence combines sample size (up to 20 gaps) and fit to history. With fewer than three scored outcomes it is capped at 72%; with enough outcomes it also uses observed timing error and is capped at 94%. This score is a heuristic, not the probability an event will occur at this time.")
                    Text("The window is 1.25 × estimated error, bounded to ±1–12 hours. It is a practical range, not a statistically calibrated confidence interval.")
                }
            }
            .navigationTitle("Forecast statistics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

struct PredictionSettingsSheet: View {
    @EnvironmentObject private var store: NesticStore
    @Environment(\.dismiss) private var dismiss
    let subject: NestSubject
    let initial: NestPredictionPreferences
    @State private var inputIDs: Set<UUID>
    @State private var targetIDs: Set<UUID>

    init(subject: NestSubject, initial: NestPredictionPreferences) {
        self.subject = subject
        self.initial = initial
        _inputIDs = State(initialValue: Set(initial.inputTrackerIDs))
        _targetIDs = State(initialValue: Set(initial.targetTrackerIDs))
    }

    private var trackers: [NestTracker] { store.trackers(for: subject) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Each selected tracker gets its own forecast. Restricted forecasts sync only to permitted members. Inputs are used only when every forecast reader can see them.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    ForEach(trackers) { tracker in
                        selectionRow(tracker, selected: targetIDs.contains(tracker.id), label: "Predicted event") {
                            toggle(tracker.id, in: &targetIDs)
                        }
                    }
                } header: { Text("Predict these events") }
                Section {
                    Text("By default, Nestic learns from every other recorded metric, including its timing, recent activity, and values. Predicted events are never used as inputs for one another. Private inputs are used only for private forecasts. Deselect anything you do not want included. Nothing here is sent to a prediction service.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    ForEach(trackers.filter { !targetIDs.contains($0.id) }) { tracker in
                        selectionRow(tracker, selected: inputIDs.contains(tracker.id), label: "Learning signal") {
                            toggle(tracker.id, in: &inputIDs)
                        }
                    }
                } header: { Text("Learn from these data points") }
                Section {
                    Label("Nestic needs at least two updates for a baseline, and three or more intervals before it starts fitting a model.", systemImage: "lock.privacy")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle()
            .navigationTitle("Tune forecast")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        store.updatePredictionPreferences(for: subject, inputTrackerIDs: Array(inputIDs), targetTrackerIDs: Array(targetIDs))
                        dismiss()
                    }.disabled(targetIDs.isEmpty)
                }
            }
        }
    }

    private func selectionRow(_ tracker: NestTracker, selected: Bool, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? NesticTheme.forest : .secondary)
                TrackerIconView(tracker: tracker).foregroundStyle(trackerColor(tracker)).frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(tracker.name).foregroundStyle(NesticTheme.ink)
                    Text(label).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
        }.buttonStyle(.plain)
    }

    private func toggle(_ id: UUID, in set: inout Set<UUID>) {
        if set.contains(id) { set.remove(id) } else { set.insert(id) }
    }
}
