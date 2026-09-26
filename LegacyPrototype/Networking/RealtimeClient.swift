//
//  RealtimeClient.swift
//  Nestic-iOS
//
//  Created by Tim Bausch on 2/28/26.
//

import Foundation

import Combine

struct EntityResponse: Codable {
    let id: UUID
    let nestId: UUID
    let kind: String
    let name: String
    let tags: [String]
    let metadata: [String: String]?
    let birthday: Date?
    let imageURL: String?
    let createdAt: Date?
    let updatedAt: Date?
}

struct TrackableActionResponse: Codable {
    let id: UUID
    let nestId: UUID
    let name: String
    let valueType: String
    let unit: String?
    let description: String?
    let createdAt: Date?
    let updatedAt: Date?
}

struct MemberResponse: Codable {
    let userId: UUID
    let email: String
    let role: String
    let createdAt: Date?
}

struct EntityDeletedResponse: Codable {
    let id: UUID
    let nestId: UUID
}

struct MemberDeletedResponse: Codable {
    let userId: UUID
    let nestId: UUID
}

struct PinnedActionsUpdatedResponse: Codable {
    let entityId: UUID
    let nestId: UUID
    let actionIds: [UUID]
}

struct WSMessageHeader: Codable {
    let v: Int
    let type: String
    let nestId: UUID
    let ts: Date
}

@MainActor
final class RealtimeClient: ObservableObject {
    enum State {
        case disconnected
        case connecting
        case connected
    }

    @Published private(set) var state: State = .disconnected

    private var task: URLSessionWebSocketTask?
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    private var currentNestId: UUID?

    // Called when an action event arrives
    var onActionEventCreated: ((ActionEventResponse) -> Void)?
    var onEntityCreated: ((EntityResponse) -> Void)?
    var onEntityUpdated: ((EntityResponse) -> Void)?
    var onEntityDeleted: ((EntityDeletedResponse) -> Void)?

    var onActionCreated: ((TrackableActionResponse) -> Void)?
    var onPinnedActionsUpdated: ((PinnedActionsUpdatedResponse) -> Void)?

    var onMemberCreated: ((MemberResponse) -> Void)?
    var onMemberUpdated: ((MemberResponse) -> Void)?
    var onMemberDeleted: ((MemberDeletedResponse) -> Void)?

    init() {
        self.session = URLSession(configuration: .default)

        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        self.decoder = d

        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        self.encoder = e
    }

