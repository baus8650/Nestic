import Foundation
import Security
import CryptoKit

enum NesticAppLinks {
    /// Production API origin used by Release and TestFlight builds.
    static let apiBaseURL = "https://api.nestic-app.com"
    static let privacyURL = URL(string: "https://www.nestic-app.com/privacy")!
    static let supportURL = URL(string: "https://www.nestic-app.com/support")!
    static let termsURL = URL(string: "https://www.nestic-app.com/terms")!
    static let termsVersion = "2026-10-05"
    static let appLicenseURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    static let subscriptionsURL = URL(string: "https://apps.apple.com/account/subscriptions")!
}

enum NestCoding {
    /// Consume the entire input so a typo such as "12abc" cannot become a valid log.
    static func parseAmount(_ input: String, locale: Locale = .current) -> Double? {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let separator = locale.decimalSeparator ?? "."
        let normalized = value.replacingOccurrences(of: separator, with: ".")
        guard normalized.range(of: #"^[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)$"#, options: .regularExpression) != nil,
              let number = Double(normalized), number.isFinite else { return nil }
        return number
    }

    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: string) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: string) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO 8601 date: \(string)")
        }
        return decoder
    }

    static func serverKey(_ server: String) -> String {
        SHA256.hash(data: Data(server.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func validatedServer(_ input: String) throws -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed),
              ["https", "http"].contains(components.scheme?.lowercased() ?? ""),
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil else {
            throw NesticError.message("Enter a full server address, such as \(NesticAppLinks.apiBaseURL).")
        }
        components.scheme = components.scheme?.lowercased()
        components.host = host.lowercased()
        while components.path.hasSuffix("/") { components.path.removeLast() }
        guard let normalized = components.url?.absoluteString else {
            throw NesticError.message("That server address is not valid.")
        }
        return normalized
    }
}

struct NestAPI {
    let baseURL: String
    let token: String?
    var session: URLSession = .shared

    func data(path: String, method: String = "GET", body: Data? = nil, authorization: String? = nil, contentType: String = "application/json") async throws -> Data {
        guard let url = URL(string: baseURL + "/" + path) else {
            throw NesticError.message("The server address is invalid.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        if let authorization {
            request.setValue(authorization, forHTTPHeaderField: "Authorization")
        } else if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw NesticError.message("Couldn’t reach your nest’s server. Check your connection and server address. Your saved data is still available on this device.")
        }
        guard let http = response as? HTTPURLResponse else {
            throw NesticError.message("The server sent an unreadable response.")
        }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 428 { throw NesticError.termsAcceptanceRequired }
            if http.statusCode == 401, token != nil { throw NesticError.unauthorized }
            struct Failure: Decodable { var reason: String? }
            let reason = (try? JSONDecoder().decode(Failure.self, from: data).reason)
            if http.statusCode == 401 {
                throw NesticError.message("That email and password didn’t match. Please try again.")
            }
            throw NesticError.message(reason ?? "The server couldn’t complete that request (\(http.statusCode)).")
        }
        return data
    }

    func get<T: Decodable>(_ path: String, as type: T.Type = T.self) async throws -> T {
        try NestCoding.decoder().decode(type, from: await data(path: path))
    }

    func post<T: Encodable, R: Decodable>(_ path: String, body: T, as type: R.Type = R.self) async throws -> R {
        let encoded = try NestCoding.encoder().encode(body)
        return try NestCoding.decoder().decode(type, from: await data(path: path, method: "POST", body: encoded))
    }

    func patch<T: Encodable, R: Decodable>(_ path: String, body: T, as type: R.Type = R.self) async throws -> R {
        let encoded = try NestCoding.encoder().encode(body)
        return try NestCoding.decoder().decode(type, from: await data(path: path, method: "PATCH", body: encoded))
    }

    func put<T: Encodable, R: Decodable>(_ path: String, body: T, as type: R.Type = R.self) async throws -> R {
        let encoded = try NestCoding.encoder().encode(body)
        return try NestCoding.decoder().decode(type, from: await data(path: path, method: "PUT", body: encoded))
    }

    func upload<R: Decodable>(_ path: String, body: Data, contentType: String,
                              method: String = "PUT", as type: R.Type = R.self) async throws -> R {
        try NestCoding.decoder().decode(type, from: await data(path: path, method: method, body: body, contentType: contentType))
    }

    func delete<R: Decodable>(_ path: String, as type: R.Type = R.self) async throws -> R {
        try NestCoding.decoder().decode(type, from: await data(path: path, method: "DELETE"))
    }

    func delete(_ path: String) async throws {
        _ = try await data(path: path, method: "DELETE")
    }
}

struct NestSession: Codable {
    var token: String
    var user: NestPerson
}

struct NestKeychain {
    private let service = "com.nestic.app.session.v1"

    func save(_ session: NestSession, server: String) throws {
        let data = try NestCoding.encoder().encode(session)
        let query = key(server)
        let update = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else { throw error(updateStatus) }
        var insert = query
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(insert as CFDictionary, nil)
        guard status == errSecSuccess else { throw error(status) }
    }

