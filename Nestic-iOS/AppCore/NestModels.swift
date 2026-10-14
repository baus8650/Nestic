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
    var manualPro: Bool = false
    var isAdmin: Bool = false
    var appleLinked: Bool = false

    enum CodingKeys: String, CodingKey {
        case id, email, displayName, role, manualPro, isAdmin, appleLinked
    }

    init(id: UUID, email: String, displayName: String, role: String? = nil, manualPro: Bool = false, isAdmin: Bool = false) {
        self.id = id
        self.email = email
        self.displayName = displayName
        self.role = role
        self.manualPro = manualPro
        self.isAdmin = isAdmin
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        email = try container.decode(String.self, forKey: .email)
        displayName = try container.decode(String.self, forKey: .displayName)
        role = try container.decodeIfPresent(String.self, forKey: .role)
        manualPro = try container.decodeIfPresent(Bool.self, forKey: .manualPro) ?? false
        isAdmin = try container.decodeIfPresent(Bool.self, forKey: .isAdmin) ?? false
        appleLinked = try container.decodeIfPresent(Bool.self, forKey: .appleLinked) ?? false
    }

    var initials: String {
        let parts = displayName.split(separator: " ")
        return parts.prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
    }
}

enum NestFeedbackStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case open
    case inProgress = "in_progress"
    case resolved

    var id: String { rawValue }

    var title: String {
        switch self {
        case .open: "Open"
        case .inProgress: "In progress"
        case .resolved: "Resolved"
        }
    }
}

struct NestFeedbackMessage: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var authorUserId: UUID
    var authorDisplayName: String
    var authorEmail: String
    var isAdmin: Bool
    var body: String
    var createdAt: Date?
}

struct NestFeedbackThread: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var userId: UUID
    var userDisplayName: String
    var userEmail: String
    var subject: String
    var category: String
    var status: NestFeedbackStatus
    var createdAt: Date?
    var lastActivityAt: Date
    var messageCount: Int
    var lastMessagePreview: String?
    var lastMessageIsAdmin: Bool?
    var messages: [NestFeedbackMessage]
}

struct NestAdminUser: Decodable, Identifiable, Sendable {
    var id: UUID
    var email: String
    var displayName: String
    var emailVerified: Bool
    var createdAt: Date?
    var nestCount: Int
    var manualPro: Bool?
}

struct NestAdminDashboard: Decodable, Sendable {
    var totalUsers: Int
    var verifiedUsers: Int
    var totalNests: Int
    var totalEvents: Int
    var activeUsersLast30Days: Int
    var openFeedback: Int
    var inProgressFeedback: Int
    var resolvedFeedback: Int
    var recentUsers: [NestAdminUser]
    var recentFeedback: [NestFeedbackThread]
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
    var photoData: String? = nil
    /// Server-side R2 reference. `photoData` is only a local cache for rendering.
    var photoURL: String? = nil
}

enum NestValueType: String, Codable, CaseIterable, Identifiable, Sendable {
    case none, number, text, boolean, json, photo, health
    var id: String { rawValue }
    var title: String {
        switch self {
        case .none: "Just an update"
        case .number: "Number"
        case .text: "Text"
        case .boolean: "Yes or no"
        case .json: "Details"
        case .photo: "Photo"
        case .health: "Health event"
        }
    }
    var symbol: String {
        switch self {
        case .none: "checkmark"
        case .number: "number"
        case .text: "text.alignleft"
        case .boolean: "switch.2"
        case .json: "list.bullet.rectangle"
        case .photo: "camera.fill"
        case .health: "cross.case.fill"
        }
    }
}

enum TrackerUnitCatalog {
    static func suggestions(for trackerName: String) -> [String] {
        let name = trackerName.lowercased()
        if name.contains("food") || name.contains("feed") || name.contains("meal") || name.contains("treat") {
            return ["cups", "tablespoons", "teaspoons", "grams", "ounces", "pounds", "servings", "pieces", "calories"]
        }
        if name.contains("water") || name.contains("drink") || name.contains("hydration") || name.contains("fluid") {
            return ["cups", "fluid ounces", "milliliters", "liters", "glasses", "bottles"]
        }
        return ["count", "minutes", "hours", "cups", "grams", "ounces", "servings"]
    }
}

