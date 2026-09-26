//
//  RegisterView.swift
//  Nestic-iOS
//
//  Created by Tim Bausch on 2/28/26.
//

import SwiftUI

struct RegisterView: View {
    @EnvironmentObject var auth: AuthViewModel

    var body: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    TextField("Email", text: $auth.email)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    SecureField("Password", text: $auth.password)

                    TextField("Display Name", text: $auth.displayName)

                    TextField("Image URL (optional)", text: $auth.imageURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                if let msg = auth.errorMessage {
                    Section {
                        Text(msg).foregroundStyle(.red)
                    }
                }

                Section {
                    Button(auth.isLoading ? "Registering..." : "Register") {
                        auth.register()
                    }
                    .disabled(auth.isLoading)
                }
            }
            .navigationTitle("Register")
        }
    }
}
