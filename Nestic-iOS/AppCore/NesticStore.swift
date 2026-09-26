import Foundation
import Combine

@MainActor
final class NesticStore: ObservableObject {
    @Published private(set) var currentUser: NestPerson?
    @Published private(set) var isDemo = false
    @Published private(set) var nests: [NestSpace] = []
    @Published private(set) var selectedNestID: UUID?
    @Published private(set) var subjects: [NestSubject] = []
    @Published private(set) var trackers: [NestTracker] = []
    @Published private(set) var entries: [NestEntry] = []
    @Published private(set) var members: [NestPerson] = []
    @Published private(set) var predictionPreferences: [UUID: NestPredictionPreferences] = [:]
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?
    @Published private(set) var connectionStatus = "Not connected"
    @Published private(set) var serverURL: String

    var selectedNest: NestSpace? { nests.first { $0.id == selectedNestID } }
    var isAuthenticated: Bool { currentUser != nil }
    var canManageNest: Bool {
        isDemo || members.contains { $0.id == currentUser?.id && ["owner", "admin"].contains($0.role ?? "") }
    }
    var canLog: Bool {
        isDemo || members.contains { $0.id == currentUser?.id && $0.role != "viewer" }
    }

    private let defaults: UserDefaults
    private let session: URLSession
    private let keychain = NestKeychain()
    private var token: String?
    private var snapshots: [String: NestSnapshot] = [:]
    private var generation = UUID()
    private var refreshSequence = 0
    private var loadingCount = 0
    private var socket: URLSessionWebSocketTask?
    private var socketNestID: UUID?
    private var realtimeTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?

