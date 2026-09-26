import SwiftUI
import WidgetKit

struct NesticWidgetSnapshot: Codable {
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

struct NesticWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: NesticWidgetSnapshot?
}

struct NesticWidgetProvider: TimelineProvider {
    private let appGroup = "group.com.bausch.Nestic-iOS"
    private let snapshotKey = "nestic.widget.snapshot.v1"

    func placeholder(in context: Context) -> NesticWidgetEntry {
        NesticWidgetEntry(date: Date(), snapshot: NesticWidgetSnapshot(subjectID: UUID(), subjectName: "Milo", subjectEmoji: "🐶", peeTrackerID: UUID(), poopTrackerID: UUID(), peeTrackerName: "Pee", poopTrackerName: "Poop", lastPee: Date().addingTimeInterval(-3600), lastPoop: Date().addingTimeInterval(-7200), todayPeeCount: 2, todayPoopCount: 1, predictedAt: Date().addingTimeInterval(3600), predictionConfidence: 72))
    }

    func getSnapshot(in context: Context, completion: @escaping (NesticWidgetEntry) -> Void) {
        completion(NesticWidgetEntry(date: Date(), snapshot: load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NesticWidgetEntry>) -> Void) {
        let now = Date()
        let entry = NesticWidgetEntry(date: now, snapshot: load())
        completion(Timeline(entries: [entry], policy: .after(now.addingTimeInterval(30 * 60))))
    }

    private func load() -> NesticWidgetSnapshot? {
        guard let data = UserDefaults(suiteName: appGroup)?.data(forKey: snapshotKey) else { return nil }
        return try? JSONDecoder().decode(NesticWidgetSnapshot.self, from: data)
    }
}

struct NesticWidgetView: View {
    let entry: NesticWidgetEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if let snapshot = entry.snapshot {
                switch family {
                case .systemSmall: small(snapshot)
                case .systemMedium: medium(snapshot)
                case .systemLarge: large(snapshot)
                case .accessoryRectangular: lockScreen(snapshot)
                default: medium(snapshot)
                }
            } else {
                empty
            }
        }
        .containerBackground(for: .widget) {
            LinearGradient(colors: [Color(red: 0.14, green: 0.30, blue: 0.24), Color(red: 0.23, green: 0.42, blue: 0.31)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    private func small(_ snapshot: NesticWidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(snapshot.subjectEmoji).font(.largeTitle)
            Text(snapshot.subjectName).font(.headline).foregroundStyle(.white).lineLimit(1)
            Spacer(minLength: 0)
            if let predictedAt = snapshot.predictedAt {
                Label { Text(predictedAt, format: .dateTime.hour().minute()) } icon: { Image(systemName: "wand.and.stars") }
                    .font(.caption.weight(.semibold)).foregroundStyle(Color(red: 0.84, green: 0.93, blue: 0.60))
            } else {
                Text("Log a break to start a forecast").font(.caption2).foregroundStyle(.white.opacity(0.78))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(15)
    }

    private func medium(_ snapshot: NesticWidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(snapshot.subjectEmoji)  \(snapshot.subjectName)").font(.headline).foregroundStyle(.white)
                Spacer()
                if let confidence = snapshot.predictionConfidence { Text("\(confidence)% forecast").font(.caption2.weight(.semibold)).foregroundStyle(Color(red: 0.84, green: 0.93, blue: 0.60)) }
            }
            HStack(spacing: 10) {
                lastEvent(title: snapshot.peeTrackerName ?? "Pee", date: snapshot.lastPee, count: snapshot.todayPeeCount, icon: "drop.fill")
                lastEvent(title: snapshot.poopTrackerName ?? "Poop", date: snapshot.lastPoop, count: snapshot.todayPoopCount, icon: "leaf.fill")
            }
            HStack(spacing: 8) {
                quickLog(snapshot, trackerID: snapshot.peeTrackerID, title: "Pee", icon: "drop.fill")
                quickLog(snapshot, trackerID: snapshot.poopTrackerID, title: "Poop", icon: "leaf.fill")
            }
        }
        .padding(15)
    }

    private func large(_ snapshot: NesticWidgetSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(snapshot.subjectEmoji)  \(snapshot.subjectName)").font(.title3.bold()).foregroundStyle(.white)
                    Text("Today’s care at a glance").font(.caption).foregroundStyle(.white.opacity(0.75))
                }
                Spacer()
            }
            Divider().overlay(.white.opacity(0.25))
            HStack(spacing: 12) {
                metric(title: "Pee", value: "\(snapshot.todayPeeCount)", icon: "drop.fill")
                metric(title: "Poop", value: "\(snapshot.todayPoopCount)", icon: "leaf.fill")
            }
            if let predictedAt = snapshot.predictedAt {
                VStack(alignment: .leading, spacing: 3) {
                    Text("NEXT LIKELY BREAK").font(.caption2.weight(.bold)).tracking(0.9).foregroundStyle(.white.opacity(0.7))
                    Text(predictedAt, format: .dateTime.weekday(.wide).hour().minute()).font(.headline).foregroundStyle(Color(red: 0.84, green: 0.93, blue: 0.60))
                }
            }
            Spacer()
            HStack(spacing: 8) {
                quickLog(snapshot, trackerID: snapshot.peeTrackerID, title: "Log pee", icon: "drop.fill")
                quickLog(snapshot, trackerID: snapshot.poopTrackerID, title: "Log poop", icon: "leaf.fill")
            }
        }
        .padding(18)
    }

    private func lockScreen(_ snapshot: NesticWidgetSnapshot) -> some View {
        HStack(spacing: 8) {
            Text(snapshot.subjectEmoji)
            VStack(alignment: .leading) {
                Text(snapshot.subjectName).font(.headline)
                if let predictedAt = snapshot.predictedAt { Text(predictedAt, style: .time).font(.caption) }
                else { Text("Log a break to learn").font(.caption) }
            }
        }
    }

    private var empty: some View {
        VStack(spacing: 5) {
            Image(systemName: "pawprint.fill").font(.title2).foregroundStyle(Color(red: 0.84, green: 0.93, blue: 0.60))
            Text("Open Nestic to choose a subject").font(.caption).multilineTextAlignment(.center).foregroundStyle(.white)
        }.padding(14)
    }

    private func lastEvent(title: String, date: Date?, count: Int, icon: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon).foregroundStyle(Color(red: 0.84, green: 0.93, blue: 0.60))
            VStack(alignment: .leading, spacing: 2) {
                Text("\(count) today").font(.subheadline.bold()).foregroundStyle(.white)
                Text(date.map { "Last \(title.lowercased()) \($0.formatted(.dateTime.hour().minute()))" } ?? "No \(title.lowercased()) yet")
                    .font(.caption2).foregroundStyle(.white.opacity(0.72)).lineLimit(1)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func metric(title: String, value: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Image(systemName: icon).foregroundStyle(Color(red: 0.84, green: 0.93, blue: 0.60))
            Text(value).font(.system(size: 28, weight: .bold, design: .rounded)).foregroundStyle(.white)
            Text(title).font(.caption).foregroundStyle(.white.opacity(0.72))
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func quickLog(_ snapshot: NesticWidgetSnapshot, trackerID: UUID?, title: String, icon: String) -> some View {
        Group {
            if let trackerID, let url = URL(string: "nestic://log?subjectID=\(snapshot.subjectID.uuidString)&trackerID=\(trackerID.uuidString)") {
                Link(destination: url) {
                    Label(title, systemImage: icon).font(.caption.weight(.semibold)).frame(maxWidth: .infinity).padding(.vertical, 8)
                        .background(.white.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))
                }
            }
        }
        .foregroundStyle(.white)
    }
}

struct NesticWidget: Widget {
    let kind = "NesticWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NesticWidgetProvider()) { entry in
            NesticWidgetView(entry: entry)
        }
        .configurationDisplayName("Nestic care")
        .description("See bathroom updates and your next likely break.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular])
    }
}

@main
struct NesticWidgetBundle: WidgetBundle {
    var body: some Widget { NesticWidget() }
}
