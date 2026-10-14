import Foundation
import Combine

private struct NestUserSettingsUpdate: Encodable {
    let predictionPreferencesJSON: String?
    let quietHoursJSON: String?
    let remindersJSON: String?
}

private extension NestSharedForecast {
    init(nestId: UUID, subjectId: UUID, trackerId: UUID, prediction: EventPrediction, computedAt: Date) {
        self.init(id: UUID(), nestId: nestId, subjectId: subjectId, trackerId: trackerId,
                  predictedAt: prediction.predictedAt,
                  baselinePredictedAt: prediction.baselinePredictedAt,
                  contextualPredictedAt: prediction.contextualPredictedAt,
                  model: prediction.model.rawValue, intervalHours: prediction.intervalHours,
                  confidence: prediction.confidence, sampleCount: prediction.sampleCount,
                  validationSampleCount: prediction.validationSampleCount,
                  expectedErrorHours: prediction.expectedErrorHours,
                  predictionWindowHours: prediction.predictionWindowHours,
                  targetNames: prediction.targetNames, inputNames: prediction.inputNames,
                  lastEventAt: prediction.lastEventAt, computedAt: computedAt, updatedAt: nil)
    }

    func eventPrediction() -> EventPrediction {
        EventPrediction(targetTrackerID: trackerId, predictedAt: predictedAt,
                        baselinePredictedAt: baselinePredictedAt,
                        contextualPredictedAt: contextualPredictedAt,
                        model: ForecastModelKind(rawValue: model) ?? .baseline,
                        intervalHours: intervalHours, confidence: confidence,
                        sampleCount: sampleCount, validationSampleCount: validationSampleCount,
                        expectedErrorHours: expectedErrorHours,
                        predictionWindowHours: predictionWindowHours,
                        targetNames: targetNames, inputNames: inputNames,
                        lastEventAt: lastEventAt,
                        explanation: "Shared forecast for this nest")
    }
}

enum NesticNavigationDestination: Equatable, Sendable {
    case subject(UUID)
    case insights(UUID)
    case record(subjectID: UUID, trackerID: UUID)
}

@MainActor
final class NesticStore: ObservableObject {
    @Published private(set) var currentUser: NestPerson?
    @Published private(set) var isDemo = false { didSet { invalidatePredictionCache() } }
    @Published private(set) var nests: [NestSpace] = []
    @Published private(set) var selectedNestID: UUID? { didSet { invalidatePredictionCache() } }
    @Published private(set) var subjects: [NestSubject] = [] { didSet { invalidatePredictionCache(); subjectLookupCache = nil } }
    @Published private(set) var allTrackers: [NestTracker] = [] { didSet { invalidatePredictionCache(); trackerLookupCache = nil } }
    @Published private(set) var entries: [NestEntry] = [] { didSet { invalidatePredictionCache(); subjectEntryCache = nil } }
    @Published private(set) var members: [NestPerson] = []
    @Published private(set) var routines: [NestRoutine] = []
    @Published private(set) var predictionPreferences: [UUID: NestPredictionPreferences] = [:] { didSet { invalidatePredictionCache() } }
    @Published private(set) var sharedForecasts: [NestSharedForecast] = []
    @Published private(set) var quietHoursPreferences = NestQuietHoursPreferences() { didSet { invalidatePredictionCache() } }
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMoreEntries = false
    @Published private(set) var hasMoreEntries = false
    @Published var errorMessage: String?
    @Published var accountDeletionNotice: String?
    @Published private(set) var pendingNavigation: NesticNavigationDestination?
    @Published private(set) var connectionStatus = "Not connected"
    @Published private(set) var serverURL: String
    @Published private(set) var careLinks: [NestCareLink] = []
    @Published private(set) var careLinkSession: NestCareSession?
    @Published var careLinkError: String?
    @Published private(set) var feedbackThreads: [NestFeedbackThread] = []

    var selectedNest: NestSpace? { nests.first { $0.id == selectedNestID } }
    var isAuthenticated: Bool { currentUser != nil }
    var isNestOwner: Bool {
        isDemo || members.contains { $0.id == currentUser?.id && $0.role == "owner" }
    }
    var canManageNest: Bool {
        isDemo || members.contains { $0.id == currentUser?.id && ["owner", "admin"].contains($0.role ?? "") }
    }
    var canLog: Bool {
        isDemo || members.contains { $0.id == currentUser?.id && $0.role != "viewer" }
    }
    /// Routines are a Pro quality-of-life feature. Individual tracker logging
    /// remains available to every signed-in member.
    var hasRoutineAccess: Bool { isDemo || predictionAccess }
    /// Forecasts and the controls that change forecast behavior are a Pro
    /// feature. Keep this separate from routines so the free core stays useful.
    var hasForecastAccess: Bool { isDemo || predictionAccess }

    private let defaults: UserDefaults
    private let session: URLSession
    private let reminderStore: NesticReminderStore?
    private let keychain = NestKeychain()
    private var token: String?
    private var snapshots: [String: NestSnapshot] = [:]
    private var generation = UUID()
    private var refreshSequence = 0
    private var refreshTask: Task<Void, Error>?
    private var lastSuccessfulRefreshAt: Date?
    private var loadingCount = 0
    private var socket: URLSessionWebSocketTask?
    private var socketNestID: UUID?
    private var realtimeTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var realtimeRefreshTask: Task<Void, Never>?
    private var realtimeRefreshRequested = false
    private var realtimeRetryNotBefore: Date?
    private var appIsActive = false
    // Prediction output is intentionally kept out of the widget and the
    // model until StoreKit has confirmed the subscription. Demo mode is the
    // only local preview exception.
    private var predictionAccess = false
    private var forecastSnapshots: [ForecastSnapshot] = [] {
        didSet {
            // Capturing an unscored forecast does not change the model. Only
            // actual scored outcomes affect model selection and confidence.
            if oldValue.filter({ $0.actualEventAt != nil }) != forecastSnapshots.filter({ $0.actualEventAt != nil }) {
                invalidatePredictionCache()
            }
        }
    }
    private var settingsRevision = 0
    private var settingsSyncTask: Task<Void, Never>?
    private var forecastSyncTask: Task<Void, Never>?
    private var lastPublishedForecastSignature: String?

    private struct CachedLocalForecast {
        let subject: NestSubject
        let minute: Int
        let calendar: Calendar
        let predictions: [EventPrediction]
    }
    private var localForecastCache: [UUID: CachedLocalForecast] = [:]
    private var subjectEntryCache: [UUID: [NestEntry]]?
    private var subjectLookupCache: [UUID: NestSubject]?
    private var trackerLookupCache: [UUID: NestTracker]?

    private func invalidatePredictionCache() {
        localForecastCache.removeAll(keepingCapacity: true)
    }

    func subject(id: UUID) -> NestSubject? {
        if subjectLookupCache == nil {
            subjectLookupCache = Dictionary(subjects.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
        }
        return subjectLookupCache?[id]
    }

    var trackers: [NestTracker] { allTrackers.filter { $0.isArchived != true } }

    func tracker(id: UUID) -> NestTracker? {
        if trackerLookupCache == nil {
            trackerLookupCache = Dictionary(allTrackers.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
        }
        return trackerLookupCache?[id]
    }


    init(defaults: UserDefaults = .standard, session: URLSession = .shared, restoreSession: Bool = true,
         reminderStore: NesticReminderStore? = nil) {
        self.defaults = defaults
        self.session = session
        self.reminderStore = reminderStore
        let bundledServerURL = Bundle.main.object(forInfoDictionaryKey: "NesticServerURL") as? String
        #if DEBUG
        let savedServerURL = defaults.string(forKey: "nestic.server.v1")
        #else
        let savedServerURL: String? = nil
        #endif
        self.serverURL = savedServerURL ?? bundledServerURL ?? NesticAppLinks.apiBaseURL
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
        restoreForecastSnapshots()
        reconcileForecastSnapshots()
        // Clear any stale prediction payload from a previous entitlement
        // before StoreKit finishes restoring the current subscription.
        refreshWidget()
    }

    func trackers(for subject: NestSubject) -> [NestTracker] {
        let currentSubject = self.subject(id: subject.id) ?? subject
        return currentSubject.pinnedActionIDs.compactMap { tracker(id: $0) }.filter { $0.isArchived != true }
    }

    func historicalTrackers(for subject: NestSubject) -> [NestTracker] {
        let ids = Set(entries(for: subject).map(\.actionId)).union(subject.pinnedActionIDs)
        return allTrackers.filter { ids.contains($0.id) }
    }

    func routines(for subject: NestSubject) -> [NestRoutine] {
        routines.filter { $0.targets.contains { $0.entityID == subject.id } }
    }

    func preferences(for subject: NestSubject) -> NestPredictionPreferences {
        let subjectTrackers = trackers(for: subject)
        let targetIDs = EventPredictionEngine.inferredTargetIDs(trackers: subjectTrackers)
        return predictionPreferences[subject.id] ?? .init(
            inputTrackerIDs: EventPredictionEngine.defaultInputIDs(trackers: subjectTrackers, targetIDs: targetIDs),
            targetTrackerIDs: targetIDs
        )
    }

    /// Every selected tracker receives its own forecast. Target trackers are
    /// outcomes to predict, never context signals for one another.
    func predictionTargetIDs(for subject: NestSubject) -> [UUID] {
        let subjectTrackers = trackers(for: subject)
        let preferences = preferences(for: subject)
        let selectedIDs = preferences.targetTrackerIDs.isEmpty
            ? EventPredictionEngine.inferredTargetIDs(trackers: subjectTrackers)
            : preferences.targetTrackerIDs
        let selectedSet = Set(selectedIDs)
        return subjectTrackers.map(\.id).filter { selectedSet.contains($0) }
    }

    func predictions(for subject: NestSubject, now: Date = Date()) -> [EventPrediction] {
        guard isDemo || predictionAccess else { return [] }
        let local = localPredictions(for: subject, now: now)
        let profilePreferences = preferences(for: subject)
        guard !isDemo, !sharedForecasts.isEmpty, !profilePreferences.includeAge, !profilePreferences.includeWeight else { return local }

        let subjectTrackerIDs = Set(trackers(for: subject).map(\.id))
        let sharedTargetIDs = sharedForecasts
            .filter { $0.subjectId == subject.id && subjectTrackerIDs.contains($0.trackerId) }
            .map(\.trackerId)
        let latestByTracker = Dictionary(uniqueKeysWithValues: sharedTargetIDs.compactMap { trackerID -> (UUID, Date)? in
            guard let latest = entries.first(where: {
                $0.entityId == subject.id && $0.actionId == trackerID && $0.shouldIncludeInPredictions
            }) else { return nil }
            return (trackerID, latest.occurredAt)
        })
        let remoteByTracker = Dictionary(uniqueKeysWithValues: sharedForecasts.compactMap { forecast -> (UUID, EventPrediction)? in
            guard !forecast.inputNames.contains("Subject age"), !forecast.inputNames.contains("Subject weight"), forecast.subjectId == subject.id,
                  let latestEventAt = latestByTracker[forecast.trackerId],
                  abs(latestEventAt.timeIntervalSince(forecast.lastEventAt)) < 1 else { return nil }
            return (forecast.trackerId, forecast.eventPrediction())
        })
        guard !remoteByTracker.isEmpty else { return local }
        let localByTracker = Dictionary(uniqueKeysWithValues: local.compactMap { prediction -> (UUID, EventPrediction)? in
            guard let trackerID = prediction.targetTrackerID else { return nil }
            return (trackerID, prediction)
        })
        let targetIDs = Set(predictionTargetIDs(for: subject)).union(remoteByTracker.keys)
        return targetIDs.compactMap { trackerID in
            remoteByTracker[trackerID] ?? localByTracker[trackerID]
        }.sorted { $0.predictedAt < $1.predictedAt }
    }

    private func localPredictions(for subject: NestSubject, now: Date) -> [EventPrediction] {
        let minute = Int(floor(now.timeIntervalSince1970 / 60))
        let calendar = Calendar.current
        if let cached = localForecastCache[subject.id], cached.subject == subject,
           cached.minute == minute, cached.calendar == calendar {
            return cached.predictions
        }
        let subjectTrackers = trackers(for: subject)
        let preferences = preferences(for: subject)
        let result = predictionTargetIDs(for: subject).compactMap { targetID in
            EventPredictionEngine.predict(
                subject: subject,
                trackers: subjectTrackers.filter { source in subjectTrackers.first { $0.id == targetID }.map { source.canContribute(to: $0) } ?? false },
                entries: entries(for: subject).filter { entry in subjectTrackers.contains { source in source.id == entry.actionId && (subjectTrackers.first { $0.id == targetID }.map { source.canContribute(to: $0) } ?? false) } },
                preferences: preferences,
                targetTrackerIDs: [targetID],
                feedback: forecastSnapshots,
                now: now
            )
        }
        .map { prediction in
            var deferred = prediction
            deferred.predictedAt = quietHoursPreferences.nextForecastDate(
                predictedAt: prediction.predictedAt,
                confidence: prediction.confidence,
                intervalHours: prediction.intervalHours,
                calendar: .current
            )
            return deferred
        }
        .sorted { $0.predictedAt < $1.predictedAt }
        localForecastCache[subject.id] = CachedLocalForecast(subject: subject, minute: minute,
                                                           calendar: calendar, predictions: result)
        return result
    }

    func prediction(for subject: NestSubject, now: Date = Date()) -> EventPrediction? {
        predictions(for: subject, now: now).first
    }

    func bathroomPrediction(for subject: NestSubject, now: Date = Date()) -> EventPrediction? {
        prediction(for: subject, now: now)
    }

    /// Captures the current forecast locally so a later real update can score
    /// it. Repeated renders do not create duplicate snapshots for the same
    /// target history, which keeps the ledger small and meaningful.
    func recordForecasts(for subject: NestSubject, now: Date = Date()) {
        guard isDemo || predictionAccess else { return }
        let currentPredictions = predictions(for: subject, now: now)
        let changed = captureForecasts(for: subject, predictions: currentPredictions, now: now)
        guard changed else { return }
        persistForecastSnapshots()
    }

    func setPredictionAccess(_ allowed: Bool) {
        let updated = allowed || isDemo
        guard predictionAccess != updated else { return }
        predictionAccess = updated
        refreshWidget()
    }

    func updatePredictionPreferences(for subject: NestSubject, inputTrackerIDs: [UUID], targetTrackerIDs: [UUID], includeAge: Bool = false, includeWeight: Bool = false) {
        predictionPreferences[subject.id] = NestPredictionPreferences(inputTrackerIDs: inputTrackerIDs,
                                                                       targetTrackerIDs: targetTrackerIDs, includeAge: includeAge, includeWeight: includeWeight)
        localForecastCache.removeValue(forKey: subject.id)
        sharedForecasts.removeAll { $0.subjectId == subject.id }
        persistPredictionPreferences()
        markSettingsChanged()
        refreshWidget()
    }

    func updateQuietHours(periods: [NestQuietHoursPeriod], confidenceThresholdPercent: Int) {
        quietHoursPreferences = NestQuietHoursPreferences(periods: periods,
                                                          confidenceThresholdPercent: confidenceThresholdPercent)
        persistQuietHoursPreferences()
        markSettingsChanged()
        refreshWidget()
    }

    /// Publishes only local results that are newer than the shared nest copy.
    /// The server resolves concurrent writers by shared event time, so a
    /// delayed member cannot roll the nest back to an older forecast.
    private func scheduleSharedForecastSync(_ forecasts: [NestSharedForecast]) {
        guard !isDemo, predictionAccess, let nestID = selectedNestID, !forecasts.isEmpty else { return }
        let pending = forecasts.filter { $0.nestId == nestID }.filter { forecast in
            guard let shared = sharedForecasts.first(where: {
                $0.subjectId == forecast.subjectId && $0.trackerId == forecast.trackerId
            }) else { return true }
            return forecast.lastEventAt > shared.lastEventAt
        }
        guard !pending.isEmpty else { return }

        let signature = pending.sorted { $0.trackerId.uuidString < $1.trackerId.uuidString }
            .map { "\($0.subjectId.uuidString)|\($0.trackerId.uuidString)|\($0.lastEventAt.timeIntervalSince1970)|\($0.predictedAt.timeIntervalSince1970)" }
            .joined(separator: ";")
        guard signature != lastPublishedForecastSignature else { return }
        lastPublishedForecastSignature = signature
        forecastSyncTask?.cancel()
        forecastSyncTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled, let self else { return }
                let body = pending.map { forecast in
                    let target = self.trackers.first { $0.id == forecast.trackerId }
                    let ids = self.trackers.filter { source in forecast.inputNames.contains(source.name) && (target.map { source.canContribute(to: $0) } ?? false) }.map(\.id)
                    return NestSharedForecastUpsert(forecast, inputTrackerIDs: ids)
                }
                let shared: [NestSharedForecast] = try await self.api().put(
                    "nests/\(nestID)/forecasts", body: body)
                guard !Task.isCancelled else { return }
                self.sharedForecasts = shared
                self.refreshWidget()
            } catch {
                // Keep the local forecast usable and retry publication after a
                // later foreground refresh or new shared event.
                self?.lastPublishedForecastSignature = nil
            }
            self?.forecastSyncTask = nil
        }
    }