    func load(server: String) throws -> NestSession? {
        var query = key(server)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw error(status) }
        guard let data = result as? Data else { return nil }
        return try NestCoding.decoder().decode(NestSession.self, from: data)
    }

    func delete(server: String) throws {
        let status = SecItemDelete(key(server) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw error(status) }
    }

    private func key(_ server: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: NestCoding.serverKey(server)]
    }

    private func error(_ status: OSStatus) -> NesticError {
        .message("Couldn’t access your secure sign-in details (\(status)). Please try again.")
    }
}

struct NestEntityResponse: Decodable {
    let id: UUID
    let nestId: UUID
    let name: String
    let kind: NestSubjectKind
    let metadata: [String: String]?
    let imageURL: String?
    let pinnedActionIDs: [UUID]?
    func subject(pins: [UUID]? = nil) -> NestSubject {
        let resolvedPins = pins ?? pinnedActionIDs ?? []
        return .init(id: id, nestId: nestId, name: name, kind: kind,
                     emoji: metadata?["emoji"] ?? kind.emoji,
                     pinnedActionIDs: resolvedPins,
                     photoData: metadata?["photoData"],
                     photoURL: imageURL, metadata: metadata)
    }
}

struct NestMemberResponse: Decodable {
    let userId: UUID
    let email: String
    let displayName: String?
    let role: String
    func person() -> NestPerson {
        .init(id: userId, email: email, displayName: displayName ?? email.components(separatedBy: "@").first ?? email, role: role)
    }
}

struct NestRoutineResponse: Decodable {
    let id: UUID
    let nestId: UUID
    let entityId: UUID
    let name: String
    let items: [NestRoutineItem]
    let targets: [NestRoutineTarget]?
    let createdAt: Date?
    let updatedAt: Date?
    let privateOwnerId: UUID?

    func routine() -> NestRoutine {
        .init(id: id, nestId: nestId, subjectID: entityId, name: name, items: items,
              targets: targets ?? [],
              createdAt: createdAt, updatedAt: updatedAt, privateOwnerId: privateOwnerId)
    }
}

struct NestCareLinkResponse: Decodable {
    let id: UUID
    let nestId: UUID
    let label: String
    let expiresAt: Date
    let entityIDs: [UUID]
    let actionIDs: [UUID]
    let canLog: Bool
    let canViewHistory: Bool
    let revokedAt: Date?
    let createdAt: Date?
    let token: String?

    func link() -> NestCareLink {
        .init(id: id, nestId: nestId, label: label, expiresAt: expiresAt,
              entityIDs: entityIDs, actionIDs: actionIDs, canLog: canLog,
              canViewHistory: canViewHistory, revokedAt: revokedAt,
              createdAt: createdAt, token: token)
    }
}

struct NestCareLinkActionResponse: Decodable {
    let id: UUID
    let nestId: UUID
    let name: String
    let valueType: NestValueType
    let unit: String?
    let symbol: String?
    let color: String?
    let groupName: String?

    func tracker() -> NestTracker {
        .init(id: id, nestId: nestId, name: name, valueType: valueType,
              unit: unit, symbol: symbol, color: color, groupName: groupName)
    }
}

struct NestCareLinkSnapshotResponse: Decodable {
    let link: NestCareLinkResponse
    let nestName: String
    let entities: [NestEntityResponse]
    let actions: [NestCareLinkActionResponse]
    let routines: [NestRoutineResponse]
    let events: [NestEntry]

    func snapshot() -> NestCareSnapshot {
        NestCareSnapshot(
            link: link.link(),
            nestName: nestName,
            subjects: entities.map { $0.subject() },
            trackers: actions.map { $0.tracker() },
            routines: routines.map { $0.routine() },
            entries: events.sorted { $0.occurredAt > $1.occurredAt }
        )
    }
}

struct NestCareLinkCreateRequest: Encodable {
    let label: String
    let expiresAt: Date
    let entityIDs: [UUID]
    let actionIDs: [UUID]
    let canLog: Bool
    let canViewHistory: Bool
}

struct NestCareEventRequest: Encodable {
    let entityID: UUID
    let actionID: UUID
    let occurredAt: Date?
    let valueNumber: Double?
    let valueText: String?
    let valueBool: Bool?
    let valueJSON: [String: String]?
    let note: String?
    let wasAccident: Bool?
    let includeInPredictions: Bool?
}

struct NestCareRoutineRequest: Encodable {
    let occurredAt: Date?
    let note: String?
}

struct NestPinResponse: Decodable { let actionId: UUID }

struct NestUserSettingsResponse: Decodable {
    let predictionPreferencesJSON: String?
    let quietHoursJSON: String?
    let remindersJSON: String?
    let updatedAt: Date?
}

