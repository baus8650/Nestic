//
//  AuthView.swift
//  Nestic-iOS
//
//  Created by Tim Bausch on 2/28/26.
//

import SwiftUI

struct AuthView: View {
    var body: some View {
        TabView {
            RegisterView()
                .tabItem { Label("Register", systemImage: "person.badge.plus") }

            LoginView()
                .tabItem { Label("Login", systemImage: "person") }
        }
    }
}
