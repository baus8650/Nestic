import SwiftUI

struct NesticTabs: View {
    @EnvironmentObject private var store: NesticStore
    var body: some View {
        TabView {
            NavigationStack { DashboardView() }.id(store.selectedNestID)
                .tabItem { Label("Home", systemImage: "house.fill") }
            NavigationStack { AnalyticsView() }.id(store.selectedNestID)
                .tabItem { Label("Insights", systemImage: "chart.xyaxis.line") }
            NavigationStack { ActivityView() }
                .tabItem { Label("Activity", systemImage: "clock.arrow.circlepath") }
            NavigationStack { NestSettingsView() }
                .tabItem { Label("Your nest", systemImage: "person.2.fill") }
        }.tint(NesticTheme.forest)
    }
}

struct DashboardView: View {
    @EnvironmentObject private var store: NesticStore
    @State private var showNests = false
    @State private var showAdd = false
    @State private var filter: NestSubjectKind?
    @State private var logSelection: LogSelection?
    @State private var error: String?

    private var filteredSubjects: [NestSubject] {
        store.subjects.filter { filter == nil || $0.kind == filter || (filter == .thing && $0.kind == .custom) }
    }
    private var todayCount: Int { store.entries.filter { Calendar.current.isDateInToday($0.occurredAt) }.count }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                header
                if store.isDemo {
                    HStack(spacing: 7) {
                        Image(systemName: "sparkles")
                        Text("Sample nest · saved on this device")
                    }.font(.caption.weight(.medium)).foregroundStyle(NesticTheme.forest)
                }
                if let message = store.errorMessage {
                    HStack(alignment: .top) {
                        Image(systemName: "wifi.exclamationmark")
                        Text(message).font(.caption)
                        Spacer()
                        Button { store.errorMessage = nil } label: { Image(systemName: "xmark") }
                            .accessibilityLabel("Dismiss connection message")
                    }.padding(14).background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
                }
                hero
                if store.selectedNest == nil {
                    VStack {
                        EmptyNestView(symbol: "person.2.badge.plus", title: "Make room for your people", message: "Create your first nest, or ask a nest owner to add your account by email.")
                        PrimaryButton(title: "Create a nest", symbol: "plus") { showNests = true }
                    }.nesticCard()
                } else {
                    VStack(spacing: 16) {
                        HStack {
                            SectionHeading(title: "Around your nest", detail: "\(store.subjects.count) tracking")
                            if store.canManageNest {
                                Button { showAdd = true } label: {
                                    Image(systemName: "plus").font(.system(size: 14, weight: .semibold))
                                        .frame(width: 32, height: 32).background(NesticTheme.forest.opacity(0.08), in: Circle())
                                }.accessibilityLabel("Add something to track").accessibilityIdentifier("home.addSubject")
                            }
                        }
                        filters
                        if filteredSubjects.isEmpty {
                            EmptyNestView(symbol: "leaf", title: store.subjects.isEmpty ? "A little care starts here" : "Nothing here just yet", message: "Add a pet, a person, or something at home. Then choose the little things you want to keep track of.")
                            if store.canManageNest {
                                Button("Add something to track") { showAdd = true }.font(.subheadline.weight(.semibold))
                            }
                        }
                        ForEach(filteredSubjects) { subject in
                            SubjectCard(subject: subject) { tracker in logSelection = LogSelection(subject: subject, tracker: tracker) }
                        }
                    }
                    VStack(spacing: 16) {
                        SectionHeading(title: "The latest little things", detail: "RECENT ACTIVITY")
                        if store.entries.isEmpty {
                            Text("Your first update will appear here. Everyone in your nest can follow along.")
                                .font(.subheadline).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).nesticCard()
                        } else {
                            VStack(spacing: 0) {
                                ForEach(Array(store.entries.prefix(4).enumerated()), id: \.element.id) { index, entry in
                                    EntryRow(entry: entry)
                                    if index < min(store.entries.count, 4) - 1 { Divider().padding(.leading, 52).padding(.vertical, 12) }
                                }
                            }.nesticCard()
                        }
                    }
                }
                HStack(spacing: 6) {
                    NestMark().frame(width: 19, height: 20)
                    Text("Little updates. Shared care.").font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity).padding(.vertical, 10)
            }.padding(22).padding(.bottom, 12)
        }
        .background(NesticTheme.paper).toolbar(.hidden, for: .navigationBar)
        .refreshable { do { try await store.refresh() } catch { self.error = error.localizedDescription } }
        .sheet(isPresented: $showNests) { NestSwitcherSheet() }
        .sheet(isPresented: $showAdd) { AddSubjectSheet() }
        .sheet(item: $logSelection) { LogEntrySheet(subject: $0.subject, tracker: $0.tracker, date: $0.date) }
        .alert("Couldn’t refresh", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }
    private var header: some View {
        HStack(alignment: .center) {
            HStack(spacing: 7) {
                NestMark().frame(width: 34, height: 36)
                Text("nestic").font(.system(size: 29, weight: .bold, design: .rounded)).tracking(-1.2)
            }.foregroundStyle(NesticTheme.forest)
            Spacer()
            Button { showNests = true } label: {
                HStack(spacing: 7) {
                    Text(store.selectedNest?.name ?? "Choose nest").lineLimit(1)
                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
                }.font(.caption.weight(.semibold)).padding(.horizontal, 13).padding(.vertical, 11)
                    .background(NesticTheme.card, in: Capsule())
            }.accessibilityIdentifier("home.switchNest")
        }
    }
    private var hero: some View {
        VStack(alignment: .leading, spacing: 21) {
            HStack {
                Text(Date.now.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()).uppercased())
                    .font(.system(size: 10, weight: .semibold)).tracking(1.3)
                Spacer()
                HStack(spacing: 5) {
                    Circle().fill(NesticTheme.lime).frame(width: 5, height: 5)
                    Text(store.isDemo ? "SAMPLE" : store.connectionStatus.uppercased())
                        .lineLimit(1).font(.system(size: 9, weight: .bold)).tracking(0.7)
                }
            }.foregroundStyle(.white.opacity(0.74))
            HStack(alignment: .center) {
                Text("A little more\ntogether.")
                    .font(.system(size: 34, weight: .semibold, design: .rounded)).tracking(-1.1)
                    .foregroundStyle(.white).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 5)
                NestMark(color: NesticTheme.lime).frame(width: 78, height: 78).rotationEffect(.degrees(-8))
            }
            Rectangle().fill(.white.opacity(0.15)).frame(height: 1)
            HStack(spacing: 6) {
                Text("\(todayCount)").font(.system(.title2, design: .rounded, weight: .semibold)).foregroundStyle(NesticTheme.lime)
                Text(todayCount == 1 ? "update today" : "updates today").font(.caption).foregroundStyle(.white.opacity(0.8))
                Spacer()
                HStack(spacing: -7) {
                    ForEach(Array(store.members.prefix(3))) { person in
                        Text(person.initials).font(.system(size: 10, weight: .bold))
                            .foregroundStyle(NesticTheme.deepForest).frame(width: 30, height: 30)
                            .background(NesticTheme.lime, in: Circle())
                            .overlay(Circle().stroke(NesticTheme.deepForest, lineWidth: 2))
                    }
                }.accessibilityLabel("\(store.members.count) nest members")
            }
        }.padding(23).background(NesticTheme.deepForest, in: RoundedRectangle(cornerRadius: 28))
    }
    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterButton("Everything", kind: nil)
                filterButton("Pets", kind: .pet)
                filterButton("People", kind: .person)
                filterButton("Home & more", kind: .thing)
            }
        }
    }
    private func filterButton(_ title: String, kind: NestSubjectKind?) -> some View {
        Button { withAnimation(.easeInOut(duration: 0.15)) { filter = kind } } label: {
            Text(title).font(.caption.weight(.semibold)).padding(.horizontal, 15).padding(.vertical, 10)
                .foregroundStyle(filter == kind ? NesticTheme.paper : NesticTheme.ink.opacity(0.65))
                .background(filter == kind ? NesticTheme.forest : NesticTheme.card, in: Capsule())
        }
    }
}