    init(defaults: UserDefaults = .standard, session: URLSession = .shared, restoreSession: Bool = true) {
        self.defaults = defaults
        self.session = session
        let bundledServerURL = Bundle.main.object(forInfoDictionaryKey: "NesticServerURL") as? String
        self.serverURL = defaults.string(forKey: "nestic.server.v1") ?? bundledServerURL ?? "http://127.0.0.1:8080"
        guard restoreSession, !defaults.bool(forKey: "nestic.signedOut.\(NestCoding.serverKey(serverURL))") else { return }
        do {
            if let saved = try keychain.load(server: serverURL) {
                token = saved.token
                currentUser = saved.user
                restoreArchive()
                connectionStatus = "Connecting…"
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        restorePredictionPreferences()
    }

    func trackers(for subject: NestSubject) -> [NestTracker] {
        subject.pinnedActionIDs.compactMap { id in trackers.first { $0.id == id } }
    }

    func preferences(for subject: NestSubject) -> NestPredictionPreferences {
        let subjectTrackers = trackers(for: subject)
        let targetIDs = BathroomPredictionEngine.inferredTargetIDs(trackers: subjectTrackers)
        return predictionPreferences[subject.id] ?? .init(
            inputTrackerIDs: BathroomPredictionEngine.defaultInputIDs(trackers: subjectTrackers, targetIDs: targetIDs),
            targetTrackerIDs: targetIDs
        )
    }

    func bathroomPrediction(for subject: NestSubject, now: Date = Date()) -> BathroomPrediction? {
        BathroomPredictionEngine.predict(subject: subject, trackers: trackers(for: subject), entries: entries,
                                         preferences: preferences(for: subject), now: now)
    }

    func updatePredictionPreferences(for subject: NestSubject, inputTrackerIDs: [UUID], targetTrackerIDs: [UUID]) {
        predictionPreferences[subject.id] = NestPredictionPreferences(inputTrackerIDs: inputTrackerIDs,
                                                                       targetTrackerIDs: targetTrackerIDs)
        persistPredictionPreferences()
        refreshWidget()
    }

    func entries(for subject: NestSubject) -> [NestEntry] {
        entries.filter { $0.entityId == subject.id }.sorted { $0.occurredAt > $1.occurredAt }
    }

    func latestEntry(for tracker: NestTracker, subject: NestSubject) -> NestEntry? {
        entries.first { $0.actionId == tracker.id && $0.entityId == subject.id }
    }

    func configureServer(_ value: String) throws {
        let validated = try NestCoding.validatedServer(value)
        guard validated != serverURL else { return }
        signOut()
        serverURL = validated
        defaults.set(validated, forKey: "nestic.server.v1")
        errorMessage = nil
    }

    /// Call on launch and when the app returns to the foreground.
    func start() async {
        guard isAuthenticated, !isDemo else { return }
        do { try await refresh() }
        catch { handle(error) }
        connectRealtimeIfNeeded()
    }

    func enterDemo(reset: Bool = false) {
        disconnectRealtime()
        generation = UUID()
        token = nil
        isDemo = true
        errorMessage = nil
        if !reset, let data = defaults.data(forKey: "nestic.demo.v1"),
           let archive = try? NestCoding.decoder().decode(NestArchive.self, from: data) {
            apply(archive)
        } else {
            apply(Self.makeDemo())
            persist()
        }
        restorePredictionPreferences()
        refreshWidget()
        connectionStatus = "Demo · on this device"
    }

    func signIn(email: String, password: String) async throws {
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard email.contains("@"), !password.isEmpty else {
            throw NesticError.message("Enter your email and password.")
        }
        beginLoading()
        defer { endLoading() }
        let requestGeneration = generation
        let api = NestAPI(baseURL: serverURL, token: nil, session: session)
        let credentials = Data("\(email):\(password)".utf8).base64EncodedString()
        struct Response: Decodable { let token: String }
        let data = try await api.data(path: "auth/login", method: "POST", authorization: "Basic \(credentials)")
        let response = try NestCoding.decoder().decode(Response.self, from: data)
        try checkGeneration(requestGeneration)
        try await acceptSession(response.token)
    }

    func register(name: String, email: String, password: String) async throws {
        let name = try nonempty(name, label: "Your name")
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard email.contains("@"), password.count >= 8 else {
            throw NesticError.message("Use a valid email and a password with at least 8 characters.")
        }
        beginLoading()
        defer { endLoading() }
        let requestGeneration = generation
        struct Request: Encodable { let email: String; let password: String; let displayName: String }
        struct Response: Decodable { let token: String }
        let response: Response = try await NestAPI(baseURL: serverURL, token: nil, session: session)
            .post("auth/register", body: Request(email: email, password: password, displayName: name))
        try checkGeneration(requestGeneration)
        try await acceptSession(response.token)
    }

    func signOut() {
        if !isDemo {
            defaults.set(true, forKey: "nestic.signedOut.\(NestCoding.serverKey(serverURL))")
            do { try keychain.delete(server: serverURL) }
            catch { errorMessage = error.localizedDescription }
        }
        disconnectRealtime()
        generation = UUID()
        token = nil
        currentUser = nil
        isDemo = false
        nests = []
        selectedNestID = nil
        snapshots = [:]
        predictionPreferences = [:]
        applySnapshot(NestSnapshot())
        NesticWidgetBridge.clear()
        connectionStatus = "Not connected"
    }

    func refresh() async throws {
        guard !isDemo, let token, currentUser != nil else { return }
        beginLoading()
        defer { endLoading() }
        let requestGeneration = generation
        refreshSequence += 1
        let sequence = refreshSequence
        let api = NestAPI(baseURL: serverURL, token: token, session: session)
        do {
            let remoteNests: [NestSpace] = try await api.get("nests")
            try checkGeneration(requestGeneration)
            guard sequence == refreshSequence else { return }
            let nestID = remoteNests.first { $0.id == selectedNestID }?.id ?? remoteNests.first?.id
            let snapshot: NestSnapshot
            if let nestID { snapshot = try await loadSnapshot(nestID: nestID, api: api) }
            else { snapshot = NestSnapshot() }
            try checkGeneration(requestGeneration)
            guard sequence == refreshSequence else { return }
            nests = remoteNests
            selectedNestID = nestID
            snapshots = snapshots.filter { key, _ in remoteNests.contains { $0.id.uuidString == key } }
            applySnapshot(snapshot)
            persist()
            errorMessage = nil
            if selectedNestID == nil { connectionStatus = "Connected" }
            connectRealtimeIfNeeded()
        } catch {
            guard requestGeneration == generation else { throw NesticError.staleSession }
            handle(error)
            throw error
        }
    }

    func selectNest(_ nest: NestSpace) async throws {
        guard nests.contains(where: { $0.id == nest.id }) else { throw NesticError.message("That nest is no longer available.") }
        guard nest.id != selectedNestID else { return }
        persist()
        generation = UUID()
        disconnectRealtime()
        selectedNestID = nest.id
        applySnapshot(snapshots[nest.id.uuidString] ?? NestSnapshot())
        persist()
        if !isDemo { try await refresh() }
    }

    func createNest(name: String) async throws {
        let name = try nonempty(name, label: "Nest name")
        guard let user = currentUser else { throw NesticError.unauthorized }
        let nest: NestSpace
        if isDemo { nest = NestSpace(id: UUID(), name: name) }
        else {
            let requestGeneration = generation
            struct Request: Encodable { let name: String }
            nest = try await api().post("nests", body: Request(name: name))
            try checkGeneration(requestGeneration)
        }
        persist()
        disconnectRealtime()
        generation = UUID()
        nests.append(nest)
        selectedNestID = nest.id
        var owner = user
        owner.role = "owner"
        applySnapshot(NestSnapshot(members: [owner]))
        persist()
        await refreshAfterMutation()
    }

    func addMember(email: String) async throws {
        let nestID = try requireNest()
        guard canManageNest else { throw NesticError.message("Only a nest owner or admin can add people.") }
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard email.contains("@"), email.contains(".") else { throw NesticError.message("Enter a valid email address.") }
        guard !members.contains(where: { $0.email.lowercased() == email }) else {
            throw NesticError.message("That person is already in your nest.")
        }
        let person: NestPerson
        if isDemo {
            person = .init(id: UUID(), email: email, displayName: email.components(separatedBy: "@")[0].capitalized, role: "member")
        } else {
            let requestGeneration = generation
            struct Request: Encodable { let email: String; let role = "member" }
            let response: NestMemberResponse = try await api().post("nests/\(nestID)/members", body: Request(email: email))
            try checkGeneration(requestGeneration)
            person = response.person()
        }
        members.append(person)
        persist()
        await refreshAfterMutation()
    }

    func createSubject(name: String, kind: NestSubjectKind, emoji: String, trackerTemplates: [NestTrackerTemplate]) async throws {
        let nestID = try requireNest()
        guard canLog else { throw NesticError.message("You have view-only access to this nest.") }
        let name = try nonempty(name, label: "Name")
        let emoji = emoji.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? kind.emoji : String(emoji.prefix(4))
        var subject: NestSubject
        let requestGeneration = generation
        if isDemo {
            subject = .init(id: UUID(), nestId: nestID, name: name, kind: kind, emoji: emoji)
        } else {
            struct Request: Encodable { let kind: NestSubjectKind; let name: String; let metadata: [String: String] }
            let response: NestEntityResponse = try await api().post("nests/\(nestID)/entities", body: Request(kind: kind, name: name, metadata: ["emoji": emoji]))
            try checkGeneration(requestGeneration)
            subject = response.subject()
        }
        subjects.append(subject)
        persist()
        do {
            for template in trackerTemplates {
                let tracker = try await makeTracker(name: template.name, valueType: template.valueType, unit: template.unit)
                try checkGeneration(requestGeneration)
                if !subject.pinnedActionIDs.contains(tracker.id) { subject.pinnedActionIDs.append(tracker.id) }
            }
            if !isDemo { try await savePins(subject) }
            try checkGeneration(requestGeneration)
            if let index = subjects.firstIndex(where: { $0.id == subject.id }) { subjects[index] = subject }
            persist()
            await refreshAfterMutation()
        } catch {
            await refreshAfterMutation()
            throw NesticError.message("\(name) was created, but some trackers couldn’t be added. Open \(name) to add a tracker. \(error.localizedDescription)")
        }
    }

    func createTracker(subjectID: UUID, name: String, valueType: NestValueType, unit: String? = nil) async throws {
        guard var subject = subjects.first(where: { $0.id == subjectID }) else { throw NesticError.message("This item no longer exists.") }
        guard canManageNest else { throw NesticError.message("Only a nest owner or admin can create trackers.") }
        let requestGeneration = generation
        let tracker = try await makeTracker(name: name, valueType: valueType, unit: unit)
        try checkGeneration(requestGeneration)
        guard !subject.pinnedActionIDs.contains(tracker.id) else { throw NesticError.message("This tracker is already on \(subject.name).") }
        subject.pinnedActionIDs.append(tracker.id)
        if !isDemo { try await savePins(subject) }
        try checkGeneration(requestGeneration)
        if let index = subjects.firstIndex(where: { $0.id == subject.id }) { subjects[index] = subject }
        persist()
        await refreshAfterMutation()
    }

    func updateTracker(_ tracker: NestTracker, name: String, valueType: NestValueType, unit: String? = nil) async throws {
        guard trackers.contains(where: { $0.id == tracker.id }) else { throw NesticError.message("This tracker no longer exists.") }
        guard canManageNest else { throw NesticError.message("Only a nest owner or admin can edit trackers.") }
        let cleanName = try nonempty(name, label: "Tracker name")
        let cleanUnit = valueType == .number ? unit?.trimmingCharacters(in: .whitespacesAndNewlines) : nil
        let updated: NestTracker
        if isDemo {
            updated = NestTracker(id: tracker.id, nestId: tracker.nestId, name: cleanName, valueType: valueType,
                                  unit: cleanUnit?.isEmpty == true ? nil : cleanUnit)
        } else {
            struct Request: Encodable { let name: String; let valueType: NestValueType; let unit: String? }
            updated = try await api().patch("actions/\(tracker.id)", body: Request(name: cleanName, valueType: valueType,
                                                                                        unit: cleanUnit?.isEmpty == true ? nil : cleanUnit))
        }
        if let index = trackers.firstIndex(where: { $0.id == tracker.id }) { trackers[index] = updated }
        persist()
        await refreshAfterMutation()
    }

    func deleteTracker(_ tracker: NestTracker) async throws {
        guard trackers.contains(where: { $0.id == tracker.id }) else { return }
        guard canManageNest else { throw NesticError.message("Only a nest owner or admin can delete trackers.") }
        if !isDemo { _ = try await api().data(path: "actions/\(tracker.id)", method: "DELETE") }
        trackers.removeAll { $0.id == tracker.id }
        entries.removeAll { $0.actionId == tracker.id }
        subjects = subjects.map { subject in
            var copy = subject
            copy.pinnedActionIDs.removeAll { $0 == tracker.id }
            return copy
        }
        persist()
        await refreshAfterMutation()
    }

    func log(subjectID: UUID, trackerID: UUID, date: Date = Date(), number: Double? = nil, text: String? = nil, bool: Bool? = nil, json: [String: String]? = nil, note: String? = nil) async throws {
        let nestID = try requireNest()
        guard canLog else { throw NesticError.message("You have view-only access to this nest.") }
        guard let subject = subjects.first(where: { $0.id == subjectID }),
              subject.pinnedActionIDs.contains(trackerID),
              let tracker = trackers.first(where: { $0.id == trackerID }) else {
            throw NesticError.message("This tracker is no longer available. Refresh your nest and try again.")
        }
        try Self.validateValue(type: tracker.valueType, number: number, text: text, bool: bool, json: json)
        guard date <= Date().addingTimeInterval(60) else { throw NesticError.message("Choose a time in the present or past.") }
        let cleanedText = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        var entry = NestEntry(id: UUID(), nestId: nestID, entityId: subjectID, actionId: trackerID, actorUserId: currentUser?.id, occurredAt: date,
                              valueNumber: number, valueText: cleanedText, valueBool: bool, valueJSON: json,
                              note: cleanedNote?.isEmpty == true ? nil : cleanedNote)
        if !isDemo {
            let requestGeneration = generation
            struct Request: Encodable {
                let actionID: UUID; let occurredAt: Date; let valueNumber: Double?
                let valueText: String?; let valueBool: Bool?; let valueJSON: [String: String]?; let note: String?
            }
            entry = try await api().post("entities/\(subjectID)/events", body: Request(actionID: trackerID, occurredAt: date, valueNumber: number, valueText: cleanedText, valueBool: bool, valueJSON: json, note: entry.note))
            try checkGeneration(requestGeneration)
        }
        entries.removeAll { $0.id == entry.id }
        entries.append(entry)
        entries.sort { $0.occurredAt > $1.occurredAt }
        persist()
        await refreshAfterMutation()
    }

    func deleteEntry(_ entry: NestEntry) async throws {
        guard entry.nestId == selectedNestID else { throw NesticError.staleSession }
        guard canManageNest || (canLog && entry.actorUserId == currentUser?.id) else {
            throw NesticError.message("You can remove your own updates. A nest owner or admin can remove other updates.")
        }
        if !isDemo {
            let requestGeneration = generation
            _ = try await api().data(path: "events/\(entry.id)", method: "DELETE")
            try checkGeneration(requestGeneration)
        }
        entries.removeAll { $0.id == entry.id }
        persist()
        await refreshAfterMutation()
    }

    static func validateValue(type: NestValueType, number: Double?, text: String?, bool: Bool?, json: [String: String]?) throws {
        let supplied = [number != nil, text != nil, bool != nil, json != nil].filter { $0 }.count
        switch type {
        case .none:
            guard supplied == 0 else { throw NesticError.message("This tracker records an update without a value.") }
        case .number:
            guard supplied == 1, let number, number.isFinite else { throw NesticError.message("Enter a valid number.") }
        case .text:
            guard supplied == 1, let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw NesticError.message("Add a few words for this update.") }
        case .boolean:
            guard supplied == 1, bool != nil else { throw NesticError.message("Choose yes or no.") }
        case .json:
            guard supplied == 1, let json, !json.isEmpty, json.keys.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { throw NesticError.message("Add at least one named detail.") }
        }
    }

    private func acceptSession(_ value: String) async throws {
        let requestGeneration = generation
        let user: NestPerson = try await NestAPI(baseURL: serverURL, token: value, session: session).get("auth/me")
        try checkGeneration(requestGeneration)
        try keychain.save(NestSession(token: value, user: user), server: serverURL)
        disconnectRealtime()
        generation = UUID()
        token = value
        currentUser = user
        isDemo = false
        nests = []
        selectedNestID = nil
        snapshots = [:]
        applySnapshot(NestSnapshot())
        predictionPreferences = [:]
        defaults.set(false, forKey: "nestic.signedOut.\(NestCoding.serverKey(serverURL))")
        restoreArchive()
        restorePredictionPreferences()
        errorMessage = nil
        await start()
    }

    private func loadSnapshot(nestID: UUID, api: NestAPI) async throws -> NestSnapshot {
        async let remoteSubjects: [NestEntityResponse] = api.get("nests/\(nestID)/entities")
        async let remoteTrackers: [NestTracker] = api.get("nests/\(nestID)/actions")
        async let remoteEntries: [NestEntry] = api.get("nests/\(nestID)/events?limit=200")
        async let remoteMembers: [NestMemberResponse] = api.get("nests/\(nestID)/members")
        let (entities, actions, events, people) = try await (remoteSubjects, remoteTrackers, remoteEntries, remoteMembers)
        var subjects: [NestSubject] = []
        for entity in entities {
            let pins: [NestPinResponse] = try await api.get("entities/\(entity.id)/pinned-actions")
            subjects.append(entity.subject(pins: pins.map(\.actionId)))
        }
        return NestSnapshot(subjects: subjects, trackers: actions, entries: events.sorted { $0.occurredAt > $1.occurredAt }, members: people.map { $0.person() })
    }

    private func makeTracker(name: String, valueType: NestValueType, unit: String?) async throws -> NestTracker {
        let nestID = try requireNest()
        let name = try nonempty(name, label: "Tracker name")
        let trimmed = unit?.trimmingCharacters(in: .whitespacesAndNewlines)
        let unit = valueType == .number && trimmed?.isEmpty == false ? trimmed : nil
        if let existing = trackers.first(where: { $0.name.lowercased() == name.lowercased() && $0.valueType == valueType && $0.unit == unit }) { return existing }
        guard canManageNest else { throw NesticError.message("Only a nest owner or admin can create trackers.") }
        let tracker: NestTracker
        if isDemo { tracker = .init(id: UUID(), nestId: nestID, name: name, valueType: valueType, unit: unit) }
        else {
            let requestGeneration = generation
            struct Request: Encodable { let name: String; let valueType: NestValueType; let unit: String? }
            tracker = try await api().post("nests/\(nestID)/actions", body: Request(name: name, valueType: valueType, unit: unit))
            try checkGeneration(requestGeneration)
        }
        if !trackers.contains(where: { $0.id == tracker.id }) { trackers.append(tracker) }
        return tracker
    }

    private func savePins(_ subject: NestSubject) async throws {
        struct Request: Encodable { let actionIds: [UUID] }
        let body = try NestCoding.encoder().encode(Request(actionIds: subject.pinnedActionIDs))
        _ = try await api().data(path: "entities/\(subject.id)/pinned-actions", method: "PUT", body: body)
    }

    private func api() throws -> NestAPI {
        guard let token, currentUser != nil else { throw NesticError.unauthorized }
        return NestAPI(baseURL: serverURL, token: token, session: session)
    }

    private func requireNest() throws -> UUID {
        guard let selectedNestID, currentUser != nil else { throw NesticError.message("Create or choose a nest first.") }
        return selectedNestID
    }

    private func nonempty(_ value: String, label: String) throws -> String {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw NesticError.message("\(label) can’t be empty.") }
        guard value.count <= 100 else { throw NesticError.message("Keep \(label.lowercased()) under 100 characters.") }
        return value
    }

