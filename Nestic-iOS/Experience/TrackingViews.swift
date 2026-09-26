import SwiftUI

struct AddSubjectSheet: View {
    @EnvironmentObject private var store: NesticStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var kind: NestSubjectKind = .pet
    @State private var emoji = "🐶"
    @State private var useStarterTrackers = true
    @State private var busy = false
    @State private var error: String?
    private var templates: [NestTrackerTemplate] {
        guard useStarterTrackers else { return [] }
        switch kind {
        case .pet: return NestTrackerTemplate.dog
        case .person: return NestTrackerTemplate.person
        case .thing: return NestTrackerTemplate.home
        case .custom: return []
        }
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 12) {
                        SubjectAvatar(emoji: emoji, size: 84)
                        Text("What would you like to care for?")
                            .font(.system(.title3, design: .rounded, weight: .bold))
                        Text("A pet, a person, a plant. Make it yours.").font(.subheadline).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity).padding(.vertical, 16)
                }.listRowBackground(Color.clear)
                Section(content: {
                    TextField("Name, e.g. Milo", text: $name).accessibilityIdentifier("subject.name")
                    Picker("Category", selection: $kind) {
                        ForEach(NestSubjectKind.allCases, id: \.self) { Text($0.title).tag($0) }
                    }.onChange(of: kind) { _, new in emoji = new.emoji }
                    HStack {
                        Text("Icon")
                        Spacer()
                        TextField("Emoji", text: $emoji).multilineTextAlignment(.trailing).frame(width: 90)
                            .onChange(of: emoji) { _, value in emoji = String(value.prefix(2)) }
                    }
                }, header: {
                    Text("The basics")
                })
                Section {
                    if kind != .custom {
                        Toggle("Add starter trackers", isOn: $useStarterTrackers)
                        if useStarterTrackers {
                            ForEach(templates, id: \.name) { template in
                                Label(template.name, systemImage: template.valueType.symbol).foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        Text("Add any custom trackers after creating this item.").foregroundStyle(.secondary)
                    }
                } header: {
                    Text("A little head start")
                } footer: {
                    Text("You can add your own trackers at any time: bathroom breaks, meals, chores, and anything in between.")
                }
                if let error { Text(error).foregroundStyle(.red) }
            }.formStyle().navigationTitle("Add to your nest").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(busy) }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(busy ? "Adding…" : "Add") {
                            busy = true; error = nil
                            Task {
                                defer { busy = false }
                                do {
                                    try await store.createSubject(name: name, kind: kind, emoji: emoji.isEmpty ? kind.emoji : emoji, trackerTemplates: templates)
                                    dismiss()
                                } catch { self.error = error.localizedDescription }
                            }
                        }.fontWeight(.semibold).disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || busy)
                            .accessibilityIdentifier("subject.save")
                    }
                }.interactiveDismissDisabled(busy)
        }
    }
}

