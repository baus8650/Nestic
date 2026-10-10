import SwiftUI

struct CareLinkView: View {
    @EnvironmentObject private var store: NesticStore
    @State private var selectedTarget: CareLogTarget?
    @State private var selectedRoutine: NestRoutine?

    private var session: NestCareSession? { store.careLinkSession }

    var body: some View {
        NavigationStack {
            if let session {
                List {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Label(session.snapshot.link.label, systemImage: "person.crop.circle.badge.checkmark")
                                .font(.system(.title2, design: .rounded, weight: .bold))
                                .foregroundStyle(NesticTheme.forest)
                            Text(session.snapshot.nestName)
                                .font(.subheadline.weight(.semibold))
                            Text("Access ends \(session.snapshot.link.expiresAt, format: .dateTime.month().day().hour().minute())")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(permissionSummary(session.snapshot.link))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 8)
                    }
                    if session.snapshot.link.canLog {
                        Section("Routines") {
                            if session.snapshot.routines.isEmpty {
                                Text("No shared routines are available.").foregroundStyle(.secondary)
                            } else {
                                ForEach(session.snapshot.routines) { routine in
                                    Button { selectedRoutine = routine } label: {
                                        HStack(spacing: 12) {
                                            Image(systemName: "checklist")
                                                .foregroundStyle(NesticTheme.forest)
                                                .frame(width: 28, height: 28)
                                                .background(NesticTheme.lime.opacity(0.35), in: Circle())
                                            VStack(alignment: .leading, spacing: 3) {
                                                Text(routine.name).font(.subheadline.weight(.semibold))
                                                Text(routineSummary(routine, snapshot: session.snapshot))
                                                    .font(.caption).foregroundStyle(.secondary)
                                            }
                                            Spacer()
                                            Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(.tertiary)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    Section("Subjects and trackers") {
                        ForEach(session.snapshot.subjects) { subject in
                            let subjectTrackers = session.snapshot.trackers.filter { session.snapshot.link.actionIDs.contains($0.id) }
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(spacing: 12) {
                                    SubjectAvatar(emoji: subject.emoji, photoData: subject.photoData, size: 46)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(subject.name).font(.headline)
                                        Text(subject.kind.title).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                if session.snapshot.link.canLog {
                                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 135), spacing: 8)], spacing: 8) {
                                        ForEach(subjectTrackers) { tracker in
                                            Button {
                                                guard tracker.valueType != .photo else { return }
                                                selectedTarget = CareLogTarget(subject: subject, tracker: tracker)
                                            } label: {
                                                HStack(spacing: 7) {
                                                    TrackerIconView(tracker: tracker, size: .subheadline)
                                                    Text(tracker.name).lineLimit(1)
                                                    Spacer(minLength: 0)
                                                }
                                                .font(.subheadline.weight(.medium))
                                                .padding(.horizontal, 10).padding(.vertical, 9)
                                                .foregroundStyle(trackerColor(tracker))
                                                .background(trackerColor(tracker).opacity(0.12), in: Capsule())
                                            }
                                            .buttonStyle(.plain)
                                            .disabled(tracker.valueType == .photo)
                                        }
                                    }
                                } else {
                                    Text("View-only access")
                                        .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 5)
                        }
                    }
                    if session.snapshot.link.canViewHistory {
                        Section("Recent updates") {
                            if session.snapshot.entries.isEmpty {
                                Text("No updates yet.").foregroundStyle(.secondary)
                            } else {
                                ForEach(session.snapshot.entries.prefix(100)) { entry in
                                    CareEntryRow(entry: entry, snapshot: session.snapshot)
                                }
                            }
                        }
                    }
                    Section {
                        Text("This access link only exposes the subjects and trackers selected by the nest owner. It does not provide access to account settings, photos, members, or other nests.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .formStyle()
                .navigationTitle("Care access")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { store.closeCareLink() }
                    }
                }
                .sheet(item: $selectedTarget) { target in
                    CareLogSheet(subject: target.subject, tracker: target.tracker)
                }
                .sheet(item: $selectedRoutine) { routine in
                    CareRoutineLogSheet(routine: routine)
                }
            } else {
                ProgressView("Opening care access…")
                    .navigationTitle("Care access")
            }
        }
    }

    private func permissionSummary(_ link: NestCareLink) -> String {
        switch (link.canLog, link.canViewHistory) {
        case (true, true): "Can record updates and view recent history"
        case (true, false): "Can record updates"
        case (false, true): "Can view recent history"
        case (false, false): "No actions available"
        }
    }

    private func routineSummary(_ routine: NestRoutine, snapshot: NestCareSnapshot) -> String {
        let entities = routine.targets.compactMap { target in
            snapshot.subjects.first { $0.id == target.entityID }?.name
        }
        let trackerCount = routine.targets.reduce(0) { $0 + $1.items.count }
        let subjectText = entities.isEmpty ? "Selected subjects" : entities.joined(separator: ", ")
        return "\(subjectText) · \(trackerCount) tracker\(trackerCount == 1 ? "" : "s")"
    }
}

private struct CareLogTarget: Identifiable {
    let subject: NestSubject
    let tracker: NestTracker
    var id: String { "\(subject.id.uuidString)-\(tracker.id.uuidString)" }
}

private struct CareEntryRow: View {
    let entry: NestEntry
    let snapshot: NestCareSnapshot

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: tracker?.valueType.symbol ?? "checkmark.circle")
                .foregroundStyle(tracker.map { trackerColor($0) } ?? NesticTheme.forest)
                .frame(width: 26, height: 26)
                .background(NesticTheme.lime.opacity(0.28), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text("\(subject?.name ?? "Subject") · \(tracker?.name ?? "Tracker")")
                    .font(.subheadline.weight(.semibold))
                Text(entry.displayValue(unit: tracker?.unit))
                    .font(.subheadline)
                if let note = entry.note, !note.isEmpty {
                    Text(note).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Text(entry.occurredAt, format: .dateTime.month().day().hour().minute())
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
    }

    private var subject: NestSubject? { snapshot.subjects.first { $0.id == entry.entityId } }
    private var tracker: NestTracker? { snapshot.trackers.first { $0.id == entry.actionId } }
}

struct CareLogSheet: View {
    @EnvironmentObject private var store: NesticStore
    @Environment(\.dismiss) private var dismiss
    let subject: NestSubject
    let tracker: NestTracker
    @State private var date = Date()
    @State private var number = ""
    @State private var text = ""
    @State private var jsonValue = ""
    @State private var boolValue = false
    @State private var note = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        SubjectAvatar(emoji: subject.emoji, photoData: subject.photoData, size: 44)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(subject.name).font(.headline)
                            Label(tracker.name, systemImage: tracker.valueType.symbol)
                                .font(.subheadline).foregroundStyle(trackerColor(tracker))
                        }
                    }
                }
                Section("Update") {
                    switch tracker.valueType {
                    case .none:
                        Text("This records that the update happened.").foregroundStyle(.secondary)
                    case .number:
                        TextField(tracker.unit.map { "Amount (\($0))" } ?? "Amount", text: $number)
                            .keyboardType(.decimalPad)
                    case .text, .health:
                        TextField(tracker.valueType == .health ? "Describe the health event" : "What happened?", text: $text, axis: .vertical)
                            .lineLimit(3...6)
                    case .boolean:
                        Toggle("Yes", isOn: $boolValue)
                    case .json:
                        TextField("Detail", text: $jsonValue, axis: .vertical).lineLimit(3...6)
                    case .photo:
                        Text("Photo trackers can be viewed here but must be updated from the Nestic app.")
                            .foregroundStyle(.secondary)
                    }
                    DatePicker("When", selection: $date, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                }
                Section("Note · optional") {
                    TextField("Anything else to share?", text: $note, axis: .vertical).lineLimit(3...6)
                }
                if let error { Text(error).foregroundStyle(.red) }
                Section {
                    PrimaryButton(title: "Record update", symbol: "checkmark", busy: busy) { save() }
                        .disabled(busy || tracker.valueType == .photo)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            .formStyle()
            .navigationTitle("Record update")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(busy)
                }
            }
            .interactiveDismissDisabled(busy)
        }
    }

    private func save() {
        error = nil
        let parsedNumber = NestCoding.parseAmount(number)
        let json = tracker.valueType == .json ? ["detail": jsonValue] : nil
        guard tracker.valueType != .number || parsedNumber != nil else {
            error = "Enter a valid number."
            return
        }
        busy = true
        Task {
            defer { busy = false }
            do {
                try await store.logCareEvent(subjectID: subject.id, trackerID: tracker.id, date: date,
                                              number: tracker.valueType == .number ? parsedNumber : nil,
                                              text: [.text, .health].contains(tracker.valueType) ? text : nil,
                                              bool: tracker.valueType == .boolean ? boolValue : nil,
                                              json: tracker.valueType == .json ? json : nil,
                                              note: note.isEmpty ? nil : note)
                dismiss()
            } catch let caughtError { self.error = caughtError.localizedDescription }
        }
    }
}

struct CareRoutineLogSheet: View {
    @EnvironmentObject private var store: NesticStore
    @Environment(\.dismiss) private var dismiss
    let routine: NestRoutine
    @State private var date = Date()
    @State private var note = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(routine.name).font(.system(.title3, design: .rounded, weight: .bold))
                    Text("Record this routine for all of its selected subjects and trackers.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Section("When") {
                    DatePicker("Recorded at", selection: $date, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                }
                Section("Note · optional") {
                    TextField("Anything else to share?", text: $note, axis: .vertical).lineLimit(3...6)
                }
                if let error { Text(error).foregroundStyle(.red) }
                Section {
                    PrimaryButton(title: "Record routine", symbol: "checkmark", busy: busy) { save() }
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            .formStyle()
            .navigationTitle("Record routine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(busy)
                }
            }
        }
    }

    private func save() {
        busy = true
        error = nil
        Task {
            defer { busy = false }
            do {
                try await store.logCareRoutine(routine, date: date, note: note.isEmpty ? nil : note)
                dismiss()
            } catch let caughtError { self.error = caughtError.localizedDescription }
        }
    }
}
