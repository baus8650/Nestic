//
//  RootView.swift
//  Nestic-iOS
//
//  Created by Tim Bausch on 2/28/26.
//

import SwiftUI

struct RootView: View {
    @EnvironmentObject var auth: AuthViewModel

    var body: some View {
        if auth.isAuthenticated {
            MainView()
        } else {
            AuthView()
        }
    }
}