struct SubjectDetailView: View {
    @EnvironmentObject private var store: NesticStore
    let subject: NestSubject
    @State private var showAdd = false
    @State private var selection: LogSelection?
    @State private var editingTracker: NestTracker?
    @State private var deletingTracker: NestTracker?
    @State private var trackerError: String?
    private var currentSubject: NestSubject { store.subjects.first { $0.id == subject.id } ?? subject }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 25) {
                HStack(spacing: 18) {
                    SubjectAvatar(emoji: currentSubject.emoji, size: 82)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(currentSubject.name).font(.system(.largeTitle, design: .rounded, weight: .bold))
                        Text("A little care, all in one place.").font(.subheadline).foregroundStyle(.secondary)
                    }
                }.padding(.vertical, 10)
                SectionHeading(title: "Trackers", detail: "TAP TO LOG")
                ForEach(store.trackers(for: currentSubject)) { tracker in
                    HStack(spacing: 8) {
                        Button { selection = LogSelection(subject: currentSubject, tracker: tracker) } label: {
                            HStack(spacing: 14) {
                                Image(systemName: trackerSymbol(tracker)).font(.title3).frame(width: 26).foregroundStyle(NesticTheme.forest)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(tracker.name).font(.headline).foregroundStyle(NesticTheme.ink)
                                    if let last = store.latestEntry(for: tracker, subject: currentSubject) {
                                        Text(last.occurredAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                                            .font(.caption).foregroundStyle(.secondary)
                                    } else { Text("Ready for your first update").font(.caption).foregroundStyle(.secondary) }
                                }
                                Spacer()
                                Image(systemName: "plus.circle.fill").font(.title2).foregroundStyle(NesticTheme.forest)
                            }
                        }.buttonStyle(.plain)
                            .accessibilityLabel("Quick log \(tracker.name) for \(currentSubject.name)")
                        if store.canManageNest {
                            Menu {
                                Button("Edit tracker", systemImage: "pencil") { editingTracker = tracker }
                                Button("Delete tracker", systemImage: "trash", role: .destructive) { deletingTracker = tracker }
                            } label: {
                                Image(systemName: "ellipsis.circle").font(.title3).foregroundStyle(.secondary)
                                    .frame(width: 34, height: 44)
                            }.accessibilityLabel("Manage \(tracker.name)").accessibilityIdentifier("tracker.menu.\(tracker.name)")
                        }
                    }.nesticCard()
                        .contextMenu {
                            if store.canManageNest {
                                Button("Edit tracker", systemImage: "pencil") { editingTracker = tracker }
                                Button("Delete tracker", systemImage: "trash", role: .destructive) { deletingTracker = tracker }
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if store.canManageNest {
                                Button("Delete", systemImage: "trash", role: .destructive) { deletingTracker = tracker }
                                Button("Edit", systemImage: "pencil") { editingTracker = tracker }
                                    .tint(NesticTheme.forest)
                            }
                        }
                }
                if store.canManageNest {
                    Button { showAdd = true } label: {
                        Label("Add a custom tracker", systemImage: "plus").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).padding()
                    }.accessibilityIdentifier("subject.addTracker")
                }
                SectionHeading(title: "Recent history", detail: "\(store.entries(for: currentSubject).count) UPDATES")
                if store.entries(for: currentSubject).isEmpty {
                    EmptyNestView(symbol: "clock", title: "A fresh start", message: "Log a tracker above to start building a shared history.")
                } else {
                    VStack(spacing: 16) {
                        ForEach(store.entries(for: currentSubject)) { EntryRow(entry: $0) }
                    }.nesticCard()
                }
            }.padding(22)
        }.background(NesticTheme.paper).navigationTitle(currentSubject.name).navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showAdd) { AddTrackerSheet(subject: currentSubject) }
            .sheet(item: $editingTracker) { tracker in AddTrackerSheet(subject: currentSubject, tracker: tracker) }
            .sheet(item: $selection) { LogEntrySheet(subject: $0.subject, tracker: $0.tracker, date: $0.date) }
            .confirmationDialog("Delete \(deletingTracker?.name ?? "this tracker")?", isPresented: Binding(get: { deletingTracker != nil }, set: { if !$0 { deletingTracker = nil } }), titleVisibility: .visible) {
                Button("Delete tracker", role: .destructive) {
                    guard let tracker = deletingTracker else { return }
                    deletingTracker = nil
                    Task {
                        do { try await store.deleteTracker(tracker) }
                        catch { trackerError = error.localizedDescription }
                    }
                }
                Button("Cancel", role: .cancel) { deletingTracker = nil }
            } message: {
                Text("This removes the tracker, its quick-log button, and its history for \(currentSubject.name).")
            }
            .alert("Tracker change failed", isPresented: Binding(get: { trackerError != nil }, set: { if !$0 { trackerError = nil } })) {
                Button("OK") { trackerError = nil }
            } message: { Text(trackerError ?? "") }
    }
}

struct AddTrackerSheet: View {
    @EnvironmentObject private var store: NesticStore
    @Environment(\.dismiss) private var dismiss
    let subject: NestSubject
    let editingTracker: NestTracker?
    @State private var name = ""
    @State private var valueType: NestValueType = .none
    @State private var unit = ""
    @State private var busy = false
    @State private var error: String?
    init(subject: NestSubject, tracker: NestTracker? = nil) {
        self.subject = subject
        self.editingTracker = tracker
        _name = State(initialValue: tracker?.name ?? "")
        _valueType = State(initialValue: tracker?.valueType ?? .none)
        _unit = State(initialValue: tracker?.unit ?? "")
    }
    var body: some View {
        NavigationStack {
            Form {
                Section(content: {
                    TextField("Tracker name, e.g. Bathroom break", text: $name).accessibilityIdentifier("tracker.name")
                    Picker("What to record", selection: $valueType) {
                        ForEach(NestValueType.allCases.filter { editingTracker != nil || $0 != .json }, id: \.self) { Text($0.title).tag($0) }
                    }.accessibilityIdentifier("tracker.type")
                    if valueType == .number { TextField("Unit (optional), e.g. cups or minutes", text: $unit) }
                }, header: {
                    Text(editingTracker == nil ? "Tracking for \(subject.name)" : "Edit tracker for \(subject.name)")
                }, footer: {
                    Text("A simple check-in records that something happened. Choose a number, text, or yes/no when you want more detail.")
                })
                if let error { Text(error).foregroundStyle(.red) }
            }.formStyle().navigationTitle(editingTracker == nil ? "New tracker" : "Edit tracker").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(busy) }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(busy ? "Saving…" : (editingTracker == nil ? "Add" : "Save")) {
                            busy = true
                            Task {
                                defer { busy = false }
                                do {
                                    if let editingTracker {
                                        try await store.updateTracker(editingTracker, name: name, valueType: valueType, unit: unit)
                                    } else {
                                        try await store.createTracker(subjectID: subject.id, name: name, valueType: valueType, unit: unit)
                                    }
                                    dismiss()
                                } catch { self.error = error.localizedDescription }
                            }
                        }.fontWeight(.semibold).disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || busy)
                            .accessibilityIdentifier("tracker.save")
                    }
                }.interactiveDismissDisabled(busy)
        }
    }
}