    private func checkGeneration(_ value: UUID) throws {
        guard generation == value else { throw NesticError.staleSession }
    }

    private func beginLoading() { loadingCount += 1; isLoading = true }
    private func endLoading() { loadingCount = max(0, loadingCount - 1); isLoading = loadingCount > 0 }

    private func handle(_ error: Error) {
        if error is CancellationError { return }
        if case NesticError.staleSession = error { return }
        if case NesticError.unauthorized = error {
            signOut()
        } else if !isDemo {
            connectionStatus = "Offline · saved updates"
        }
        errorMessage = error.localizedDescription
    }

    private func refreshAfterMutation() async {
        guard !isDemo else { return }
        // The mutation already succeeded. A failed catch-up must not ask the user to submit it twice.
        do { try await refresh() }
        catch { handle(error) }
    }

    private var archiveKey: String? {
        if isDemo { return "nestic.demo.v1" }
        guard let currentUser else { return nil }
        return "nestic.cache.v1.\(NestCoding.serverKey(serverURL)).\(currentUser.id.uuidString)"
    }

    private func persist() {
        guard let currentUser, let archiveKey else { return }
        if let selectedNestID {
            snapshots[selectedNestID.uuidString] = NestSnapshot(subjects: subjects, trackers: trackers, entries: entries, members: members)
        }
        let archive = NestArchive(user: currentUser, nests: nests, selectedNestID: selectedNestID, snapshots: snapshots)
        do { defaults.set(try NestCoding.encoder().encode(archive), forKey: archiveKey) }
        catch { errorMessage = "Couldn’t save updates on this device. \(error.localizedDescription)" }
        persistPredictionPreferences()
        refreshWidget()
    }

