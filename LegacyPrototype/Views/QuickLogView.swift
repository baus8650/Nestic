//
//  QuickLogView.swift
//  Nestic-iOS
//
//  Created by Tim Bausch on 2/28/26.
//

import SwiftUI

struct QuickLogView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject var vm: QuickLogViewModel

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(vm.actionName)
                        .font(.headline)

                    switch vm.valueType {
                    case .none:
                        Text("No value required.")
                            .foregroundStyle(.secondary)
                    case .number:
                        HStack {
                            TextField("Value", text: $vm.valueNumberText)
                                .keyboardType(.decimalPad)
                            if let unit = vm.unit, !unit.isEmpty {
                                Text(unit).foregroundStyle(.secondary)
                            }
                        }
                    case .text:
                        TextField("Value", text: .constant(""))
                            .disabled(true)
                            .foregroundStyle(.secondary)
                            .overlay(Text("Text type not wired yet").foregroundStyle(.secondary))
                    case .boolean:
                        Toggle("True/False", isOn: .constant(false))
                            .disabled(true)
                    case .json:
                        Text("JSON value type not wired yet.")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Note (optional)") {
                    TextField("Add a note", text: $vm.note)
                }

                if let err = vm.errorMessage {
                    Section {
                        Text(err).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Log Action")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(vm.isSaving ? "Saving..." : "Save") {
                        Task {
                            let ok = await vm.save()
                            if ok { dismiss() }
                        }
                    }
                    .disabled(vm.isSaving)
                }
            }
        }
    }
}
