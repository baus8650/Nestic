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
    @State private var selectedSubjectID: UUID?
    @State private var range: NesticAnalyticsRange = .week
    @State private var showPredictionSettings = false

    private var subject: NestSubject? {
        if let selectedSubjectID, let subject = store.subjects.first(where: { $0.id == selectedSubjectID }) { return subject }
        return store.subjects.first
    }

    private var subjectTrackers: [NestTracker] {
        guard let subject else { return [] }
        return store.trackers(for: subject)
    }

    private var points: [AnalyticsPoint] {
        guard let subject else { return [] }
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -(range.dayCount - 1), to: calendar.startOfDay(for: Date())) ?? Date()
        let trackerMap = Dictionary(uniqueKeysWithValues: subjectTrackers.map { ($0.id, $0) })
        var counts: [AnalyticsPointKey: Int] = [:]
        for entry in store.entries where entry.entityId == subject.id && entry.occurredAt >= start {
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
        subjectTrackers.map { tracker in
            (tracker, points.filter { $0.trackerID == tracker.id }.reduce(0) { $0 + $1.count })
        }.filter { $0.count > 0 }
    }

    private var historyDays: [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return (0..<range.dayCount).compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }.reversed()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if store.subjects.isEmpty {
                    EmptyNestView(symbol: "chart.xyaxis.line", title: "Your trends will live here", message: "Add a subject and start logging updates to see Daily Scoop-style history and patterns.")
                        .nesticCard()
                } else if let subject {
                    subjectPicker
                    rangePicker
                    trendCard(for: subject)
                    summaryCard
                    if subject.kind == .pet {
                        BathroomPredictionCard(subject: subject, showSettings: { showPredictionSettings = true })
                    }
                    historyCard(for: subject)
                }
            }
            .padding(22)
            .padding(.bottom, 20)
        }
        .background(NesticTheme.paper)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { selectedSubjectID = selectedSubjectID ?? store.subjects.first?.id }
        .onChange(of: store.selectedNestID) { _, _ in selectedSubjectID = store.subjects.first?.id }
        .onChange(of: store.subjects) { _, subjects in
            if let selectedSubjectID, subjects.contains(where: { $0.id == selectedSubjectID }) == false {
                self.selectedSubjectID = subjects.first?.id
            }
        }
        .sheet(isPresented: $showPredictionSettings) {
            if let subject { PredictionSettingsSheet(subject: subject, initial: store.preferences(for: subject)) }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Insights").font(.system(.largeTitle, design: .rounded, weight: .bold))
                Text("Patterns that make care feel easier.").font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chart.xyaxis.line").font(.title2).foregroundStyle(NesticTheme.forest)
        }
    }

    private var subjectPicker: some View {
        Picker("Subject", selection: Binding(get: { selectedSubjectID ?? store.subjects.first?.id ?? UUID() }, set: { selectedSubjectID = $0 })) {
            ForEach(store.subjects) { subject in
                Label("\(subject.emoji)  \(subject.name)", systemImage: subject.kind == .pet ? "pawprint.fill" : "circle.fill").tag(subject.id)
            }
        }
        .pickerStyle(.menu)
        .font(.headline)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(NesticTheme.card, in: RoundedRectangle(cornerRadius: 16))
    }

    private var rangePicker: some View {
        Picker("Range", selection: $range) {
            ForEach(NesticAnalyticsRange.allCases) { range in Text(range.title).tag(range) }
        }
        .pickerStyle(.segmented)
    }

    private func trendCard(for subject: NestSubject) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeading(title: "At a glance", detail: range.title.uppercased())
            if points.isEmpty {
                Text("Log a few updates for \(subject.name) and the shape of the day will appear here.")
                    .font(.subheadline).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 22)
            } else {
                Chart {
                    ForEach(points) { point in
                        BarMark(x: .value("When", point.date), y: .value("Updates", point.count))
                            .foregroundStyle(by: .value("Tracker", point.trackerName))
                            .position(by: .value("Tracker", point.trackerName))
                            .cornerRadius(4)
                    }
                }
                .chartForegroundStyleScale(domain: subjectTrackers.map(\.name), range: chartColors)
                .chartYAxis { AxisMarks(preset: .extended, position: .leading) }
                .chartXAxis {
                    AxisMarks(values: .automatic) { value in
                        AxisGridLine().foregroundStyle(.secondary.opacity(0.15))
                        AxisValueLabel(format: range == .today ? .dateTime.hour() : .dateTime.weekday(.abbreviated))
                    }
                }
                .chartLegend(position: .bottom, alignment: .leading, spacing: 12)
                .frame(height: 210)
            }
        }
        .nesticCard()
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 15) {
            SectionHeading(title: "Totals", detail: range.title.uppercased())
            if totals.isEmpty {
                Text("No updates in this range.").font(.subheadline).foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(totals, id: \.tracker.id) { item in
                        HStack(spacing: 10) {
                            Image(systemName: trackerSymbol(item.tracker)).foregroundStyle(NesticTheme.forest)
                                .frame(width: 30, height: 30).background(NesticTheme.lime.opacity(0.25), in: Circle())
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
        VStack(alignment: .leading, spacing: 14) {
            SectionHeading(title: "History", detail: "DAILY")
            HStack(spacing: 6) {
                ForEach(Calendar.current.shortWeekdaySymbols, id: \.self) { day in
                    Text(String(day.prefix(1))).font(.caption2.weight(.semibold)).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                }
            }
            let leadingBlanks = max(0, Calendar.current.component(.weekday, from: historyDays.first ?? Date()) - 1)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 7), spacing: 8) {
                ForEach(0..<leadingBlanks, id: \.self) { _ in Color.clear.frame(height: 37) }
                ForEach(historyDays, id: \.self) { day in
                    let count = points.filter { Calendar.current.isDate($0.date, inSameDayAs: day) }.reduce(0) { $0 + $1.count }
                    VStack(spacing: 4) {
                        Text(day, format: .dateTime.day()).font(.caption.weight(.semibold))
                        Circle().fill(count == 0 ? NesticTheme.paper : NesticTheme.forest.opacity(min(1, 0.18 + Double(count) * 0.15)))
                            .frame(width: 9 + min(CGFloat(count), 4) * 3, height: 9 + min(CGFloat(count), 4) * 3)
                    }
                    .frame(maxWidth: .infinity).frame(height: 37)
                    .background(Calendar.current.isDateInToday(day) ? NesticTheme.lime.opacity(0.35) : Color.clear, in: RoundedRectangle(cornerRadius: 10))
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(day.formatted(date: .abbreviated, time: .omitted)), \(count) updates")
                }
            }
            Text("A gentler view of your shared story, one day at a time.").font(.caption).foregroundStyle(.secondary)
        }
        .nesticCard()
    }

    private var chartColors: [Color] {
        [NesticTheme.forest, Color(red: 0.86, green: 0.47, blue: 0.31), Color(red: 0.35, green: 0.55, blue: 0.73), Color(red: 0.67, green: 0.46, blue: 0.72), Color(red: 0.82, green: 0.65, blue: 0.22)]
    }
}

