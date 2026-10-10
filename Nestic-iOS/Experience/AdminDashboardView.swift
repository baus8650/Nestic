import SwiftUI

struct AdminDashboardView: View {
    @EnvironmentObject private var store: NesticStore
    @State private var dashboard: NestAdminDashboard?
    @State private var error: String?
    @State private var loading = false

    var body: some View {
        List {
            if store.currentUser?.isAdmin == true, !store.isDemo {
                Section {
                    NavigationLink("Feedback inbox") { AdminFeedbackView() }
                    NavigationLink("User accounts") { AdminUsersView() }
                }
                if let dashboard {
                    Section("Across Nestic") {
                        LabeledContent("Accounts", value: dashboard.totalUsers.formatted())
                        LabeledContent("Verified accounts", value: dashboard.verifiedUsers.formatted())
                        LabeledContent("Active users · last 30 days", value: dashboard.activeUsersLast30Days.formatted())
                        LabeledContent("Nests", value: dashboard.totalNests.formatted())
                        LabeledContent("Recorded updates", value: dashboard.totalEvents.formatted())
                    }
                    Section("Feedback") {
                        LabeledContent("Open", value: dashboard.openFeedback.formatted())
                        LabeledContent("In progress", value: dashboard.inProgressFeedback.formatted())
                        LabeledContent("Resolved", value: dashboard.resolvedFeedback.formatted())
                    }
                    Section("Recent conversations") {
                        ForEach(dashboard.recentFeedback) { thread in
                            NavigationLink {
                                FeedbackThreadView(thread: thread, isAdmin: true)
                            } label: {
                                VStack(alignment: .leading) {
                                    Text(thread.userDisplayName).font(.caption).foregroundStyle(.secondary)
                                    FeedbackThreadRow(thread: thread)
                                }
                            }
                        }
                        if dashboard.recentFeedback.isEmpty { Text("No feedback yet").foregroundStyle(.secondary) }
                    }
                    Section("Recent accounts") {
                        ForEach(dashboard.recentUsers) { user in AdminUserRow(user: user) }
                    }
                } else if loading {
                    ProgressView("Loading dashboard…")
                }
            } else {
                ContentUnavailableView("Administrator access required", systemImage: "lock")
            }
        }
        .formStyle()
        .navigationTitle("Admin dashboard")
        .task { await refresh() }
        .refreshable { await refresh() }
        .alert("Couldn’t load dashboard", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }

    private func refresh() async {
        guard store.currentUser?.isAdmin == true, !store.isDemo else { return }
        loading = true
        defer { loading = false }
        do { dashboard = try await store.loadAdminDashboard() }
        catch { self.error = error.localizedDescription }
    }
}

private struct AdminFeedbackView: View {
    @EnvironmentObject private var store: NesticStore
    @State private var threads: [NestFeedbackThread] = []
    @State private var status: NestFeedbackStatus?
    @State private var search = ""
    @State private var loading = false
    @State private var error: String?

    private var filteredThreads: [NestFeedbackThread] {
        threads.filter { thread in
            (status == nil || thread.status == status) &&
            (search.isEmpty || [thread.subject, thread.userDisplayName, thread.userEmail].contains { $0.localizedCaseInsensitiveContains(search) })
        }
    }