struct LogEntrySheet: View {
    @EnvironmentObject private var store: NesticStore
    @Environment(\.dismiss) private var dismiss
    let subject: NestSubject
    let tracker: NestTracker
    let initialDate: Date
    @State private var occurredAt: Date
    @State private var number = ""
    @State private var text = ""
    @State private var yes = true
    @State private var note = ""
    @State private var busy = false
    @State private var error: String?
    init(subject: NestSubject, tracker: NestTracker, date: Date = Date()) {
        self.subject = subject
        self.tracker = tracker
        self.initialDate = date
        _occurredAt = State(initialValue: date)
    }
    private var canLog: Bool {
        store.canLog
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 15) {
                        SubjectAvatar(emoji: subject.emoji, size: 62)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(tracker.name).font(.system(.title2, design: .rounded, weight: .bold))
                            Text("An update for \(subject.name)").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }.padding(.vertical, 10)
                }.listRowBackground(Color.clear)
                Section(content: {
                    switch tracker.valueType {
                    case .none:
                        Label("Mark it as done", systemImage: "checkmark.circle.fill").foregroundStyle(NesticTheme.forest)
                    case .number:
                        HStack {
                            TextField("Amount", text: $number).keyboardType(.decimalPad).accessibilityIdentifier("log.number")
                            if let unit = tracker.unit { Text(unit).foregroundStyle(.secondary) }
                        }
                    case .text:
                        TextField("What would you like to record?", text: $text, axis: .vertical).lineLimit(2...5).accessibilityIdentifier("log.text")
                    case .boolean:
                        Toggle("Yes", isOn: $yes).accessibilityIdentifier("log.bool")
                    case .json:
                        TextField("{\"detail\": \"value\"}", text: $text, axis: .vertical)
                            .textInputAutocapitalization(.never).autocorrectionDisabled().font(.system(.body, design: .monospaced))
                        Text("Enter a JSON object with text keys and values.").font(.caption).foregroundStyle(.secondary)
                    }
                    DatePicker("When", selection: $occurredAt, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                }, header: {
                    Text("The little details")
                })
                Section(content: {
                    TextField("Anything your nest should know?", text: $note, axis: .vertical).lineLimit(3...6).accessibilityIdentifier("log.note")
                }, header: {
                    Text("Note · optional")
                })
                if let error { Text(error).foregroundStyle(.red) }
                if !canLog { Text("You have view-only access to this nest. Ask an owner or admin if you need to log updates.").foregroundStyle(.secondary) }
                Section {
                    PrimaryButton(title: store.isDemo ? "Save update" : "Share update", symbol: "checkmark", busy: busy) { save() }
                        .disabled(!canLog).accessibilityIdentifier("log.save")
                } footer: {
                    Text(store.isDemo ? "This sample update stays on this device." : "Everyone in \(store.selectedNest?.name ?? "your nest") will see this update.")
                }.listRowBackground(Color.clear).listRowInsets(EdgeInsets())
            }.formStyle().navigationTitle("A little update").navigationBarTitleDisplayMode(.inline)
                .scrollDismissesKeyboard(.interactively)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(busy) }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(busy ? "Saving…" : "Save") { save() }
                            .fontWeight(.semibold).disabled(busy || !canLog)
                            .accessibilityIdentifier("log.saveToolbar")
                    }
                }
                .interactiveDismissDisabled(busy)
        }
    }
    private func save() {
        error = nil
        var parsedNumber: Double?
        var parsedJSON: [String: String]?
        if tracker.valueType == .number {
            parsedNumber = NestCoding.parseAmount(number)
            guard let value = parsedNumber, value.isFinite, !number.isEmpty else { error = "Enter a valid amount."; return }
        }
        if tracker.valueType == .text && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            error = "Add a value before saving."; return
        }
        if tracker.valueType == .json {
            guard let data = text.data(using: .utf8), let object = try? JSONDecoder().decode([String: String].self, from: data), !object.isEmpty else {
                error = "Enter a valid JSON object with text keys and values."; return
            }
            parsedJSON = object
        }
        busy = true
        Task {
            defer { busy = false }
            do {
                try await store.log(subjectID: subject.id, trackerID: tracker.id, date: occurredAt, number: parsedNumber,
                                    text: tracker.valueType == .text ? text : nil, bool: tracker.valueType == .boolean ? yes : nil,
                                    json: parsedJSON, note: note)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                dismiss()
            } catch { self.error = error.localizedDescription }
        }
    }
}
