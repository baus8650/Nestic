import SwiftUI

extension NesticStore {
    var onboardingScope: String {
        guard let currentUser, !isDemo else { return "" }
        return serverURL + "|" + currentUser.id.uuidString
    }
}

enum NesticOnboarding {
    static let tutorialViewedKey = "nestic.tutorial.viewed.v1"

    static func contains(_ scopes: String, _ scope: String) -> Bool {
        !scope.isEmpty && scopes.components(separatedBy: "\n").contains(scope)
    }
    static func remembering(_ scope: String, in scopes: String) -> String {
        guard !scope.isEmpty, !contains(scopes, scope) else { return scopes }
        return scopes.isEmpty ? scope : scopes + "\n" + scope
    }
}

struct NesticTutorialView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(NesticOnboarding.tutorialViewedKey) private var tutorialViewed = false
    @State private var step = 0

    private let pages: [(symbol: String, title: String, body: String, example: String, plan: String)] = [
        ("house.fill", "Keep track of your nest", "Your nest is a private place for routines, habits, and everyday updates. Create your first nest, or ask a nest owner to add your account by email.", "One nest is free. Additional nests require Nestic Pro.", "Free · Pro for additional nests"),
        ("square.grid.2x2.fill", "Choose what matters to you", "Add a person, pet, plant, or something at home. Choose starter trackers or create your own. Track a completion, number and unit, text, yes/no answer, details, photo, or health event. You can customize names, colors, icons, and subject photos.", "Parker → Walk · Home → Water plants · You → Reading", "Free"),
        ("plus.circle.fill", "Record your first update", "Open an item on Home and choose a tracker. Check the time, enter its value, add a note or photo if useful, and save. Activity keeps the shared history, with search and filters. You can edit your own updates; nest managers can manage shared records.", "Walk → 20 minutes → Save. Your update appears in Activity.", "Free"),
        ("cross.case.fill", "Follow health events over time", "Use a health tracker to record when an episode starts. Add follow-up notes and progress photos while it is open, then mark it resolved when it ends. Its timeline keeps the updates together. Reports let you review and share this history.", "Health events, follow-up updates, photos, and reports are free. These are records, not diagnoses.", "Free"),
        ("chart.bar.fill", "Understand your patterns", "Insights shows graphs, totals, and recorded history. Basic views are free; 30-day trends and forecasts require Pro. Forecasts estimate the next update from your history, with confidence and explanations of the model’s inputs. Pro also includes forecast settings and quiet hours.", "Record more history to help forecasts learn. Predicted times are estimates, not promises.", "Free graphs · Pro trends & forecasts"),
        ("square.stack.3d.up.fill", "Group habits into routines", "A routine bundles trackers, even across different items, so you can record several updates together. Choose the trackers and saved values once, then record the routine from Home or an item’s Record screen.", "Morning routine → Walk + Breakfast + Water plants. Creating and recording routines requires Pro.", "Nestic Pro"),
        ("person.2.fill", "Share on your terms", "Add registered members from Your nest and choose their role. Temporary caregiver links are a Pro feature: choose which items and trackers a guest can access, allow recording or history as needed, and set an expiration. Nest managers can revoke a link at any time.", "Regular nest membership is free. Controlled, expiring caregiver links require Pro.", "Free members · Pro caregiver links"),
        ("bell.fill", "Stay connected to your habits", "Shared reminder schedules are free. Each member controls their own iPhone notifications. iPhone and iPad widgets show recent updates and support quick recording; Pro adds predicted times. The Apple Watch companion can record trackers and routines after syncing with the iPhone app.", "Basic widgets and Watch tracker recording are free. Watch routines and widget forecasts require Pro. Browser notification support differs from iOS.", "Free reminders · Pro predictions & routines"),
        ("gearshape.fill", "Your nest, your preferences", "Your nest has appearance settings, member controls, feedback, support, privacy information, and account deletion. You can reopen this tutorial here whenever you need it. Pro is optional; subscription details and purchase management are available in the iPhone app.", "Free: individual trackers, shared activity, health updates, reports, reminders, basic widgets. Pro: routines, forecasts, 30-day trends, predictive widgets, additional nests, caregiver links.", "Free & Pro overview")
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Step \(step + 1) of \(pages.count)").font(.subheadline).foregroundStyle(.secondary)
                    Menu("Jump to a topic") {
                        ForEach(pages.indices, id: \.self) { index in
                            Button(pages[index].title) { step = index }
                        }
                    }
                    Text(pages[step].plan).font(.caption.weight(.semibold))
                        .foregroundStyle(NesticTheme.forest).padding(.horizontal, 12).padding(.vertical, 8)
                        .background(NesticTheme.lime.opacity(0.3), in: Capsule())
                    ProgressView(value: Double(step + 1), total: Double(pages.count))
                        .accessibilityLabel("Tutorial progress")
                    Image(systemName: pages[step].symbol)
                        .font(.system(size: 52)).foregroundStyle(NesticTheme.forest)
                        .padding(24).background(NesticTheme.lime.opacity(0.3), in: RoundedRectangle(cornerRadius: 28))
                        .accessibilityHidden(true)
                    Text(pages[step].title).font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .accessibilityAddTraits(.isHeader)
                    Text(pages[step].body).font(.body).lineSpacing(5)
                    Text(pages[step].example).font(.callout).foregroundStyle(NesticTheme.forest)
                        .padding(18).frame(maxWidth: .infinity, alignment: .leading).nesticCard()
                    HStack {
                        if step > 0 { Button("Back") { step -= 1 }.buttonStyle(.bordered) }
                        Spacer()
                        Button(step == pages.count - 1 ? "Let’s get started" : "Next") {
                            if step == pages.count - 1 { dismiss() } else { step += 1 }
                        }.buttonStyle(.borderedProminent).accessibilityIdentifier("tutorial.next")
                    }
                    Text("You can reopen this guide from Your nest → Help & legal.")
                        .font(.footnote).foregroundStyle(.secondary)
                }.padding(24).frame(maxWidth: 600).frame(maxWidth: .infinity)
            }
            .background(NesticTheme.paper)
            .navigationTitle("Getting started")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Skip") { dismiss() }.accessibilityIdentifier("tutorial.skip") } }
        }
        .tint(NesticTheme.forest)
        // Viewing the guide counts even when it is skipped or swiped away.
        .onAppear { tutorialViewed = true }
    }
}

