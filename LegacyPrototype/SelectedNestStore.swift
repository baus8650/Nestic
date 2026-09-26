//
//  SelectedNestStore.swift
//  Nestic-iOS
//
//  Created by Tim Bausch on 2/28/26.
//

import Foundation
import Combine

@MainActor
final class SelectedNestStore: ObservableObject {
    @Published var selectedNestId: String? = nil

    private let defaults = UserDefaults.standard
    private let defaultKey = "defaultNestId" // device-wide

    var defaultNestId: String? {
        get { defaults.string(forKey: defaultKey) }
        set {
            if let newValue {
                defaults.set(newValue, forKey: defaultKey)
            } else {
                defaults.removeObject(forKey: defaultKey)
            }
            objectWillChange.send()
        }
    }

    func select(id: String) {
        selectedNestId = id
    }

    func setDefault(id: String) {
        defaultNestId = id
        selectedNestId = id
    }

    func clearDefault() {
        defaultNestId = nil
    }
}
