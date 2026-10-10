import SwiftUI

struct NesticTabs: View {
    @EnvironmentObject private var store: NesticStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var selectedTab: NesticTab = .home
    @State private var homePath = NavigationPath()
    @State private var iPadPath = NavigationPath()
    @State private var sidebarVisibility: NavigationSplitViewVisibility = .all
    @State private var widgetLogSelection: LogSelection?
    @State private var requestedSubjectModes: [UUID: SubjectDetailMode] = [:]

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                iPadLayout
            } else {
                phoneLayout
            }
        }
        .tint(NesticTheme.forest)
        .sheet(item: $widgetLogSelection) { LogEntrySheet(subject: $0.subject, tracker: $0.tracker, date: $0.date) }
        .onAppear { applyPendingNavigation() }
        .onChange(of: selectedTab) { _, _ in
            homePath = NavigationPath()
            iPadPath = NavigationPath()
        }
        .onChange(of: homePath) { _, path in
            if path.isEmpty { requestedSubjectModes.removeAll() }
        }
        .onChange(of: iPadPath) { _, path in
            if path.isEmpty { requestedSubjectModes.removeAll() }
        }
        .onChange(of: store.pendingNavigation) { _, _ in applyPendingNavigation() }
        .onChange(of: store.subjects) { _, _ in applyPendingNavigation() }
    }

    private var phoneLayout: some View {
        TabView(selection: tabSelection) {
            homeNavigation
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(NesticTab.home)
            NavigationStack { ActivityView() }
                .tabItem { Label("Activity", systemImage: "clock.arrow.circlepath") }
                .tag(NesticTab.activity)
            NavigationStack { ReportsView() }
                .tabItem { Label("Reports", systemImage: "doc.text.magnifyingglass") }
                .tag(NesticTab.reports)
            NavigationStack { NestSettingsView() }
                .tabItem { Label("Your nest", systemImage: "person.2.fill") }
                .tag(NesticTab.settings)
        }
    }

    private var iPadLayout: some View {
        NavigationSplitView(columnVisibility: $sidebarVisibility) {
            List(selection: sidebarSelection) {
                Section("Nestic") {
                    Label("Home", systemImage: "house.fill")
                        .tag(NesticTab.home)
                    Label("Activity", systemImage: "clock.arrow.circlepath")
                        .tag(NesticTab.activity)
                    Label("Reports", systemImage: "doc.text.magnifyingglass")
                        .tag(NesticTab.reports)
                    Label("Your nest", systemImage: "person.2.fill")
                        .tag(NesticTab.settings)
                        .accessibilityIdentifier("ipad.destination.settings")
                }
            }
            .navigationTitle(store.selectedNest?.name ?? "Nestic")
            .navigationBarTitleDisplayMode(.inline)
            .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
        } detail: {
            iPadDetail
        }
        .navigationSplitViewStyle(.balanced)
    }

    private var iPadDetail: some View {
        NavigationStack(path: $iPadPath) {
            selectedPadContent
                .navigationBarTitleDisplayMode(.inline)
                .navigationDestination(for: UUID.self) { subjectID in
                    subjectDestination(for: subjectID)
                }
        }

    }

    @ViewBuilder
    private var selectedPadContent: some View {
        switch selectedTab {
        case .home:
            DashboardView()
        case .activity:
            ActivityView()
        case .reports:
            ReportsView()
        case .settings:
            NestSettingsView()
        }
    }

    private var homeNavigation: some View {
        NavigationStack(path: $homePath) {
            DashboardView()
                .navigationDestination(for: UUID.self) { subjectID in
                    subjectDestination(for: subjectID)
                }
        }
        .id(store.selectedNestID)
    }

    @ViewBuilder
    private func subjectDestination(for subjectID: UUID) -> some View {
        if let subject = store.subjects.first(where: { $0.id == subjectID }) {
            SubjectDetailView(subject: subject, initialMode: requestedSubjectModes[subjectID] ?? .record)
        } else {
            ContentUnavailableView("Subject unavailable", systemImage: "person.crop.circle.badge.exclamationmark")
        }
    }

    private var tabSelection: Binding<NesticTab> {
        Binding(
            get: { selectedTab },
            set: selectTab
        )
    }

    private var sidebarSelection: Binding<NesticTab?> {
        Binding(
            get: { selectedTab },
            set: { tab in
                guard let tab else { return }
                selectTab(tab)
            }
        )
    }

    private func selectTab(_ tab: NesticTab) {
        homePath = NavigationPath()
        iPadPath = NavigationPath()
        selectedTab = tab
    }

    private func applyPendingNavigation() {
        guard let destination = store.pendingNavigation else { return }
        let subjectID: UUID
        switch destination {
        case .subject(let id), .insights(let id): subjectID = id
        case .record(let id, _): subjectID = id
        }
        guard store.subjects.contains(where: { $0.id == subjectID }) else { return }
        guard let destination = store.consumePendingNavigation() else { return }

        switch destination {
        case .subject(let id):
            openSubject(id, mode: .record)
        case .insights(let id):
            openSubject(id, mode: .insights)
        case .record(let id, let trackerID):
            guard let subject = store.subjects.first(where: { $0.id == id }),
                  let tracker = store.trackers(for: subject).first(where: { $0.id == trackerID }) else { return }
            widgetLogSelection = LogSelection(subject: subject, tracker: tracker)
        }
    }

    private func openSubject(_ id: UUID, mode: SubjectDetailMode) {
        homePath = NavigationPath()
        iPadPath = NavigationPath()
        requestedSubjectModes[id] = mode
        selectedTab = .home
        Task { @MainActor in
            await Task.yield()
            if horizontalSizeClass == .regular {
                iPadPath.append(id)
            } else {
                homePath.append(id)
            }
        }
    }
}

