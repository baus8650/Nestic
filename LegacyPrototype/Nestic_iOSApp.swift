//
//  Nestic_iOSApp.swift
//  Nestic-iOS
//
//  Created by Tim Bausch on 2/28/26.
//

import SwiftUI
import CoreData

@main
struct Nestic_iOSApp: App {
    let persistenceController: PersistenceController

    @StateObject private var auth = AuthViewModel()
    @StateObject private var selectedNest = SelectedNestStore()
    @StateObject private var sync: SyncCoordinator

    init() {
        let persistence = PersistenceController.shared
        self.persistenceController = persistence

        let ctx = persistence.container.viewContext
        let authVM = AuthViewModel()
        let selected = SelectedNestStore()

        _auth = StateObject(wrappedValue: authVM)
        _selectedNest = StateObject(wrappedValue: selected)
        _sync = StateObject(wrappedValue: SyncCoordinator(auth: authVM, selectedNest: selected, context: ctx))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environmentObject(auth)
                .environmentObject(selectedNest)
                .environmentObject(sync) // not used by views yet, but keeps it alive
        }
    }
}
