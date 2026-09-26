//
//  WSEnvelope.swift
//  Nestic-iOS
//
//  Created by Tim Bausch on 2/28/26.
//

import Foundation

struct WSEnvelope<T: Decodable>: Decodable {
    let v: Int
    let type: String
    let nestId: UUID
    let ts: Date
    let data: T
}

struct WSClientMessage: Encodable {
    let type: String
    let nestId: UUID?
}