struct NestHealthPhoto: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var capturedAt: Date
    /// Private server-side reference. The image is fetched through an
    /// authenticated endpoint and cached on-device only after it is viewed.
    var photoURL: String
    /// Optional text update recorded alongside the photo. An empty `photoURL`
    /// represents a text-only health update.
    var note: String? = nil
}

struct NestTracker: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var nestId: UUID
    var name: String
    var valueType: NestValueType
    var unit: String?
    /// An SF Symbol name or a single emoji selected by the nest owner.
    /// Older servers may omit this field, so the UI falls back to a smart default.
    var symbol: String? = nil
    /// A six-digit hex color selected by the nest owner.
    var color: String? = nil
    /// Optional grouping label, such as "Medication". Older API responses do
    /// not include this field, so decoding intentionally treats it as nil.
    var groupName: String? = nil
    var privateOwnerId: UUID? = nil
    var allowedMemberIDs: [UUID]? = nil
    var isArchived: Bool? = nil
    var privacyLabel: String { isPrivate ? ((allowedMemberIDs ?? []).isEmpty ? "Only me" : "Selected members") : "Everyone" }
    func canContribute(to target: NestTracker) -> Bool {
        guard let owner = privateOwnerId else { return true }
        guard let targetOwner = target.privateOwnerId else { return false }
        return Set(target.allowedMemberIDs ?? []).union([targetOwner]).isSubset(of: Set(allowedMemberIDs ?? []).union([owner]))
    }
    var isPrivate: Bool { privateOwnerId != nil }
    enum CodingKeys: String, CodingKey {
        case id, nestId, name, valueType, unit, symbol, color, groupName, privateOwnerId, allowedMemberIDs, isArchived
    }

    init(id: UUID, nestId: UUID, name: String, valueType: NestValueType, unit: String? = nil, symbol: String? = nil, color: String? = nil, groupName: String? = nil, privateOwnerId: UUID? = nil, allowedMemberIDs: [UUID]? = nil) {
        self.id = id
        self.nestId = nestId
        self.name = name
        self.valueType = valueType
        self.unit = unit
        self.symbol = symbol
        self.color = color
        self.groupName = groupName
        self.privateOwnerId = privateOwnerId
        self.allowedMemberIDs = allowedMemberIDs
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        nestId = try container.decode(UUID.self, forKey: .nestId)
        name = try container.decode(String.self, forKey: .name)
        valueType = try container.decode(NestValueType.self, forKey: .valueType)
        unit = try container.decodeIfPresent(String.self, forKey: .unit)
        symbol = try container.decodeIfPresent(String.self, forKey: .symbol)
        color = try container.decodeIfPresent(String.self, forKey: .color)
        groupName = try container.decodeIfPresent(String.self, forKey: .groupName)
        privateOwnerId = try container.decodeIfPresent(UUID.self, forKey: .privateOwnerId)
        allowedMemberIDs = try container.decodeIfPresent([UUID].self, forKey: .allowedMemberIDs)
        isArchived = try container.decodeIfPresent(Bool.self, forKey: .isArchived)
    }
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
    /// Optional for backwards-compatible decoding of events created before
    /// event metadata was added.
    var wasAccident: Bool? = nil
    var includeInPredictions: Bool? = nil
    /// Private server-side reference for a photo attached to this event.
    /// The binary itself is fetched through an authenticated API endpoint.
    var photoURL: String? = nil
    /// Health-event lifecycle metadata. `occurredAt` is the onset; a nil
    /// resolution timestamp means the episode is still open.
    var resolvedAt: Date? = nil
    var resolutionNote: String? = nil
    /// Additional dated photos added after the onset photo. Optional keeps
    /// snapshots created by older app/server versions decodable.
    var photoUpdates: [NestHealthPhoto]? = nil

    var isAccident: Bool { wasAccident ?? false }
    var shouldIncludeInPredictions: Bool { includeInPredictions ?? true }

    func displayValue(unit: String? = nil, trackerName: String? = nil) -> String {
        if let valueNumber {
            let amount = valueNumber.formatted(.number.precision(.fractionLength(0...2)))
            return unit.flatMap { $0.isEmpty ? nil : "\(amount) \($0)" } ?? amount
        }
        if let valueText { return valueText }
        if let valueBool { return valueBool ? "Yes" : "No" }
        if let valueJSON {
            return valueJSON.keys.sorted().map { "\($0): \(valueJSON[$0] ?? "")" }.joined(separator: " · ")
        }
        return "Done"
    }
}

