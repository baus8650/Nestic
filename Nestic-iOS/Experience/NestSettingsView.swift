import SwiftUI
import AuthenticationServices
import StoreKit

struct NestSettingsView: View {
    @EnvironmentObject private var store: NesticStore
    @EnvironmentObject private var subscription: NesticSubscriptionStore
    @EnvironmentObject private var reminders: NesticReminderStore
    @AppStorage("nestic.shareUsageAnalytics") private var shareUsageAnalytics = false
    @State private var showTutorial = false
    @State private var showSwitcher = false
    @State private var showInvite = false
    @State private var showReminderEditor = false
    @State private var showQuietHoursEditor = false
    @State private var showCareLinks = false
    @State private var showFeedback = false
    @State private var showSupport = false
    @State private var showSafetyReport = false
    @State private var memberToRemove: NestPerson?
    @State private var editingReminder: NesticReminder?
    @State private var showProPaywall = false
    @State private var showSignOut = false
    @State private var showDeleteAccount = false
    @State private var showLeaveNest = false
    @State private var showAppleDeletion = false
    @State private var deleteBusy = false
    @State private var appleBusy = false
    @State private var error: String?
    @AppStorage(NesticAppearanceMode.storageKey) private var appearance = NesticAppearanceMode.system.rawValue

    private var nestReminders: [NesticReminder] {
        guard let nestID = store.selectedNestID else { return [] }
        return reminders.reminders(for: nestID)
    }