    private var predictionPreferencesKey: String {
        if isDemo { return "nestic.predictions.demo.v1" }
        guard let currentUser else { return "nestic.predictions.anonymous.v1" }
        return "nestic.predictions.\(NestCoding.serverKey(serverURL)).\(currentUser.id.uuidString).v1"
    }

    private func persistPredictionPreferences() {
        guard let data = try? NestCoding.encoder().encode(predictionPreferences) else { return }
        defaults.set(data, forKey: predictionPreferencesKey)
    }

    private func restorePredictionPreferences() {
        guard let data = defaults.data(forKey: predictionPreferencesKey),
              let preferences = try? NestCoding.decoder().decode([UUID: NestPredictionPreferences].self, from: data) else { return }
        predictionPreferences = preferences
    }

    private func refreshWidget() {
        guard let subject = subjects.first(where: { $0.kind == .pet }) ?? subjects.first else {
            NesticWidgetBridge.clear()
            return
        }
        NesticWidgetBridge.refresh(subject: subject, trackers: trackers(for: subject), entries: entries,
                                   prediction: bathroomPrediction(for: subject))
    }

    func handleDeepLink(_ url: URL) async {
        guard url.scheme == "nestic", url.host == "log",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let subjectValue = components.queryItems?.first(where: { $0.name == "subjectID" })?.value,
              let trackerValue = components.queryItems?.first(where: { $0.name == "trackerID" })?.value,
              let subjectID = UUID(uuidString: subjectValue), let trackerID = UUID(uuidString: trackerValue) else { return }
        do { try await log(subjectID: subjectID, trackerID: trackerID) }
        catch { errorMessage = error.localizedDescription }
    }

