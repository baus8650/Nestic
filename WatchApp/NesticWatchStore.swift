import Foundation
import Security
import SwiftUI
import WatchKit

@MainActor
final class NesticWatchStore: ObservableObject {
    static let shared = NesticWatchStore()

    @Published private(set) var payload: NesticWatchPayload?
    @Published private(set) var pendingRequests: [NesticWatchLogRequest] = []
    @Published private(set) var pendingRoutineRequests: [NesticWatchRoutineLogRequest] = []
    @Published private(set) var isSyncing = false
    @Published private(set) var isRefreshing = false
    @Published var statusMessage: String?
    @Published private(set) var isRecording = false
    @Published private(set) var recordingReceipt: NesticWatchRecordingReceipt?

    private let defaults = UserDefaults.standard
    private let pendingKey = "nestic.watch.pending.v1"
    private let pendingRoutineKey = "nestic.watch.pending-routines.v1"
    private let payloadKey = "nestic.watch.payload.v1"
    private let tokenStore = NesticWatchTokenStore()

    private init() {
        if let data = defaults.data(forKey: payloadKey),
           let saved = try? NestCoding.decoder().decode(NesticWatchPayload.self, from: data) {
            payload = saved
        }
        if let data = defaults.data(forKey: pendingKey),
           let saved = try? NestCoding.decoder().decode([NesticWatchLogRequest].self, from: data) {
            pendingRequests = saved
        }
        if let data = defaults.data(forKey: pendingRoutineKey),
           let saved = try? NestCoding.decoder().decode([NesticWatchRoutineLogRequest].self, from: data) {
            pendingRoutineRequests = saved
        }

        let connectivity = NesticWatchConnectivity.shared
        connectivity.onContextData = { [weak self] data in
            Task { @MainActor in self?.applyContext(data) }
        }
        connectivity.onLogAcknowledged = { [weak self] id in
            Task { @MainActor in self?.acknowledge(id) }
        }
        connectivity.onSyncStatus = { [weak self] syncing, message in
            Task { @MainActor in
                self?.isSyncing = syncing
                self?.statusMessage = message
            }
        }
        connectivity.start()
    }

    var subjects: [NestSubject] { payload?.snapshot.subjects ?? [] }
    var routines: [NestRoutine] { payload?.snapshot.routines ?? [] }

    func routineTargets(for routine: NestRoutine) -> [NesticWatchRoutineTarget] {
        guard let snapshot = payload?.snapshot else { return [] }
        return routine.targets.compactMap { target in
            guard let subject = snapshot.subjects.first(where: { $0.id == target.entityID }) else { return nil }
            let trackers = target.items.compactMap { item in
                snapshot.trackers.first(where: { $0.id == item.trackerID }).map {
                    NesticWatchRoutineTracker(tracker: $0)
                }
            }
            return NesticWatchRoutineTarget(subject: subject, trackers: trackers)
        }
    }

    func routineSummary(for routine: NestRoutine) -> String {
        let summary = routineTargets(for: routine).map { target in
            let trackerNames = target.trackers.map(\.tracker.name).joined(separator: ", ")
            return trackerNames.isEmpty ? target.subject.name : "\(target.subject.name): \(trackerNames)"
        }.joined(separator: " · ")
        return summary.isEmpty ? "Entity and tracker details unavailable" : summary
    }

    func trackers(for subject: NestSubject) -> [NestTracker] {
        guard let snapshot = payload?.snapshot else { return [] }
        return subject.pinnedActionIDs.compactMap { trackerID in
            snapshot.trackers.first { $0.id == trackerID }
        }
    }

    func subjectTrackerPairs() -> [(NestSubject, [NestTracker])] {
        subjects.map { ($0, trackers(for: $0)) }
    }

    func reloadStoredContext() {
        NesticWatchConnectivity.shared.reloadStoredContext()
    }