private struct AnalyticsPointKey: Hashable {
    let date: Date
    let trackerID: UUID
}

struct BathroomPredictionCard: View {
    @EnvironmentObject private var store: NesticStore
    @EnvironmentObject private var subscription: NesticSubscriptionStore
    let subject: NestSubject
    let showSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                Label("Bathroom forecast", systemImage: "wand.and.stars")
                    .font(.system(.title3, design: .rounded, weight: .bold))
                Spacer()
                Image(systemName: subscription.hasPredictionAccess ? "checkmark.seal.fill" : "lock.fill")
                    .foregroundStyle(subscription.hasPredictionAccess ? NesticTheme.forest : .secondary)
            }
            if subscription.hasPredictionAccess {
                if let prediction = store.bathroomPrediction(for: subject) {
                    Text(prediction.predictedAt, format: .dateTime.weekday(.wide).hour().minute())
                        .font(.system(.title2, design: .rounded, weight: .bold)).foregroundStyle(NesticTheme.forest)
                    HStack(spacing: 8) {
                        Text("~\(prediction.confidencePercent)% confidence")
                        Text("·")
                        Text("last break \(prediction.lastBathroomAt, format: .relative(presentation: .named))")
                    }.font(.caption).foregroundStyle(.secondary)
                    Text(prediction.explanation).font(.caption).foregroundStyle(.secondary)
                    if !prediction.inputNames.isEmpty {
                        Text("Using: \(prediction.inputNames.joined(separator: ", "))").font(.caption.weight(.medium)).foregroundStyle(NesticTheme.ink)
                    }
                } else {
                    Text("Log at least two bathroom updates to start a baseline. More history makes the forecast more useful.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Button("Tune what Nestic learns") { showSettings() }.font(.subheadline.weight(.semibold))
            } else {
                Text("Unlock a private, on-device pattern model that estimates when \(subject.name) may need the next bathroom break. Choose the data points it learns from.")
                    .font(.subheadline).foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Button(store.isDemo ? "Preview with sample data" : "Unlock Pro · \(subscription.priceDescription)") {
                        Task {
                            if store.isDemo { subscription.enableSamplePreview() }
                            else { await subscription.purchase() }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Restore") { Task { await subscription.restorePurchases() } }.buttonStyle(.bordered)
                }
                Text("Pattern estimates are not veterinary advice.").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .nesticCard()
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
                    Text("Choose the bathroom events Nestic should learn to predict. You can select pee, poop, or any custom tracker that represents a break.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    ForEach(trackers) { tracker in
                        selectionRow(tracker, selected: targetIDs.contains(tracker.id), label: "Bathroom event") {
                            toggle(tracker.id, in: &targetIDs)
                        }
                    }
                } header: { Text("Predict these events") }
                Section {
                    Text("These signals become features in the local model. Nothing here is sent to a prediction service.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    ForEach(trackers.filter { !targetIDs.contains($0.id) }) { tracker in
                        selectionRow(tracker, selected: inputIDs.contains(tracker.id), label: "Learning signal") {
                            toggle(tracker.id, in: &inputIDs)
                        }
                    }
                } header: { Text("Learn from these data points") }
                Section {
                    Label("Nestic needs at least two bathroom updates for a baseline, and three or more intervals before it starts fitting a model.", systemImage: "lock.privacy")
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
                Image(systemName: trackerSymbol(tracker)).foregroundStyle(NesticTheme.forest).frame(width: 22)
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
