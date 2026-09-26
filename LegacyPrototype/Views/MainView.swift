//
//  MainView.swift
//  Nestic-iOS
//
//  Created by Tim Bausch on 2/28/26.
//

import SwiftUI

struct MainView: View {
    @EnvironmentObject var auth: AuthViewModel
    @EnvironmentObject var selectedNest: SelectedNestStore

    var body: some View {
        if selectedNest.selectedNestId == nil {
            NestPickerView()
        } else {
            NavigationStack {
                HomeView(nestId: selectedNest.selectedNestId!)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Nests") {
                                selectedNest.selectedNestId = nil
                            }
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Logout") {
                                auth.logout()
                                selectedNest.selectedNestId = nil
                            }
                        }
                    }
            }
        }
    }
}
