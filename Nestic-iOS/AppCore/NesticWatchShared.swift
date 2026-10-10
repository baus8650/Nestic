import Foundation

/// Small, Codable messages shared by the iPhone companion and the watch
/// extension. The watch receives a complete current snapshot so it can render
/// and record without opening the phone app.
enum NesticWatchTransfer {
    static let applicationContextKey = "nestic.watch.context.v1"
    static let snapshotRequestKey = "nestic.watch.request-context.v1"
    static let logRequestKey = "nestic.watch.log.v1"
    static let routineLogRequestKey = "nestic.watch.routine.log.v1"
    static let logAckKey = "nestic.watch.log.ack.v1"
}

struct NesticWatchPayload: Codable, Sendable {
    var serverURL: String
    var token: String?
    var user: NestPerson
    var nests: [NestSpace]
    var selectedNestID: UUID?
    var snapshot: NestSnapshot
}

struct NesticWatchLogRequest: Codable, Identifiable, Sendable {
    var id: UUID
    var serverURL: String
    var nestID: UUID
    var subjectID: UUID
    var trackerID: UUID
    var occurredAt: Date
    var valueNumber: Double?
    var valueText: String?
    var valueBool: Bool?
    var valueJSON: [String: String]?
    var note: String?
}

struct NesticWatchRoutineLogRequest: Codable, Identifiable, Sendable {
    var id: UUID
    var serverURL: String
    var nestID: UUID
    var routineID: UUID
    var occurredAt: Date
    var note: String?
}
