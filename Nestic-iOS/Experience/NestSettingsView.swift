import SwiftUI

struct NestSettingsView: View {
    @EnvironmentObject private var store: NesticStore
    @State private var showSwitcher = false
    @State private var showInvite = false
    @State private var showServer = false
    @State private var showSignOut = false
    @State private var error: String?
    var body: some View {
        List {
            Section {
                VStack(spacing: 12) {
                    NestMark().frame(width: 74, height: 78)
                    Text(store.selectedNest?.name ?? "Your next little chapter")
                        .font(.system(.title2, design: .rounded, weight: .bold))
                    Text(store.isDemo ? "A sample space to make yourself at home." : "A shared space for the things that matter.")
                        .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }.frame(maxWidth: .infinity).padding(.vertical, 15)
            }.listRowBackground(Color.clear)
            Section("Your people") {
                if store.members.isEmpty { Text("Create or choose a nest to add your people.").foregroundStyle(.secondary) }
                ForEach(store.members) { person in
                    HStack(spacing: 12) {
                        Text(person.initials).font(.subheadline.weight(.semibold)).foregroundStyle(NesticTheme.forest)
                            .frame(width: 42, height: 42).background(NesticTheme.lime.opacity(0.3), in: Circle())
                        VStack(alignment: .leading, spacing: 3) {
                            Text(person.displayName).font(.subheadline.weight(.semibold))
                            Text(person.email).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(person.role?.capitalized ?? "Member").font(.caption2).foregroundStyle(.secondary)
                    }.padding(.vertical, 4)
                }
                if store.canManageNest && store.selectedNest != nil {
                    Button { showInvite = true } label: { Label("Add a nest member", systemImage: "person.badge.plus") }
                        .accessibilityIdentifier("nest.addMember")
                }
            }
            Section("Make yourself at home") {
                Button { showSwitcher = true } label: { Label("Switch or create a nest", systemImage: "house") }
                LabeledContent { Text(store.isDemo ? "Sample · local only" : store.connectionStatus).font(.subheadline) } label: { Label("Connection", systemImage: "antenna.radiowaves.left.and.right") }
                if !store.isDemo { Button { showServer = true } label: { Label("Server settings", systemImage: "network") } }
            }
            Section {
                if let user = store.currentUser {
                    LabeledContent("Signed in as", value: store.isDemo ? "Sample member" : user.displayName)
                }
                Button(store.isDemo ? "Leave sample nest" : "Sign out", role: .destructive) { showSignOut = true }
                    .accessibilityIdentifier("nest.signOut")
            } footer: {
                Text(store.isDemo ? "Sample changes are saved on this device. Create an account to start a real shared nest." : "Your nest’s updates stay with your nest when you sign out.")
            }
            Section {
                VStack(spacing: 5) {
                    Text("nestic").font(.system(.title3, design: .rounded, weight: .bold)).foregroundStyle(NesticTheme.forest)
                    Text("Little updates. Shared care.").font(.caption).foregroundStyle(.secondary)
                    Text("Version 1.0").font(.caption2).foregroundStyle(.tertiary)
                }.frame(maxWidth: .infinity).padding(.vertical, 12)
            }.listRowBackground(Color.clear)
        }.formStyle().navigationTitle("Your nest")
            .sheet(isPresented: $showSwitcher) { NestSwitcherSheet() }
            .sheet(isPresented: $showInvite) { AddMemberSheet() }
            .sheet(isPresented: $showServer) { ServerSettingsSheet() }
            .confirmationDialog(store.isDemo ? "Leave the sample nest?" : "Sign out of Nestic?", isPresented: $showSignOut, titleVisibility: .visible) {
                Button(store.isDemo ? "Leave sample nest" : "Sign out", role: .destructive) { store.signOut() }
            }
            .refreshable { do { try await store.refresh() } catch { self.error = error.localizedDescription } }
            .alert("Couldn’t refresh", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") { error = nil }
            } message: { Text(error ?? "") }
    }
}

struct NestSwitcherSheet: View {
    @EnvironmentObject private var store: NesticStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                if !store.nests.isEmpty {
                    Section("Your nests") {
                        ForEach(store.nests) { nest in
                            Button {
                                busy = true
                                Task {
                                    defer { busy = false }
                                    do { try await store.selectNest(nest); dismiss() }
                                    catch { self.error = error.localizedDescription }
                                }
                            } label: {
                                HStack {
                                    Label(nest.name, systemImage: "house")
                                    Spacer()
                                    if nest.id == store.selectedNestID { Image(systemName: "checkmark.circle.fill") }
                                }
                            }.disabled(busy)
                        }
                    }
                }
                Section {
                    TextField("Nest name, e.g. Our little home", text: $name).accessibilityIdentifier("nest.name")
                    Button {
                        busy = true; error = nil
                        Task {
                            defer { busy = false }
                            do { try await store.createNest(name: name); dismiss() }
                            catch { self.error = error.localizedDescription }
                        }
                    } label: {
                        HStack { Label("Create nest", systemImage: "plus.circle"); if busy { Spacer(); ProgressView() } }
                    }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || busy)
                        .accessibilityIdentifier("nest.create")
                } header: { Text("Start something together") } footer: { Text("Keep different groups in their own nests. Each has its own members, trackers, and activity.") }
                if let error { Text(error).foregroundStyle(.red) }
            }.formStyle().navigationTitle("Find your nest").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() }.disabled(busy) } }
                .interactiveDismissDisabled(busy)
        }
    }
}

struct AddMemberSheet: View {
    @EnvironmentObject private var store: NesticStore
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Good things are shared.").font(.system(.title2, design: .rounded, weight: .bold))
                        Text("Add someone to \(store.selectedNest?.name ?? "your nest") so they can see and log updates with you.").foregroundStyle(.secondary)
                    }.padding(.vertical, 10)
                }.listRowBackground(Color.clear)
                Section {
                    TextField("Email address", text: $email).keyboardType(.emailAddress).textContentType(.emailAddress)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().accessibilityIdentifier("member.email")
                } header: { Text("Their Nestic account") } footer: {
                    Text(store.isDemo ? "This adds a sample member locally. No invitation is sent." : "They’ll need to create a Nestic account first. Adding their email gives them member access immediately; no email invitation is sent. They can pull to refresh to find the nest.")
                }
                if let error { Text(error).foregroundStyle(.red) }
                Section {
                    PrimaryButton(title: "Add to nest", symbol: "person.badge.plus", busy: busy) {
                        busy = true; error = nil
                        Task {
                            defer { busy = false }
                            do { try await store.addMember(email: email); dismiss() }
                            catch { self.error = error.localizedDescription }
                        }
                    }.disabled(email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("member.save")
                }.listRowBackground(Color.clear).listRowInsets(EdgeInsets())
            }.formStyle().navigationTitle("Add a member").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(busy) } }
                .interactiveDismissDisabled(busy)
        }
    }
}