    func refresh() async {
        guard let payload, let token = tokenStore.load(), !payload.serverURL.isEmpty else {
            NesticWatchConnectivity.shared.reloadStoredContext()
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let api = NestAPI(baseURL: payload.serverURL, token: token)
            guard let nestID = payload.selectedNestID else { return }
            async let remoteSubjects: [NestEntityResponse] = api.get("nests/\(nestID)/entities")
            async let remoteTrackers: [NestTracker] = api.get("nests/\(nestID)/actions")
            async let remoteEntries: [NestEntry] = api.get("nests/\(nestID)/events?limit=200")
            async let remoteRoutines: [NestRoutineResponse] = api.get("nests/\(nestID)/routines")
            let (subjects, trackers, entries, routines) = try await (remoteSubjects, remoteTrackers, remoteEntries, remoteRoutines)
            var snapshot = payload.snapshot
            snapshot.subjects = subjects.map { $0.subject() }
            snapshot.trackers = trackers
            snapshot.entries = entries.sorted { $0.occurredAt > $1.occurredAt }
            snapshot.routines = routines.map { $0.routine() }
            self.payload = NesticWatchPayload(serverURL: payload.serverURL, token: nil, user: payload.user,
                                               nests: payload.nests, selectedNestID: payload.selectedNestID,
                                               snapshot: snapshot)
            persist()
            statusMessage = "Updated just now"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    @discardableResult
    func record(subjectID: UUID, trackerID: UUID, number: Double? = nil, text: String? = nil,
                bool: Bool? = nil, json: [String: String]? = nil) async -> Bool {
        guard !isRecording else { return false }
        guard let payload, let token = tokenStore.load(), let nestID = payload.selectedNestID,
              let tracker = payload.snapshot.trackers.first(where: { $0.id == trackerID }),
              payload.snapshot.subjects.contains(where: { $0.id == subjectID && $0.pinnedActionIDs.contains(trackerID) }) else {
            statusMessage = "Open Nestic on your iPhone to choose a tracker."
            return false
        }

        isRecording = true
        statusMessage = nil
        defer { isRecording = false }
        let request = NesticWatchLogRequest(id: UUID(), serverURL: payload.serverURL, nestID: nestID,
                                            subjectID: subjectID, trackerID: trackerID, occurredAt: Date(),
                                            valueNumber: number, valueText: text, valueBool: bool,
                                            valueJSON: json, note: nil)
        do {
            struct CreateEventRequest: Encodable {
                let actionID: UUID
                let occurredAt: Date
                let valueNumber: Double?
                let valueText: String?
                let valueBool: Bool?
                let valueJSON: [String: String]?
                let note: String?
            }
            let api = NestAPI(baseURL: payload.serverURL, token: token)
            let entry: NestEntry = try await api.post("entities/\(subjectID)/events", body: CreateEventRequest(
                actionID: trackerID, occurredAt: request.occurredAt, valueNumber: number,
                valueText: text, valueBool: bool, valueJSON: json, note: nil))
            append(entry)
            confirmRecording(id: request.id, name: tracker.name, detail: subjects.first { $0.id == subjectID }?.name, date: request.occurredAt, queued: false)
        } catch {
            pendingRequests.append(request)
            persistPending()
            NesticWatchConnectivity.shared.transfer(request)
            confirmRecording(id: request.id, name: tracker.name, detail: subjects.first { $0.id == subjectID }?.name, date: request.occurredAt, queued: true)
        }
        return true
    }

    @discardableResult
    func record(routine: NestRoutine) async -> Bool {
        guard !isRecording else { return false }
        guard let payload, let token = tokenStore.load(), let nestID = payload.selectedNestID,
              payload.snapshot.routines.contains(where: { $0.id == routine.id }) else {
            statusMessage = "Open Nestic on your iPhone to load routines."
            return false
        }

        isRecording = true
        statusMessage = nil
        defer { isRecording = false }
        let request = NesticWatchRoutineLogRequest(id: UUID(), serverURL: payload.serverURL,
                                                    nestID: nestID, routineID: routine.id,
                                                    occurredAt: Date(), note: nil)
        do {
            struct LogRoutineRequest: Encodable {
                let occurredAt: Date
                let note: String?
            }
            let api = NestAPI(baseURL: payload.serverURL, token: token)
            let entries: [NestEntry] = try await api.post(
                "routines/\(routine.id)/log",
                body: LogRoutineRequest(occurredAt: request.occurredAt, note: request.note)
            )
            for entry in entries { append(entry) }
            confirmRecording(id: request.id, name: routine.name, detail: "\(entries.count) updates", date: request.occurredAt, queued: false)
        } catch {
            pendingRoutineRequests.append(request)
            persistPending()
            NesticWatchConnectivity.shared.transfer(request)
            confirmRecording(id: request.id, name: routine.name, detail: "Routine saved", date: request.occurredAt, queued: true)
        }
        return true
    }

    func dismissRecordingReceipt() {
        if let receipt = recordingReceipt, !receipt.queued,
           statusMessage == "Recorded \(receipt.name)" {
            statusMessage = nil
        }
        recordingReceipt = nil
    }

    private func confirmRecording(id: UUID, name: String, detail: String?, date: Date, queued: Bool) {
        recordingReceipt = NesticWatchRecordingReceipt(id: id, name: name, detail: detail, date: date, queued: queued)
        statusMessage = queued ? "Saved on your watch. It will sync when connected." : "Recorded \(name)"
        WKInterfaceDevice.current().play(.success)
    }

    func recordFromIntent(trackerID: UUID, subjectID: UUID) async -> String {
        guard let tracker = payload?.snapshot.trackers.first(where: { $0.id == trackerID }) else {
            return "I couldn’t find that tracker on this watch."
        }
        switch tracker.valueType {
        case .none:
            await record(subjectID: subjectID, trackerID: trackerID)
        case .number:
            // The spoken command has no amount, so a number tracker records one
            // unit. The watch UI remains available when an exact amount matters.
            await record(subjectID: subjectID, trackerID: trackerID, number: 1)
        case .boolean:
            await record(subjectID: subjectID, trackerID: trackerID, bool: true)
        case .text:
            await record(subjectID: subjectID, trackerID: trackerID, text: "Recorded by Siri")
        case .json:
            return "\(tracker.name) needs details. Use the Nestic watch app to record it."
        case .photo:
            return "\(tracker.name) needs a photo. Use Nestic on your iPhone to record it."
        case .health:
            return "\(tracker.name) needs onset details and possibly a photo. Use Nestic on your iPhone to record it."
        }
        return statusMessage ?? "Recorded \(tracker.name)."
    }

    private func applyContext(_ data: Data) {
        guard !data.isEmpty else {
            recordingReceipt = nil
            payload = nil
            pendingRequests.removeAll()
            pendingRoutineRequests.removeAll()
            defaults.removeObject(forKey: payloadKey)
            defaults.removeObject(forKey: pendingKey)
            defaults.removeObject(forKey: pendingRoutineKey)
            tokenStore.delete()
            statusMessage = "Signed out on iPhone"
            return
        }
        guard let received = try? NestCoding.decoder().decode(NesticWatchPayload.self, from: data) else {
            statusMessage = "Couldn’t read iPhone data. Update Nestic on both devices and try Sync again."
            return
        }
        if let token = received.token { tokenStore.save(token) }
        payload = NesticWatchPayload(serverURL: received.serverURL, token: nil, user: received.user,
                                     nests: received.nests, selectedNestID: received.selectedNestID,
                                     snapshot: received.snapshot)
        persist()
        statusMessage = nil
    }

    private func append(_ entry: NestEntry) {
        guard var payload else { return }
        var snapshot = payload.snapshot
        snapshot.entries.removeAll { $0.id == entry.id }
        snapshot.entries.append(entry)
        snapshot.entries.sort { $0.occurredAt > $1.occurredAt }
        payload.snapshot = snapshot
        self.payload = payload
        persist()
    }

    private func acknowledge(_ id: UUID) {
        pendingRequests.removeAll { $0.id == id }
        pendingRoutineRequests.removeAll { $0.id == id }
        persistPending()
        statusMessage = "Synced with Nestic"
    }

    private func persist() {
        guard let payload, let data = try? NestCoding.encoder().encode(payload) else { return }
        defaults.set(data, forKey: payloadKey)
        persistPending()
    }

    private func persistPending() {
        guard let data = try? NestCoding.encoder().encode(pendingRequests) else { return }
        defaults.set(data, forKey: pendingKey)
        if let routineData = try? NestCoding.encoder().encode(pendingRoutineRequests) {
            defaults.set(routineData, forKey: pendingRoutineKey)
        }
    }
}

struct NesticWatchRecordingReceipt: Identifiable {
    let id: UUID
    let name: String
    let detail: String?
    let date: Date
    let queued: Bool
}

struct NesticWatchRoutineTracker: Identifiable {
    let tracker: NestTracker
    var id: UUID { tracker.id }
}

struct NesticWatchRoutineTarget: Identifiable {
    let subject: NestSubject
    let trackers: [NesticWatchRoutineTracker]
    var id: UUID { subject.id }
}

private struct NesticWatchTokenStore {
    private let service = "com.nestic.watch.token.v1"
    private let account = "default"

    func save(_ token: String) {
        let data = Data(token.utf8)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: account]
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var insert = query
            insert[kSecValueData as String] = data
            insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(insert as CFDictionary, nil)
        }
    }

    func load() -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: service,
                                   kSecAttrAccount as String: account,
                                   kSecReturnData as String: true,
                                   kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func delete() {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
    }
}