    private func restoreArchive() {
        guard let archiveKey, let data = defaults.data(forKey: archiveKey),
              let archive = try? NestCoding.decoder().decode(NestArchive.self, from: data),
              archive.user.id == currentUser?.id else { return }
        apply(archive)
    }

    private func apply(_ archive: NestArchive) {
        currentUser = archive.user
        nests = archive.nests
        selectedNestID = archive.nests.first { $0.id == archive.selectedNestID }?.id ?? archive.nests.first?.id
        snapshots = archive.snapshots
        applySnapshot(selectedNestID.flatMap { snapshots[$0.uuidString] } ?? NestSnapshot())
    }

    private func applySnapshot(_ snapshot: NestSnapshot) {
        subjects = snapshot.subjects
        trackers = snapshot.trackers
        entries = snapshot.entries.sorted { $0.occurredAt > $1.occurredAt }
        members = snapshot.members
    }

    private func disconnectRealtime() {
        realtimeTask?.cancel()
        realtimeTask = nil
        heartbeatTask?.cancel()
        heartbeatTask = nil
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        socketNestID = nil
    }

    private func connectRealtimeIfNeeded() {
        guard !isDemo, token != nil, let nestID = selectedNestID else { return }
        guard socketNestID != nestID || realtimeTask == nil else { return }
        disconnectRealtime()
        socketNestID = nestID
        let requestGeneration = generation
        realtimeTask = Task { [weak self] in
            await self?.runRealtime(nestID: nestID, requestGeneration: requestGeneration)
        }
    }

