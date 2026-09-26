import Foundation

struct NestSpace: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var name: String
}

struct NestPerson: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var email: String
    var displayName: String
    var role: String? = nil

    var initials: String {
        let parts = displayName.split(separator: " ")
        return parts.prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
    }
}

enum NestSubjectKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case pet, person, thing, custom
    var id: String { rawValue }
    var title: String {
        switch self {
        case .pet: "Pet"
        case .person: "Person"
        case .thing: "Home & things"
        case .custom: "Something else"
        }
    }
    var emoji: String {
        switch self {
        case .pet: "🐶"
        case .person: "🌻"
        case .thing: "🏡"
        case .custom: "✨"
        }
    }
}

struct NestSubject: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var nestId: UUID
    var name: String
    var kind: NestSubjectKind
    var emoji: String
    var pinnedActionIDs: [UUID] = []
}

enum NestValueType: String, Codable, CaseIterable, Identifiable, Sendable {
    case none, number, text, boolean, json
    var id: String { rawValue }
    var title: String {
        switch self {
        case .none: "Just an update"
        case .number: "Number"
        case .text: "Text"
        case .boolean: "Yes or no"
        case .json: "Details"
        }
    }
    var symbol: String {
        switch self {
        case .none: "checkmark"
        case .number: "number"
        case .text: "text.alignleft"
        case .boolean: "switch.2"
        case .json: "list.bullet.rectangle"
        }
    }
}

struct NestTracker: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var nestId: UUID
    var name: String
    var valueType: NestValueType
    var unit: String?
}

struct NestEntry: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var nestId: UUID
    var entityId: UUID
    var actionId: UUID
    var actorUserId: UUID?
    var occurredAt: Date
    var valueNumber: Double? = nil
    var valueText: String? = nil
    var valueBool: Bool? = nil
    var valueJSON: [String: String]? = nil
    var note: String? = nil

    func displayValue(unit: String? = nil) -> String {
        if let valueNumber {
            let amount = valueNumber.formatted(.number.precision(.fractionLength(0...2)))
            return unit.flatMap { $0.isEmpty ? nil : "\(amount) \($0)" } ?? amount
        }
        if let valueText { return valueText }
        if let valueBool { return valueBool ? "Yes" : "No" }
        if let valueJSON { return valueJSON.keys.sorted().map { "\($0): \(valueJSON[$0] ?? "")" }.joined(separator: " · ") }
        return "Done"
    }
}

struct NestTrackerTemplate: Identifiable, Hashable, Sendable {
    var name: String
    var valueType: NestValueType = .none
    var unit: String? = nil
    var id: String { "\(name)-\(valueType.rawValue)" }

    static let dog: [Self] = [
        .init(name: "Pee"), .init(name: "Poop"),
        .init(name: "Food", valueType: .number, unit: "cups"),
        .init(name: "Walk", valueType: .number, unit: "min")
    ]
    static let home: [Self] = [
        .init(name: "Water plants"), .init(name: "Clean"), .init(name: "Groceries", valueType: .text)
    ]
    static let person: [Self] = [
        .init(name: "Water", valueType: .number, unit: "glasses"),
        .init(name: "Sleep", valueType: .number, unit: "hours"),
        .init(name: "Mood", valueType: .text)
    ]
}

enum NesticError: LocalizedError {
    case message(String)
    case unauthorized
    case staleSession
    var errorDescription: String? {
        switch self {
        case .message(let message): message
        case .unauthorized: "Your session has expired. Please sign in again."
        case .staleSession: "Your nest or account changed. Please try again."
        }
    }
}

struct NestSnapshot: Codable {
    var subjects: [NestSubject] = []
    var trackers: [NestTracker] = []
    var entries: [NestEntry] = []
    var members: [NestPerson] = []
}

struct NestArchive: Codable {
    var user: NestPerson
    var nests: [NestSpace]
    var selectedNestID: UUID?
    var snapshots: [String: NestSnapshot]
}