private enum NesticTab: Hashable {
    case home, activity, reports, settings
}

struct DashboardView: View {
    @EnvironmentObject private var store: NesticStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var showTutorial = false
    @AppStorage(NesticOnboarding.tutorialViewedKey) private var tutorialViewed = false
    @State private var showNests = false
    @State private var showAdd = false
    @State private var subjectFilter: NestSubjectKind?
    @State private var logSelection: LogSelection?
    @State private var error: String?
    @State private var quickLogError: String?
    @State private var quickLogDate: Date?
    @State private var quickLogSubjectID: UUID?
    @State private var showRoutineEditor = false
    @State private var editingRoutine: NestRoutine?
    @State private var deletingRoutine: NestRoutine?
    @State private var routineBusyID: UUID?
    @State private var routineError: String?

    private func offerTutorial() {
        guard store.isAuthenticated, store.careLinkSession == nil, !tutorialViewed else { return }
        if store.isDemo {
            #if DEBUG
            let arguments = ProcessInfo.processInfo.arguments
            guard arguments.contains("--reset-tutorial") || arguments.contains("--show-tutorial-in-demo") else { return }
            #else
            return
            #endif
        }
        showTutorial = true
    }

    private var todayCount: Int { store.entries.filter { Calendar.current.isDateInToday($0.occurredAt) }.count }
    private var isWideLayout: Bool { horizontalSizeClass == .regular }
    private var subjectGridColumns: [GridItem] {
        let count = isWideLayout ? 3 : 2
        return Array(repeating: GridItem(.flexible(), spacing: isWideLayout ? 16 : 12), count: count)
    }
    private var filteredSubjects: [NestSubject] {
        store.subjects.filter { subject in
            subjectFilter == nil || subject.kind == subjectFilter || (subjectFilter == .thing && subject.kind == .custom)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                Text("Keep track of your nest.")
                    .font(.subheadline)
                    .foregroundStyle(NesticTheme.forest.opacity(0.75))
                    .accessibilityIdentifier("home.slogan")
                if let message = store.errorMessage {
                    HStack(alignment: .top) {
                        Image(systemName: "wifi.exclamationmark")
                        Text(message).font(.caption)
                        Spacer()
                        Button { store.errorMessage = nil } label: { Image(systemName: "xmark") }
                            .accessibilityLabel("Dismiss connection message")
                    }.padding(14).background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
                }
                summary
                NesticSetupChecklist(createNest: { showNests = true }, addSubject: { showAdd = true }, tutorial: { showTutorial = true })
                if store.selectedNest == nil {
                    VStack {
                        EmptyNestView(symbol: "person.2.badge.plus", title: "Make room for your people", message: "Create your first nest, or ask a nest owner to add your account by email.")
                        PrimaryButton(title: "Create a nest", symbol: "plus") { showNests = true }
                    }.nesticCard()
                } else {
                    quickLog
                    if store.hasRoutineAccess {
                        routinesSection
                    }
                    latest
                }
            }
            .frame(maxWidth: isWideLayout ? 1240 : .infinity)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, isWideLayout ? 34 : 22)
            .padding(.top, isWideLayout ? 28 : 22)
            .padding(.bottom, 12)
        }
        .background(NesticTheme.paper)
        .toolbar(isWideLayout ? .visible : .hidden, for: .navigationBar)
        .refreshable { do { try await store.refresh() } catch { self.error = error.localizedDescription } }
        .task {
            // Let the sign-in sheet finish dismissing before presenting the guide.
            do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
            offerTutorial()
        }
        .sheet(isPresented: $showTutorial) { NesticTutorialView() }
        .sheet(isPresented: $showNests) { NestSwitcherSheet() }
        .sheet(isPresented: $showAdd) { AddSubjectSheet() }
        .sheet(isPresented: $showRoutineEditor, onDismiss: { editingRoutine = nil }) {
            RoutineEditorSheet(routine: editingRoutine)
        }
        .sheet(item: $logSelection) { LogEntrySheet(subject: $0.subject, tracker: $0.tracker, date: $0.date) }
        .alert("Couldn’t refresh", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
        .alert("Couldn’t record update", isPresented: Binding(get: { quickLogError != nil }, set: { if !$0 { quickLogError = nil } })) {
            Button("OK") { quickLogError = nil }
        } message: { Text(quickLogError ?? "") }
        .alert("Couldn’t update routine", isPresented: Binding(get: { routineError != nil }, set: { if !$0 { routineError = nil } })) {
            Button("OK") { routineError = nil }
        } message: { Text(routineError ?? "") }
        .confirmationDialog("Delete this routine?", item: $deletingRoutine) { routine in
            Button("Delete routine", role: .destructive) { deleteRoutine(routine) }
            Button("Cancel", role: .cancel) { }
        } message: { routine in
            Text(routine.isPrivate ? "This removes \(routine.name) from your devices." : "This removes \(routine.name) for everyone in the nest.")
        }
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
    private var summary: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(Date.now.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                        .font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.7))
                    Text(store.selectedNest?.name ?? "Your nest")
                        .font(.system(.title2, design: .rounded, weight: .bold)).foregroundStyle(.white)
                }
                Spacer()
                NestMark(color: NesticTheme.lime).frame(width: 48, height: 48)
            }
            HStack(spacing: 8) {
                HomeStat(value: "\(todayCount)", label: todayCount == 1 ? "update today" : "updates today")
                HomeStat(value: "\(store.subjects.count)", label: "tracked items")
                HomeStat(value: "\(store.members.count)", label: store.members.count == 1 ? "member" : "members")
            }
        }.padding(18).background(NesticTheme.deepForest, in: RoundedRectangle(cornerRadius: 24))
    }
    private var quickLog: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionHeading(title: "In your nest", detail: "TAP TO OPEN · HOLD TO CHOOSE & LOG")
                Spacer()
                if store.canManageNest {
                    Button { showAdd = true } label: {
                        Image(systemName: "plus").font(.system(size: 14, weight: .semibold))
                            .frame(width: 32, height: 32).background(NesticTheme.forest.opacity(0.08), in: Circle())
                    }.accessibilityLabel("Add something to track").accessibilityIdentifier("home.addSubject")
                }
            }
            if store.subjects.isEmpty {
                EmptyNestView(symbol: "leaf", title: "Your event history starts here", message: "Add a pet, a person, or something at home, then choose what you want to keep track of.")
                if store.canManageNest {
                    Button("Add something to track") { showAdd = true }.font(.subheadline.weight(.semibold))
                }
            } else if filteredSubjects.isEmpty {
                filters
                EmptyNestView(symbol: "line.3.horizontal.decrease.circle", title: "Nothing here just yet", message: "Try another filter or add something new to your nest.")
                if store.canManageNest {
                    Button("Add something to track") { showAdd = true }.font(.subheadline.weight(.semibold))
                }
            } else {
                filters
                    LazyVGrid(columns: subjectGridColumns, spacing: isWideLayout ? 16 : 12) {
                    ForEach(filteredSubjects) { subject in
                        NavigationLink(value: subject.id) {
                            SubjectGridTile(subject: subject, isBusy: quickLogSubjectID == subject.id)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("subject.open.\(subject.name)")
                        .accessibilityHint("Tap to open details. Long press to choose what to record")
                        .simultaneousGesture(LongPressGesture(minimumDuration: 0.55).onEnded { _ in
                            quickLogDate = Date()
                        })
                        .contextMenu {
                            ForEach(store.trackers(for: subject)) { tracker in
                                Button {
                                    let date = quickLogDate ?? Date()
                                    quickLogDate = nil
                                    quickLog(subject, tracker: tracker, date: date)
                                } label: {
                                    Text(tracker.name)
                                }
                                .accessibilityIdentifier("quicklog.\(subject.name).\(tracker.name)")
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var routinesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionHeading(title: "Routines", detail: "ONE TAP · MULTIPLE UPDATES")
                Spacer()
                if store.canLog {
                    Button { editingRoutine = nil; showRoutineEditor = true } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .semibold))
                            .frame(width: 32, height: 32)
                            .background(NesticTheme.forest.opacity(0.08), in: Circle())
                    }
                    .accessibilityLabel("Create a nest routine")
                }
            }
            if store.routines.isEmpty {
                Text(store.canManageNest
                     ? "Bundle a meal, medications, or updates for several entities into one tap."
                     : "No routines have been set up in this nest yet.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .nesticCard()
                if store.canLog {
                    Button { editingRoutine = nil; showRoutineEditor = true } label: {
                        Label("Create a nest routine", systemImage: "square.stack.3d.up.fill")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                }
            } else {
                ForEach(store.routines) { routine in
                    nestRoutineRow(routine)
                }
            }
        }
    }

    private func nestRoutineRow(_ routine: NestRoutine) -> some View {
        HStack(spacing: 10) {
            Button { logRoutine(routine) } label: {
                HStack(spacing: 13) {
                    Image(systemName: "play.circle.fill")
                        .font(.title2)
                        .foregroundStyle(NesticTheme.forest)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Log \(routine.name)")
                            .font(.headline)
                            .foregroundStyle(NesticTheme.ink)
                        Text(routineSummary(routine))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 4)
                    if routineBusyID == routine.id {
                        ProgressView().tint(NesticTheme.forest)
                    } else {
                        Image(systemName: "arrow.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(routineBusyID != nil)
            .accessibilityLabel("Log \(routine.name)")
            if store.canManageNest || (store.canLog && routine.isPrivate && routine.privateOwnerId == store.currentUser?.id) {
                Menu {
                    Button("Edit routine", systemImage: "pencil") {
                        editingRoutine = routine
                        showRoutineEditor = true
                    }
                    Button("Delete routine", systemImage: "trash", role: .destructive) {
                        deletingRoutine = routine
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .frame(width: 34, height: 44)
                }
                .accessibilityLabel("Manage \(routine.name)")
            }
        }
        .nesticCard()
    }

    private func routineSummary(_ routine: NestRoutine) -> String {
        routine.targets.compactMap { target in
            guard let subject = store.subjects.first(where: { $0.id == target.entityID }) else { return nil }
            let trackerNames = target.items.compactMap { item in
                store.trackers.first(where: { $0.id == item.trackerID })?.name
            }.joined(separator: " · ")
            return "\(subject.name): \(trackerNames)"
        }.joined(separator: "  •  ")
    }

    private func logRoutine(_ routine: NestRoutine) {
        routineBusyID = routine.id
        Task {
            defer { routineBusyID = nil }
            do {
                try await store.logRoutine(routine)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } catch { routineError = error.localizedDescription }
        }
    }

    private func deleteRoutine(_ routine: NestRoutine) {
        Task {
            do { try await store.deleteRoutine(routine) }
            catch { routineError = error.localizedDescription }
        }
    }

    private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterButton("Everything", kind: nil)
                filterButton("Pets", kind: .pet)
                filterButton("People", kind: .person)
                filterButton("Other", kind: .thing)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Filter nest items")
    }

    private func filterButton(_ title: String, kind: NestSubjectKind?) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { subjectFilter = kind }
        } label: {
            Text(title)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 15)
                .padding(.vertical, 10)
                .foregroundStyle(subjectFilter == kind ? NesticTheme.paper : NesticTheme.ink.opacity(0.65))
                .background(subjectFilter == kind ? NesticTheme.forest : NesticTheme.card, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Filter by \(title)")
        .accessibilityAddTraits(subjectFilter == kind ? .isSelected : [])
        .accessibilityIdentifier("home.filter.\(kind?.rawValue ?? "all")")
    }

    private func quickLog(_ subject: NestSubject, tracker: NestTracker, date: Date) {
        if tracker.valueType != .none {
            logSelection = LogSelection(subject: subject, tracker: tracker, date: date)
            return
        }
        Task {
            quickLogSubjectID = subject.id
            defer { quickLogSubjectID = nil }
            do {
                try await store.log(subjectID: subject.id, trackerID: tracker.id, date: date)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } catch {
                quickLogError = error.localizedDescription
            }
        }
    }
    private var latest: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(title: "Latest", detail: "SHARED ACTIVITY")
            if store.entries.isEmpty {
                Text("Your first update will appear here. Everyone in your nest can follow along.")
                    .font(.subheadline).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).nesticCard()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(store.entries.prefix(3).enumerated()), id: \.element.id) { index, entry in
                        EntryRow(entry: entry)
                        if index < min(store.entries.count, 3) - 1 { Divider().padding(.leading, 52).padding(.vertical, 10) }
                    }
                }.nesticCard()
            }
        }
    }
}