    private func runRealtime(nestID: UUID, requestGeneration: UUID) async {
        var failures = 0
        while !Task.isCancelled, generation == requestGeneration, let token {
            guard var url = URLComponents(string: serverURL + "/ws") else { return }
            url.scheme = url.scheme == "https" ? "wss" : "ws"
            guard let websocketURL = url.url else { return }
            var request = URLRequest(url: websocketURL)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.timeoutInterval = 20
            let socket = session.webSocketTask(with: request)
            self.socket = socket
            connectionStatus = failures == 0 ? "Connecting…" : "Reconnecting…"
            socket.resume()
            heartbeatTask = Task { [weak self, weak socket] in
                while !Task.isCancelled {
                    do {
                        try await Task.sleep(for: .seconds(25))
                        guard let socket else { return }
                        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                            socket.sendPing { error in
                                if let error { continuation.resume(throwing: error) }
                                else { continuation.resume() }
                            }
                        }
                    } catch {
                        guard !Task.isCancelled else { return }
                        self?.connectionStatus = "Reconnecting…"
                        socket?.cancel(with: .goingAway, reason: nil)
                        return
                    }
                }
            }
            do {
                struct Subscribe: Encodable { let type = "subscribe"; let nestId: UUID }
                let subscription = String(decoding: try NestCoding.encoder().encode(Subscribe(nestId: nestID)), as: UTF8.self)
                try await socket.send(.string(subscription))
                while !Task.isCancelled, generation == requestGeneration {
                    let message = try await socket.receive()
                    let data: Data
                    switch message {
                    case .data(let value): data = value
                    case .string(let value): data = Data(value.utf8)
                    @unknown default: continue
                    }
                    struct Envelope: Decodable { var type: String?; var nestId: UUID?; var error: Bool?; var reason: String? }
                    let envelope = try NestCoding.decoder().decode(Envelope.self, from: data)
                    if envelope.error == true { throw NesticError.message(envelope.reason ?? "Live updates could not connect.") }
                    if envelope.type == "ws.ready" { try await socket.send(.string(subscription)); continue }
                    guard envelope.nestId == nestID else { continue }
                    try checkGeneration(requestGeneration)
                    if envelope.type == "ws.subscribed" {
                        failures = 0
                        try await refresh()
                        connectionStatus = "Live · up to date"
                    } else {
                        // Fetching the authoritative snapshot also catches deletes, role changes and reconnect gaps.
                        try await refresh()
                        connectionStatus = "Live · up to date"
                    }
                }
            } catch {
                guard !Task.isCancelled, generation == requestGeneration else { break }
                connectionStatus = "Reconnecting · saved updates"
                if case NesticError.unauthorized = error { handle(error); break }
            }
            heartbeatTask?.cancel()
            socket.cancel(with: .goingAway, reason: nil)
            guard !Task.isCancelled, generation == requestGeneration else { break }
            failures += 1
            do { try await Task.sleep(for: .seconds(min(pow(2, Double(min(failures, 5))), 30))) }
            catch { break }
        }
    }
}
