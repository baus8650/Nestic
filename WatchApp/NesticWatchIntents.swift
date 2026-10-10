import AppIntents
import Foundation

/// App Shortcuts currently allow only one dynamic parameter in each phrase.
/// Modeling the tracker/entity pair as one entity keeps the spoken form
/// natural: Siri can resolve a target such as “Pee for Milo”.
struct NesticWatchTargetEntity: AppEntity, Hashable {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Tracker")

    struct Query: EntityQuery {
        static let persistentIdentifier = "NesticWatch.TargetQuery"

        func entities(for identifiers: [String]) async throws -> [NesticWatchTargetEntity] {
            let pairs = await NesticWatchStore.shared.subjectTrackerPairs()
            return pairs.flatMap { subject, trackers in
                trackers.compactMap { tracker in
                    let target = Self.entity(subject: subject, tracker: tracker)
                    return identifiers.contains(target.id) ? target : nil
                }
            }
        }

        func suggestedEntities() async throws -> [NesticWatchTargetEntity] {
            let pairs = await NesticWatchStore.shared.subjectTrackerPairs()
            return pairs.flatMap { subject, trackers in
                trackers.map { Self.entity(subject: subject, tracker: $0) }
            }
        }

        private static func entity(subject: NestSubject, tracker: NestTracker) -> NesticWatchTargetEntity {
            NesticWatchTargetEntity(
                id: "\(subject.id.uuidString)|\(tracker.id.uuidString)",
                subjectID: subject.id.uuidString,
                trackerID: tracker.id.uuidString,
                displayString: "\(tracker.name) for \(subject.name)"
            )
        }
    }

    static let defaultQuery = Query()

    var id: String
    var subjectID: String
    var trackerID: String
    var displayString: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(displayString)")
    }

    init(id: String, subjectID: String, trackerID: String, displayString: String) {
        self.id = id
        self.subjectID = subjectID
        self.trackerID = trackerID
        self.displayString = displayString
    }
}

struct NesticWatchRecordTrackerIntent: AppIntent {
    static var title: LocalizedStringResource { "Record Tracker" }
    static var description: IntentDescription { "Record a tracker for an entity in Nestic." }
    static var openAppWhenRun: Bool { false }

    @Parameter(title: "Tracker for entity")
    var target: NesticWatchTargetEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Record \(\.$target)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let trackerID = UUID(uuidString: target.trackerID),
              let entityID = UUID(uuidString: target.subjectID) else {
            return .result(dialog: "I couldn’t identify that tracker or entity.")
        }
        let message = await NesticWatchStore.shared.recordFromIntent(trackerID: trackerID, subjectID: entityID)
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

struct NesticWatchShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: NesticWatchRecordTrackerIntent(),
            phrases: [
                "Record \(\.$target) in \(.applicationName)",
                "Log \(\.$target) in \(.applicationName)"
            ],
            shortTitle: "Record a tracker",
            systemImageName: "checkmark.circle"
        )
    }
}
