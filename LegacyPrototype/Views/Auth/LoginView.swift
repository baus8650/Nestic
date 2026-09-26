//
//  LoginView.swift
//  Nestic-iOS
//
//  Created by Tim Bausch on 2/28/26.
//

import SwiftUI

struct LoginView: View {
    @EnvironmentObject var auth: AuthViewModel

    var body: some View {
        NavigationStack {
            Form {
                Section("Credentials") {
                    TextField("Email", text: $auth.email)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    SecureField("Password", text: $auth.password)
                }

                if let msg = auth.errorMessage {
                    Section {
                        Text(msg).foregroundStyle(.red)
                    }
                }

                Section {
                    Button(auth.isLoading ? "Logging in..." : "Login") {
                        auth.login()
                    }
                    .disabled(auth.isLoading)
                }
            }
            .navigationTitle("Login")
        }
    }
}
