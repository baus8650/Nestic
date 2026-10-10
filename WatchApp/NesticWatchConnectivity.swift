import Foundation
import WatchConnectivity

/// Watch-side delivery for the latest phone snapshot and queued log requests.
final class NesticWatchConnectivity: NSObject, WCSessionDelegate, @unchecked Sendable {
    static let shared = NesticWatchConnectivity()

    private let session = WCSession.default
    var onContextData: ((Data) -> Void)?
    var onLogAcknowledged: ((UUID) -> Void)?
    var onSyncStatus: ((Bool, String?) -> Void)?
    private var syncID: UUID?
    private var syncTimeout: DispatchWorkItem?
    private var pendingTransfers: [[String: Any]] = []

    private override init() {
        super.init()
    }

    func start() {
        guard WCSession.isSupported() else { return }
        session.delegate = self
        session.activate()
        if session.activationState == .activated {
            deliverStoredContext()
            requestLatestContext()
        }
    }

    func reloadStoredContext() {
        deliverStoredContext()
        requestLatestContext()
    }

    private func requestLatestContext() {
        DispatchQueue.main.async { [weak self] in self?.requestContextOnMain() }
    }

    private func requestContextOnMain() {
        guard syncID == nil else { return }
        let id = UUID()
        syncID = id
        onSyncStatus?(true, "Connecting to iPhone…")
        let timeout = DispatchWorkItem { [weak self] in
            guard let self, self.syncID == id else { return }
            self.queueSnapshotRequest()
            self.finishSync("No response yet. Open Nestic on your iPhone, then try Sync again.")
        }
        syncTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: timeout)
        guard session.activationState == .activated else { return }
        if !session.isReachable {
            queueSnapshotRequest()
            finishSync("Waiting for iPhone. Your data will arrive when it reconnects.")
            return
        }
        session.sendMessage([NesticWatchTransfer.snapshotRequestKey: true], replyHandler: { [weak self] response in
            let hasContext = response[NesticWatchTransfer.applicationContextKey] is Data
            self?.receive(response)
            DispatchQueue.main.async {
                guard let self, self.syncID == id else { return }
                self.finishSync(!hasContext
                    ? "Open Nestic and sign in on your iPhone, then try Sync again." : nil)
            }
        }, errorHandler: { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, self.syncID == id else { return }
                self.queueSnapshotRequest()
                self.finishSync("Couldn’t reach iPhone. Open Nestic there, then try Sync again.")
            }
        })
    }

    private func queueSnapshotRequest() {
        guard session.activationState == .activated,
              !session.outstandingUserInfoTransfers.contains(where: {
                  $0.userInfo[NesticWatchTransfer.snapshotRequestKey] as? Bool == true
              }) else { return }
        session.transferUserInfo([NesticWatchTransfer.snapshotRequestKey: true])
    }

    private func finishSync(_ message: String?) {
        syncTimeout?.cancel()
        syncTimeout = nil
        syncID = nil
        onSyncStatus?(false, message)
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        requestLatestContext()
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        receive(message)
    }

    func transfer(_ request: NesticWatchLogRequest) {
        guard let data = try? NestCoding.encoder().encode(request) else { return }
        transfer([NesticWatchTransfer.logRequestKey: data])
    }

    func transfer(_ request: NesticWatchRoutineLogRequest) {
        guard let data = try? NestCoding.encoder().encode(request) else { return }
        transfer([NesticWatchTransfer.routineLogRequestKey: data])
    }

    private func transfer(_ userInfo: [String: Any]) {
        guard WCSession.isSupported() else { return }
        guard session.activationState == .activated else {
            pendingTransfers.append(userInfo)
            return
        }
        session.transferUserInfo(userInfo)
    }

    private func flushPendingTransfers() {
        guard session.activationState == .activated else { return }
        let transfers = pendingTransfers
        pendingTransfers.removeAll()
        for userInfo in transfers {
            session.transferUserInfo(userInfo)
        }
    }

    private func deliverStoredContext() {
        guard let data = session.receivedApplicationContext[NesticWatchTransfer.applicationContextKey] as? Data else { return }
        DispatchQueue.main.async { [weak self] in
            self?.onContextData?(data)
        }
    }

    private func receive(_ userInfo: [String: Any]) {
        if let data = userInfo[NesticWatchTransfer.applicationContextKey] as? Data {
            DispatchQueue.main.async { [weak self] in
                self?.finishSync(nil)
                self?.onContextData?(data)
            }
        }
        if let data = userInfo[NesticWatchTransfer.logAckKey] as? Data,
           let id = try? NestCoding.decoder().decode(UUID.self, from: data) {
            DispatchQueue.main.async { [weak self] in self?.onLogAcknowledged?(id) }
        }
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {
        guard activationState == .activated else {
            DispatchQueue.main.async { [weak self] in
                self?.finishSync("Couldn’t connect to iPhone. Try Sync again.")
            }
            return
        }
        DispatchQueue.main.async { [weak self] in self?.finishSync(nil) }
        deliverStoredContext()
        requestLatestContext()
        flushPendingTransfers()
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        receive(applicationContext)
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        receive(userInfo)
    }

}