    func connect(baseURL: String, token: String, nestId: UUID) {
        disconnect()

        currentNestId = nestId

        let wsBase = baseURL
            .replacingOccurrences(of: "http://", with: "ws://")
            .replacingOccurrences(of: "https://", with: "wss://")

        guard var comps = URLComponents(string: "\(wsBase)/ws") else {
            print("WS failed to build URL components")
            return
        }

        comps.queryItems = [
            URLQueryItem(name: "token", value: token)
        ]

        guard let url = comps.url else {
            print("WS failed to build URL")
            return
        }

        print("WS connecting to \(url.absoluteString)")
        state = .connecting

        let task = session.webSocketTask(with: url)
        self.task = task
        task.resume()

        receiveLoop()

        Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            self.subscribe(nestId: nestId)
        }
    }

    func subscribe(nestId: UUID) {
        guard let task else {
            print("WS subscribe called with no active task")
            return
        }

        let msg = WSClientMessage(type: "subscribe", nestId: nestId)

        do {
            let data = try encoder.encode(msg)
            let text = String(data: data, encoding: .utf8) ?? ""
            print("WS sending subscribe: \(text)")

            task.send(.string(text)) { error in
                if let error {
                    print("WS subscribe send failed: \(error)")
                } else {
                    print("WS subscribe sent")
                }
            }
        } catch {
            print("WS failed to encode subscribe message: \(error)")
        }
    }

    func disconnect() {
        state = .disconnected
        currentNestId = nil

        task?.cancel(with: .goingAway, reason: nil)
        task = nil
    }

    private func receiveLoop() {
        guard let task else { return }

        task.receive { [weak self] result in
            guard let self else { return }

            Task { @MainActor in
                switch result {
                case .failure(let error):
                    print("WS receive failed: \(error)")
                    self.state = .disconnected
                    return

                case .success(let message):
                    switch message {
                    case .string(let text):
                        print("WS received text: \(text)")
                        self.handle(text: text)

                    case .data(let data):
                        let text = String(data: data, encoding: .utf8) ?? "<non-utf8 data>"
                        print("WS received data: \(text)")
                        self.handle(data: data)

                    @unknown default:
                        print("WS received unknown message type")
                    }

                    self.receiveLoop()
                }
            }
        }
    }

    private func handle(text: String) {
        guard let data = text.data(using: .utf8) else {
            print("WS could not convert text to data")
            return
        }
        handle(data: data)
    }

    private func handle(data: Data) {
        let header: WSMessageHeader
        do {
            header = try decoder.decode(WSMessageHeader.self, from: data)
        } catch {
            if let raw = String(data: data, encoding: .utf8) {
                print("WS failed to decode message header: \(error)")
                print("WS unparsed raw message: \(raw)")
            } else {
                print("WS failed to decode message header: \(error)")
            }
            return
        }

        if let currentNestId, header.nestId != currentNestId, header.type != "ws.subscribed" {
            print("WS ignoring event for non-current nest: \(header.type) \(header.nestId)")
            return
        }

        switch header.type {
        case "actionEvent.created", "entity.event.created":
            do {
                let env = try decoder.decode(WSEnvelope<ActionEventResponse>.self, from: data)
                print("WS decoded action event created for entity \(env.data.entityId)")
                onActionEventCreated?(env.data)
            } catch {
                print("WS failed to decode ActionEvent envelope: \(error)")
            }

        case "entity.created":
            do {
                let env = try decoder.decode(WSEnvelope<EntityResponse>.self, from: data)
                print("WS decoded entity created: \(env.data.id)")
                onEntityCreated?(env.data)
            } catch {
                print("WS failed to decode Entity created envelope: \(error)")
            }

        case "entity.updated":
            do {
                let env = try decoder.decode(WSEnvelope<EntityResponse>.self, from: data)
                print("WS decoded entity updated: \(env.data.id)")
                onEntityUpdated?(env.data)
            } catch {
                print("WS failed to decode Entity updated envelope: \(error)")
            }

        case "entity.deleted":
            do {
                let env = try decoder.decode(WSEnvelope<EntityDeletedResponse>.self, from: data)
                print("WS decoded entity deleted: \(env.data.id)")
                onEntityDeleted?(env.data)
            } catch {
                print("WS failed to decode EntityDeleted envelope: \(error)")
            }

        case "action.created":
            do {
                let env = try decoder.decode(WSEnvelope<TrackableActionResponse>.self, from: data)
                print("WS decoded action created: \(env.data.id)")
                onActionCreated?(env.data)
            } catch {
                print("WS failed to decode TrackableAction envelope: \(error)")
            }

        case "pinnedActions.updated":
            do {
                let env = try decoder.decode(WSEnvelope<PinnedActionsUpdatedResponse>.self, from: data)
                print("WS decoded pinned actions updated for entity \(env.data.entityId)")
                onPinnedActionsUpdated?(env.data)
            } catch {
                print("WS failed to decode PinnedActionsUpdated envelope: \(error)")
            }

        case "member.created":
            do {
                let env = try decoder.decode(WSEnvelope<MemberResponse>.self, from: data)
                print("WS decoded member created: \(env.data.userId)")
                onMemberCreated?(env.data)
            } catch {
                print("WS failed to decode Member created envelope: \(error)")
            }

        case "member.updated":
            do {
                let env = try decoder.decode(WSEnvelope<MemberResponse>.self, from: data)
                print("WS decoded member updated: \(env.data.userId)")
                onMemberUpdated?(env.data)
            } catch {
                print("WS failed to decode Member updated envelope: \(error)")
            }

        case "member.deleted":
            do {
                let env = try decoder.decode(WSEnvelope<MemberDeletedResponse>.self, from: data)
                print("WS decoded member deleted: \(env.data.userId)")
                onMemberDeleted?(env.data)
            } catch {
                print("WS failed to decode MemberDeleted envelope: \(error)")
            }

        case "ws.subscribed":
            do {
                let ack = try decoder.decode(WSEnvelope<WSAck>.self, from: data)
                print("WS subscribed ack received for nest \(ack.nestId)")
                state = .connected
            } catch {
                print("WS failed to decode ack envelope: \(error)")
            }

        default:
            if let raw = String(data: data, encoding: .utf8) {
                print("WS unhandled message type: \(header.type)")
                print("WS raw message: \(raw)")
            } else {
                print("WS unhandled message type: \(header.type)")
            }
        }
    }
}