/// A short-lived, scope-limited sharing link for a sitter or other helper.
/// The raw token is only present on the link returned immediately after
/// creation; the server never returns it when listing existing links.
struct NestCareLink: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var nestId: UUID
    var label: String
    var expiresAt: Date
    var entityIDs: [UUID]
    var actionIDs: [UUID]
    var canLog: Bool
    var canViewHistory: Bool
    var revokedAt: Date?
    var createdAt: Date?
    var token: String?

    var isActive: Bool { revokedAt == nil && expiresAt > Date() }

    func shareURL(serverURL: String) -> URL? {
        guard let token, !token.isEmpty else { return nil }
        var components = URLComponents()
        components.scheme = "nestic"
        components.host = "care"
        components.queryItems = [
            URLQueryItem(name: "token", value: token),
            URLQueryItem(name: "server", value: serverURL)
        ]
        return components.url
    }
}

struct NestCareSnapshot: Hashable, Sendable {
    var link: NestCareLink
    var nestName: String
    var subjects: [NestSubject]
    var trackers: [NestTracker]
    var routines: [NestRoutine]
    var entries: [NestEntry]
}

struct NestCareSession: Sendable {
    var token: String
    var serverURL: String
    var snapshot: NestCareSnapshot
}

struct NestRoutineItem: Codable, Hashable, Sendable, Identifiable {
    var trackerID: UUID
    var valueNumber: Double? = nil
    var valueText: String? = nil
    var valueBool: Bool? = nil
    var valueJSON: [String: String]? = nil

    var id: UUID { trackerID }
}

struct NestRoutineTarget: Codable, Hashable, Sendable, Identifiable {
    var entityID: UUID
    var items: [NestRoutineItem]

    var id: UUID { entityID }
}

struct NestRoutine: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var nestId: UUID
    var subjectID: UUID
    var name: String
    var items: [NestRoutineItem]
    var targets: [NestRoutineTarget]
    var createdAt: Date? = nil
    var updatedAt: Date? = nil
    var privateOwnerId: UUID? = nil
    var isPrivate: Bool { privateOwnerId != nil }

    init(id: UUID, nestId: UUID, subjectID: UUID, name: String, items: [NestRoutineItem],
         targets: [NestRoutineTarget] = [], createdAt: Date? = nil, updatedAt: Date? = nil, privateOwnerId: UUID? = nil) {
        self.privateOwnerId = privateOwnerId
        self.id = id
        self.nestId = nestId
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        let resolvedTargets = targets.isEmpty
            ? [NestRoutineTarget(entityID: subjectID, items: items)]
            : targets
        self.targets = resolvedTargets
        self.subjectID = resolvedTargets[0].entityID
        self.items = resolvedTargets[0].items
    }

    enum CodingKeys: String, CodingKey {
        case id, nestId, subjectID, name, items, targets, createdAt, updatedAt
        case entityId, privateOwnerId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        nestId = try container.decode(UUID.self, forKey: .nestId)
        let legacySubjectID: UUID
        if let subjectID = try container.decodeIfPresent(UUID.self, forKey: .subjectID) {
            legacySubjectID = subjectID
        } else {
            legacySubjectID = try container.decode(UUID.self, forKey: .entityId)
        }
        name = try container.decode(String.self, forKey: .name)
        let legacyItems = try container.decodeIfPresent([NestRoutineItem].self, forKey: .items) ?? []
        let decodedTargets = try container.decodeIfPresent([NestRoutineTarget].self, forKey: .targets) ?? []
        let resolvedTargets = decodedTargets.isEmpty
            ? [NestRoutineTarget(entityID: legacySubjectID, items: legacyItems)]
            : decodedTargets
        targets = resolvedTargets
        subjectID = resolvedTargets[0].entityID
        items = resolvedTargets[0].items
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
        privateOwnerId = try container.decodeIfPresent(UUID.self, forKey: .privateOwnerId)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(nestId, forKey: .nestId)
        try container.encode(subjectID, forKey: .subjectID)
        try container.encode(name, forKey: .name)
        try container.encode(items, forKey: .items)
        try container.encode(targets, forKey: .targets)
        try container.encodeIfPresent(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(privateOwnerId, forKey: .privateOwnerId)
    }

    mutating func syncLegacyTargetFields() {
        guard let first = targets.first else { return }
        subjectID = first.entityID
        items = first.items
    }
}