    var body: some View {
        List {
            Section {
                Toggle("Share optional usage analytics",isOn:$shareUsageAnalytics)
                    .onChange(of:shareUsageAnalytics) { _, enabled in if enabled && !store.isDemo { Task { await NesticUsageAnalytics.send(serverURL:store.serverURL,path:"settings") } } }
            } header: { Text("Privacy") } footer: { Text("Helps Nestic understand traction using app opens, device/app versions, language, time zone, and approximate country, region, and city. Only Nestic administrators see analytics. No tracker contents, precise location, or raw IP addresses are stored. You can turn this off at any time.") }

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
                    memberRow(person)
                }
                if store.canManageNest && store.selectedNest != nil {
                    Button { showInvite = true } label: { Label("Add a nest member", systemImage: "person.badge.plus") }
                        .accessibilityIdentifier("nest.addMember")
                }
            }
            Section("Nest settings") {
                Button { showSwitcher = true } label: { Label("Switch or create a nest", systemImage: "house") }
            }
            if store.selectedNestID != nil, store.canManageNest {
                Section("Caregiver access") {
                    if subscription.hasPredictionAccess {
                        Button { showCareLinks = true } label: {
                            Label("Temporary access links", systemImage: "person.crop.circle.badge.checkmark")
                        }
                        Text("Create a link for a sitter with selected subjects, trackers, history, and an expiration time. You can revoke it at any time.")
                            .font(.footnote).foregroundStyle(.secondary)
                    } else {
                        Label("Temporary access links are part of Nestic Pro.", systemImage: "lock.fill")
                            .foregroundStyle(.secondary)
                        Button("Unlock Pro") { showProPaywall = true }
                    }
                }
            }
            if store.selectedNestID != nil {
                Section("Reminders") {
                    if nestReminders.isEmpty {
                        Text("Create a reminder for medication, meals, chores, or any tracker that needs a nudge.")
                            .font(.footnote).foregroundStyle(.secondary)
                    } else {
                        ForEach(nestReminders) { reminder in
                            SharedReminderRow(reminder: reminder) { editingReminder = reminder }
                            .swipeActions {
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    deleteReminder(reminder)
                                }
                            }
                        }
                    }
                    Button { showReminderEditor = true } label: {
                        Label("Add a reminder", systemImage: "plus")
                    }
                    Text("Reminders follow the tracker’s visibility. Each member chooses notification, alarm, or both for their account. Alarms require iOS 26 or later and permission on each device.")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                Section("Forecast quiet hours") {
                    if store.hasForecastAccess {
                        if store.quietHoursPreferences.periods.isEmpty {
                            Text("No quiet hours are set. Forecasts will appear at any time.")
                                .font(.subheadline).foregroundStyle(.secondary)
                        } else {
                            ForEach(store.quietHoursPreferences.periods) { period in
                                Label(quietHoursTitle(period), systemImage: "moon.zzz.fill")
                            }
                            Text("Forecasts below \(store.quietHoursPreferences.confidenceThresholdPercent)% confidence advance by their learned cadence until the next modeled occurrence outside these daily periods.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        Button { showQuietHoursEditor = true } label: {
                            Label(store.quietHoursPreferences.periods.isEmpty ? "Add quiet hours" : "Manage quiet hours",
                                  systemImage: "moon.zzz.fill")
                        }
                    } else {
                        Text("Quiet hours are part of Forecasts in Nestic Pro.")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Button("Unlock Forecasts") { showProPaywall = true }
                    }
                }
            }
            if !store.isDemo {
                Section("Nestic Pro — Family") {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(subscription.hasPredictionAccess ? "Pro is active" : "Make shared updates easier")
                                .font(.subheadline.weight(.semibold))
                            Text(subscription.hasPredictionAccess
                                 ? "Forecasts, advanced trends, and predictive widgets are unlocked."
                                 : "Forecasts, 30-day trends, predictive widgets, and unlimited nests for your family.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: subscription.hasPredictionAccess ? "checkmark.seal.fill" : "sparkles")
                            .foregroundStyle(NesticTheme.forest)
                    }
                    Button(subscription.hasPredictionAccess ? "View Pro details" : "Unlock Pro · \(subscription.priceDescription)") {
                        showProPaywall = true
                    }
                    if subscription.hasPredictionAccess {
                        Button("Restore purchases") { Task { await subscription.restorePurchases() } }
                            .disabled(subscription.isLoading)
                    }
                }
            }
            if store.allTrackers.contains(where: { $0.isArchived == true }) {
                Section("Tracker archive") {
                    NavigationLink("Archived trackers") { ArchivedTrackersView() }
                }
            }
            Section("Appearance") {
                Picker("Theme", selection: $appearance) {
                    ForEach(NesticAppearanceMode.allCases) { mode in
                        Text(mode.title).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("settings.appearance")
                Text("System follows your iPhone’s appearance setting.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if !store.isDemo, store.currentUser?.isAdmin == true {
                Section("Administration") {
                    NavigationLink {
                        AdminDashboardView()
                    } label: {
                        Label("Admin dashboard", systemImage: "chart.bar.xaxis")
                    }
                }
            }
            Section("Help & legal") {
                Button { showTutorial = true } label: { Label("Getting started", systemImage: "book.closed") }
                    .accessibilityIdentifier("settings.tutorial")
                Button { showSafetyReport = true } label: {
                    Label("Report content or a member", systemImage: "flag")
                }
                Button { showFeedback = true } label: {
                    Label("Send feedback", systemImage: "bubble.left.and.bubble.right")
                }
                Button { showSupport = true } label: {
                    Label("Contact support", systemImage: "questionmark.circle")
                }
                .accessibilityIdentifier("settings.contactSupport")

                Link("Terms of Service", destination: NesticAppLinks.termsURL)
                Link("App license", destination: NesticAppLinks.appLicenseURL)
                Link("Privacy policy", destination: NesticAppLinks.privacyURL)
            }
            if !store.isDemo {
                Section("Account security") {
                    NesticAppleButton(label: .continue, onCredential: linkApple, onError: { error = $0 })
                        .frame(height: 46)
                        .overlay { if appleBusy { ProgressView().tint(.white) } }
                        .disabled(appleBusy)
                    if appleBusy { ProgressView("Linking Apple…") }
                    Text("Link Apple to this Nestic account so you can sign in without remembering another password.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            if !store.isDemo {
                Section("Account data") {
                    Link("Manage subscriptions", destination: NesticAppLinks.subscriptionsURL)
                    if store.selectedNestID != nil && !store.isNestOwner {
                        Button("Leave this nest", role: .destructive) { showLeaveNest = true }
                        Text("Leaving immediately removes this nest’s people and shared updates from your account. You can report a concern above before you leave.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Button("Delete account", role: .destructive) { showDeleteAccount = true }
                        .disabled(deleteBusy || store.isLoading)
                    Text("This permanently deletes your account and your recorded updates. Shared nests stay available to other members when possible. Deleting your account does not cancel an Apple subscription; manage or cancel it above.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
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
                        Text("Little updates. Bigger picture.").font(.caption).foregroundStyle(.secondary)
                    Text("Version 1.0").font(.caption2).foregroundStyle(.tertiary)
                }.frame(maxWidth: .infinity).padding(.vertical, 12)
            }.listRowBackground(Color.clear)
        }.formStyle().navigationTitle("Your nest")
            .sheet(isPresented: $showTutorial) { NesticTutorialView() }
            .sheet(isPresented: $showSwitcher) { NestSwitcherSheet() }
            .sheet(isPresented: $showInvite) { AddMemberSheet() }
            .sheet(isPresented: $showReminderEditor) { ReminderEditorSheet() }
            .sheet(isPresented: $showQuietHoursEditor) { QuietHoursSettingsSheet(initial: store.quietHoursPreferences) }
            .sheet(isPresented: $showCareLinks) { CareLinkSettingsView() }
            .sheet(isPresented: $showFeedback) { NavigationStack { FeedbackView() } }
            .sheet(isPresented: $showSupport) { NavigationStack { FeedbackView(supportRequest: true) } }
            .sheet(isPresented: $showSafetyReport) { NavigationStack { FeedbackView(reportConcern: true) } }
            .confirmationDialog("Remove access to this nest?", isPresented: Binding(get: { memberToRemove != nil }, set: { if !$0 { memberToRemove = nil } }), titleVisibility: .visible) {
                Button("Remove access", role: .destructive) {
                    guard let person = memberToRemove else { return }
                    Task {
                        do { try await store.removeMember(person) }
                        catch { self.error = error.localizedDescription }
                        memberToRemove = nil
                    }
                }
            } message: { Text("This member will no longer be able to view or record updates in your nest.") }
            .confirmationDialog("Leave this nest?", isPresented: $showLeaveNest, titleVisibility: .visible) {
                Button("Leave nest", role: .destructive) {
                    Task {
                        do { try await store.leaveSelectedNest() }
                        catch { self.error = error.localizedDescription }
                    }
                }
            } message: {
                Text("You will immediately stop seeing this nest’s shared updates. This cannot be undone without an invitation from an owner.")
            }
            .sheet(isPresented: $showAppleDeletion) { AppleAccountDeletionView() }
            .sheet(item: $editingReminder) { reminder in ReminderEditorSheet(reminder: reminder) }
            .sheet(isPresented: $showProPaywall) { NesticProPaywall() }
            .alert(store.isDemo ? "Leave the sample nest?" : "Sign out of Nestic?", isPresented: $showSignOut) {
                Button(store.isDemo ? "Leave sample nest" : "Sign out", role: .destructive) { store.signOut() }
                Button("Cancel", role: .cancel) { showSignOut = false }
            }
            .alert("Delete your account?", isPresented: $showDeleteAccount) {
                Button("Delete account", role: .destructive) {
                    if store.currentUser?.appleLinked == true { showAppleDeletion = true }
                    else { deleteAccount() }
                }
                Button("Cancel", role: .cancel) { showDeleteAccount = false }
            } message: {
                Text("This cannot be undone. Your account, private nests, recorded updates, and attached photos will be removed. Shared nests may remain for other members. Apple subscriptions continue until you cancel them in subscription settings.")
            }
            .refreshable { do { try await store.refresh() } catch let caughtError { self.error = caughtError.localizedDescription } }
            .alert("Couldn’t refresh", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") { error = nil }
            } message: { Text(error ?? "") }
    }

    private func quietHoursTitle(_ period: NestQuietHoursPeriod) -> String {
        "\(quietHoursDate(for: period.startMinute).formatted(.dateTime.hour().minute())) – \(quietHoursDate(for: period.endMinute).formatted(.dateTime.hour().minute()))"
    }

    private func quietHoursDate(for minute: Int) -> Date {
        Calendar.current.date(byAdding: .minute, value: minute,
                              to: Calendar.current.startOfDay(for: Date())) ?? Date()
    }

    private func linkApple(_ credential: AppleCredentialPayload) {
        appleBusy = true; error = nil
        Task {
            defer { appleBusy = false }
            do {
                try await store.linkApple(identityToken: credential.identityToken,
                                          user: credential.user,
                                          email: credential.email,
                                          displayName: credential.displayName,
                                          nonce: credential.nonce)
            } catch let caughtError { self.error = caughtError.localizedDescription }
        }
    }

    @ViewBuilder
    private func memberRow(_ person: NestPerson) -> some View {
        let roleTitle = person.role?.capitalized ?? "Member"
        HStack(spacing: 12) {
            Text(person.initials)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(NesticTheme.forest)
                .frame(width: 42, height: 42)
                .background(NesticTheme.lime.opacity(0.3), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(person.displayName).font(.subheadline.weight(.semibold))
                Text(person.email).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(roleTitle).font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .swipeActions {
            if store.isNestOwner, person.id != store.currentUser?.id {
                Button("Remove access", role: .destructive) { memberToRemove = person }
            }
        }
    }

    private func deleteReminder(_ reminder: NesticReminder) {
        Task {
            do {
                try await store.deleteReminder(reminder)
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private func deleteAccount() {
        deleteBusy = true
        error = nil
        Task {
            defer { deleteBusy = false }
            do { try await store.deleteAccount() }
            catch let caughtError { self.error = caughtError.localizedDescription }
        }
    }
}

private struct AppleAccountDeletionView: View {
    @EnvironmentObject private var store: NesticStore
    @Environment(\.dismiss) private var dismiss
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Confirm with your linked Apple account to delete your Nestic account and remove its Apple sign-in authorization.")
                    NesticAppleButton(label: .continue, onCredential: { delete(apple: $0) }, onError: { error = $0 })
                        .frame(height: 48).disabled(busy)
                    if busy { ProgressView("Deleting account…") }
                }
                Section {
                    Link("Manage subscriptions", destination: NesticAppLinks.subscriptionsURL)
                    Text("Deleting Nestic does not cancel your Apple subscription.")
                }
                Section {
                    Button("Delete without Apple confirmation", role: .destructive) { delete(apple: nil) }
                        .disabled(busy)
                } footer: {
                    Text("If you cannot confirm with Apple, you can still delete your Nestic data. Remove Nestic from Sign in with Apple in Settings afterward.")
                }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .formStyle()
            .navigationTitle("Delete account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(busy) } }
            .interactiveDismissDisabled(busy)
        }
    }

    private func delete(apple: AppleCredentialPayload?) {
        busy = true
        Task {
            defer { busy = false }
            do { try await store.deleteAccount(apple: apple); dismiss() }
            catch { self.error = error.localizedDescription }
        }
    }
}

struct QuietHoursSettingsSheet: View {
    @EnvironmentObject private var store: NesticStore
    @Environment(\.dismiss) private var dismiss
    @State private var periods: [NestQuietHoursPeriod]
    @State private var thresholdPercent: Int

    init(initial: NestQuietHoursPreferences) {
        _periods = State(initialValue: initial.periods)
        _thresholdPercent = State(initialValue: initial.confidenceThresholdPercent)
    }

    private var hasInvalidPeriod: Bool {
        periods.contains { $0.startMinute == $0.endMinute }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Quiet hours repeat every day. A period can cross midnight, such as 23:00 to 06:00. During a quiet period, Nestic hides a forecast unless its confidence reaches your threshold.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }

                Section("Daily quiet periods") {
                    ForEach($periods) { $period in
                        VStack(alignment: .leading, spacing: 8) {
                            DatePicker("From", selection: timeBinding(for: $period, start: true), displayedComponents: .hourAndMinute)
                            DatePicker("Until", selection: timeBinding(for: $period, start: false), displayedComponents: .hourAndMinute)
                            if period.startMinute == period.endMinute {
                                Text("Choose different start and end times.")
                                    .font(.caption).foregroundStyle(.red)
                            }
                        }
                        .swipeActions {
                            Button("Delete", systemImage: "trash", role: .destructive) {
                                periods.removeAll { $0.id == period.id }
                            }
                        }
                    }
                    Button { addPeriod() } label: {
                        Label("Add another period", systemImage: "plus")
                    }
                }

                Section("Quiet-hour threshold") {
                    Picker("Minimum confidence", selection: $thresholdPercent) {
                        ForEach(Array(stride(from: 50, through: 100, by: 5)), id: \.self) { value in
                            Text("\(value)%").tag(value)
                        }
                    }
                    Text("For example, at 80%, a 65%-confidence forecast during quiet hours is hidden, while an 80% forecast is still shown.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .formStyle()
            .navigationTitle("Quiet hours")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        store.updateQuietHours(periods: periods, confidenceThresholdPercent: thresholdPercent)
                        dismiss()
                    }
                    .disabled(hasInvalidPeriod)
                }
            }
        }
    }

    private func addPeriod() {
        periods.append(NestQuietHoursPeriod(startMinute: 23 * 60, endMinute: 6 * 60))
    }

    private func timeBinding(for period: Binding<NestQuietHoursPeriod>, start: Bool) -> Binding<Date> {
        Binding(
            get: {
                date(for: start ? period.wrappedValue.startMinute : period.wrappedValue.endMinute)
            },
            set: { value in
                let minute = Calendar.current.component(.hour, from: value) * 60 + Calendar.current.component(.minute, from: value)
                if start {
                    period.wrappedValue.startMinute = minute
                } else {
                    period.wrappedValue.endMinute = minute
                }
            }
        )
    }

    private func date(for minute: Int) -> Date {
        Calendar.current.date(byAdding: .minute, value: minute,
                              to: Calendar.current.startOfDay(for: Date())) ?? Date()
    }
}

struct ReminderEditorSheet: View {
    @EnvironmentObject private var store: NesticStore
    @EnvironmentObject private var reminders: NesticReminderStore
    @Environment(\.dismiss) private var dismiss
    let reminder: NesticReminder?
    @State private var routineID: UUID?
    @State private var draft: ReminderScheduleDraft
    @State private var subjectID: UUID?
    @State private var medicationTrackerID: UUID?
    @State private var cadence: NesticReminderCadence
    @State private var mealTrackerID: UUID?
    @State private var delayMinutes: Int
    @State private var anchorDate: Date
    @State private var intervalHours: String = "8"
    @State private var intervalUnit: String = "hours"
    private var resolvedIntervalHours: Double? { Double(intervalHours).map { $0 * (intervalUnit == "minutes" ? 1.0 / 60.0 : intervalUnit == "days" ? 24 : 1) } }
    @State private var totalPills: String = ""
    @State private var busy = false
    @State private var error: String?

    init(reminder: NesticReminder? = nil, initialSubjectID: UUID? = nil, initialTrackerID: UUID? = nil, initialDate: Date? = nil) {
        self.reminder = reminder
        _routineID = State(initialValue: reminder?.routineID)
        _draft = State(initialValue: ReminderScheduleDraft(reminder))
        _subjectID = State(initialValue: reminder?.subjectID ?? initialSubjectID)
        _medicationTrackerID = State(initialValue: reminder?.medicationTrackerID ?? initialTrackerID)
        _cadence = State(initialValue: reminder?.cadence ?? (initialTrackerID == nil ? .everyOtherDay : .afterDose))
        _mealTrackerID = State(initialValue: reminder?.linkedMealTrackerID)
        _delayMinutes = State(initialValue: reminder?.delayMinutes ?? 5)
        _anchorDate = State(initialValue: reminder?.anchorDate ?? initialDate ?? Calendar.current.startOfDay(for: Date()))
        let hours = reminder?.intervalHours ?? 8
        let unit = hours < 1 ? "minutes" : hours >= 24 && hours.truncatingRemainder(dividingBy: 24) == 0 ? "days" : "hours"
        _intervalUnit = State(initialValue: unit)
        _intervalHours = State(initialValue: String(format: "%g", hours * (unit == "minutes" ? 60 : unit == "days" ? 1.0 / 24 : 1)))
        _totalPills = State(initialValue: reminder?.totalPills.map(String.init) ?? "")
    }

    private var subject: NestSubject? {
        guard let subjectID else { return store.subjects.first }
        return store.subjects.first { $0.id == subjectID }
    }

    private var trackers: [NestTracker] {
        guard let subject else { return [] }
        return store.trackers(for: subject)
    }

    private var medicationTracker: NestTracker? {
        trackers.first { $0.id == medicationTrackerID } ?? trackers.first
    }

    private var mealTracker: NestTracker? {
        trackers.first { $0.id == mealTrackerID } ?? trackers.first
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("For", selection: Binding(
                        get: { subjectID ?? store.subjects.first?.id ?? UUID() },
                        set: { subjectID = $0 }
                    )) {
                        ForEach(store.subjects) { subject in
                            Label("\(subject.emoji)  \(subject.name)", systemImage: "person.fill").tag(subject.id)
                        }
                    }
                    Picker("Remind me about", selection: $routineID) {
                        Text("An individual tracker").tag(UUID?.none)
                        ForEach(store.routines.filter { routine in routine.targets.contains { $0.entityID == subject?.id } }) { routine in
                            Text("Routine · \(routine.name)").tag(Optional(routine.id))
                        }
                    }
                    if routineID == nil {
                        Picker("Tracker", selection: $medicationTrackerID) {
                            Text("Choose a tracker").tag(UUID?.none)
                            ForEach(trackers) { Text($0.name).tag(Optional($0.id)) }
                        }
                    }
                } header: {
                    Text("Reminder")
                } footer: {
                    Text("Use a simple update tracker for one-tap logging from the notification. Trackers that require a number or yes/no value will open Nestic for the full entry.")
                }

                ReminderScheduleFields(draft: $draft, trackers: trackers, allowsPillTotal: routineID == nil, isRoutine: routineID != nil)

                if let error {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }
            }
            .formStyle()
            .navigationTitle(reminder == nil ? "New reminder" : "Edit reminder")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if subjectID == nil { subjectID = store.subjects.first?.id }
                if medicationTrackerID == nil { medicationTrackerID = trackers.first?.id }
                if mealTrackerID == nil {
                    mealTrackerID = trackers.first {
                        let name = $0.name.lowercased()
                        return name.contains("food") || name.contains("meal") || name.contains("feed")
                    }?.id ?? trackers.first { $0.id != medicationTrackerID }?.id
                }
            }
            .onChange(of: subjectID) { _, _ in
                if let routineID, !store.routines.contains(where: { $0.id == routineID && $0.targets.contains { $0.entityID == subjectID } }) { self.routineID = nil }
                if !trackers.contains(where: { $0.id == medicationTrackerID }) {
                    medicationTrackerID = trackers.first?.id
                }
                if !trackers.contains(where: { $0.id == mealTrackerID }) {
                    mealTrackerID = trackers.first { $0.id != medicationTrackerID }?.id
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(busy ? "Saving…" : "Save") { save() }
                        .disabled(busy || subject == nil || (routineID == nil && medicationTracker == nil))
                }
            }
        }
    }

    private func save() {
        guard let nestID = store.selectedNestID, let subject else { return }
        let routine = store.routines.first { $0.id == routineID }
        guard routine != nil || medicationTracker != nil else { return }
        let updated: NesticReminder
        do {
            updated = try draft.makeReminder(nestID: nestID, subject: subject, targetID: routine?.id ?? medicationTracker!.id, targetName: routine?.name ?? medicationTracker!.name, routineID: routine?.id, previous: reminder)
        } catch { self.error = error.localizedDescription; return }
        busy = true
        error = nil
        Task {
            defer { busy = false }
            do {
                try await store.saveReminder(updated, isNew: reminder == nil)
                if let saved = reminders.reminders(for: nestID).first(where: { $0.medicationTrackerID == updated.medicationTrackerID && $0.subjectID == subject.id && $0.cadence == updated.cadence }) { try await store.setReminderDelivery(draft.delivery, for: saved) }
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    private var scheduleHelpText: String {
        switch cadence {
        case .everyOtherDay:
            "Nestic will continue this schedule every \(reminder?.recurrenceDays ?? 2) days and refresh upcoming reminders as your time zone changes."
        case .monthly:
            "Nestic will remind you on this day each month. Dates such as the 31st use the last day of shorter months."
        case .yearly:
            "Nestic will remind you on this month and day each year. February 29 uses February 28 in non-leap years."
        case .afterDose:
            "Each logged update restarts the reminder interval."
        case .afterMeal:
            "Nestic will notify you after the linked meal tracker is logged."
        }
    }
}

struct NestSwitcherSheet: View {
    @EnvironmentObject private var store: NesticStore
    @EnvironmentObject private var subscription: NesticSubscriptionStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var busy = false
    @State private var error: String?
    @State private var showProPaywall = false
    var body: some View {
        NavigationStack {
            Form {
                if busy {
                    Section { HStack(spacing: 10) { ProgressView(); Text("Loading your nest…").foregroundStyle(.secondary) } }
                }
                if !store.nests.isEmpty {
                    Section("Your nests") {
                        ForEach(store.nests) { nest in
                            Button {
                                busy = true
                                Task {
                                    defer { busy = false }
                                    do { try await store.selectNest(nest); dismiss() }
                                    catch let caughtError { self.error = caughtError.localizedDescription }
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
                        guard store.isDemo || store.nests.isEmpty || subscription.hasPredictionAccess else {
                            showProPaywall = true
                            return
                        }
                        busy = true; error = nil
                        Task {
                            defer { busy = false }
                            do { try await store.createNest(name: name); dismiss() }
                            catch let caughtError { self.error = caughtError.localizedDescription }
                        }
                    } label: {
                        HStack { Label("Create nest", systemImage: "plus.circle"); if busy { Spacer(); ProgressView() } }
                    }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || busy)
                        .accessibilityIdentifier("nest.create")
                } header: { Text("Start something together") } footer: {
                    if !store.isDemo && !store.nests.isEmpty && !subscription.hasPredictionAccess {
                        Text("Your first nest is free. Nestic Pro unlocks additional nests without limiting the people, subjects, trackers, or updates in your nest.")
                    } else {
                        Text("Keep different groups in their own nests. Each has its own members, trackers, and activity.")
                    }
                }
                if let error { Text(error).foregroundStyle(.red) }
            }.formStyle().navigationTitle("Find your nest").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() }.disabled(busy) } }
                .interactiveDismissDisabled(busy)
                .sheet(isPresented: $showProPaywall) { NesticProPaywall() }
        }
    }
}

struct AddMemberSheet: View {
    @EnvironmentObject private var store: NesticStore
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var role = "member"
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
                    Text(store.isDemo ? "This adds a sample person locally. No invitation is sent." : "They’ll need to create a Nestic account first. Adding their email gives them access immediately; no email invitation is sent. They can pull to refresh to find the nest.")
                }
                Section {
                    Picker("Access", selection: $role) {
                        Text("Member").tag("member")
                        if store.isNestOwner {
                            Text("Owner").tag("owner")
                        }
                    }
                    if role == "owner" {
                        Text("Owners have equal control of this nest. You can add more than one owner.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                } header: { Text("Nest access") }
                if let error { Text(error).foregroundStyle(.red) }
                Section {
                    PrimaryButton(title: "Add to nest", symbol: "person.badge.plus", busy: busy) {
                        busy = true; error = nil
                        Task {
                            defer { busy = false }
                            do { try await store.addMember(email: email, role: role); dismiss() }
                            catch let caughtError { self.error = caughtError.localizedDescription }
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

struct CareLinkSettingsView: View {
    @EnvironmentObject private var store: NesticStore
    @Environment(\.dismiss) private var dismiss
    @State private var showCreate = false
    @State private var newlyCreatedLink: NestCareLink?
    @State private var linkToRevoke: NestCareLink?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Create a temporary link for a house sitter, baby sitter, pet sitter, or helper. Select exactly what they can see and do, then share the link from this device.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                if store.careLinks.isEmpty {
                    Section {
                        ContentUnavailableView("No caregiver links", systemImage: "person.crop.circle.badge.plus",
                                               description: Text("Create a link when someone needs limited access to your nest."))
                    }
                } else {
                    Section("Active and previous links") {
                        ForEach(store.careLinks) { link in
                            VStack(alignment: .leading, spacing: 9) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(link.label).font(.headline)
                                        Text(careLinkStatus(link))
                                            .font(.caption)
                                            .foregroundStyle(link.isActive ? Color.secondary : Color.red)
                                    }
                                    Spacer()
                                    if link.isActive { Image(systemName: "checkmark.circle.fill").foregroundStyle(NesticTheme.forest) }
                                }
                                Text("\(link.entityIDs.count) subject\(link.entityIDs.count == 1 ? "" : "s") · \(link.actionIDs.count) tracker\(link.actionIDs.count == 1 ? "" : "s") · \(permissionSummary(link))")
                                    .font(.caption).foregroundStyle(.secondary)
                                if let url = link.shareURL(serverURL: store.serverURL) {
                                    ShareLink(item: url) {
                                        Label("Share link", systemImage: "square.and.arrow.up")
                                    }
                                    .disabled(!link.isActive)
                                } else if link.isActive {
                                    Text("For security, this link can only be shared from the device where it was created.")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                if link.isActive {
                                    Button("Revoke access", role: .destructive) { linkToRevoke = link }
                                        .font(.subheadline)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                if let error { Text(error).foregroundStyle(.red) }
                Section {
                    Button { showCreate = true } label: {
                        Label("Create caregiver link", systemImage: "plus.circle.fill")
                    }
                }
            }
            .formStyle()
            .navigationTitle("Caregiver access")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
            .task {
                do { _ = try await store.listCareLinks() }
                catch let caughtError { self.error = caughtError.localizedDescription }
            }
            .sheet(isPresented: $showCreate) {
                CareLinkEditorView { link in
                    newlyCreatedLink = link
                    showCreate = false
                }
            }
            .sheet(item: $newlyCreatedLink) { link in
                CareLinkShareView(link: link)
            }
            .confirmationDialog("Revoke this caregiver link?", isPresented: Binding(
                get: { linkToRevoke != nil },
                set: { if !$0 { linkToRevoke = nil } }
            ), presenting: linkToRevoke) { link in
                Button("Revoke access", role: .destructive) {
                    Task {
                        do { try await store.revokeCareLink(link) }
                        catch let caughtError { self.error = caughtError.localizedDescription }
                    }
                }
                Button("Cancel", role: .cancel) { linkToRevoke = nil }
            } message: { link in
                Text("Anyone with this link will lose access immediately.")
            }
        }
    }

    private func permissionSummary(_ link: NestCareLink) -> String {
        switch (link.canLog, link.canViewHistory) {
        case (true, true): "record + history"
        case (true, false): "record only"
        case (false, true): "history only"
        case (false, false): "no actions"
        }
    }

    private func careLinkStatus(_ link: NestCareLink) -> String {
        if link.revokedAt != nil { return "Revoked" }
        if link.expiresAt <= Date() { return "Expired" }
        let formattedDate = link.expiresAt.formatted(date: .abbreviated, time: .shortened)
        return "Expires \(formattedDate)"
    }
}

private struct CareLinkEditorView: View {
    @EnvironmentObject private var store: NesticStore
    @Environment(\.dismiss) private var dismiss
    let onCreated: (NestCareLink) -> Void
    @State private var label = "Pet sitter"
    @State private var expiresAt = Date().addingTimeInterval(3 * 24 * 60 * 60)
    @State private var canLog = true
    @State private var canViewHistory = true
    @State private var selectedEntityIDs: Set<UUID> = []
    @State private var selectedActionIDs: Set<UUID> = []
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Link name", text: $label)
                    DatePicker("Expires", selection: $expiresAt, in: Date().addingTimeInterval(300)...,
                               displayedComponents: [.date, .hourAndMinute])
                } header: {
                    Text("Link details")
                } footer: {
                    Text("Links expire automatically after the time you choose and can be revoked sooner.")
                }
                Section("Permissions") {
                    Toggle("Allow recording updates", isOn: $canLog)
                    Toggle("Allow viewing recent history", isOn: $canViewHistory)
                }
                Section("Subjects") {
                    if store.subjects.isEmpty {
                        Text("Add a subject to your nest first.").foregroundStyle(.secondary)
                    } else {
                        ForEach(store.subjects) { subject in
                            selectionRow(subject.name, subtitle: subject.kind.title,
                                         selected: selectedEntityIDs.contains(subject.id), symbol: subject.emoji) {
                                toggle(subject.id, in: &selectedEntityIDs)
                            }
                        }
                    }
                }
                Section {
                    if store.trackers.isEmpty {
                        Text("Add a tracker to your nest first.").foregroundStyle(.secondary)
                    } else {
                        ForEach(store.trackers.filter { !$0.isPrivate }) { tracker in
                            Button { toggle(tracker.id, in: &selectedActionIDs) } label: {
                                HStack(spacing: 10) {
                                    TrackerIconView(tracker: tracker, size: .subheadline)
                                        .foregroundStyle(trackerColor(tracker))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(tracker.name).foregroundStyle(.primary)
                                        Text(tracker.valueType.title).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: selectedActionIDs.contains(tracker.id) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(selectedActionIDs.contains(tracker.id) ? NesticTheme.forest : .secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } header: {
                    Text("Trackers")
                } footer: {
                    Text("The recipient can only see and record the subjects and trackers selected here. Photo uploads are not available through caregiver links.")
                }
                if let error { Text(error).foregroundStyle(.red) }
                Section {
                    PrimaryButton(title: "Create and share", symbol: "square.and.arrow.up", busy: busy) { create() }
                        .disabled(busy || selectedEntityIDs.isEmpty || selectedActionIDs.isEmpty || (!canLog && !canViewHistory))
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            .formStyle()
            .navigationTitle("New caregiver link")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(busy) }
            }
            .task {
                if selectedEntityIDs.isEmpty { selectedEntityIDs = Set(store.subjects.map(\.id)) }
                if selectedActionIDs.isEmpty { selectedActionIDs = Set(store.trackers.filter { !$0.isPrivate }.map(\.id)) }
            }
        }
    }

    private func selectionRow(_ title: String, subtitle: String, selected: Bool, symbol: String,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(symbol).frame(width: 28, height: 28).background(NesticTheme.lime.opacity(0.35), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(.primary)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? NesticTheme.forest : .secondary)
            }
        }
        .buttonStyle(.plain)
    }

    private func toggle(_ id: UUID, in set: inout Set<UUID>) {
        if set.contains(id) { set.remove(id) } else { set.insert(id) }
    }

    private func create() {
        busy = true
        error = nil
        Task {
            defer { busy = false }
            do {
                let link = try await store.createCareLink(label: label, expiresAt: expiresAt,
                                                          entityIDs: Array(selectedEntityIDs),
                                                          actionIDs: Array(selectedActionIDs),
                                                          canLog: canLog, canViewHistory: canViewHistory)
                onCreated(link)
                dismiss()
            } catch let caughtError { self.error = caughtError.localizedDescription }
        }
    }
}

private struct CareLinkShareView: View {
    @EnvironmentObject private var store: NesticStore
    @Environment(\.dismiss) private var dismiss
    let link: NestCareLink

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                Label("Link ready to share", systemImage: "checkmark.circle.fill")
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .foregroundStyle(NesticTheme.forest)
                Text("Send this link to the sitter now. For security, Nestic does not show the private token again after this screen is closed.")
                    .font(.subheadline).foregroundStyle(.secondary)
                if let url = link.shareURL(serverURL: store.serverURL) {
                    ShareLink(item: url) {
                        Label("Share caregiver link", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    Text(url.absoluteString)
                        .font(.footnote.monospaced())
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(24)
            .background(NesticTheme.paper)
            .navigationTitle("Share access")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        }
    }
}

struct NesticProPaywall: View {
    @EnvironmentObject private var subscription: NesticSubscriptionStore
    @Environment(\.dismiss) private var dismiss
    @State private var loadingProduct = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Nestic Pro", systemImage: "sparkles")
                            .font(.system(.title2, design: .rounded, weight: .bold))
                            .foregroundStyle(NesticTheme.forest)
                        Text("Know what is likely next, and make the whole family’s updates a little easier.")
                            .font(.title3.weight(.semibold))
                        Text(subscription.product?.isFamilyShareable == true
                             ? "This subscription supports Apple Family Sharing. The basic Nestic experience stays free."
                             : "The basic Nestic experience stays free. Subscribe to unlock Pro features.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 13) {
                        proFeature("wand.and.stars", "Personalized forecasts", "Estimate the next meal, outing, medication, wellness update, chore, or routine event.")
                        proFeature("square.stack.3d.up.fill", "Routines", "Bundle trackers across your nest and record related habits together.")
                        proFeature("chart.xyaxis.line", "Advanced trends", "Unlock 30-day patterns and longer-term insight into what is changing.")
                        proFeature("widget.small", "Predictive widgets", "See the next likely event alongside your family’s quick-log widgets.")
                        proFeature("person.crop.circle.badge.checkmark", "Temporary caregiver links", "Share a controlled, expiring view for a sitter without adding them to your nest.")
                        proFeature("house", "Unlimited nests", "Keep separate spaces for family, pets, plants, or another group.")
                    }
                    .padding(18)
                    .background(NesticTheme.card, in: RoundedRectangle(cornerRadius: 20))

                    Text("Recording trackers, shared activity, health reports, and reminders remain available without a subscription.")
                        .font(.footnote).foregroundStyle(.secondary)

                    if subscription.hasPredictionAccess {
                        Label("Pro is active.", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(NesticTheme.forest)
                            .font(.subheadline.weight(.semibold))
                    } else {
                        Button {
                            Task {
                                if subscription.product == nil {
                                    loadingProduct = true
                                    await subscription.load()
                                    loadingProduct = false
                                }
                                await subscription.purchase()
                            }
                        } label: {
                            HStack {
                                Text(loadingProduct || subscription.isLoading ? "Preparing…" : "Unlock Pro · \(subscription.priceDescription)")
                                Spacer()
                                Image(systemName: "arrow.right")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(loadingProduct || subscription.isLoading || subscription.product == nil)

                        if subscription.product == nil && !loadingProduct {
                            Button("Retry subscription options") { Task { await loadProduct() } }
                        }

                        Button("Restore purchases") { Task { await subscription.restorePurchases() } }
                            .frame(maxWidth: .infinity)
                            .disabled(subscription.isLoading)
                    }

                    if let error = subscription.errorMessage {
                        Text(error).font(.footnote).foregroundStyle(.red)
                    }
                    Text("Subscriptions renew automatically until canceled in your Apple account settings. Forecasts are estimates and are not health or professional advice.")
                        .font(.caption).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 12) {
                        Link("Manage subscriptions", destination: NesticAppLinks.subscriptionsURL)
                        Link("Terms of Service", destination: NesticAppLinks.termsURL)
                        Link("App license", destination: NesticAppLinks.appLicenseURL)
                        Link("Privacy policy", destination: NesticAppLinks.privacyURL)
                    }.font(.footnote)
                }
                .padding(22)
            }
            .background(NesticTheme.paper)
            .navigationTitle("Nestic Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
            .task { await loadProduct() }
        }
    }

    private func loadProduct() async {
        loadingProduct = true
        defer { loadingProduct = false }
        await subscription.load()
    }

    private func proFeature(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).foregroundStyle(NesticTheme.forest).frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}


private struct ArchivedTrackersView: View {
    @EnvironmentObject private var store: NesticStore
    @State private var clearing: NestTracker?
    @State private var deleting: NestTracker?
    @State private var restoring: NestTracker?
    @State private var restoreSubject: NestSubject?
    @State private var selectedEntry: NestEntry?
    @State private var error: String?
    var body: some View {
        List {
            ForEach(store.allTrackers.filter { $0.isArchived == true }) { tracker in
                Section {
                    DisclosureGroup {
                        let entries = store.entries.filter { $0.actionId == tracker.id }.sorted { $0.occurredAt > $1.occurredAt }
                        if entries.isEmpty { Text("No recorded history").foregroundStyle(.secondary) }
                        ForEach(entries) { entry in
                            Button { selectedEntry = entry } label: {
                                VStack(alignment: .leading) {
                                    Text(store.subjects.first { $0.id == entry.entityId }?.name ?? "Update")
                                    Text(entry.occurredAt, format: .dateTime.month().day().year().hour().minute()).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    } label: {
                        VStack(alignment: .leading) {
                            Text(tracker.name)
                            Text(tracker.isPrivate ? tracker.privacyLabel : "Everyone").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if tracker.isPrivate ? (store.canLog && tracker.privateOwnerId == store.currentUser?.id) : store.canManageNest {
                        Menu("Restore tracker…") {
                            ForEach(store.subjects) { subject in
                                Button("Restore for \(subject.name)") { restoring = tracker; restoreSubject = subject }
                            }
                        }
                        Button("Clear history…", role: .destructive) { clearing = tracker }
                        Button("Delete tracker permanently…", role: .destructive) { deleting = tracker }
                    }
                }
            }
            if !store.isDemo { Button("Load older history") { Task { try? await store.loadOlderEntries() } } }
        }
        .navigationTitle("Archived trackers")
        .sheet(item: $selectedEntry) { EntryDetailSheet(entry: $0) }
        .alert("Restore \(restoring?.name ?? "tracker")?", isPresented: Binding(get: { restoring != nil }, set: { if !$0 { restoring = nil } })) {
            Button("Restore tracker") {
                guard let tracker = restoring, let subject = restoreSubject else { return }; restoring = nil
                Task { do { try await store.restoreTracker(tracker, subject: subject) } catch { self.error = error.localizedDescription } }
            }
            Button("Cancel", role: .cancel) { restoring = nil }
        } message: { Text("This makes the tracker active and adds a quick-log shortcut for \(restoreSubject?.name ?? "this subject"). Saved history, photos, and sharing restrictions stay. Previously removed routines and reminder schedules are not recreated; set those up again if needed.") }
        .alert("Permanently delete \(deleting?.name ?? "tracker")?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Delete tracker and history", role: .destructive) {
                guard let tracker = deleting else { return }; deleting = nil
                Task { do { try await store.permanentlyDeleteTracker(tracker) } catch { self.error = error.localizedDescription } }
            }
            Button("Cancel", role: .cancel) { deleting = nil }
        } message: { Text("This permanently deletes the tracker and every update, note, and photo across all subjects in this nest. Quick-log shortcuts, its reminders, and its routine items are removed. Unlike archiving, nothing is kept for restoration. This cannot be undone.") }
        .alert("Permanently clear history?", isPresented: Binding(get: { clearing != nil }, set: { if !$0 { clearing = nil } })) {
            Button("Clear history", role: .destructive) {
                guard let tracker = clearing else { return }; clearing = nil
                Task { do { try await store.clearTrackerHistory(tracker) } catch { self.error = error.localizedDescription } }
            }
            Button("Cancel", role: .cancel) { clearing = nil }
        } message: { Text("Every update, note, and photo for this tracker across all subjects in this nest will be permanently removed. The archived tracker stays. This cannot be undone.") }
        .alert("Tracker action failed", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") { error = nil } } message: { Text(error ?? "") }
    }
}
