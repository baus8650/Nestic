import SwiftUI

@main
struct NesticWatchApp: App {
    @StateObject private var store = NesticWatchStore.shared

    init() {
        NesticWatchShortcuts.updateAppShortcutParameters()
    }

    var body: some Scene {
        WindowGroup {
            NesticWatchRootView()
                .environmentObject(store)
        }
    }
}

struct NesticWatchRootView: View {
    @EnvironmentObject private var store: NesticWatchStore
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var navigation = NesticWatchNavigationState()

    var body: some View {
        NavigationStack {
            Group {
                if store.subjects.isEmpty && store.routines.isEmpty {
                    ScrollView {
                        VStack(spacing: 12) {
                            Image(systemName: "applewatch").font(.largeTitle)
                            Text("Connect Nestic").font(.headline)
                            Text("Open Nestic on your iPhone to load your trackers and routines.")
                                .font(.footnote).foregroundStyle(.secondary)
                            Button("Sync from iPhone") { store.reloadStoredContext() }
                                .disabled(store.isSyncing)
                            syncStatus
                        }
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    }
                } else {
                    List {
                        syncStatus
                        if !store.routines.isEmpty {
                            Section("Routines") {
                                ForEach(store.routines) { routine in
                                    NesticWatchRoutineRow(routine: routine)
                                }
                            }
                        }
                        ForEach(store.subjects) { subject in
                            Section {
                                ForEach(store.trackers(for: subject)) { tracker in
                                    Button {
                                        if tracker.valueType == .number || tracker.valueType == .text {
                                            navigation.valueTracker = NesticWatchTrackerSelection(subject: subject, tracker: tracker)
                                        } else if tracker.valueType == .boolean {
                                            Task { await store.record(subjectID: subject.id, trackerID: tracker.id, bool: true) }
                                        } else if tracker.valueType == .none {
                                            Task { await store.record(subjectID: subject.id, trackerID: tracker.id) }
                                        } else if tracker.valueType == .health {
                                            store.statusMessage = "Record onset details and resolution on your iPhone."
                                        } else {
                                            store.statusMessage = "Use Nestic on your iPhone for structured details."
                                        }
                                    } label: {
                                        Label(tracker.name, systemImage: tracker.symbol ?? "checkmark.circle")
                                            .foregroundStyle(watchTrackerColor(tracker))
                                    }
                                    .tint(watchTrackerColor(tracker))
                                    .disabled(store.isRecording)
                                }
                            } header: {
                                Label(subject.name, systemImage: "person.crop.circle")
                            }
                        }
                    }
                }
            }
            .navigationTitle("Nestic")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await store.refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(store.isRefreshing || store.isSyncing)
                }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { store.reloadStoredContext() }
        }
        .sheet(item: $navigation.valueTracker) { selection in
            NesticWatchValueView(selection: selection)
                .environmentObject(store)
        }
        .overlay {
            if let receipt = store.recordingReceipt {
                NesticWatchRecordingConfirmation(receipt: receipt)
                    .environmentObject(store)
            }
        }
    }

    @ViewBuilder
    private var syncStatus: some View {
        if store.isSyncing {
            Text("Syncing with iPhone…")
                .font(.footnote)
                .foregroundStyle(.secondary)
        } else if store.isRecording {
            Text("Recording…")
                .font(.footnote)
        } else if let status = store.statusMessage, store.recordingReceipt == nil {
            Text(status)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

}

private struct NesticWatchRoutineRow: View {
    @EnvironmentObject private var store: NesticWatchStore
    let routine: NestRoutine

    var body: some View {
        NavigationLink {
            NesticWatchRoutineDetail(routine: routine)
                .environmentObject(store)
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Label(routine.name, systemImage: "checklist")
                Text(store.routineSummary(for: routine))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }
}

private struct NesticWatchRoutineDetail: View {
    @EnvironmentObject private var store: NesticWatchStore
    @Environment(\.dismiss) private var dismiss
    let routine: NestRoutine

    private var targets: [NesticWatchRoutineTarget] {
        store.routineTargets(for: routine)
    }

    var body: some View {
        List {
            Section("Records for") {
                if targets.isEmpty {
                    Text("Entity and tracker details are unavailable.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(targets) { target in
                        VStack(alignment: .leading, spacing: 4) {
                            Label(target.subject.name, systemImage: "person.crop.circle")
                                .font(.subheadline.weight(.semibold))
                            ForEach(target.trackers) { item in
                                Label(item.tracker.name, systemImage: item.tracker.symbol ?? "checkmark.circle")
                                    .font(.footnote)
                                    .foregroundStyle(watchTrackerColor(item.tracker))
                                    .padding(.leading, 6)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            Section {
                Button {
                    Task {
                        if await store.record(routine: routine) { dismiss() }
                    }
                } label: {
                    if store.isRecording {
                        ProgressView("Recording…")
                    } else {
                        Label("Log routine", systemImage: "checkmark.circle.fill")
                    }
                }
                .tint(.accentColor)
                .disabled(store.isRecording || targets.isEmpty)
                .accessibilityIdentifier("watch.recordRoutine")
            }
        }
        .navigationTitle(routine.name)
    }
}

private struct NesticWatchTrackerSelection: Identifiable {
    let subject: NestSubject
    let tracker: NestTracker
    var id: String { "\(subject.id.uuidString)-\(tracker.id.uuidString)" }
}

private struct NesticWatchValueView: View {
    @EnvironmentObject private var store: NesticWatchStore
    @Environment(\.dismiss) private var dismiss
    let selection: NesticWatchTrackerSelection
    @StateObject private var form = NesticWatchValueForm()

    var body: some View {
        NavigationStack {
            Form {
                TextField(selection.tracker.unit ?? "Value", text: $form.value)
                Button("Record") {
                    Task {
                        let recorded: Bool
                        if selection.tracker.valueType == .number {
                            guard let number = NestCoding.parseAmount(form.value) else {
                                store.statusMessage = "Enter a valid number."
                                return
                            }
                            recorded = await store.record(subjectID: selection.subject.id, trackerID: selection.tracker.id, number: number)
                        } else {
                            recorded = await store.record(subjectID: selection.subject.id, trackerID: selection.tracker.id, text: form.value)
                        }
                        if recorded { dismiss() }
                    }
                }
                .disabled(store.isRecording || form.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if store.isRecording { ProgressView("Recording…") }
                if let message = store.statusMessage, store.recordingReceipt == nil {
                    Text(message).font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle(selection.tracker.name)
            .tint(watchTrackerColor(selection.tracker))
        }
    }
}

private struct NesticWatchRecordingConfirmation: View {
    @EnvironmentObject private var store: NesticWatchStore
    let receipt: NesticWatchRecordingReceipt

    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: receipt.queued ? "checkmark.icloud" : "checkmark.circle.fill")
                .font(.system(size: 32))
                .foregroundStyle(.green)
            Text(receipt.queued ? "Saved on watch" : "Recorded")
                .font(.headline)
            Text(receipt.name).font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.center).lineLimit(2)
            if receipt.queued {
                Text("Will sync when connected").font(.caption2).foregroundStyle(.secondary)
            } else if let detail = receipt.detail {
                Text(detail).font(.caption2).foregroundStyle(.secondary)
            }
            Text(receipt.date, style: .time).font(.caption2).foregroundStyle(.secondary)
            Button("Done") { store.dismissRecordingReceipt() }
                .accessibilityIdentifier("watch.recordingDone")
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black)
        .accessibilityIdentifier("watch.recordingConfirmation")
        .task(id: receipt.id) {
            do {
                try await Task.sleep(for: .seconds(4))
                if store.recordingReceipt?.id == receipt.id { store.dismissRecordingReceipt() }
            } catch { }
        }
    }
}

@MainActor
private final class NesticWatchNavigationState: ObservableObject {
    @Published var valueTracker: NesticWatchTrackerSelection?
}

@MainActor
private final class NesticWatchValueForm: ObservableObject {
    @Published var value = ""
}

private func watchTrackerColor(_ tracker: NestTracker) -> Color {
    Color(nesticHex: tracker.color)
}

private extension Color {
    init(nesticHex hex: String?) {
        let normalized = (hex ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        guard normalized.count == 6, let value = UInt64(normalized, radix: 16) else {
            self = .accentColor
            return
        }
        self.init(red: Double((value >> 16) & 0xFF) / 255,
                  green: Double((value >> 8) & 0xFF) / 255,
                  blue: Double(value & 0xFF) / 255)
    }
}