private struct HomeStat: View {
    let value: String
    let label: String
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value).font(.system(.title3, design: .rounded, weight: .bold)).foregroundStyle(NesticTheme.lime)
            Text(label).font(.caption2).foregroundStyle(.white.opacity(0.72)).lineLimit(1)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SubjectGridTile: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let subject: NestSubject
    var isBusy = false

    private var tileHeight: CGFloat { horizontalSizeClass == .regular ? 190 : 154 }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottomLeading) {
                if let image = SubjectPhoto.image(from: subject.photoData) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                } else {
                    NesticTheme.lime.opacity(0.22)
                    Text(subject.emoji)
                        .font(.system(size: 72))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                LinearGradient(
                    colors: [.clear, .black.opacity(0.78)],
                    startPoint: .center,
                    endPoint: .bottom
                )

                Text(subject.name)
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
                    .padding(14)

                if isBusy {
                    ZStack {
                        Rectangle()
                            .fill(.black.opacity(0.42))
                        ProgressView("Saving…")
                            .font(.caption.weight(.semibold))
                            .tint(.white)
                            .foregroundStyle(.white)
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay {
                RoundedRectangle(cornerRadius: 20)
                    .stroke(.white.opacity(0.16), lineWidth: 1)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: tileHeight)
        .background(NesticTheme.card)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .contentShape(RoundedRectangle(cornerRadius: 20))
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

struct EntryRow: View {
    @EnvironmentObject private var store: NesticStore
    let entry: NestEntry
    private var subject: NestSubject? { store.subject(id: entry.entityId) }
    private var tracker: NestTracker? { store.tracker(id: entry.actionId) }
    private var actor: String {
        if entry.actorUserId == store.currentUser?.id { return "You" }
        return store.members.first { $0.id == entry.actorUserId }?.displayName ?? "A nest member"
    }
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            SubjectAvatar(emoji: subject?.emoji ?? "🌱", photoData: subject?.photoData, size: 40)
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(subject?.name ?? "Item") · \(tracker?.name ?? "Update")")
                        .font(.subheadline.weight(.semibold))
                    Spacer(minLength: 4)
                    Text(entry.occurredAt, style: .time).font(.caption2).foregroundStyle(.secondary)
                }
                let value = entry.displayValue(unit: tracker?.unit, trackerName: tracker?.name)
                if tracker?.valueType == .photo || (tracker?.valueType == .health && entry.photoURL != nil) {
                    NesticEntryPhotoView(entry: entry, size: 78)
                }
                if tracker?.valueType == .health {
                    if let resolvedAt = entry.resolvedAt {
                        Label("Resolved \(resolvedAt.formatted(date: .abbreviated, time: .shortened))", systemImage: "checkmark.circle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(NesticTheme.forest)
                    } else {
                        Label("Open since onset", systemImage: "exclamationmark.circle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                    if !value.isEmpty { Text(value).font(.subheadline).foregroundStyle(NesticTheme.ink) }
                } else if tracker?.valueType != .photo, !value.isEmpty {
                    Text(value).font(.subheadline).foregroundStyle(NesticTheme.forest)
                }
                if let note = entry.note, !note.isEmpty { Text(note).font(.caption).foregroundStyle(.secondary) }
                Text("\(actor) logged this").font(.caption2).foregroundStyle(.secondary)
            }
        }.accessibilityElement(children: .combine)
    }
}
