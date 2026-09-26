import Foundation
import Security
import CryptoKit

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
            throw NesticError.message("Enter a full server address, such as https://api.nestic-app.com.")
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

    func data(path: String, method: String = "GET", body: Data? = nil, authorization: String? = nil) async throws -> Data {
        guard let url = URL(string: baseURL + "/" + path) else {
            throw NesticError.message("The server address is invalid.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
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
            throw NesticError.message("Couldn’t reach your nest’s server. Check your connection and server address. Your saved updates are still on this device.")
        }
        guard let http = response as? HTTPURLResponse else {
            throw NesticError.message("The server sent an unreadable response.")
        }
        guard (200..<300).contains(http.statusCode) else {
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
    func subject(pins: [UUID] = []) -> NestSubject {
        .init(id: id, nestId: nestId, name: name, kind: kind, emoji: metadata?["emoji"] ?? kind.emoji, pinnedActionIDs: pins)
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

struct NestPinResponse: Decodable { let actionId: UUID }
