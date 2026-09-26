//
//  APIClient.swift
//  Nestic-iOS
//
//  Created by Tim Bausch on 2/28/26.
//

import Foundation

enum APIError: Error, LocalizedError {
    case invalidResponse
    case http(Int, String?)
    case decoding(Error)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid server response."
        case .http(let code, let msg):
            if let msg, !msg.isEmpty { return "Server error (\(code)): \(msg)" }
            return "Server error (\(code))."
        case .decoding(let err):
            return "Failed to decode response: \(err.localizedDescription)"
        }
    }
}

final class APIClient {
    private let baseURL: URL

    init(baseURL: URL = Config.apiBaseURL) {
        self.baseURL = baseURL
    }

    func request<T: Decodable>(
        _ path: String,
        method: String = "GET",
        bearerToken: String? = nil,
        basicAuth: (user: String, pass: String)? = nil,
        body: Encodable? = nil
    ) async throws -> T {
        // Build URL safely: appendingPathComponent encodes "/" if provided in a single string.
        // So we split on "/" and append components one-by-one.
        let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var url = baseURL
        for part in trimmed.split(separator: "/") {
            url.appendPathComponent(String(part))
        }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        
        print("➡️ API REQUEST:", req.httpMethod ?? "?", req.url?.absoluteString ?? "nil")
        if let auth = req.value(forHTTPHeaderField: "Authorization") {
            print("   Auth:", auth.prefix(20), "…")
        }

        if let bearerToken {
            req.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        } else if let basicAuth {
            let creds = "\(basicAuth.user):\(basicAuth.pass)"
            let b64 = Data(creds.utf8).base64EncodedString()
            req.setValue("Basic \(b64)", forHTTPHeaderField: "Authorization")
        }

        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONEncoder.nestic.encode(AnyEncodable(body))
        }

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw APIError.invalidResponse }

        if !(200...299).contains(http.statusCode) {
            let msg = String(data: data, encoding: .utf8)
            throw APIError.http(http.statusCode, msg)
        }

        do {
            return try JSONDecoder.nestic.decode(T.self, from: data)
        } catch {
            throw APIError.decoding(error)
        }
    }
}

// Type erasure for Encodable bodies
struct AnyEncodable: Encodable {
    private let _encode: (Encoder) throws -> Void
    init(_ value: Encodable) { self._encode = value.encode(to:) }
    func encode(to encoder: Encoder) throws { try _encode(encoder) }
}

extension JSONDecoder {
    static let nestic: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

extension JSONEncoder {
    static let nestic: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
}