    var body: some View {
        List {
            Section {
                Picker("Status", selection: $status) {
                    Text("All").tag(nil as NestFeedbackStatus?)
                    ForEach(NestFeedbackStatus.allCases) { value in Text(value.title).tag(Optional(value)) }
                }
            }
            Section {
                ForEach(filteredThreads) { thread in
                    NavigationLink {
                        FeedbackThreadView(thread: thread, isAdmin: true)
                    } label: {
                        VStack(alignment: .leading) {
                            Text(thread.userDisplayName + " · " + thread.userEmail)
                                .font(.caption).foregroundStyle(.secondary)
                            FeedbackThreadRow(thread: thread)
                        }
                    }
                }
                if loading && threads.isEmpty { ProgressView("Loading feedback…") }
                else if filteredThreads.isEmpty { Text("No matching conversations").foregroundStyle(.secondary) }
            } footer: {
                Text("Showing up to 200 recent conversations. Pull to refresh replies and status changes.")
            }
        }
        .formStyle()
        .navigationTitle("Feedback inbox")
        .searchable(text: $search, prompt: "Subject, name, or email")
        .task { await refresh() }
        .refreshable { await refresh() }
        .alert("Couldn’t load feedback", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }

    private func refresh() async {
        loading = true
        defer { loading = false }
        do { threads = try await store.loadAdminFeedback() }
        catch { self.error = error.localizedDescription }
    }
}

private struct AdminUsersView: View {
    @EnvironmentObject private var store: NesticStore
    @State private var users: [NestAdminUser] = []
    @State private var search = ""
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        List {
            Section {
                ForEach(users) { user in
                    NavigationLink {
                        AdminUserAccessView(user: user) { updated in
                            if let index = users.firstIndex(where: { $0.id == updated.id }) {
                                users[index] = updated
                            }
                        }
                    } label: {
                        AdminUserRow(user: user)
                    }
                }
                if loading && users.isEmpty { ProgressView("Loading accounts…") }
            } footer: { Text("Showing up to 200 recent accounts.") }
        }
        .formStyle()
        .navigationTitle("User accounts")
        .searchable(text: $search, prompt: "Name or email")
        .task(id: search) {
            do {
                if !search.isEmpty { try await Task.sleep(for: .milliseconds(300)) }
                try Task.checkCancellation()
                await refresh()
            } catch { }
        }
        .refreshable { await refresh() }
        .alert("Couldn’t load accounts", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }

    private func refresh() async {
        loading = true
        defer { loading = false }
        do {
            let result = try await store.loadAdminUsers(search: search)
            try Task.checkCancellation()
            users = result
        } catch is CancellationError { }
        catch { self.error = error.localizedDescription }
    }
}

private struct AdminUserAccessView: View {
    @EnvironmentObject private var store: NesticStore
    @State var user: NestAdminUser
    let onUpdate: (NestAdminUser) -> Void
    @State private var saving = false
    @State private var confirming = false
    @State private var error: String?

    var body: some View {
        List {
            Section("Account") { AdminUserRow(user: user) }
            Section {
                LabeledContent("Manual Pro access", value: user.manualPro == nil ? "Unavailable" : user.manualPro == true ? "Enabled" : "Not enabled")
                if saving {
                    ProgressView("Updating access…")
                } else {
                    Button(user.manualPro == true ? "Remove manual Pro" : "Grant manual Pro", role: user.manualPro == true ? .destructive : nil) {
                        confirming = true
                    }
                    .disabled(user.manualPro == nil)
                    .accessibilityIdentifier("admin.manualPro")
                }
            } header: { Text("Pro access") } footer: {
                Text("Manual access takes effect when the account next refreshes or signs in. Removing it does not cancel an App Store subscription.")
            }
        }
        .formStyle()
        .navigationTitle("Account access")
        .confirmationDialog(user.manualPro == true ? "Remove manual Pro access?" : "Grant manual Pro access?", isPresented: $confirming, titleVisibility: .visible) {
            Button(user.manualPro == true ? "Remove manual Pro" : "Grant manual Pro", role: user.manualPro == true ? .destructive : nil) {
                Task { await updateAccess() }
            }
        } message: { Text(user.email) }
        .alert("Couldn’t update access", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }

    private func updateAccess() async {
        guard !saving, let enabled = user.manualPro else { return }
        saving = true
        defer { saving = false }
        do {
            user = try await store.setManualProAccess(for: user, enabled: !enabled)
            onUpdate(user)
        } catch { self.error = error.localizedDescription }
    }
}

private struct AdminUserRow: View {
    let user: NestAdminUser

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(user.displayName).font(.headline)
            Text(user.email).font(.subheadline).textSelection(.enabled)
            HStack {
                Label(user.emailVerified ? "Verified" : "Unverified", systemImage: user.emailVerified ? "checkmark.seal" : "envelope")
                Spacer()
                Text("\(user.nestCount) \(user.nestCount == 1 ? "nest" : "nests")")
            }.font(.caption).foregroundStyle(.secondary)
            if let manualPro = user.manualPro {
                Text(manualPro ? "Manual Pro enabled" : "Manual Pro not enabled")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let date = user.createdAt {
                Text("Joined " + date.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 4)
    }
}