struct LogSelection: Identifiable {
    let id = UUID()
    let subject: NestSubject
    let tracker: NestTracker
    /// Captured when the quick-log control is pressed, rather than when the sheet finishes appearing.
    let date: Date

    init(subject: NestSubject, tracker: NestTracker, date: Date = Date()) {
        self.subject = subject
        self.tracker = tracker
        self.date = date
    }
}

struct SubjectCard: View {
    @EnvironmentObject private var store: NesticStore
    let subject: NestSubject
    var log: (NestTracker) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            NavigationLink {
                SubjectDetailView(subject: subject)
            } label: {
                HStack(spacing: 13) {
                    SubjectAvatar(emoji: subject.emoji)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(subject.name).font(.system(.title3, design: .rounded, weight: .bold)).foregroundStyle(NesticTheme.ink)
                        Text("\(store.trackers(for: subject).count) trackers · \(subject.kind.title)").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "arrow.up.right").font(.subheadline).foregroundStyle(NesticTheme.forest)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityIdentifier("subject.open.\(subject.name)")
            if store.trackers(for: subject).isEmpty {
                Text("Open to add your first tracker.").font(.caption).foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(store.trackers(for: subject).prefix(4).enumerated()), id: \.element.id) { index, tracker in
                        if index > 0 { Divider().padding(.vertical, 9) }
                        Button { log(tracker) } label: {
                            HStack(spacing: 10) {
                                Image(systemName: trackerSymbol(tracker)).font(.system(size: 13)).foregroundStyle(NesticTheme.forest).frame(width: 20)
                                Text(tracker.name).font(.subheadline.weight(.medium)).foregroundStyle(NesticTheme.ink)
                                Spacer(minLength: 5)
                                if let last = store.latestEntry(for: tracker, subject: subject) {
                                    Text(last.occurredAt, format: .relative(presentation: .numeric, unitsStyle: .abbreviated)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                } else {
                                    Text("No updates yet").font(.caption).foregroundStyle(.secondary)
                                }
                                Image(systemName: "plus").font(.system(size: 10, weight: .bold))
                                    .frame(width: 26, height: 26).background(NesticTheme.forest.opacity(0.07), in: Circle())
                            }.contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityLabel("Quick log \(tracker.name) for \(subject.name)")
                            .accessibilityIdentifier("quicklog.\(subject.name).\(tracker.name)")
                    }
                }
            }
        }.nesticCard()
    }
}

struct EntryRow: View {
    @EnvironmentObject private var store: NesticStore
    let entry: NestEntry
    private var subject: NestSubject? { store.subjects.first { $0.id == entry.entityId } }
    private var tracker: NestTracker? { store.trackers.first { $0.id == entry.actionId } }
    private var actor: String {
        if entry.actorUserId == store.currentUser?.id { return "You" }
        return store.members.first { $0.id == entry.actorUserId }?.displayName ?? "A nest member"
    }
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            SubjectAvatar(emoji: subject?.emoji ?? "🌱", size: 40)
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(subject?.name ?? "Item") · \(tracker?.name ?? "Update")")
                        .font(.subheadline.weight(.semibold))
                    Spacer(minLength: 4)
                    Text(entry.occurredAt, style: .time).font(.caption2).foregroundStyle(.secondary)
                }
                let value = entry.displayValue(unit: tracker?.unit)
                if !value.isEmpty { Text(value).font(.subheadline).foregroundStyle(NesticTheme.forest) }
                if let note = entry.note, !note.isEmpty { Text(note).font(.caption).foregroundStyle(.secondary) }
                Text("\(actor) logged this").font(.caption2).foregroundStyle(.secondary)
            }
        }.accessibilityElement(children: .combine)
    }
}