struct NestTrackerTemplate: Identifiable, Hashable, Sendable {
    var name: String
    var valueType: NestValueType = .none
    var unit: String? = nil
    var symbol: String? = nil
    var color: String? = nil
    var groupName: String? = nil
    var id: String { "\(name)-\(valueType.rawValue)" }

    static let dog: [Self] = [
        .init(name: "Daily check-in", symbol: "heart.text.clipboard"),
        .init(name: "Outdoor time", valueType: .number, unit: "min"),
        .init(name: "Meal", valueType: .number, unit: "cups"),
        .init(name: "Weight", valueType: .number, unit: "lbs")
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

/// The icon picker intentionally uses system symbols rather than bundled image
/// assets. That gives users a large, crisp library of icons that adapts to light
/// and dark mode without increasing the app download size.
enum TrackerIconCatalog {
    static let symbols: [String] = [
        "checkmark.circle.fill", "circle.fill", "star.fill", "heart.fill", "bolt.fill", "sparkles", "bell.fill", "flag.fill", "exclamationmark.triangle.fill",
        "pawprint.fill", "figure.walk", "figure.run", "figure.hiking", "bicycle", "figure.pool.swim", "figure.and.child.holdinghands",
        "dog.fill", "cat.fill", "bird.fill", "fish.fill", "hare.fill", "tortoise.fill", "ladybug.fill", "ant.fill",
        "drop.fill", "humidity.fill", "cloud.rain.fill", "sun.max.fill", "moon.fill", "moon.stars.fill", "thermometer.medium", "wind",
        "fork.knife", "takeoutbag.and.cup.and.straw.fill", "cup.and.saucer.fill", "carrot.fill", "birthday.cake.fill", "cross.case.fill",
        "pills.fill", "syringe.fill", "bandage.fill", "stethoscope", "bed.double.fill", "sofa.fill", "house.fill", "building.2.fill",
        "key.fill", "lock.fill", "lightbulb.fill", "washer.fill", "refrigerator.fill", "shower.fill", "toilet.fill", "bathtub.fill",
        "trash.fill", "bubbles.and.sparkles.fill", "sprinkler.and.droplets.fill", "leaf.fill", "tree.fill", "mountain.2.fill", "tent.fill",
        "cart.fill", "bag.fill", "gift.fill", "creditcard.fill", "dollarsign.circle.fill", "calendar", "clock.fill", "timer",
        "chart.bar.fill", "chart.line.uptrend.xyaxis", "list.bullet.clipboard.fill", "note.text", "pencil.and.outline", "camera.fill",
        "book.fill", "graduationcap.fill", "briefcase.fill", "hammer.fill", "wrench.and.screwdriver.fill", "gearshape.fill", "person.fill",
        "person.2.fill", "person.3.fill", "figure.2.and.child.holdinghands", "message.fill", "phone.fill", "envelope.fill", "location.fill"
    ]

    static let emojis: [String] = [
        "🐶", "🐱", "🐭", "🐹", "🐰", "🦊", "🐻", "🐼", "🐨", "🐯", "🦁", "🐮", "🐷", "🐸", "🐵", "🙈",
        "🐔", "🐧", "🐦", "🐤", "🦆", "🦅", "🦉", "🐺", "🐗", "🐴", "🦄", "🐝", "🐛", "🦋", "🐌", "🐞",
        "🐢", "🐍", "🦎", "🐙", "🦀", "🐠", "🐟", "🐬", "🐳", "🦈", "🌻", "🌈", "☀️", "🌙", "⭐", "✨",
        "❤️", "🧡", "💛", "💚", "💙", "💜", "🖤", "🤍", "🤎", "💗", "💪", "👍", "👏", "🙏", "🎉", "🎈",
        "🍎", "🍌", "🥕", "🍽️", "🍪", "🍼", "☕", "💧", "🥤", "🛏️", "🚶", "🏃", "🚲", "🏊", "⚽", "🎾",
        "🏠", "🏡", "🛁", "🚿", "🧼", "🧹", "🧺", "🛒", "💊", "🩺", "🩹", "📅", "⏰", "📝", "📷", "🎵"
    ]

    static func isEmoji(_ value: String) -> Bool {
        value.unicodeScalars.contains { scalar in
            scalar.properties.isEmojiPresentation || (scalar.properties.isEmoji && scalar.value > 0x238C)
        }
    }

    static func defaultSymbol(for name: String, valueType: NestValueType) -> String {
        let name = name.lowercased()
        if name.contains("pee") || name.contains("water") { return "drop.fill" }
        if name.contains("poop") { return "leaf.fill" }
        if name.contains("food") || name.contains("fed") || name.contains("grocer") || name.contains("meal") { return "fork.knife" }
        if name.contains("walk") || name.contains("outdoor") { return "figure.walk" }
        if name.contains("weight") { return "scalemass.fill" }
        if name.contains("mood") { return "face.smiling" }
        if name.contains("check-in") { return "heart.text.clipboard" }
        if name.contains("sleep") { return "moon.fill" }
        if name.contains("clean") { return "sparkles" }
        if name.contains("accident") { return "exclamationmark.triangle.fill" }
        if name.contains("train") { return "graduationcap.fill" }
        if name.contains("health") || name.contains("injur") || name.contains("symptom") || name.contains("illness") {
            return "cross.case.fill"
        }
        return valueType.symbol
    }
}

struct TrackerColorOption: Identifiable, Hashable, Sendable {
    let name: String
    let hex: String
    var id: String { hex }
}

enum TrackerColorCatalog {
    static let colors: [TrackerColorOption] = [
        .init(name: "Forest", hex: "#2E6B52"), .init(name: "Ocean", hex: "#2879A8"), .init(name: "Sky", hex: "#4D9DE0"), .init(name: "Lavender", hex: "#8067B7"),
        .init(name: "Berry", hex: "#B04472"), .init(name: "Coral", hex: "#D96C57"), .init(name: "Sun", hex: "#D89B27"), .init(name: "Leaf", hex: "#6A9F3B"),
        .init(name: "Mint", hex: "#45A88A"), .init(name: "Slate", hex: "#64748B"), .init(name: "Plum", hex: "#8B5E83"), .init(name: "Rose", hex: "#C85A78")
    ]

    static func defaultColor(for name: String, valueType: NestValueType) -> String {
        let name = name.lowercased()
        if name.contains("pee") || name.contains("water") { return "#2879A8" }
        if name.contains("poop") { return "#8B5E83" }
        if name.contains("food") || name.contains("fed") { return "#D96C57" }
        if name.contains("walk") { return "#6A9F3B" }
        if name.contains("sleep") { return "#8067B7" }
        if name.contains("clean") { return "#45A88A" }
        if name.contains("accident") { return "#D96C57" }
        if name.contains("train") { return "#2E6B52" }
        switch valueType {
        case .number: return "#D89B27"
        case .text: return "#64748B"
        case .boolean: return "#2E6B52"
        case .json: return "#B04472"
        case .photo: return "#B04472"
        case .health: return "#D96C57"
        case .none: return "#2E6B52"
        }
    }
}

enum NesticError: LocalizedError {
    case termsAcceptanceRequired
    case message(String)
    case unauthorized
    case staleSession
    var errorDescription: String? {
        switch self {
        case .termsAcceptanceRequired: "Please read and agree to the Terms of Service before creating an account."
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
    var routines: [NestRoutine] = []

    enum CodingKeys: String, CodingKey {
        case subjects, trackers, entries, members, routines
    }

    init(subjects: [NestSubject] = [], trackers: [NestTracker] = [], entries: [NestEntry] = [],
         members: [NestPerson] = [], routines: [NestRoutine] = []) {
        self.subjects = subjects
        self.trackers = trackers
        self.entries = entries
        self.members = members
        self.routines = routines
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        subjects = try container.decodeIfPresent([NestSubject].self, forKey: .subjects) ?? []
        trackers = try container.decodeIfPresent([NestTracker].self, forKey: .trackers) ?? []
        entries = try container.decodeIfPresent([NestEntry].self, forKey: .entries) ?? []
        members = try container.decodeIfPresent([NestPerson].self, forKey: .members) ?? []
        routines = try container.decodeIfPresent([NestRoutine].self, forKey: .routines) ?? []
    }
}

struct NestArchive: Codable {
    var user: NestPerson
    var nests: [NestSpace]
    var selectedNestID: UUID?
    var snapshots: [String: NestSnapshot]
}