struct NesticSetupChecklist: View {
    @EnvironmentObject private var store: NesticStore
    @AppStorage("nestic.setup.dismissed.v1") private var dismissedScopes = ""
    let createNest: () -> Void
    let addSubject: () -> Void
    let tutorial: () -> Void

    private var hasNest: Bool { store.selectedNest != nil }
    private var hasTracker: Bool { store.subjects.contains { !store.trackers(for: $0).isEmpty } }
    private var hasRecord: Bool { !store.entries.isEmpty }

    var body: some View {
        if !store.isDemo, !store.isLoading, store.errorMessage == nil,
           !NesticOnboarding.contains(dismissedScopes, store.onboardingScope),
           !(hasNest && hasTracker && hasRecord) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Make yourself at home").font(.headline)
                    Spacer()
                    Button { dismissedScopes = NesticOnboarding.remembering(store.onboardingScope, in: dismissedScopes) } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Dismiss setup checklist")
                }
                Text("Three small steps to your first update.").font(.subheadline).foregroundStyle(.secondary)
                row("Create or join a nest", complete: hasNest)
                row("Add something and choose a tracker", complete: hasTracker)
                row("Record your first update", complete: hasRecord)
                if !hasNest {
                    Button("Create a nest", action: createNest).buttonStyle(.borderedProminent)
                } else if !hasTracker, store.canManageNest {
                    if let subject = store.subjects.first {
                        NavigationLink(value: subject.id) { Text("Choose a tracker") }.buttonStyle(.borderedProminent)
                    } else {
                        Button("Add something to track", action: addSubject).buttonStyle(.borderedProminent)
                    }
                } else if let subject = store.subjects.first(where: { !store.trackers(for: $0).isEmpty }), store.canLog {
                    NavigationLink(value: subject.id) { Text("Record an update") }.buttonStyle(.borderedProminent)
                } else {
                    Text("Ask a nest owner to add trackers or give you permission to record updates.").font(.callout).foregroundStyle(.secondary)
                }
                Button("Show me how", action: tutorial).font(.subheadline)
            }.padding(20).nesticCard().accessibilityIdentifier("home.setupChecklist")
        }
    }

    private func row(_ title: String, complete: Bool) -> some View {
        Label(title, systemImage: complete ? "checkmark.circle.fill" : "circle")
            .font(.subheadline).foregroundStyle(complete ? NesticTheme.forest : .secondary)
            .accessibilityLabel(title + (complete ? ", complete" : ", not complete"))
    }
}
