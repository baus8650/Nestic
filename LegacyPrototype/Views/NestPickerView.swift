//
//  NestPickerView.swift
//  Nestic-iOS
//
//  Created by Tim Bausch on 2/28/26.
//

import SwiftUI
import CoreData

struct NestPickerView: View {
    @Environment(\.managedObjectContext) private var context
    @EnvironmentObject var selectedNest: SelectedNestStore
    @EnvironmentObject var auth: AuthViewModel

    @FetchRequest(
        entity: CDNest.entity(),
        sortDescriptors: [NSSortDescriptor(key: "name", ascending: true)]
    ) private var nests: FetchedResults<CDNest>

    var body: some View {
        NavigationStack {
            List {
                if let defaultId = selectedNest.defaultNestId {
                    Section {
                        Button("Clear Default Nest") {
                            selectedNest.clearDefault()
                        }
                    }
                    .textCase(nil)
                }

                Section("Your Nests") {
                    ForEach(nests, id: \.id) { nest in
                        Button {
                            if let id = nest.id {
                                selectedNest.select(id: id)
                            }
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(nest.name ?? "Untitled")
                                    if let id = nest.id, id == selectedNest.defaultNestId {
                                        Text("Default")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if let id = nest.id, id == selectedNest.selectedNestId {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                }
                            }
                        }
                        .contextMenu {
                            if let id = nest.id {
                                Button("Set as Default") {
                                    selectedNest.setDefault(id: id)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Choose a Nest")
                        .toolbar {
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