/// The server's nest-scoped forecast payload. The forecast model is still
/// learned privately on a member's device; this is only the shared result that
/// every member should display.
struct NestSharedForecast: Codable, Hashable, Sendable, Identifiable {
    let id: UUID
    let nestId: UUID
    let subjectId: UUID
    let trackerId: UUID
    let predictedAt: Date
    let baselinePredictedAt: Date
    let contextualPredictedAt: Date?
    let model: String
    let intervalHours: Double
    let confidence: Double
    let sampleCount: Int
    let validationSampleCount: Int
    let expectedErrorHours: Double?
    let predictionWindowHours: Double
    let targetNames: [String]
    let inputNames: [String]
    let lastEventAt: Date
    let computedAt: Date
    let updatedAt: Date?

    init(id: UUID, nestId: UUID, subjectId: UUID, trackerId: UUID,
         predictedAt: Date, baselinePredictedAt: Date, contextualPredictedAt: Date?,
         model: String, intervalHours: Double, confidence: Double,
         sampleCount: Int, validationSampleCount: Int, expectedErrorHours: Double?,
         predictionWindowHours: Double, targetNames: [String], inputNames: [String],
         lastEventAt: Date, computedAt: Date, updatedAt: Date?) {
        self.id = id
        self.nestId = nestId
        self.subjectId = subjectId
        self.trackerId = trackerId
        self.predictedAt = predictedAt
        self.baselinePredictedAt = baselinePredictedAt
        self.contextualPredictedAt = contextualPredictedAt
        self.model = model
        self.intervalHours = intervalHours
        self.confidence = confidence
        self.sampleCount = sampleCount
        self.validationSampleCount = validationSampleCount
        self.expectedErrorHours = expectedErrorHours
        self.predictionWindowHours = predictionWindowHours
        self.targetNames = targetNames
        self.inputNames = inputNames
        self.lastEventAt = lastEventAt
        self.computedAt = computedAt
        self.updatedAt = updatedAt
    }
}

struct NestSharedForecastUpsert: Encodable {
    let subjectId: UUID
    let trackerId: UUID
    let predictedAt: Date
    let baselinePredictedAt: Date
    let contextualPredictedAt: Date?
    let model: String
    let intervalHours: Double
    let confidence: Double
    let sampleCount: Int
    let validationSampleCount: Int
    let expectedErrorHours: Double?
    let predictionWindowHours: Double
    let targetNames: [String]
    let inputNames: [String]
    let lastEventAt: Date
    let computedAt: Date
    let inputTrackerIDs: [UUID]

    init(_ forecast: NestSharedForecast, inputTrackerIDs: [UUID] = []) {
        self.inputTrackerIDs = inputTrackerIDs
        subjectId = forecast.subjectId
        trackerId = forecast.trackerId
        predictedAt = forecast.predictedAt
        baselinePredictedAt = forecast.baselinePredictedAt
        contextualPredictedAt = forecast.contextualPredictedAt
        model = forecast.model
        intervalHours = forecast.intervalHours
        confidence = forecast.confidence
        sampleCount = forecast.sampleCount
        validationSampleCount = forecast.validationSampleCount
        expectedErrorHours = forecast.expectedErrorHours
        predictionWindowHours = forecast.predictionWindowHours
        targetNames = forecast.targetNames
        inputNames = forecast.inputNames
        lastEventAt = forecast.lastEventAt
        computedAt = forecast.computedAt
    }
}

#if !os(watchOS)
struct NestReminderResponse: Decodable {
    let routineID: UUID?
    let recurrenceDays: Int?
    let startFromFirstTracking: Bool?
    let id: UUID
    let nestId: UUID
    let subjectId: UUID
    let subjectName: String
    let trackerId: UUID
    let trackerName: String
    let cadence: NesticReminderCadence
    let linkedTrackerId: UUID?
    let linkedTrackerName: String?
    let delayMinutes: Int
    let anchorDate: Date
    let hour: Int
    let minute: Int
    let createdByUserId: UUID
    let createdByName: String
    let intervalHours: Double?
    let totalPills: Int?
    let lastDoseAt: Date?
    let pillsTaken: Double?
    let notificationsEnabled: Bool
    let deliveryMode: String?

    func reminder() -> NesticReminder {
        NesticReminder(id: id, nestID: nestId, subjectID: subjectId, subjectName: subjectName,
                       medicationTrackerID: trackerId, medicationName: trackerName,
                       cadence: cadence, linkedMealTrackerID: linkedTrackerId,
                       linkedMealName: linkedTrackerName, delayMinutes: delayMinutes,
                       anchorDate: anchorDate, hour: hour, minute: minute,
                       enabled: notificationsEnabled, createdByName: createdByName,
                       isShared: true, intervalHours: intervalHours, totalPills: totalPills,
                       lastDoseAt: lastDoseAt, pillsTaken: pillsTaken, deliveryMode: deliveryMode, routineID: routineID, recurrenceDays: recurrenceDays, startFromFirstTracking: startFromFirstTracking)
    }
}
#endif

struct NestFeedbackCreateRequest: Encodable {
    let subject: String
    let category: String
    let message: String
}

struct NestFeedbackMessageRequest: Encodable {
    let message: String
}