    /// Marks the local settings as needing a server write. The write is
    /// best-effort so a temporary outage never prevents local changes.
    func markSettingsChanged() {
        guard !isDemo, currentUser != nil, selectedNestID != nil else { return }
        settingsRevision += 1
        defaults.set(true, forKey: settingsDirtyKey)
        scheduleSettingsSync()
    }

    private func scheduleSettingsSync() {
        guard settingsSyncTask == nil else { return }
        settingsSyncTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                let revision = self.settingsRevision
                await self.syncSettingsToServer()
                if revision == self.settingsRevision { break }
            }
            self.settingsSyncTask = nil
        }
    }

    private func syncSettingsToServer() async {
        guard !isDemo, let nestID = selectedNestID, currentUser != nil else { return }
        let revision = settingsRevision
        let scopedPreferences: [UUID: NestPredictionPreferences]
        if subjects.isEmpty {
            // Avoid replacing a server payload with an empty dictionary while
            // the first snapshot is still loading.
            scopedPreferences = predictionPreferences
        } else {
            let subjectIDs = Set(subjects.filter { $0.nestId == nestID }.map(\.id))
            scopedPreferences = predictionPreferences.filter { subjectIDs.contains($0.key) }
        }
        let request = NestUserSettingsUpdate(
            predictionPreferencesJSON: settingsJSON(scopedPreferences),
            quietHoursJSON: settingsJSON(quietHoursPreferences),
            remindersJSON: reminderStore.flatMap { settingsJSON($0.remindersForSync(nestID: nestID)) }
        )
        do {
            _ = try await api().put("nests/\(nestID)/settings", body: request, as: NestUserSettingsResponse.self)
            if revision == settingsRevision {
                defaults.removeObject(forKey: settingsDirtyKey)
            }
        } catch {
            // Keep the dirty marker so the next successful refresh retries it.
        }
    }

    func entries(for subject: NestSubject) -> [NestEntry] {
        if subjectEntryCache == nil {
            subjectEntryCache = Dictionary(grouping: entries.sorted { $0.occurredAt > $1.occurredAt }, by: \.entityId)
        }
        return subjectEntryCache?[subject.id] ?? []
    }

    func latestEntry(for tracker: NestTracker, subject: NestSubject) -> NestEntry? {
        entries(for: subject).first { $0.actionId == tracker.id }
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
        appIsActive = true
        realtimeRetryNotBefore = nil
        // Send cached data before the network refresh so the Watch does not
        // remain empty while the iPhone is waiting on the API.
        publishWatchSnapshot()
        do { try await refresh(presentConnectionError: false, force: true) }
        catch { }
    }

    func appDidBecomeActive() async {
        guard isAuthenticated, !isDemo else { return }
        appIsActive = true
        publishWatchSnapshot()
        // A new foreground session is an intentional, low-frequency chance to
        // recover a live connection after a server or network outage.
        realtimeRetryNotBefore = nil
        do { try await refresh(presentConnectionError: false, force: false, minimumInterval: 20) }
        catch { }
    }

    func appDidEnterBackground() {
        appIsActive = false
        realtimeRetryNotBefore = nil
        cancelRefresh()
        disconnectRealtime()
        if isAuthenticated, !isDemo {
            connectionStatus = "Paused · saved data"
        }
    }

    func enterDemo(reset: Bool = false) {
        cancelRefresh()
        disconnectRealtime()
        generation = UUID()
        token = nil
        careLinks = []
        careLinkSession = nil
        careLinkError = nil
        isDemo = true
        errorMessage = nil
        forecastSyncTask?.cancel()
        forecastSyncTask = nil
        sharedForecasts = []
        lastPublishedForecastSignature = nil
        forecastSnapshots = []
        if !reset, let data = defaults.data(forKey: "nestic.demo.v1"),
           let archive = try? NestCoding.decoder().decode(NestArchive.self, from: data) {
            apply(archive)
        } else {
            apply(Self.makeDemo())
            persist()
        }
        restorePredictionPreferences()
        if !reset { restoreForecastSnapshots() }
        reconcileForecastSnapshots()
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

    @discardableResult
    func register(name: String, email: String, password: String, acceptedTerms: Bool = false) async throws -> Bool {
        guard acceptedTerms else { throw NesticError.termsAcceptanceRequired }
        let name = try nonempty(name, label: "Your name")
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard email.contains("@"), password.count >= 8 else {
            throw NesticError.message("Use a valid email and a password with at least 8 characters.")
        }
        beginLoading()
        defer { endLoading() }
        let requestGeneration = generation
        struct Request: Encodable { let email: String; let password: String; let displayName: String; let acceptedTermsVersion: String }
        struct Response: Decodable { let token: String?; let requiresEmailVerification: Bool }
        let response: Response = try await NestAPI(baseURL: serverURL, token: nil, session: session)
            .post("auth/register", body: Request(email: email, password: password, displayName: name, acceptedTermsVersion: NesticAppLinks.termsVersion))
        try checkGeneration(requestGeneration)
        if let token = response.token { try await acceptSession(token); return false }
        return response.requiresEmailVerification
    }

    func requestPasswordReset(email: String) async throws {
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard email.contains("@") else { throw NesticError.message("Enter a valid email address.") }
        struct Request: Encodable { let email: String }
        struct Response: Decodable { let message: String }
        _ = try await NestAPI(baseURL: serverURL, token: nil, session: session)
            .post("auth/forgot-password", body: Request(email: email), as: Response.self)
    }

    func resendVerification(email: String) async throws {
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard email.contains("@") else { throw NesticError.message("Enter a valid email address.") }
        struct Request: Encodable { let email: String }
        struct Response: Decodable { let message: String }
        _ = try await NestAPI(baseURL: serverURL, token: nil, session: session)
            .post("auth/resend-verification", body: Request(email: email), as: Response.self)
    }

    func signInWithApple(identityToken: String, user: String, email: String?, displayName: String?, nonce: String?, acceptedTerms: Bool = false) async throws {
        guard !identityToken.isEmpty, !user.isEmpty, let nonce, !nonce.isEmpty else {
            throw NesticError.message("Apple sign-in could not be verified. Please try again.")
        }
        beginLoading()
        defer { endLoading() }
        let requestGeneration = generation
        struct Request: Encodable {
            let identityToken: String
            let user: String
            let email: String?
            let displayName: String?
            let nonce: String?
            let acceptedTermsVersion: String?
        }
        struct Response: Decodable { let token: String }
        let response: Response = try await NestAPI(baseURL: serverURL, token: nil, session: session)
            .post("auth/apple", body: Request(identityToken: identityToken, user: user, email: email, displayName: displayName, nonce: nonce, acceptedTermsVersion: acceptedTerms ? NesticAppLinks.termsVersion : nil))
        try checkGeneration(requestGeneration)
        try await acceptSession(response.token)
    }

    func linkApple(identityToken: String, user: String, email: String?, displayName: String?, nonce: String?) async throws {
        guard !identityToken.isEmpty, !user.isEmpty, let nonce, !nonce.isEmpty, token != nil else {
            throw NesticError.message("Apple sign-in could not be verified. Please try again.")
        }
        beginLoading()
        defer { endLoading() }
        let requestGeneration = generation
        struct Request: Encodable {
            let identityToken: String
            let user: String
            let email: String?
            let displayName: String?
            let nonce: String?
        }
        let profile: NestPerson = try await api().post("auth/apple/link", body: Request(identityToken: identityToken, user: user, email: email, displayName: displayName, nonce: nonce))
        try checkGeneration(requestGeneration)
        currentUser = profile
        persist()
    }

    func signOut() {
        if let reminderStore {
            Task { await reminderStore.clearAll() }
        }
        settingsSyncTask?.cancel()
        settingsSyncTask = nil
        forecastSyncTask?.cancel()
        forecastSyncTask = nil
        sharedForecasts = []
        lastPublishedForecastSignature = nil
        defaults.removeObject(forKey: settingsDirtyKey)
        settingsRevision += 1
        NesticWatchBridge.shared.clear()
        if !isDemo {
            defaults.set(true, forKey: "nestic.signedOut.\(NestCoding.serverKey(serverURL))")
            do { try keychain.delete(server: serverURL) }
            catch { errorMessage = error.localizedDescription }
        }
        cancelRefresh()
        disconnectRealtime()
        generation = UUID()
        token = nil
        currentUser = nil
        careLinks = []
        careLinkSession = nil
        careLinkError = nil
        predictionAccess = false
        isLoadingMoreEntries = false
        hasMoreEntries = false
        isDemo = false
        nests = []
        feedbackThreads = []
        selectedNestID = nil
        snapshots = [:]
        predictionPreferences = [:]
        quietHoursPreferences = NestQuietHoursPreferences()
        forecastSnapshots = []
        sharedForecasts = []
        lastPublishedForecastSignature = nil
        applySnapshot(NestSnapshot())
        NesticWidgetBridge.clear()
        connectionStatus = "Not connected"
    }

    func refresh(presentConnectionError: Bool = true, force: Bool = true,
                 minimumInterval: TimeInterval = 0) async throws {
        guard !isDemo, token != nil, currentUser != nil else { return }

        // Refresh requests can originate from launch, foregrounding, a manual
        // pull, a mutation, and realtime events. Share one request instead of
        // allowing those paths to fan out into duplicate API traffic.
        if let refreshTask {
            do {
                try await refreshTask.value
            } catch {
                if presentConnectionError { handle(error) }
                else if case NesticError.unauthorized = error { handle(error) }
                else if !appIsActive, isAuthenticated { connectionStatus = "Paused · saved data" }
                throw error
            }
            return
        }

        if !force, let lastSuccessfulRefreshAt,
           Date().timeIntervalSince(lastSuccessfulRefreshAt) < minimumInterval {
            return
        }

        let requestGeneration = generation
        refreshSequence += 1
        let sequence = refreshSequence
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            try await self.performRefresh(requestGeneration: requestGeneration, sequence: sequence)
        }
        refreshTask = task

        do {
            try await task.value
            refreshTask = nil
            connectRealtimeIfNeeded()
        } catch {
            refreshTask = nil
            guard requestGeneration == generation else { throw NesticError.staleSession }
            if presentConnectionError {
                handle(error)
            } else if case NesticError.unauthorized = error {
                handle(error)
            } else if !appIsActive, isAuthenticated {
                connectionStatus = "Paused · saved data"
            } else if !isDemo {
                connectionStatus = "Offline · showing saved data"
            }
            throw error
        }
    }

    private func performRefresh(requestGeneration: UUID, sequence: Int) async throws {
        guard !isDemo, let token, currentUser != nil else { return }
        beginLoading()
        defer { endLoading() }
        let api = NestAPI(baseURL: serverURL, token: token, session: session)

        // Refresh the account profile as well as nest data so server-side
        // support overrides, such as manual Pro access, take effect for an
        // already-signed-in device.
        let remoteUser: NestPerson = try await api.get("auth/me")
        try checkGeneration(requestGeneration)
        currentUser = remoteUser
        try? keychain.save(NestSession(token: token, user: remoteUser), server: serverURL)
        let remoteNests: [NestSpace] = try await api.get("nests")
        try checkGeneration(requestGeneration)
        guard sequence == refreshSequence else { return }
        let nestID = remoteNests.first { $0.id == selectedNestID }?.id ?? remoteNests.first?.id
        let snapshot: NestSnapshot
        if let nestID { snapshot = try await loadSnapshot(nestID: nestID, api: api) }
        else { snapshot = NestSnapshot() }
        var remoteSettings: NestUserSettingsResponse?
        var remoteReminders: [NestReminderResponse]?
        var remoteForecasts: [NestSharedForecast]?
        if let nestID {
            // Settings are optional for backwards compatibility while older
            // server deployments roll forward.
            async let settings: NestUserSettingsResponse? = try? api.get("nests/\(nestID)/settings")
            // Shared reminder schedules are intentionally separate from
            // private settings. A member's notification choice is resolved by
            // the server for just that member.
            async let reminders: [NestReminderResponse]? = try? api.get("nests/\(nestID)/reminders")
            // Forecasts are nest-scoped so every member receives the same
            // latest result. A missing endpoint remains compatible with older
            // server deployments and falls back to the local model.
            async let forecasts: [NestSharedForecast]? = try? api.get("nests/\(nestID)/forecasts")
            (remoteSettings, remoteReminders, remoteForecasts) = await (settings, reminders, forecasts)
        }
        try checkGeneration(requestGeneration)
        guard sequence == refreshSequence else { return }
        nests = remoteNests
        selectedNestID = nestID
        restoreQuietHoursPreferences()
        if let nestID, let remoteSettings {
            applyServerSettings(remoteSettings, nestID: nestID, subjectIDs: Set(snapshot.subjects.map(\.id)))
        }
        if let nestID, let remoteReminders {
            reminderStore?.replaceReminders(remoteReminders.map { $0.reminder() }, for: nestID)
            // Notification services can stall on a simulator (and during
            // system recovery). They must not hold the downloaded nest or
            // its loading indicator hostage. Scheduling is independent of
            // applying the server snapshot.
            Task { [weak reminderStore] in
                await reminderStore?.reconcileLinkedReminders(entries: snapshot.entries, nestID: nestID)
                await reminderStore?.sync()
            }
        }
        snapshots = snapshots.filter { key, _ in remoteNests.contains { $0.id.uuidString == key } }
        applySnapshot(snapshot)
        sharedForecasts = remoteForecasts ?? []
        reconcileForecastSnapshots()
        persist()
        lastSuccessfulRefreshAt = Date()
        errorMessage = nil
        if selectedNestID == nil {
            connectionStatus = "Connected"
        } else if !appIsActive {
            connectionStatus = "Paused · saved data"
        } else if let retryNotBefore = realtimeRetryNotBefore, retryNotBefore > Date() {
            connectionStatus = "Connected · live sync paused"
        }
    }

    func selectNest(_ nest: NestSpace) async throws {
        guard nests.contains(where: { $0.id == nest.id }) else { throw NesticError.message("That nest is no longer available.") }
        guard nest.id != selectedNestID else { return }
        persist()
        cancelRefresh()
        generation = UUID()
        disconnectRealtime()
        settingsRevision += 1
        settingsSyncTask?.cancel()
        settingsSyncTask = nil
        selectedNestID = nest.id
        sharedForecasts = []
        lastPublishedForecastSignature = nil
        restoreQuietHoursPreferences()
        applySnapshot(snapshots[nest.id.uuidString] ?? NestSnapshot())
        reconcileForecastSnapshots()
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
        cancelRefresh()
        disconnectRealtime()
        generation = UUID()
        nests.append(nest)
        selectedNestID = nest.id
        restoreQuietHoursPreferences()
        var owner = user
        owner.role = "owner"
        applySnapshot(NestSnapshot(members: [owner]))
        persist()
        await refreshAfterMutation()
    }

    func addMember(email: String, role: String = "member") async throws {
        let nestID = try requireNest()
        guard canManageNest else { throw NesticError.message("Only a nest owner or admin can add people.") }
        guard ["member", "owner"].contains(role) else { throw NesticError.message("That nest role is not available.") }
        guard role != "owner" || isNestOwner else { throw NesticError.message("Only a nest owner can add another owner.") }
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard email.contains("@"), email.contains(".") else { throw NesticError.message("Enter a valid email address.") }
        guard !members.contains(where: { $0.email.lowercased() == email }) else {
            throw NesticError.message("That person is already in your nest.")
        }
        let person: NestPerson
        if isDemo {
            person = .init(id: UUID(), email: email, displayName: email.components(separatedBy: "@")[0].capitalized, role: role)
        } else {
            let requestGeneration = generation
            struct Request: Encodable { let email: String; let role: String }
            let response: NestMemberResponse = try await api().post("nests/\(nestID)/members", body: Request(email: email, role: role))
            try checkGeneration(requestGeneration)
            person = response.person()
        }
        members.append(person)
        persist()
        await refreshAfterMutation()
    }

    // MARK: - Temporary caregiver access
    func removeMember(_ person: NestPerson) async throws {
        guard isNestOwner, person.id != currentUser?.id else {
            throw NesticError.message("Only an owner can remove another member’s access.")
        }
        let nestID = try requireNest()
        if !isDemo {
            let requestGeneration = generation
            _ = try await api().data(path: "nests/\(nestID)/members/\(person.id)", method: "DELETE")
            try checkGeneration(requestGeneration)
        }
        members.removeAll { $0.id == person.id }
        persist()
        await refreshAfterMutation()
    }

    /// Lets a member immediately stop receiving or seeing activity from a
    /// shared nest. Owners must transfer ownership first so a nest always has
    /// an accountable owner.
    func leaveSelectedNest() async throws {
        guard !isDemo else { throw NesticError.message("Leave the sample nest to return to the welcome screen.") }
        guard !isNestOwner else {
            throw NesticError.message("Transfer ownership or remove the nest before leaving it.")
        }
        let nestID = try requireNest()
        guard let userID = currentUser?.id else {
            throw NesticError.message("Sign in again before leaving this nest.")
        }
        let requestGeneration = generation
        _ = try await api().data(path: "nests/\(nestID)/members/\(userID)", method: "DELETE")
        try checkGeneration(requestGeneration)
        nests.removeAll { $0.id == nestID }
        selectedNestID = nests.first?.id
        members = []
        subjects = []
        allTrackers = []
        entries = []
        routines = []
        persist()
        if selectedNestID != nil { try await refresh() }
    }


    func listCareLinks() async throws -> [NestCareLink] {
        guard !isDemo else { careLinks = []; return [] }
        let nestID = try requireNest()
        guard canManageNest else { throw NesticError.message("Only a nest owner or admin can manage caregiver links.") }
        let requestGeneration = generation
        let responses: [NestCareLinkResponse] = try await api().get("nests/\(nestID)/care-links")
        try checkGeneration(requestGeneration)
        careLinks = responses.map { $0.link() }
        return careLinks
    }

    @discardableResult
    func createCareLink(label: String, expiresAt: Date, entityIDs: [UUID], actionIDs: [UUID],
                        canLog: Bool, canViewHistory: Bool) async throws -> NestCareLink {
        guard !isDemo else { throw NesticError.message("Caregiver links are available for a signed-in nest.") }
        guard hasForecastAccess else { throw NesticError.message("Caregiver links are part of Nestic Pro.") }
        let nestID = try requireNest()
        guard canManageNest else { throw NesticError.message("Only a nest owner or admin can create caregiver links.") }
        let label = try nonempty(label, label: "Link name")
        guard !entityIDs.isEmpty, !actionIDs.isEmpty else {
            throw NesticError.message("Choose at least one subject and tracker.")
        }
        struct Request: Encodable {
            let label: String
            let expiresAt: Date
            let entityIDs: [UUID]
            let actionIDs: [UUID]
            let canLog: Bool
            let canViewHistory: Bool
        }
        let requestGeneration = generation
        let response: NestCareLinkResponse = try await api().post(
            "nests/\(nestID)/care-links",
            body: Request(label: label, expiresAt: expiresAt,
                          entityIDs: Array(Set(entityIDs)), actionIDs: Array(Set(actionIDs)),
                          canLog: canLog, canViewHistory: canViewHistory)
        )
        try checkGeneration(requestGeneration)
        let link = response.link()
        careLinks.insert(link, at: 0)
        return link
    }

    func revokeCareLink(_ link: NestCareLink) async throws {
        guard !isDemo else { return }
        let nestID = try requireNest()
        guard canManageNest else { throw NesticError.message("Only a nest owner or admin can revoke caregiver links.") }
        let requestGeneration = generation
        try await api().delete("nests/\(nestID)/care-links/\(link.id)")
        try checkGeneration(requestGeneration)
        if let index = careLinks.firstIndex(where: { $0.id == link.id }) {
            careLinks[index].revokedAt = Date()
        }
    }

    func openCareLink(token: String, serverURL suppliedServerURL: String? = nil) async {
        do {
            let resolvedServerURL = try NestCoding.validatedServer(suppliedServerURL ?? serverURL)
            let publicAPI = NestAPI(baseURL: resolvedServerURL, token: nil, session: session)
            let response: NestCareLinkSnapshotResponse = try await publicAPI.get("care-links/\(token)")
            careLinkSession = NestCareSession(token: token, serverURL: resolvedServerURL,
                                              snapshot: response.snapshot())
            careLinkError = nil
        } catch {
            careLinkSession = nil
            careLinkError = error.localizedDescription
        }
    }

    func closeCareLink() {
        careLinkSession = nil
        careLinkError = nil
    }

    func logCareEvent(subjectID: UUID, trackerID: UUID, date: Date, number: Double? = nil,
                      text: String? = nil, bool: Bool? = nil, json: [String: String]? = nil,
                      note: String? = nil, wasAccident: Bool = false,
                      includeInPredictions: Bool = true) async throws {
        guard let session = careLinkSession else { throw NesticError.message("This caregiver link is no longer open.") }
        guard session.snapshot.link.canLog else { throw NesticError.message("This caregiver link is view-only.") }
        guard session.snapshot.subjects.contains(where: { $0.id == subjectID }),
              let tracker = session.snapshot.trackers.first(where: { $0.id == trackerID }) else {
            throw NesticError.message("That subject or tracker is not included in this link.")
        }
        guard date <= Date().addingTimeInterval(60) else { throw NesticError.message("Choose a time in the present or past.") }
        try Self.validateValue(type: tracker.valueType, number: number, text: text, bool: bool, json: json)
        let request = NestCareEventRequest(entityID: subjectID, actionID: trackerID,
                                            occurredAt: date, valueNumber: number,
                                            valueText: text, valueBool: bool, valueJSON: json,
                                            note: note, wasAccident: wasAccident,
                                            includeInPredictions: includeInPredictions)
        let publicAPI = NestAPI(baseURL: session.serverURL, token: nil, session: self.session)
        let entry: NestEntry = try await publicAPI.post("care-links/\(session.token)/events", body: request)
        updateCareSession(with: entry, token: session.token)
    }

    func logCareRoutine(_ routine: NestRoutine, date: Date = Date(), note: String? = nil) async throws {
        guard let session = careLinkSession else { throw NesticError.message("This caregiver link is no longer open.") }
        guard session.snapshot.link.canLog else { throw NesticError.message("This caregiver link is view-only.") }
        let publicAPI = NestAPI(baseURL: session.serverURL, token: nil, session: self.session)
        let request = NestCareRoutineRequest(occurredAt: date, note: note)
        let entries: [NestEntry] = try await publicAPI.post("care-links/\(session.token)/routines/\(routine.id)/log", body: request)
        for entry in entries { updateCareSession(with: entry, token: session.token) }
    }

    private func updateCareSession(with entry: NestEntry, token: String) {
        guard var session = careLinkSession, session.token == token else { return }
        session.snapshot.entries.removeAll { $0.id == entry.id }
        session.snapshot.entries.append(entry)
        session.snapshot.entries.sort { $0.occurredAt > $1.occurredAt }
        careLinkSession = session
    }

    func createSubject(name: String, kind: NestSubjectKind, emoji: String, photoData: String? = nil, profile: NesticSubjectProfileDraft? = nil, trackerTemplates: [NestTrackerTemplate]) async throws {
        let nestID = try requireNest()
        guard canLog else { throw NesticError.message("You have view-only access to this nest.") }
        let name = try nonempty(name, label: "Name")
        let emoji = emoji.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? kind.emoji : String(emoji.prefix(4))
        let metadata = try (profile ?? NesticSubjectProfileDraft()).metadata(merging: ["emoji": emoji])
        var subject: NestSubject
        let requestGeneration = generation
        if isDemo {
            subject = .init(id: UUID(), nestId: nestID, name: name, kind: kind, emoji: emoji, photoData: photoData, metadata: metadata)
        } else {
            struct Request: Encodable { let kind: NestSubjectKind; let name: String; let metadata: [String: String] }
            let response: NestEntityResponse = try await api().post("nests/\(nestID)/entities", body: Request(kind: kind, name: name, metadata: metadata))
            try checkGeneration(requestGeneration)
            subject = response.subject()
            if let photoData, let photoBytes = Data(base64Encoded: photoData) {
                let uploaded: NestEntityResponse = try await api().upload("entities/\(subject.id)/photo", body: photoBytes, contentType: "image/jpeg")
                try checkGeneration(requestGeneration)
                subject = uploaded.subject(pins: subject.pinnedActionIDs)
                subject.photoData = photoData
            }
        }
        subjects.append(subject)
        persist()
        do {
            for template in trackerTemplates {
                let tracker = try await makeTracker(name: template.name, valueType: template.valueType, unit: template.unit,
                                                    symbol: template.symbol, color: template.color, groupName: template.groupName)
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

    func updateSubjectProfile(_ subject: NestSubject, profile: NesticSubjectProfileDraft) async throws {
        guard canManageNest else { throw NesticError.message("Only a nest owner or admin can edit subject details.") }
        let metadata = try profile.metadata(merging: (subject.metadata ?? [:]).merging(["emoji": subject.emoji]) { _, new in new })
        var updated = subject
        if !isDemo {
            let requestGeneration = generation
            struct Request: Encodable { let metadata: [String: String]; let replaceProfileDetails = true }
            let response: NestEntityResponse = try await api().patch("entities/\(subject.id)", body: Request(metadata: metadata))
            try checkGeneration(requestGeneration)
            updated = response.subject(pins: subject.pinnedActionIDs)
            updated.photoData = subject.photoData
        } else { updated.metadata = metadata }
        if let index = subjects.firstIndex(where: { $0.id == subject.id }) { subjects[index] = updated }
        persist()
    }

    func updateSubjectPhoto(_ subject: NestSubject, photoData: String?) async throws {
        guard canManageNest else { throw NesticError.message("Only a nest owner or admin can change subject photos.") }
        let metadata = (subject.metadata ?? [:]).merging(["emoji": subject.emoji]) { _, new in new }
        let requestGeneration = generation
        let updated: NestSubject
        if isDemo {
            var copy = subject
            copy.photoData = photoData
            copy.photoURL = nil
            updated = copy
        } else {
            struct Request: Encodable { let metadata: [String: String] }
            let response: NestEntityResponse = try await api().patch("entities/\(subject.id)", body: Request(metadata: metadata))
            try checkGeneration(requestGeneration)
            var copy = response.subject(pins: subject.pinnedActionIDs)
            if let photoData, let photoBytes = Data(base64Encoded: photoData) {
                let uploaded: NestEntityResponse = try await api().upload("entities/\(subject.id)/photo", body: photoBytes, contentType: "image/jpeg")
                try checkGeneration(requestGeneration)
                copy = uploaded.subject(pins: subject.pinnedActionIDs)
                copy.photoData = photoData
            } else {
                let cleared: NestEntityResponse = try await api().delete("entities/\(subject.id)/photo")
                try checkGeneration(requestGeneration)
                copy = cleared.subject(pins: subject.pinnedActionIDs)
            }
            updated = copy
        }
        if let index = subjects.firstIndex(where: { $0.id == subject.id }) { subjects[index] = updated }
        persist()
        await refreshAfterMutation()
    }

    func deleteSubject(_ subject: NestSubject) async throws {
        let nestID = try requireNest()
        guard subjects.contains(where: { $0.id == subject.id }) else { return }
        guard subject.nestId == nestID else { throw NesticError.staleSession }
        guard canManageNest else { throw NesticError.message("Only a nest owner or admin can delete entities.") }

        if !isDemo {
            let requestGeneration = generation
            try await api().delete("entities/\(subject.id)")
            try checkGeneration(requestGeneration)
        }

        subjects.removeAll { $0.id == subject.id }
        entries.removeAll { $0.entityId == subject.id }
        routines = routines.compactMap { routine in
            var copy = routine
            copy.targets.removeAll { $0.entityID == subject.id }
            copy.syncLegacyTargetFields()
            return copy.targets.isEmpty ? nil : copy
        }
        await reminderStore?.removeReminders(for: subject.id)
        persist()
        await refreshAfterMutation()
    }

    @discardableResult
    func createTracker(subjectID: UUID, name: String, valueType: NestValueType, unit: String? = nil, symbol: String? = nil, color: String? = nil, groupName: String? = nil, isPrivate: Bool = false) async throws -> NestTracker {
        guard var subject = subjects.first(where: { $0.id == subjectID }) else { throw NesticError.message("This item no longer exists.") }
        guard canManageNest || (isPrivate && canLog) else { throw NesticError.message("Only a nest owner or admin can create shared trackers.") }
        let requestGeneration = generation
        let tracker = try await makeTracker(name: name, valueType: valueType, unit: unit, symbol: symbol, color: color, groupName: groupName, isPrivate: isPrivate)
        try checkGeneration(requestGeneration)
        guard !subject.pinnedActionIDs.contains(tracker.id) else { throw NesticError.message("This tracker is already on \(subject.name).") }
        subject.pinnedActionIDs.append(tracker.id)
        if !isDemo { try await savePins(subject) }
        try checkGeneration(requestGeneration)
        if let index = subjects.firstIndex(where: { $0.id == subject.id }) { subjects[index] = subject }
        persist()
        await refreshAfterMutation()
        return tracker
    }

    func updateTracker(_ tracker: NestTracker, name: String, valueType: NestValueType, unit: String? = nil, symbol: String? = nil, color: String? = nil, groupName: String? = nil) async throws {
        guard trackers.contains(where: { $0.id == tracker.id }) else { throw NesticError.message("This tracker no longer exists.") }
        guard tracker.isPrivate ? (canLog && tracker.privateOwnerId == currentUser?.id) : canManageNest else { throw NesticError.message("You can edit your private trackers. Shared trackers require an owner or admin.") }
        let cleanName = try nonempty(name, label: "Tracker name")
        let cleanUnit = valueType == .number ? unit?.trimmingCharacters(in: .whitespacesAndNewlines) : nil
        let cleanSymbol = symbol?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanColor = color?.trimmingCharacters(in: .whitespacesAndNewlines)
        let updated: NestTracker
        if isDemo {
            updated = NestTracker(id: tracker.id, nestId: tracker.nestId, name: cleanName, valueType: valueType,
                                  unit: cleanUnit?.isEmpty == true ? nil : cleanUnit,
                                  symbol: cleanSymbol?.isEmpty == true ? nil : cleanSymbol,
                                  color: cleanColor?.isEmpty == true ? nil : cleanColor,
                                  groupName: groupName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true ? nil : groupName?.trimmingCharacters(in: .whitespacesAndNewlines), privateOwnerId: tracker.privateOwnerId, allowedMemberIDs: tracker.allowedMemberIDs)
        } else {
            struct Request: Encodable {
                let name: String; let valueType: NestValueType; let unit: String?; let symbol: String?
                let color: String?; let groupName: String?
            }
            updated = try await api().patch("actions/\(tracker.id)", body: Request(name: cleanName, valueType: valueType,
                                                                                        unit: cleanUnit?.isEmpty == true ? nil : cleanUnit,
                                                                                        symbol: cleanSymbol?.isEmpty == true ? nil : cleanSymbol,
                                                                                        color: cleanColor?.isEmpty == true ? nil : cleanColor,
                                                                                        groupName: groupName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true ? nil : groupName?.trimmingCharacters(in: .whitespacesAndNewlines)))
        }
        if (tracker.valueType == .photo || tracker.valueType == .health) && updated.valueType != tracker.valueType {

        }
        if let index = allTrackers.firstIndex(where: { $0.id == tracker.id }) { allTrackers[index] = updated }
        persist()
        await refreshAfterMutation()
    }

    func setTrackerSharing(_ tracker: NestTracker, members: [UUID]) async throws {
        guard tracker.privateOwnerId == currentUser?.id, canLog else { throw NesticError.message("Only the creator can manage sharing.") }
        struct Request: Encodable { let allowedMemberIDs: [UUID] }
        let selected = Array(Set(members).subtracting(currentUser.map { [$0.id] } ?? []))
        let updated: NestTracker
        if isDemo { var copy = trackers.first { $0.id == tracker.id } ?? tracker; copy.allowedMemberIDs = selected; updated = copy }
        else {
            let capabilities: [String: Bool] = try await api().get("capabilities")
            guard capabilities["selectedTrackerMembers"] == true else { throw NesticError.message("Selected-member sharing requires the updated server.") }
            updated = try await api().put("actions/\(tracker.id)/sharing", body: Request(allowedMemberIDs: selected))
        }
        if let index = allTrackers.firstIndex(where: { $0.id == tracker.id }) { allTrackers[index] = updated }
        sharedForecasts.removeAll()
        forecastSnapshots.removeAll()
        persistForecastSnapshots()
        persist()
        await refreshAfterMutation()
    }

    func restoreTracker(_ tracker: NestTracker, subject: NestSubject) async throws {
        guard tracker.isPrivate ? (canLog && tracker.privateOwnerId == currentUser?.id) : canManageNest else { throw NesticError.message("Only an administrator or the restricted tracker’s creator can restore it.") }
        guard !trackers.contains(where: { $0.id != tracker.id && $0.name == tracker.name && $0.privateOwnerId == tracker.privateOwnerId }) else { throw NesticError.message("An active tracker already uses this name. Rename it before restoring this one.") }
        let requestGeneration = generation
        if !isDemo {
            struct RestoreRequest: Encodable { let entityID: UUID }
            _ = try await api().data(path: "actions/\(tracker.id)/restore", method: "POST", body: try NestCoding.encoder().encode(RestoreRequest(entityID: subject.id)))
            try checkGeneration(requestGeneration)
        }
        if let index = allTrackers.firstIndex(where: { $0.id == tracker.id }) { allTrackers[index].isArchived = false }
        if let index = subjects.firstIndex(where: { $0.id == subject.id }), !subjects[index].pinnedActionIDs.contains(tracker.id) { subjects[index].pinnedActionIDs.append(tracker.id) }
        persist(); await refreshAfterMutation()
    }

    func clearTrackerHistory(_ tracker: NestTracker) async throws {
        guard tracker.isPrivate ? (canLog && tracker.privateOwnerId == currentUser?.id) : canManageNest else {
            throw NesticError.message("Only a nest administrator or the restricted tracker’s creator can clear history.")
        }
        let requestGeneration = generation
        if !isDemo { _ = try await api().data(path: "actions/\(tracker.id)/history", method: "DELETE"); try checkGeneration(requestGeneration) }
        for entry in entries where entry.actionId == tracker.id {
            NesticEntryPhotoStore.remove(for: entry.id)
            (entry.photoUpdates ?? []).forEach { NesticEntryPhotoStore.remove(forPhotoID: $0.id) }
        }
        entries.removeAll { $0.actionId == tracker.id }
        sharedForecasts.removeAll(); forecastSnapshots = []
        persist()
        await reminderStore?.resetSchedules(referencing: tracker.id)
        await refreshAfterMutation()
    }

    func permanentlyDeleteTracker(_ tracker: NestTracker) async throws {
        guard tracker.isPrivate ? (canLog && tracker.privateOwnerId == currentUser?.id) : canManageNest else { throw NesticError.message("Only an administrator or the restricted tracker’s creator can delete it.") }
        let requestGeneration = generation
        if !isDemo { _ = try await api().data(path: "actions/\(tracker.id)/permanent", method: "DELETE"); try checkGeneration(requestGeneration) }
        for entry in entries where entry.actionId == tracker.id {
            NesticEntryPhotoStore.remove(for: entry.id)
            (entry.photoUpdates ?? []).forEach { NesticEntryPhotoStore.remove(forPhotoID: $0.id) }
        }
        try await deleteTracker(tracker, localOnly: true)
        entries.removeAll { $0.actionId == tracker.id }
        allTrackers.removeAll { $0.id == tracker.id }
        persist(); await refreshAfterMutation()
    }

    func deleteTracker(_ tracker: NestTracker, localOnly: Bool = false) async throws {
        guard trackers.contains(where: { $0.id == tracker.id }) else { return }
        guard tracker.isPrivate ? (canLog && tracker.privateOwnerId == currentUser?.id) : canManageNest else { throw NesticError.message("You can delete your private trackers. Shared trackers require an owner or admin.") }
        if !isDemo && !localOnly { _ = try await api().data(path: "actions/\(tracker.id)", method: "DELETE") }

        if let index = allTrackers.firstIndex(where: { $0.id == tracker.id }) { allTrackers[index].isArchived = true }
        sharedForecasts.removeAll()
        forecastSnapshots = []
        subjects = subjects.map { subject in
            var copy = subject
            copy.pinnedActionIDs.removeAll { $0 == tracker.id }
            return copy
        }
        routines = routines.compactMap { routine in
            var copy = routine
            copy.targets = copy.targets.compactMap { target in
                let items = target.items.filter { $0.trackerID != tracker.id }
                return items.isEmpty ? nil : NestRoutineTarget(entityID: target.entityID, items: items)
            }
            copy.syncLegacyTargetFields()
            return copy.targets.isEmpty ? nil : copy
        }
        await reminderStore?.removeReminders(referencing: tracker.id)
        persist()
        await refreshAfterMutation()
    }

    func createRoutine(subjectID: UUID, name: String, items: [NestRoutineItem]) async throws {
        try await createRoutine(name: name, targets: [NestRoutineTarget(entityID: subjectID, items: items)])
    }

    @discardableResult
    func createRoutine(name: String, targets: [NestRoutineTarget]) async throws -> NestRoutine {
        let nestID = try requireNest()
        guard hasRoutineAccess else { throw NesticError.message("Routines are part of Nestic Pro.") }
        let isPrivate = targets.flatMap(\.items).contains { item in trackers.contains { $0.id == item.trackerID && $0.isPrivate } }
        guard canManageNest || (isPrivate && canLog) else { throw NesticError.message("Shared routines require an owner or admin. Include a private tracker to create an Only me routine.") }
        let cleanName = try nonempty(name, label: "Routine name")
        try validateRoutineTargets(targets)
        let requestGeneration = generation
        let routine: NestRoutine
        if isDemo {
            routine = NestRoutine(id: UUID(), nestId: nestID, subjectID: targets[0].entityID,
                                  name: cleanName, items: targets[0].items, targets: targets, privateOwnerId: isPrivate ? currentUser?.id : nil)
        } else {
            struct Request: Encodable { let name: String; let targets: [NestRoutineTarget] }
            let response: NestRoutineResponse = try await api().post("nests/\(nestID)/routines",
                                                                       body: Request(name: cleanName, targets: targets))
            try checkGeneration(requestGeneration)
            routine = response.routine()
        }
        routines.append(routine)
        persist()
        await refreshAfterMutation()
        return routine
    }

    func updateRoutine(_ routine: NestRoutine, name: String, items: [NestRoutineItem]) async throws {
        try await updateRoutine(routine, name: name, targets: [NestRoutineTarget(entityID: routine.subjectID, items: items)])
    }

    func updateRoutine(_ routine: NestRoutine, name: String, targets: [NestRoutineTarget]) async throws {
        guard hasRoutineAccess else { throw NesticError.message("Routines are part of Nestic Pro.") }
        guard routines.contains(where: { $0.id == routine.id }) else {
            throw NesticError.message("This routine is no longer available.")
        }
        guard canManageNest || (canLog && routine.isPrivate && routine.privateOwnerId == currentUser?.id) else { throw NesticError.message("You can manage your private routines. Shared routines require an owner or admin.") }
        let cleanName = try nonempty(name, label: "Routine name")
        try validateRoutineTargets(targets)
        let requestGeneration = generation
        let updated: NestRoutine
        if isDemo {
            updated = NestRoutine(id: routine.id, nestId: routine.nestId, subjectID: targets[0].entityID,
                                  name: cleanName, items: targets[0].items, targets: targets,
                                  createdAt: routine.createdAt, updatedAt: Date(), privateOwnerId: routine.privateOwnerId)
        } else {
            struct Request: Encodable { let name: String; let targets: [NestRoutineTarget] }
            let response: NestRoutineResponse = try await api().patch("routines/\(routine.id)",
                                                                        body: Request(name: cleanName, targets: targets))
            try checkGeneration(requestGeneration)
            updated = response.routine()
        }
        if let index = routines.firstIndex(where: { $0.id == routine.id }) { routines[index] = updated }
        persist()
        await refreshAfterMutation()
    }

    func deleteRoutine(_ routine: NestRoutine) async throws {
        guard hasRoutineAccess else { throw NesticError.message("Routines are part of Nestic Pro.") }
        guard routines.contains(where: { $0.id == routine.id }) else { return }
        guard canManageNest || (canLog && routine.isPrivate && routine.privateOwnerId == currentUser?.id) else { throw NesticError.message("You can manage your private routines. Shared routines require an owner or admin.") }
        if !isDemo { _ = try await api().data(path: "routines/\(routine.id)", method: "DELETE") }
        routines.removeAll { $0.id == routine.id }
        await reminderStore?.removeReminders(referencing: routine.id)
        persist()
        await refreshAfterMutation()
    }

    func logRoutine(_ routine: NestRoutine, date: Date = Date(), note: String? = nil) async throws {
        let nestID = try requireNest()
        guard hasRoutineAccess else { throw NesticError.message("Routines are part of Nestic Pro.") }
        guard canLog else { throw NesticError.message("You have view-only access to this nest.") }
        guard routine.nestId == nestID else {
            throw NesticError.message("This routine is no longer available. Refresh your nest and try again.")
        }
        try validateRoutineTargets(routine.targets)
        guard date <= Date().addingTimeInterval(60) else { throw NesticError.message("Choose a time in the present or past.") }

        let cleanedNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        let loggedEntries: [NestEntry]
        if isDemo {
            loggedEntries = routine.targets.flatMap { target in
                target.items.map { item in
                    NestEntry(id: UUID(), nestId: nestID, entityId: target.entityID, actionId: item.trackerID,
                              actorUserId: currentUser?.id, occurredAt: date, valueNumber: item.valueNumber,
                              valueText: item.valueText, valueBool: item.valueBool, valueJSON: item.valueJSON,
                              note: cleanedNote?.isEmpty == true ? nil : cleanedNote)
                }
            }
        } else {
            let requestGeneration = generation
            struct Request: Encodable { let occurredAt: Date; let note: String? }
            loggedEntries = try await api().post("routines/\(routine.id)/log",
                                                 body: Request(occurredAt: date, note: cleanedNote))
            try checkGeneration(requestGeneration)
        }
        evaluateForecasts(with: loggedEntries)
        entries.append(contentsOf: loggedEntries)
        entries.sort { $0.occurredAt > $1.occurredAt }
        persist()
        for entry in loggedEntries { await reminderStore?.handleLoggedEntry(entry) }
        await reminderStore?.handleLoggedRoutine(routine.id, at: date)
        await refreshAfterMutation()
    }

    private func validateRoutineItems(_ items: [NestRoutineItem], for subject: NestSubject) throws {
        guard !items.isEmpty, items.count <= 50, Set(items.map(\.trackerID)).count == items.count else {
            throw NesticError.message("Choose between one and 50 unique trackers for a routine.")
        }
        for item in items {
            guard subject.pinnedActionIDs.contains(item.trackerID),
                  let tracker = trackers.first(where: { $0.id == item.trackerID }) else {
                throw NesticError.message("Every routine tracker must be enabled for \(subject.name).")
            }
            guard tracker.valueType != .photo && tracker.valueType != .health else {
                throw NesticError.message("Photo and health-event trackers are logged individually on the iPhone and cannot be included in routines.")
            }
            try Self.validateValue(type: tracker.valueType, number: item.valueNumber, text: item.valueText,
                                   bool: item.valueBool, json: item.valueJSON)
        }
    }

    private func validateRoutineTargets(_ targets: [NestRoutineTarget]) throws {
        let entityIDs = targets.map(\.entityID)
        let itemCount = targets.reduce(0) { $0 + $1.items.count }
        guard !targets.isEmpty, Set(entityIDs).count == entityIDs.count, itemCount <= 50 else {
            throw NesticError.message("Choose at least one entity and no more than 50 total trackers for a routine.")
        }
        for target in targets {
            guard let subject = subjects.first(where: { $0.id == target.entityID }) else {
                throw NesticError.message("One of the selected entities no longer exists.")
            }
            try validateRoutineItems(target.items, for: subject)
        }
    }


    @discardableResult
    func log(subjectID: UUID, trackerID: UUID, date: Date = Date(), number: Double? = nil, text: String? = nil,
             bool: Bool? = nil, json: [String: String]? = nil, note: String? = nil,
             wasAccident: Bool = false, includeInPredictions: Bool = true) async throws -> NestEntry {
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
                              note: cleanedNote?.isEmpty == true ? nil : cleanedNote,
                              wasAccident: wasAccident, includeInPredictions: includeInPredictions)
        if !isDemo {
            let requestGeneration = generation
            struct Request: Encodable {
                let actionID: UUID; let occurredAt: Date; let valueNumber: Double?
                let valueText: String?; let valueBool: Bool?; let valueJSON: [String: String]?; let note: String?
                let wasAccident: Bool; let includeInPredictions: Bool
            }
            entry = try await api().post("entities/\(subjectID)/events", body: Request(actionID: trackerID, occurredAt: date, valueNumber: number, valueText: cleanedText, valueBool: bool, valueJSON: json, note: entry.note,
                                                                 wasAccident: wasAccident, includeInPredictions: includeInPredictions))
            try checkGeneration(requestGeneration)
        }
        evaluateForecasts(with: [entry])
        entries.removeAll { $0.id == entry.id }
        entries.append(entry)
        entries.sort { $0.occurredAt > $1.occurredAt }
        persist()
        await reminderStore?.handleLoggedEntry(entry)
        await refreshAfterMutation()
        return entry
    }

    /// Uploads the photo for a shared photo tracker event. The local JPEG is
    /// retained as a cache, while the authenticated server endpoint stores the
    /// shared copy in the nest's existing private photo storage.
    @discardableResult
    func uploadEntryPhoto(_ sourceData: Data, for entry: NestEntry) async throws -> NestEntry {
        guard let valueType = trackers.first(where: { $0.id == entry.actionId })?.valueType,
              valueType == .photo || valueType == .health else {
            throw NesticError.message("This update does not support a photo.")
        }
        let jpeg = try NesticEntryPhotoStore.jpegData(from: sourceData)
        let uploaded: NestEntry
        if isDemo {
            var copy = entry
            copy.photoURL = "local://entry-photo"
            uploaded = copy
        } else {
            uploaded = try await api().upload("events/\(entry.id)/photo", body: jpeg, contentType: "image/jpeg")
        }
        try NesticEntryPhotoStore.save(jpeg, for: uploaded.id)
        if let index = entries.firstIndex(where: { $0.id == uploaded.id }) {
            entries[index] = uploaded
            entries.sort { $0.occurredAt > $1.occurredAt }
        }
        persist()
        return uploaded
    }

    /// Adds a dated photo update to a health episode without replacing the
    /// onset photo. Every update is shared through the same private storage
    /// used by the nest's existing event photos.
    @discardableResult
    func addHealthPhoto(_ sourceData: Data, to entry: NestEntry, at date: Date = Date(), note: String? = nil) async throws -> NestEntry {
        guard trackers.first(where: { $0.id == entry.actionId })?.valueType == .health else {
            throw NesticError.message("Only health events support photo updates.")
        }
        try validateHealthUpdateDate(date, for: entry)
        let cleanNote = try healthUpdateNote(note, required: false)
        let jpeg = try NesticEntryPhotoStore.jpegData(from: sourceData)
        let updated: NestEntry
        if isDemo {
            var copy = entry
            var updates = copy.photoUpdates ?? []
            updates.append(NestHealthPhoto(id: UUID(), capturedAt: date, photoURL: "local://health-photo", note: cleanNote))
            copy.photoUpdates = updates.sorted { $0.capturedAt < $1.capturedAt }
            updated = copy
            if let photoID = copy.photoUpdates?.last?.id {
                try NesticEntryPhotoStore.save(jpeg, forPhotoID: photoID)
            }
        } else {
            let requestGeneration = generation
            updated = try await api().upload(healthPhotoUpdatePath(for: entry.id, at: date, note: cleanNote),
                                             body: jpeg, contentType: "image/jpeg", method: "POST")
            try checkGeneration(requestGeneration)
            let previousIDs = Set((entry.photoUpdates ?? []).map(\.id))
            if let photo = updated.photoUpdates?.first(where: { !previousIDs.contains($0.id) }) {
                try NesticEntryPhotoStore.save(jpeg, forPhotoID: photo.id)
            }
        }
        replaceEntry(updated)
        persist()
        await refreshAfterMutation()
        return updated
    }

    /// Adds a text-only update to an open health episode. Text updates share
    /// the same dated timeline as progress photos.
    @discardableResult
    func addHealthUpdate(to entry: NestEntry, at date: Date = Date(), note: String) async throws -> NestEntry {
        guard trackers.first(where: { $0.id == entry.actionId })?.valueType == .health else {
            throw NesticError.message("Only health events support updates.")
        }
        try validateHealthUpdateDate(date, for: entry)
        guard let cleanNote = try healthUpdateNote(note, required: true) else {
            throw NesticError.message("Add a note for this update.")
        }

        let updated: NestEntry
        if isDemo {
            var copy = entry
            var updates = copy.photoUpdates ?? []
            updates.append(NestHealthPhoto(id: UUID(), capturedAt: date, photoURL: "", note: cleanNote))
            copy.photoUpdates = updates.sorted { $0.capturedAt < $1.capturedAt }
            updated = copy
        } else {
            struct Request: Encodable {
                let capturedAt: Date
                let note: String
            }
            let requestGeneration = generation
            updated = try await api().post("events/\(entry.id)/updates",
                                           body: Request(capturedAt: date, note: cleanNote))
            try checkGeneration(requestGeneration)
        }
        replaceEntry(updated)
        persist()
        await refreshAfterMutation()
        return updated
    }

    @discardableResult
    func removeHealthPhoto(_ photo: NestHealthPhoto, from entry: NestEntry) async throws -> NestEntry {
        guard trackers.first(where: { $0.id == entry.actionId })?.valueType == .health else {
            throw NesticError.message("Only health events support photo updates.")
        }
        let updated: NestEntry
        if isDemo {
            var copy = entry
            copy.photoUpdates = (copy.photoUpdates ?? []).filter { $0.id != photo.id }
            updated = copy
        } else {
            let requestGeneration = generation
            updated = try await api().delete("events/\(entry.id)/photos/\(photo.id)", as: NestEntry.self)
            try checkGeneration(requestGeneration)
        }
        NesticEntryPhotoStore.remove(forPhotoID: photo.id)
        replaceEntry(updated)
        persist()
        await refreshAfterMutation()
        return updated
    }

    /// Loads a shared health photo into the device cache on demand.
    func healthPhotoData(_ photo: NestHealthPhoto, for entry: NestEntry) async throws -> Data? {
        guard photo.photoURL.isEmpty == false else { return NesticEntryPhotoStore.data(forPhotoID: photo.id) }
        if let cached = NesticEntryPhotoStore.data(forPhotoID: photo.id) { return cached }
        guard !isDemo else { return nil }
        let data = try await api().data(path: "events/\(entry.id)/photos/\(photo.id)")
        try NesticEntryPhotoStore.save(data, forPhotoID: photo.id)
        return NesticEntryPhotoStore.data(forPhotoID: photo.id)
    }

    private func validateHealthUpdateDate(_ date: Date, for entry: NestEntry) throws {
        guard date >= entry.occurredAt else {
            throw NesticError.message("A health update cannot be recorded before onset.")
        }
        guard date <= Date().addingTimeInterval(60) else {
            throw NesticError.message("A health update cannot be recorded in the future.")
        }
    }

    private func healthUpdateNote(_ note: String?, required: Bool) throws -> String? {
        let clean = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (clean?.count ?? 0) <= 2_000 else {
            throw NesticError.message("Health update notes are limited to 2,000 characters.")
        }
        if required && (clean?.isEmpty != false) {
            throw NesticError.message("Add a note or choose a photo for this update.")
        }
        return clean?.isEmpty == true ? nil : clean
    }

    private func healthPhotoUpdatePath(for entryID: UUID, at date: Date, note: String?) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        var components = URLComponents()
        var queryItems = [URLQueryItem(name: "capturedAt", value: formatter.string(from: date))]
        if let note, !note.isEmpty {
            queryItems.append(URLQueryItem(name: "note", value: note))
        }
        components.queryItems = queryItems
        let query = components.percentEncodedQuery.map { "?\($0)" } ?? ""
        return "events/\(entryID)/photos\(query)"
    }

    @discardableResult
    func removeEntryPhoto(_ entry: NestEntry) async throws -> NestEntry {
        guard let valueType = trackers.first(where: { $0.id == entry.actionId })?.valueType,
              valueType == .photo || valueType == .health else {
            throw NesticError.message("This update does not support a photo.")
        }
        let updated: NestEntry
        if isDemo {
            var copy = entry
            copy.photoURL = nil
            updated = copy
        } else {
            updated = try await api().delete("events/\(entry.id)/photo", as: NestEntry.self)
        }
        NesticEntryPhotoStore.remove(for: entry.id)
        if let index = entries.firstIndex(where: { $0.id == updated.id }) {
            entries[index] = updated
        }
        persist()
        return updated
    }

    /// Loads a shared event photo into the device cache on demand. This keeps
    /// the initial nest snapshot small while still letting every member view
    /// photos recorded by another device.
    func entryPhotoData(for entry: NestEntry) async throws -> Data? {
        guard entry.photoURL != nil else {
            NesticEntryPhotoStore.remove(for: entry.id)
            return nil
        }
        if let cached = NesticEntryPhotoStore.data(for: entry.id) { return cached }
        guard !isDemo else { return nil }
        let data = try await api().data(path: "events/\(entry.id)/photo")
        try NesticEntryPhotoStore.save(data, for: entry.id)
        return NesticEntryPhotoStore.data(for: entry.id)
    }

    func logFromReminder(subjectID: UUID, trackerID: UUID) async {
        if let routine = routines.first(where: { $0.id == trackerID }) {
            do { try await logRoutine(routine) } catch { errorMessage = error.localizedDescription }
            return
        }
        guard let tracker = trackers.first(where: { $0.id == trackerID }) else { return }
        do {
            switch tracker.valueType {
            case .none:
                try await log(subjectID: subjectID, trackerID: trackerID)
            default:
                errorMessage = "Open Nestic to enter the amount or value for \(tracker.name)."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveReminder(_ reminder: NesticReminder, isNew: Bool) async throws {
        guard let reminderStore else { return }
        if isDemo {
            try await reminderStore.save(reminder)
            await reminderStore.updateDoseReminders(entries: entries, nestID: reminder.nestID)
            return
        }
        let nestID = try requireNest()
        guard reminder.nestID == nestID else { throw NesticError.message("This reminder belongs to another nest.") }
        struct Request: Encodable {
            let subjectID: UUID
            let trackerID: UUID
            let intervalHours: Double?
            let totalPills: Int?
            let routineID: UUID?
            let recurrenceDays: Int?
            let startFromFirstTracking: Bool?
            let cadence: NesticReminderCadence
            let linkedTrackerID: UUID?
            let delayMinutes: Int
            let anchorDate: Date
            let hour: Int
            let minute: Int
        }
        let request = Request(subjectID: reminder.subjectID, trackerID: reminder.medicationTrackerID,
                              intervalHours: reminder.intervalHours, totalPills: reminder.totalPills,
                              routineID: reminder.routineID, recurrenceDays: reminder.recurrenceDays, startFromFirstTracking: reminder.startFromFirstTracking, cadence: reminder.cadence, linkedTrackerID: reminder.linkedMealTrackerID,
                              delayMinutes: reminder.delayMinutes, anchorDate: reminder.anchorDate,
                              hour: reminder.hour, minute: reminder.minute)
        let response: NestReminderResponse
        if isNew || reminder.isShared != true {
            response = try await api().post("nests/\(nestID)/reminders", body: request)
        } else {
            response = try await api().patch("nests/\(nestID)/reminders/\(reminder.id)", body: request)
        }
        if reminder.isShared != true {
            await reminderStore.delete(reminder)
        }
        await applyReminder(response.reminder(), in: reminderStore, nestID: nestID)
    }

    func deleteReminder(_ reminder: NesticReminder) async throws {
        guard let reminderStore else { return }
        if isDemo {
            await reminderStore.delete(reminder)
            return
        }
        guard reminder.isShared == true else {
            await reminderStore.delete(reminder)
            return
        }
        let nestID = try requireNest()
        try await api().delete("nests/\(nestID)/reminders/\(reminder.id)")
        await reminderStore.delete(reminder)
    }

    func setReminderDelivery(_ mode: String, for reminder: NesticReminder) async throws {
        guard ["notification", "alarm", "both"].contains(mode), let reminderStore else { return }
        var updated = reminder; updated.deliveryMode = mode
        if updated.enabled { try await reminderStore.authorizeDelivery(for: updated) }
        if isDemo || reminder.isShared != true { try await reminderStore.save(updated); return }
        let nestID = try requireNest()
        struct Request: Encodable { let enabled: Bool; let deliveryMode: String }
        let response: NestReminderResponse = try await api().put("nests/\(nestID)/reminders/\(reminder.id)/notification", body: Request(enabled: reminder.enabled, deliveryMode: mode))
        await applyReminder(response.reminder(), in: reminderStore, nestID: nestID)
    }

    func setReminderNotifications(_ enabled: Bool, for reminder: NesticReminder) async throws {
        guard let reminderStore else { return }
        if isDemo {
            try await reminderStore.setNotificationsEnabled(enabled, for: reminder)
            return
        }
        guard reminder.isShared == true else {
            try await reminderStore.setNotificationsEnabled(enabled, for: reminder)
            return
        }
        let nestID = try requireNest()
        struct Request: Encodable { let enabled: Bool }
        let response: NestReminderResponse = try await api().put(
            "nests/\(nestID)/reminders/\(reminder.id)/notification", body: Request(enabled: enabled)
        )
        await applyReminder(response.reminder(), in: reminderStore, nestID: nestID)
    }

    private func applyReminder(_ reminder: NesticReminder, in reminderStore: NesticReminderStore, nestID: UUID) async {
        var values = reminderStore.remindersForSync(nestID: nestID).filter { $0.isShared == true }
        values.removeAll { $0.id == reminder.id }
        values.append(reminder)
        reminderStore.replaceReminders(values, for: nestID)
        await reminderStore.sync()
    }

    /// Handles a log that was created on the watch while the iPhone was not
    /// reachable. The API remains the source of truth; the current iPhone
    /// selection is only updated when the event belongs to that nest.
    @discardableResult
    func logFromWatch(_ request: NesticWatchLogRequest) async -> Bool {
        guard !isDemo, currentUser != nil, token != nil, request.serverURL == serverURL else { return false }
        struct Request: Encodable {
            let actionID: UUID
            let occurredAt: Date
            let valueNumber: Double?
            let valueText: String?
            let valueBool: Bool?
            let valueJSON: [String: String]?
            let note: String?
        }
        do {
            let entry: NestEntry = try await api().post(
                "entities/\(request.subjectID)/events",
                body: Request(actionID: request.trackerID, occurredAt: request.occurredAt,
                              valueNumber: request.valueNumber, valueText: request.valueText,
                              valueBool: request.valueBool, valueJSON: request.valueJSON,
                              note: request.note)
            )
            if entry.nestId == selectedNestID {
                evaluateForecasts(with: [entry])
                entries.removeAll { $0.id == entry.id }
                entries.append(entry)
                entries.sort { $0.occurredAt > $1.occurredAt }
                persist()
            } else {
                await refreshAfterMutation()
            }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Handles a routine recorded on the Watch. The routine endpoint creates
    /// all of the routine's tracker events atomically on the server.
    @discardableResult
    func logRoutineFromWatch(_ request: NesticWatchRoutineLogRequest) async -> Bool {
        guard !isDemo, currentUser != nil, token != nil, request.serverURL == serverURL else { return false }
        struct Request: Encodable {
            let occurredAt: Date
            let note: String?
        }
        do {
            let loggedEntries: [NestEntry] = try await api().post(
                "routines/\(request.routineID)/log",
                body: Request(occurredAt: request.occurredAt, note: request.note)
            )
            if request.nestID == selectedNestID {
                for entry in loggedEntries {
                    evaluateForecasts(with: [entry])
                    entries.removeAll { $0.id == entry.id }
                    entries.append(entry)
                }
                entries.sort { $0.occurredAt > $1.occurredAt }
                persist()
            } else {
                await refreshAfterMutation()
            }
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
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
        invalidateForecastOutcomes(for: entry)
        entries.removeAll { $0.id == entry.id }
        NesticEntryPhotoStore.remove(for: entry.id)
        (entry.photoUpdates ?? []).forEach { NesticEntryPhotoStore.remove(forPhotoID: $0.id) }
        persist()
        await refreshAfterMutation()
    }

    @discardableResult
    func updateEntry(_ entry: NestEntry, date: Date, number: Double? = nil, text: String? = nil,
                     bool: Bool? = nil, json: [String: String]? = nil, note: String? = nil,
                     wasAccident: Bool? = nil, includeInPredictions: Bool? = nil) async throws -> NestEntry {
        let nestID = try requireNest()
        guard entry.nestId == nestID else { throw NesticError.staleSession }
        guard canManageNest || (canLog && entry.actorUserId == currentUser?.id) else {
            throw NesticError.message("You can edit your own updates. A nest owner or admin can edit other updates.")
        }
        guard let subject = subjects.first(where: { $0.id == entry.entityId }),
              subject.pinnedActionIDs.contains(entry.actionId),
              let tracker = trackers.first(where: { $0.id == entry.actionId }) else {
            throw NesticError.message("This tracker is no longer available. Refresh your nest and try again.")
        }
        try Self.validateValue(type: tracker.valueType, number: number, text: text, bool: bool, json: json)
        guard date <= Date().addingTimeInterval(60) else { throw NesticError.message("Choose a time in the present or past.") }

        let cleanedText = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanedNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        var updated = NestEntry(id: entry.id, nestId: nestID, entityId: entry.entityId, actionId: entry.actionId,
                                actorUserId: entry.actorUserId, occurredAt: date,
                                valueNumber: number, valueText: cleanedText, valueBool: bool, valueJSON: json,
                                note: cleanedNote?.isEmpty == true ? nil : cleanedNote,
                                wasAccident: wasAccident ?? entry.wasAccident,
                                includeInPredictions: includeInPredictions ?? entry.includeInPredictions,
                                photoURL: entry.photoURL, resolvedAt: entry.resolvedAt,
                                resolutionNote: entry.resolutionNote,
                                photoUpdates: entry.photoUpdates)
        if !isDemo {
            let requestGeneration = generation
            struct Request: Encodable {
                let occurredAt: Date
                let valueNumber: Double?
                let valueText: String?
                let valueBool: Bool?
                let valueJSON: [String: String]?
                let note: String?
                let wasAccident: Bool?
                let includeInPredictions: Bool?
            }
            updated = try await api().patch("events/\(entry.id)", body: Request(
                occurredAt: date, valueNumber: number, valueText: cleanedText,
                valueBool: bool, valueJSON: json, note: updated.note,
                wasAccident: wasAccident, includeInPredictions: includeInPredictions))
            try checkGeneration(requestGeneration)
        }
        if updated.occurredAt != entry.occurredAt ||
            updated.shouldIncludeInPredictions != entry.shouldIncludeInPredictions {
            invalidateForecastOutcomes(for: entry)
        }
        if let index = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[index] = updated
        } else {
            entries.append(updated)
        }
        entries.sort { $0.occurredAt > $1.occurredAt }
        persist()
        await reminderStore?.handleUpdatedEntry(updated)
        await refreshAfterMutation()
        return updated
    }

    @discardableResult
    func resolveHealthEntry(_ entry: NestEntry, at date: Date = Date(), note: String? = nil) async throws -> NestEntry {
        let nestID = try requireNest()
        guard entry.nestId == nestID else { throw NesticError.staleSession }
        guard let tracker = trackers.first(where: { $0.id == entry.actionId }), tracker.valueType == .health else {
            throw NesticError.message("Only health events can be marked resolved.")
        }
        guard canManageNest || (canLog && entry.actorUserId == currentUser?.id) else {
            throw NesticError.message("You can resolve your own health events. A nest administrator can resolve other events.")
        }
        guard date >= entry.occurredAt else { throw NesticError.message("Resolution cannot happen before onset.") }
        guard date <= Date().addingTimeInterval(60) else { throw NesticError.message("Choose a resolution time in the present or past.") }
        let cleanNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (cleanNote?.count ?? 0) <= 2000 else { throw NesticError.message("Resolution notes are limited to 2,000 characters.") }

        let resolved: NestEntry
        if isDemo {
            var copy = entry
            copy.resolvedAt = date
            copy.resolutionNote = cleanNote?.isEmpty == true ? nil : cleanNote
            resolved = copy
        } else {
            let requestGeneration = generation
            struct Request: Encodable { let resolvedAt: Date; let note: String? }
            resolved = try await api().post("events/\(entry.id)/resolve", body: Request(
                resolvedAt: date, note: cleanNote?.isEmpty == true ? nil : cleanNote))
            try checkGeneration(requestGeneration)
        }
        replaceEntry(resolved)
        persist()
        await refreshAfterMutation()
        return resolved
    }

    @discardableResult
    func reopenHealthEntry(_ entry: NestEntry) async throws -> NestEntry {
        let nestID = try requireNest()
        guard entry.nestId == nestID else { throw NesticError.staleSession }
        guard let tracker = trackers.first(where: { $0.id == entry.actionId }), tracker.valueType == .health else {
            throw NesticError.message("Only health events can be reopened.")
        }
        guard canManageNest || (canLog && entry.actorUserId == currentUser?.id) else {
            throw NesticError.message("You can reopen your own health events. A nest administrator can reopen other events.")
        }

        let reopened: NestEntry
        if isDemo {
            var copy = entry
            copy.resolvedAt = nil
            copy.resolutionNote = nil
            reopened = copy
        } else {
            let requestGeneration = generation
            reopened = try await api().delete("events/\(entry.id)/resolve", as: NestEntry.self)
            try checkGeneration(requestGeneration)
        }
        replaceEntry(reopened)
        persist()
        await refreshAfterMutation()
        return reopened
    }

    private func replaceEntry(_ entry: NestEntry) {
        if let index = entries.firstIndex(where: { $0.id == entry.id }) {
            entries[index] = entry
        } else {
            entries.append(entry)
        }
        entries.sort { $0.occurredAt > $1.occurredAt }
    }

    func deleteAccount(apple: AppleCredentialPayload? = nil) async throws {
        guard !isDemo else { throw NesticError.message("Sample data is stored only on this device.") }
        guard currentUser != nil else { throw NesticError.unauthorized }
        beginLoading()
        defer { endLoading() }
        let requestGeneration = generation
        let wasAppleLinked = currentUser?.appleLinked == true
        struct Response: Decodable { let deleted: Bool; let appleAccessRevoked: Bool? }
        struct Request: Encodable {
            let identityToken: String
            let user: String
            let nonce: String
            let authorizationCode: String
        }
        let body: Data?
        if let apple, let code = apple.authorizationCode {
            body = try NestCoding.encoder().encode(Request(identityToken: apple.identityToken,
                user: apple.user, nonce: apple.nonce, authorizationCode: code))
        } else { body = nil }
        let response = try NestCoding.decoder().decode(Response.self,
            from: await api().data(path: "auth/me", method: "DELETE", body: body))
        try checkGeneration(requestGeneration)
        guard response.deleted else { throw NesticError.message("The account was not deleted. Please try again.") }
        let cachedEntries = snapshots.values.flatMap(\.entries) + entries
        for entry in cachedEntries {
            NesticEntryPhotoStore.remove(for: entry.id)
            for update in entry.photoUpdates ?? [] { NesticEntryPhotoStore.remove(forPhotoID: update.id) }
        }
        if let archiveKey { defaults.removeObject(forKey: archiveKey) }
        defaults.removeObject(forKey: predictionPreferencesKey)
        defaults.removeObject(forKey: forecastSnapshotsKey)
        if let user = currentUser {
            let accountPrefix = NestCoding.serverKey(serverURL) + "." + user.id.uuidString
            for nest in nests {
                defaults.removeObject(forKey: "nestic.quiet-hours." + accountPrefix + "." + nest.id.uuidString)
                defaults.removeObject(forKey: "nestic.settings-dirty." + accountPrefix + "." + nest.id.uuidString)
            }
        }
        signOut()
        if wasAppleLinked && response.appleAccessRevoked != true {
            accountDeletionNotice = "Your Nestic account and data have been deleted. To remove the remaining Apple sign-in connection, open Settings → your name → Sign in with Apple → Nestic, then stop using Sign in with Apple. Any Apple subscription must be canceled separately."
        }
    }

    private func requireAdminAccess() throws {
        guard !isDemo, currentUser?.isAdmin == true else {
            throw NesticError.message("Administrator access is required.")
        }
    }

    func loadUsageAnalytics(days: Int) async throws -> NesticUsageDashboard {
        guard currentUser?.isAdmin == true, !isDemo else { throw NesticError.message("Administrator access is required.") }
        return try await api().get("admin/analytics?days=\(days)")
    }

    func loadAdminDashboard() async throws -> NestAdminDashboard {
        try requireAdminAccess()
        let requestGeneration = generation
        let result: NestAdminDashboard = try await api().get("admin/dashboard")
        try checkGeneration(requestGeneration)
        return result
    }

    func loadAdminUsers(search: String = "") async throws -> [NestAdminUser] {
        try requireAdminAccess()
        let requestGeneration = generation
        let result: [NestAdminUser] = try await api().get("admin/users" + (search.isEmpty ? "" : "?search=" + (search.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&+=?#"))) ?? "")))
        try checkGeneration(requestGeneration)
        return result
    }

    func setManualProAccess(for user: NestAdminUser, enabled: Bool) async throws -> NestAdminUser {
        try requireAdminAccess()
        struct Request: Encodable { let enabled: Bool }
        let requestGeneration = generation
        let result: NestAdminUser = try await api().patch("admin/users/" + user.id.uuidString + "/pro", body: Request(enabled: enabled))
        try checkGeneration(requestGeneration)
        if currentUser?.id == result.id {
            currentUser?.manualPro = result.manualPro == true
            persist()
        }
        return result
    }

    func loadAdminFeedback() async throws -> [NestFeedbackThread] {
        try requireAdminAccess()
        let requestGeneration = generation
        let result: [NestFeedbackThread] = try await api().get("admin/feedback")
        try checkGeneration(requestGeneration)
        return result
    }

    func updateAdminFeedback(_ thread: NestFeedbackThread, status: NestFeedbackStatus) async throws -> NestFeedbackThread {
        try requireAdminAccess()
        struct Request: Encodable { let status: String }
        let requestGeneration = generation
        let result: NestFeedbackThread = try await api().patch("admin/feedback/" + thread.id.uuidString, body: Request(status: status.rawValue))
        try checkGeneration(requestGeneration)
        return result
    }

    func replyToAdminFeedback(_ thread: NestFeedbackThread, message: String) async throws -> NestFeedbackThread {
        try requireAdminAccess()
        let cleanMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanMessage.isEmpty else { throw NesticError.message("Write a reply before sending it.") }
        let requestGeneration = generation
        let result: NestFeedbackThread = try await api().post("admin/feedback/" + thread.id.uuidString + "/messages", body: NestFeedbackMessageRequest(message: cleanMessage))
        try checkGeneration(requestGeneration)
        return result
    }

    func loadFeedback() async throws {
        guard !isDemo else { feedbackThreads = []; return }
        let requestGeneration = generation
        let threads: [NestFeedbackThread] = try await api().get("feedback")
        try checkGeneration(requestGeneration)
        feedbackThreads = threads
    }

    func createFeedback(subject: String, category: String, message: String) async throws {
        guard !isDemo else { throw NesticError.message("Feedback is available after you create an account.") }
        let cleanSubject = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanSubject.isEmpty else { throw NesticError.message("Add a subject for your feedback.") }
        guard !cleanMessage.isEmpty else { throw NesticError.message("Write a message before sending feedback.") }
        let requestGeneration = generation
        let created: NestFeedbackThread = try await api().post(
            "feedback",
            body: NestFeedbackCreateRequest(subject: cleanSubject, category: category, message: cleanMessage)
        )
        try checkGeneration(requestGeneration)
        feedbackThreads.removeAll { $0.id == created.id }
        feedbackThreads.insert(created, at: 0)
    }

    func loadFeedbackThread(_ thread: NestFeedbackThread, asAdmin: Bool = false) async throws -> NestFeedbackThread {
        if asAdmin { try requireAdminAccess() }
        guard !isDemo else { return thread }
        let requestGeneration = generation
        let loaded: NestFeedbackThread = try await api().get("feedback/" + thread.id.uuidString)
        try checkGeneration(requestGeneration)
        if !asAdmin { replaceFeedback(loaded) }
        return loaded
    }

    func replyToFeedback(_ thread: NestFeedbackThread, message: String) async throws {
        guard !isDemo else { throw NesticError.message("Feedback is available after you create an account.") }
        let cleanMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanMessage.isEmpty else { throw NesticError.message("Write a reply before sending it.") }
        let requestGeneration = generation
        let updated: NestFeedbackThread = try await api().post(
            "feedback/" + thread.id.uuidString + "/messages",
            body: NestFeedbackMessageRequest(message: cleanMessage)
        )
        try checkGeneration(requestGeneration)
        replaceFeedback(updated)
    }

    private func replaceFeedback(_ thread: NestFeedbackThread) {
        if let index = feedbackThreads.firstIndex(where: { $0.id == thread.id }) {
            feedbackThreads[index] = thread
        } else {
            feedbackThreads.insert(thread, at: 0)
        }
        feedbackThreads.sort { $0.lastActivityAt > $1.lastActivityAt }
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
        case .photo:
            guard supplied == 0 else { throw NesticError.message("This tracker stores its photo only on this iPhone.") }
        case .health:
            guard supplied == 1, let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw NesticError.message("Describe the health event before saving.")
            }
        }
    }

    private func acceptSession(_ value: String) async throws {
        let requestGeneration = generation
        let user: NestPerson = try await NestAPI(baseURL: serverURL, token: value, session: session).get("auth/me")
        try checkGeneration(requestGeneration)
        try keychain.save(NestSession(token: value, user: user), server: serverURL)
        cancelRefresh()
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
        forecastSnapshots = []
        sharedForecasts = []
        lastPublishedForecastSignature = nil
        defaults.set(false, forKey: "nestic.signedOut.\(NestCoding.serverKey(serverURL))")
        restoreArchive()
        restorePredictionPreferences()
        restoreQuietHoursPreferences()
        restoreForecastSnapshots()
        reconcileForecastSnapshots()
        errorMessage = nil
        await start()
    }

    private func loadSnapshot(nestID: UUID, api: NestAPI) async throws -> NestSnapshot {
        // The entities response includes all pinned tracker IDs in one query.
        // Avoid one request per entity during every refresh.
        async let remoteSubjects: [NestEntityResponse] = api.get("nests/\(nestID)/entities")
        async let remoteTrackers: [NestTracker] = api.get("nests/\(nestID)/actions")
        async let remoteEntries: [NestEntry] = api.get("nests/\(nestID)/events?limit=200")
        async let remoteMembers: [NestMemberResponse] = api.get("nests/\(nestID)/members")
        async let remoteRoutines: [NestRoutineResponse] = api.get("nests/\(nestID)/routines")
        let (entities, actions, events, people, routineResponses) = try await (remoteSubjects, remoteTrackers, remoteEntries, remoteMembers, remoteRoutines)
        var subjects: [NestSubject] = []
        for entity in entities {
            var subject = entity.subject()
            let cachedSubject = snapshots[nestID.uuidString]?.subjects.first { $0.id == entity.id }
            if entity.imageURL != nil, cachedSubject?.photoURL == entity.imageURL,
               let cachedPhotoData = cachedSubject?.photoData {
                // Keep the local avatar cache when the server-side photo has
                // not changed. Full refreshes must not redownload every photo.
                subject.photoData = cachedPhotoData
            } else if entity.imageURL != nil,
                      let photoBytes = try? await api.data(path: "entities/\(entity.id)/photo") {
                subject.photoData = photoBytes.base64EncodedString()
            }
            subjects.append(subject)
        }
        return NestSnapshot(subjects: subjects, trackers: actions, entries: events.sorted { $0.occurredAt > $1.occurredAt },
                            members: people.map { $0.person() }, routines: routineResponses.map { $0.routine() })
    }

    func loadOlderEntries() async throws {
        guard !isDemo, !isLoadingMoreEntries, hasMoreEntries,
              let nestID = selectedNestID, let oldest = entries.last?.occurredAt else { return }
        isLoadingMoreEntries = true
        defer { isLoadingMoreEntries = false }
        let requestGeneration = generation
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let encodedDate = formatter.string(from: oldest).addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let older: [NestEntry] = try await api().get("nests/\(nestID)/events?limit=200&before=\(encodedDate)")
        try checkGeneration(requestGeneration)
        var merged = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
        for entry in older { merged[entry.id] = entry }
        entries = merged.values.sorted { $0.occurredAt > $1.occurredAt }
        hasMoreEntries = older.count >= 200
        persist()
    }

    private func makeTracker(name: String, valueType: NestValueType, unit: String?, symbol: String? = nil, color: String? = nil, groupName: String? = nil, isPrivate: Bool = false) async throws -> NestTracker {
        let nestID = try requireNest()
        let name = try nonempty(name, label: "Tracker name")
        let trimmed = unit?.trimmingCharacters(in: .whitespacesAndNewlines)
        let unit = valueType == .number && trimmed?.isEmpty == false ? trimmed : nil
        let symbol = symbol?.trimmingCharacters(in: .whitespacesAndNewlines)
        let color = color?.trimmingCharacters(in: .whitespacesAndNewlines)
        let groupName = groupName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let existing = trackers.first(where: { $0.isPrivate == isPrivate && $0.name.lowercased() == name.lowercased() && $0.valueType == valueType && $0.unit == unit }) { return existing }
        guard canManageNest || (isPrivate && canLog) else { throw NesticError.message("Only a nest owner or admin can create shared trackers.") }
        let tracker: NestTracker
        if isDemo { tracker = .init(id: UUID(), nestId: nestID, name: name, valueType: valueType, unit: unit, symbol: symbol?.isEmpty == true ? nil : symbol, color: color?.isEmpty == true ? nil : color, groupName: groupName?.isEmpty == true ? nil : groupName, privateOwnerId: isPrivate ? currentUser?.id : nil) }
        else {
            let requestGeneration = generation
            struct Request: Encodable {
                let name: String; let valueType: NestValueType; let unit: String?; let symbol: String?
                let color: String?; let groupName: String?; let isPrivate: Bool
            }
            if isPrivate {
                struct Capabilities: Decodable { let privateTrackers: Bool }
                let capabilities: Capabilities = try await api().get("capabilities")
                guard capabilities.privateTrackers else { throw NesticError.message("Private trackers are not available yet. Please try again later.") }
            }
            tracker = try await api().post("nests/\(nestID)/actions", body: Request(name: name, valueType: valueType, unit: unit,
                                                                                         symbol: symbol?.isEmpty == true ? nil : symbol,
                                                                                         color: color?.isEmpty == true ? nil : color,
                                                                                         groupName: groupName?.isEmpty == true ? nil : groupName, isPrivate: isPrivate))
            try checkGeneration(requestGeneration)
        }
        if !trackers.contains(where: { $0.id == tracker.id }) { allTrackers.append(tracker) }
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

    private func isBadWebSocketHandshake(_ error: Error?) -> Bool {
        guard let error else { return false }
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorBadServerResponse
    }

    private func beginLoading() { loadingCount += 1; isLoading = true }
    private func endLoading() { loadingCount = max(0, loadingCount - 1); isLoading = loadingCount > 0 }

    private func handle(_ error: Error) {
        if error is CancellationError { return }
        if case NesticError.staleSession = error { return }
        if case NesticError.unauthorized = error {
            signOut()
        } else if !isDemo {
            connectionStatus = "Offline · showing saved data"
        }
        errorMessage = error.localizedDescription
    }

    private func refreshAfterMutation() async {
        if isDemo, let nestID = selectedNestID { await reminderStore?.updateDoseReminders(entries: entries, nestID: nestID) }
        guard !isDemo else { return }
        if let nestID = selectedNestID, reminderStore?.reminders(for: nestID).contains(where: { $0.cadence == .afterDose }) == true {
            if let values: [NestReminderResponse] = try? await api().get("nests/\(nestID)/reminders") {
                reminderStore?.replaceReminders(values.map { $0.reminder() }, for: nestID)
                await reminderStore?.sync()
            }
        }
        // The mutation already succeeded. A failed catch-up must not ask the user to submit it twice.
        do { try await refresh(presentConnectionError: false, force: false, minimumInterval: 5) }
        catch { }
    }

    private var archiveKey: String? {
        if isDemo { return "nestic.demo.v1" }
        guard let currentUser else { return nil }
        return "nestic.cache.v1.\(NestCoding.serverKey(serverURL)).\(currentUser.id.uuidString)"
    }

    private func persist() {
        guard let currentUser, let archiveKey else { return }
        if let selectedNestID {
            snapshots[selectedNestID.uuidString] = NestSnapshot(subjects: subjects, trackers: allTrackers, entries: entries,
                                                                members: members, routines: routines)
        }
        let archive = NestArchive(user: currentUser, nests: nests, selectedNestID: selectedNestID, snapshots: snapshots)
        do { defaults.set(try NestCoding.encoder().encode(archive), forKey: archiveKey) }
        catch { errorMessage = "Couldn’t save updates on this device. \(error.localizedDescription)" }
        persistPredictionPreferences()
        persistForecastSnapshots()
        refreshWidget()
        publishWatchSnapshot()
    }

    func publishWatchSnapshot() {
        guard !isDemo, let currentUser else { return }
        NesticWatchBridge.shared.publish(serverURL: serverURL, token: token, user: currentUser,
                                         nests: nests, selectedNestID: selectedNestID,
                                         snapshot: NestSnapshot(subjects: subjects, trackers: allTrackers,
                                                                entries: entries, members: members,
                                                                routines: routines))
    }

    private var predictionPreferencesKey: String {
        if isDemo { return "nestic.predictions.demo.v1" }
        guard let currentUser else { return "nestic.predictions.anonymous.v1" }
        return "nestic.predictions.\(NestCoding.serverKey(serverURL)).\(currentUser.id.uuidString).v1"
    }

    private var quietHoursPreferencesKey: String {
        let nestKey = selectedNestID?.uuidString ?? "none"
        if isDemo { return "nestic.quiet-hours.demo.\(nestKey)" }
        guard let currentUser else { return "nestic.quiet-hours.anonymous.\(nestKey)" }
        return "nestic.quiet-hours.\(NestCoding.serverKey(serverURL)).\(currentUser.id.uuidString).\(nestKey)"
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

    private func persistQuietHoursPreferences() {
        guard let data = try? NestCoding.encoder().encode(quietHoursPreferences) else { return }
        defaults.set(data, forKey: quietHoursPreferencesKey)
    }

    private func restoreQuietHoursPreferences() {
        guard selectedNestID != nil,
              let data = defaults.data(forKey: quietHoursPreferencesKey),
              let preferences = try? NestCoding.decoder().decode(NestQuietHoursPreferences.self, from: data) else {
            quietHoursPreferences = NestQuietHoursPreferences()
            return
        }
        quietHoursPreferences = preferences
    }

    private var settingsDirtyKey: String {
        let nestKey = selectedNestID?.uuidString ?? "none"
        guard let currentUser else {
            return "nestic.settings-dirty.anonymous.\(NestCoding.serverKey(serverURL)).\(nestKey)"
        }
        return "nestic.settings-dirty.\(NestCoding.serverKey(serverURL)).\(currentUser.id.uuidString).\(nestKey)"
    }

    private func settingsJSON<T: Encodable>(_ value: T) -> String? {
        guard let data = try? NestCoding.encoder().encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func applyServerSettings(_ remote: NestUserSettingsResponse, nestID: UUID, subjectIDs: Set<UUID>) {
        guard !defaults.bool(forKey: settingsDirtyKey) else {
            scheduleSettingsSync()
            return
        }

        var shouldUploadLocalSettings = false
        if let raw = remote.predictionPreferencesJSON,
           let data = raw.data(using: .utf8),
           let preferences = try? NestCoding.decoder().decode([UUID: NestPredictionPreferences].self, from: data) {
            predictionPreferences = predictionPreferences.filter { !subjectIDs.contains($0.key) }
            predictionPreferences.merge(preferences) { _, remote in remote }
            persistPredictionPreferences()
        } else if predictionPreferences.contains(where: { subjectIDs.contains($0.key) }) {
            shouldUploadLocalSettings = true
        }

        if let raw = remote.quietHoursJSON,
           let data = raw.data(using: .utf8),
           let preferences = try? NestCoding.decoder().decode(NestQuietHoursPreferences.self, from: data) {
            quietHoursPreferences = preferences
            persistQuietHoursPreferences()
        } else if !quietHoursPreferences.periods.isEmpty || quietHoursPreferences.confidenceThresholdPercent != 80 {
            shouldUploadLocalSettings = true
        }

        if let raw = remote.remindersJSON,
           let data = raw.data(using: .utf8),
           let reminders = try? NestCoding.decoder().decode([NesticReminder].self, from: data) {
            reminderStore?.replaceReminders(reminders, for: nestID)
        } else if !(reminderStore?.remindersForSync(nestID: nestID).isEmpty ?? true) {
            shouldUploadLocalSettings = true
        }

        if shouldUploadLocalSettings {
            markSettingsChanged()
        }
        refreshWidget()
    }

    private var forecastSnapshotsKey: String {
        if isDemo { return "nestic.forecasts.demo.v1" }
        guard let currentUser else { return "nestic.forecasts.anonymous.v1" }
        return "nestic.forecasts.\(NestCoding.serverKey(serverURL)).\(currentUser.id.uuidString).v1"
    }

    private func persistForecastSnapshots() {
        guard let data = try? NestCoding.encoder().encode(forecastSnapshots) else { return }
        defaults.set(data, forKey: forecastSnapshotsKey)
    }

    private func restoreForecastSnapshots() {
        guard let data = defaults.data(forKey: forecastSnapshotsKey),
              let snapshots = try? NestCoding.decoder().decode([ForecastSnapshot].self, from: data) else {
            forecastSnapshots = []
            return
        }
        forecastSnapshots = Array(snapshots.suffix(300))
    }

    private func reconcileForecastSnapshots() {
        evaluateForecasts(with: entries)
    }

    private func evaluateForecasts(with candidateEntries: [NestEntry]) {
        guard !forecastSnapshots.isEmpty else { return }
        var changed = false
        for entry in candidateEntries.sorted(by: { $0.occurredAt < $1.occurredAt }) {
            for index in forecastSnapshots.indices {
                var snapshot = forecastSnapshots[index]
                guard snapshot.actualEventAt == nil,
                      entry.shouldIncludeInPredictions,
                      snapshot.subjectID == entry.entityId,
                      snapshot.targetTrackerID == entry.actionId,
                      entry.occurredAt > snapshot.lastEventAt,
                      entry.occurredAt >= snapshot.createdAt else { continue }
                let actual = entry.occurredAt
                let baselineError = abs(actual.timeIntervalSince(snapshot.baselinePredictedAt)) / 3600
                let contextualError = snapshot.contextualPredictedAt.map {
                    abs(actual.timeIntervalSince($0)) / 3600
                }
                snapshot.actualEventAt = actual
                snapshot.evaluatedAt = Date()
                snapshot.baselineErrorHours = baselineError
                snapshot.contextualErrorHours = contextualError
                snapshot.selectedErrorHours = snapshot.selectedModel == .contextual
                    ? contextualError
                    : baselineError
                forecastSnapshots[index] = snapshot
                changed = true
            }
        }
        if changed {
            persistForecastSnapshots()
            refreshWidget()
        }
    }

    private func invalidateForecastOutcomes(for entry: NestEntry) {
        var changed = false
        for index in forecastSnapshots.indices {
            var snapshot = forecastSnapshots[index]
            guard snapshot.subjectID == entry.entityId,
                  snapshot.targetTrackerID == entry.actionId,
                  snapshot.actualEventAt == entry.occurredAt else { continue }
            snapshot.actualEventAt = nil
            snapshot.evaluatedAt = nil
            snapshot.baselineErrorHours = nil
            snapshot.contextualErrorHours = nil
            snapshot.selectedErrorHours = nil
            forecastSnapshots[index] = snapshot
            changed = true
        }
        if changed {
            persistForecastSnapshots()
            refreshWidget()
        }
    }

    @discardableResult
    private func captureForecasts(for subject: NestSubject, predictions: [EventPrediction], now: Date) -> Bool {
        var changed = false
        for prediction in predictions {
            guard let targetTrackerID = prediction.targetTrackerID else { continue }
            let alreadyRecorded = forecastSnapshots.contains { snapshot in
                snapshot.subjectID == subject.id &&
                    snapshot.targetTrackerID == targetTrackerID &&
                    abs(snapshot.lastEventAt.timeIntervalSince(prediction.lastEventAt)) < 0.5
            }
            guard !alreadyRecorded else { continue }
            forecastSnapshots.append(ForecastSnapshot(
                id: UUID(),
                subjectID: subject.id,
                targetTrackerID: targetTrackerID,
                lastEventAt: prediction.lastEventAt,
                createdAt: now,
                selectedModel: prediction.model,
                selectedPredictedAt: prediction.predictedAt,
                baselinePredictedAt: prediction.baselinePredictedAt,
                contextualPredictedAt: prediction.contextualPredictedAt,
                actualEventAt: nil,
                evaluatedAt: nil,
                baselineErrorHours: nil,
                contextualErrorHours: nil,
                selectedErrorHours: nil
            ))
            changed = true
        }
        if forecastSnapshots.count > 300 {
            forecastSnapshots = Array(forecastSnapshots.suffix(300))
        }
        return changed
    }

    private func refreshWidget() {
        guard let defaultSubject = subjects.first(where: { $0.kind == .pet }) ?? subjects.first else {
            NesticWidgetBridge.clear()
            return
        }
        var widgetPredictions: [UUID: [UUID: EventPrediction]] = [:]
        var localForecastPayload: [NestSharedForecast] = []
        var forecastsChanged = false
        if isDemo || predictionAccess {
            let now = Date()
            for subject in subjects {
                let localPredictions = localPredictions(for: subject, now: now)
                if let nestID = selectedNestID {
                    localForecastPayload.append(contentsOf: localPredictions.compactMap { prediction in
                        guard let trackerID = prediction.targetTrackerID else { return nil }
                        return NestSharedForecast(nestId: nestID, subjectId: subject.id,
                                                  trackerId: trackerID, prediction: prediction,
                                                  computedAt: now)
                    })
                }
                let subjectPredictions: [UUID: EventPrediction] = Dictionary(uniqueKeysWithValues: predictions(for: subject, now: now).compactMap { prediction in
                    guard let targetID = prediction.targetTrackerID else { return nil }
                    return (targetID, prediction)
                })
                forecastsChanged = captureForecasts(for: subject,
                                                    predictions: Array(subjectPredictions.values),
                                                    now: Date()) || forecastsChanged
                widgetPredictions[subject.id] = subjectPredictions
            }
            scheduleSharedForecastSync(localForecastPayload)
        }
        if forecastsChanged { persistForecastSnapshots() }
        NesticWidgetBridge.refresh(defaultSubject: defaultSubject, subjects: subjects, trackers: trackers,
                                   entries: entries, routines: routines, predictions: widgetPredictions,
                                   hasPredictionAccess: isDemo || predictionAccess, quietHours: quietHoursPreferences.periods)
    }

    func handleDeepLink(_ url: URL) async {
        guard url.scheme == "nestic", let host = url.host,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }

        if host == "care" {
            guard let token = components.queryItems?.first(where: { $0.name == "token" })?.value,
                  !token.isEmpty else { return }
            let suppliedServerURL = components.queryItems?.first(where: { $0.name == "server" })?.value
            await openCareLink(token: token, serverURL: suppliedServerURL)
            return
        }

        guard let subjectValue = components.queryItems?.first(where: { $0.name == "subjectID" })?.value,
              let subjectID = UUID(uuidString: subjectValue) else { return }

        switch host {
        case "subject":
            pendingNavigation = .subject(subjectID)
        case "record":
            guard let trackerValue = components.queryItems?.first(where: { $0.name == "trackerID" })?.value,
                  let trackerID = UUID(uuidString: trackerValue) else { return }
            pendingNavigation = .record(subjectID: subjectID, trackerID: trackerID)
        case "insights":
            guard let trackerValue = components.queryItems?.first(where: { $0.name == "trackerID" })?.value,
                  let trackerID = UUID(uuidString: trackerValue) else { return }
            do { try await log(subjectID: subjectID, trackerID: trackerID) }
            catch { errorMessage = error.localizedDescription }
            pendingNavigation = .insights(subjectID)
        case "log":
            guard let trackerValue = components.queryItems?.first(where: { $0.name == "trackerID" })?.value,
                  let trackerID = UUID(uuidString: trackerValue) else { return }
            do { try await log(subjectID: subjectID, trackerID: trackerID) }
            catch { errorMessage = error.localizedDescription }
        default:
            return
        }
    }

    func consumePendingNavigation() -> NesticNavigationDestination? {
        defer { pendingNavigation = nil }
        return pendingNavigation
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
        restoreQuietHoursPreferences()
        applySnapshot(selectedNestID.flatMap { snapshots[$0.uuidString] } ?? NestSnapshot())
    }

    private func applySnapshot(_ snapshot: NestSnapshot) {
        let previousAudience = trackers.map { ($0.id, Set($0.allowedMemberIDs ?? []), $0.privateOwnerId) }
        let audienceChanged = snapshot.trackers.contains { incoming in
            previousAudience.contains { id, readers, owner in id == incoming.id && (readers != Set(incoming.allowedMemberIDs ?? []) || owner != incoming.privateOwnerId) }
        } || trackers.contains { old in old.isPrivate && !snapshot.trackers.contains { $0.id == old.id } }
        if audienceChanged {
            forecastSnapshots.removeAll()
            persistForecastSnapshots()
        }
        subjects = snapshot.subjects
        allTrackers = snapshot.trackers
        entries = snapshot.entries.sorted { $0.occurredAt > $1.occurredAt }
        members = snapshot.members
        routines = snapshot.routines
        hasMoreEntries = !isDemo && entries.count >= 200
    }

    private func cancelRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
        lastSuccessfulRefreshAt = nil
    }

    private func disconnectRealtime() {
        realtimeRefreshTask?.cancel()
        realtimeRefreshTask = nil
        realtimeRefreshRequested = false
        realtimeTask?.cancel()
        realtimeTask = nil
        heartbeatTask?.cancel()
        heartbeatTask = nil
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        socketNestID = nil
    }

    private func connectRealtimeIfNeeded() {
        guard appIsActive, !isDemo, token != nil, let nestID = selectedNestID else { return }
        if let retryNotBefore = realtimeRetryNotBefore, retryNotBefore > Date() { return }
        guard socketNestID != nestID || realtimeTask == nil else { return }
        disconnectRealtime()
        socketNestID = nestID
        let requestGeneration = generation
        realtimeTask = Task { [weak self] in
            await self?.runRealtime(nestID: nestID, requestGeneration: requestGeneration)
        }
    }

    private func scheduleRealtimeRefresh() {
        guard appIsActive else { return }
        realtimeRefreshRequested = true
        guard realtimeRefreshTask == nil else { return }

        realtimeRefreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.realtimeRefreshTask = nil
                self.realtimeRefreshRequested = false
            }
            do {
                while !Task.isCancelled, self.appIsActive {
                    // Collapse a burst of changes into one authoritative fetch.
                    try await Task.sleep(for: .milliseconds(750))
                    guard self.realtimeRefreshRequested else { return }
                    self.realtimeRefreshRequested = false
                    try await self.refresh(presentConnectionError: false, force: false, minimumInterval: 2)
                    if !self.realtimeRefreshRequested { return }
                }
            } catch { }
        }
    }

    private func runRealtime(nestID: UUID, requestGeneration: UUID) async {
        defer {
            // A failed realtime connection should not keep a background task
            // alive forever. The next foreground refresh can start it again.
            if generation == requestGeneration {
                realtimeTask = nil
                socket = nil
                heartbeatTask = nil
            }
        }
        var failures = 0
        var usingQueryTokenFallback = false
        let maximumFailures = 6
        while !Task.isCancelled, generation == requestGeneration, let token {
            let shouldRefreshAfterReconnect = failures > 0
            guard var url = URLComponents(string: serverURL + "/ws") else { return }
            url.scheme = url.scheme == "https" ? "wss" : "ws"
            if usingQueryTokenFallback {
                var queryItems = url.queryItems ?? []
                queryItems.append(URLQueryItem(name: "token", value: token))
                url.queryItems = queryItems
            }
            guard let websocketURL = url.url else { return }
            var request = URLRequest(url: websocketURL)
            if !usingQueryTokenFallback {
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            request.timeoutInterval = 20
            let socket = session.webSocketTask(with: request)
            self.socket = socket
            connectionStatus = failures == 0 ? "Connecting…" : "Offline · showing saved data"
            socket.resume()
            heartbeatTask = Task { [weak self, weak socket] in
                while !Task.isCancelled {
                    do {
                        // One low-frequency liveness check while the app is
                        // foregrounded. Background connections are closed.
                        try await Task.sleep(for: .seconds(45))
                        guard let socket else { return }
                        // URLSession normally calls a ping completion handler once, but a
                        // connection being torn down can race its completion on some OS
                        // versions. A checked continuation traps if that happens, turning a
                        // recoverable socket failure into an app crash. Serialize completion
                        // and accept only the first result from this one ping.
                        let completionLock = NSLock()
                        var pingCompleted = false
                        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                            socket.sendPing { error in
                                completionLock.lock()
                                defer { completionLock.unlock() }
                                guard !pingCompleted else { return }
                                pingCompleted = true
                                if let error { continuation.resume(throwing: error) }
                                else { continuation.resume() }
                            }
                        }
                    } catch {
                        guard !Task.isCancelled else { return }
                        self?.connectionStatus = "Offline · showing saved data"
                        socket?.cancel(with: .goingAway, reason: nil)
                        return
                    }
                }
            }
            var lastError: Error?
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
                        if shouldRefreshAfterReconnect {
                            // Reconnects may have missed events while the socket
                            // was down, so fetch one authoritative snapshot.
                            try await refresh(presentConnectionError: false, force: true)
                        }
                        failures = 0
                        realtimeRetryNotBefore = nil
                        connectionStatus = "Live · up to date"
                    } else {
                        // Fetching the authoritative snapshot catches deletes,
                        // role changes, and changes from another device. Debounce
                        // events so a burst does not create a request per event.
                        scheduleRealtimeRefresh()
                    }
                }
            } catch {
                lastError = error
                guard !Task.isCancelled, generation == requestGeneration else { break }
                connectionStatus = "Offline · showing saved data"
                if case NesticError.unauthorized = error { handle(error); break }
            }
            heartbeatTask?.cancel()
            socket.cancel(with: .goingAway, reason: nil)
            guard !Task.isCancelled, generation == requestGeneration else { break }
            if !usingQueryTokenFallback, isBadWebSocketHandshake(lastError) {
                // Some hosted WebSocket proxies do not forward Authorization during
                // the upgrade even though normal HTTPS requests preserve it. The
                // server already supports this fallback for WebSocket clients.
                usingQueryTokenFallback = true
                failures = 0
                continue
            }
            failures += 1
            if failures >= maximumFailures {
                realtimeRetryNotBefore = Date().addingTimeInterval(5 * 60)
                connectionStatus = "Offline · showing saved data"
                break
            }
            let baseDelay = min(pow(2, Double(min(failures, 5))), 30)
            let jitteredDelay = baseDelay * Double.random(in: 0.8...1.2)
            do { try await Task.sleep(for: .seconds(jitteredDelay)) }
            catch { break }
        }
    }
}
