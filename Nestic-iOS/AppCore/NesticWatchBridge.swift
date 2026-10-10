import Foundation
import OSLog
import WatchConnectivity

/// The iPhone side of the watch integration. Application context carries the
/// latest read-only snapshot; queued log requests use user-info transfer so
/// they are delivered even when the phone app is suspended.
final class NesticWatchBridge: NSObject, WCSessionDelegate {
    static let shared = NesticWatchBridge()

    private let session = WCSession.default
    private let logger = Logger(subsystem: "com.bausch.Nestic-iOS", category: "WatchConnectivity")
    private var pendingRequests: [NesticWatchLogRequest] = []
    private var requestHandler: ((NesticWatchLogRequest) -> Void)?
    private var pendingRoutineRequests: [NesticWatchRoutineLogRequest] = []
    private var routineRequestHandler: ((NesticWatchRoutineLogRequest) -> Void)?
    private var latestContextData: Data?

    private override init() {
        super.init()
    }

    func start() {
        guard WCSession.isSupported() else {
            logger.info("WatchConnectivity is not supported on this device")
            return
        }
        session.delegate = self
        session.activate()
    }

    func setLogRequestHandler(_ handler: @escaping (NesticWatchLogRequest) -> Void) {
        requestHandler = handler
        let pending = pendingRequests
        pendingRequests.removeAll()
        for request in pending { handler(request) }
    }

    func setRoutineLogRequestHandler(_ handler: @escaping (NesticWatchRoutineLogRequest) -> Void) {
        routineRequestHandler = handler
        let pending = pendingRoutineRequests
        pendingRoutineRequests.removeAll()
        for request in pending { handler(request) }
    }

    func publish(serverURL: String, token: String?, user: NestPerson, nests: [NestSpace],
                 selectedNestID: UUID?, snapshot: NestSnapshot) {
        guard WCSession.isSupported() else { return }
        guard let token else {
            logger.info("Skipping Watch snapshot because there is no authenticated token")
            return
        }

        // The Watch only needs the selected entities and their trackers. Keep
        // the context small enough for WatchConnectivity's application
        // context limit; the Watch can fetch entries itself when needed.
        let watchSnapshot = NestSnapshot(
            subjects: snapshot.subjects,
            trackers: snapshot.trackers,
            entries: [],
            members: [],
            routines: snapshot.routines
        )
        let payload = NesticWatchPayload(serverURL: serverURL, token: token, user: user,
                                         nests: nests, selectedNestID: selectedNestID,
                                         snapshot: watchSnapshot)
        guard let data = try? NestCoding.encoder().encode(payload) else { return }
        latestContextData = data
        publishLatestContextIfPossible()
    }

    func clear() {
        latestContextData = Data()
        publishLatestContextIfPossible()
    }

    func acknowledgeLogRequest(_ requestID: UUID) {
        guard WCSession.isSupported(), session.activationState == .activated,
              let data = try? NestCoding.encoder().encode(requestID) else { return }
        session.transferUserInfo([NesticWatchTransfer.logAckKey: data])
    }

    private func receive(_ userInfo: [String: Any]) {
        if let data = userInfo[NesticWatchTransfer.logRequestKey] as? Data,
           let request = try? NestCoding.decoder().decode(NesticWatchLogRequest.self, from: data) {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if let requestHandler { requestHandler(request) }
                else { pendingRequests.append(request) }
            }
        }
        guard let data = userInfo[NesticWatchTransfer.routineLogRequestKey] as? Data,
              let request = try? NestCoding.decoder().decode(NesticWatchRoutineLogRequest.self, from: data) else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let routineRequestHandler { routineRequestHandler(request) }
            else { pendingRoutineRequests.append(request) }
        }
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {
        if let error {
            logger.error("WatchConnectivity activation failed: \(error.localizedDescription, privacy: .public)")
        } else {
            logger.info("WatchConnectivity activated with state \(String(describing: activationState), privacy: .public)")
        }
        DispatchQueue.main.async { [weak self] in self?.publishLatestContextIfPossible() }
    }

    func sessionDidBecomeInactive(_ session: WCSession) { }

    func sessionWatchStateDidChange(_ session: WCSession) {
        DispatchQueue.main.async { [weak self] in self?.publishLatestContextIfPossible() }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async { [weak self] in self?.publishLatestContextIfPossible() }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any],
                 replyHandler: @escaping ([String: Any]) -> Void) {
        guard message[NesticWatchTransfer.snapshotRequestKey] as? Bool == true else {
            replyHandler([:])
            return
        }
        DispatchQueue.main.async { [weak self] in
            guard let data = self?.latestContextData else { replyHandler([:]); return }
            replyHandler([NesticWatchTransfer.applicationContextKey: data])
        }
    }

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        if userInfo[NesticWatchTransfer.snapshotRequestKey] as? Bool == true {
            DispatchQueue.main.async { [weak self] in
                guard let self, let data = self.latestContextData else { return }
                self.session.transferUserInfo([NesticWatchTransfer.applicationContextKey: data])
                self.publishLatestContextIfPossible()
            }
        } else {
            receive(userInfo)
        }
    }

    private func publishLatestContextIfPossible() {
        guard WCSession.isSupported(), session.activationState == .activated,
              let latestContextData else { return }
        guard session.isWatchAppInstalled else {
            logger.info("Watch snapshot is waiting because the Nestic Watch app is not installed")
            return
        }
        // Deliver immediately when both apps are open, including on paired
        // simulators where background context delivery can be delayed.
        if session.isReachable {
            session.sendMessage([NesticWatchTransfer.applicationContextKey: latestContextData],
                                replyHandler: nil, errorHandler: { [weak self] error in
                self?.logger.info("Immediate Watch snapshot deferred: \(error.localizedDescription, privacy: .public)")
            })
        }
        // Application context is the normal phone-to-Watch snapshot path. It
        // replaces older state and does not require the Watch app to be
        // running or reachable at the moment of publishing.
        do {
            try session.updateApplicationContext([
                NesticWatchTransfer.applicationContextKey: latestContextData
            ])
            logger.info("Published Watch snapshot (\(latestContextData.count) bytes)")
        } catch {
            logger.error("Application context update failed: \(error.localizedDescription, privacy: .public)")
            // Keep a queued copy as a recovery path for a freshly installed
            // counterpart or a temporarily unavailable paired Watch.
            session.transferUserInfo([
                NesticWatchTransfer.applicationContextKey: latestContextData
            ])
        }
    }
}
