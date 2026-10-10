import PhotosUI
import SwiftUI
import UIKit

private struct HealthPhotoLibraryButton: View {
    @Binding var selection: PhotosPickerItem?
    let disabled: Bool

    var body: some View {
        PhotosPicker(selection: $selection, matching: .images, photoLibrary: .shared()) {
            Label("Photo library", systemImage: "photo.badge.plus")
        }
        .buttonStyle(.bordered)
        .disabled(disabled)
    }
}

private struct HealthPhotoUpdatesSection: View {
    let entry: NestEntry
    let canEdit: Bool
    let busy: Bool
    @Binding var selectedPhotoItem: PhotosPickerItem?
    @Binding var draftPhotoData: Data?
    @Binding var updateDate: Date
    @Binding var updateNote: String
    @Binding var photoBusy: Bool
    let onTakePhoto: () -> Void
    let onSave: () -> Void
    let onRemove: (NestHealthPhoto) -> Void

    private var canSave: Bool {
        draftPhotoData != nil || !updateNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Section(content: {
            VStack(alignment: .leading, spacing: 12) {
                DatePicker("Recorded at", selection: $updateDate,
                           in: entry.occurredAt...Date(), displayedComponents: [.date, .hourAndMinute])
                TextField("What changed? · optional", text: $updateNote, axis: .vertical)
                    .lineLimit(2...5)
                if let draftPhotoData, let image = UIImage(data: draftPhotoData) {
                    HStack(spacing: 12) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 76, height: 76)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Photo attached")
                                .font(.subheadline.weight(.semibold))
                            Button("Remove photo", role: .destructive) {
                                self.draftPhotoData = nil
                            }
                            .font(.caption.weight(.semibold))
                        }
                    }
                }
                HStack(spacing: 10) {
                    HealthPhotoLibraryButton(selection: $selectedPhotoItem,
                                             disabled: !canEdit || busy || photoBusy)
                    Button("Take photo", systemImage: "camera.fill", action: onTakePhoto)
                        .buttonStyle(.bordered)
                        .disabled(!canEdit || busy || photoBusy || !UIImagePickerController.isSourceTypeAvailable(.camera))
                }
                Button("Save update", systemImage: "plus.circle.fill", action: onSave)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canEdit || busy || photoBusy || !canSave)
            }
            .padding(.vertical, 4)
            if let updates = entry.photoUpdates, !updates.isEmpty {
                ForEach(updates.sorted { $0.capturedAt < $1.capturedAt }) { photo in
                    HStack(alignment: .top, spacing: 12) {
                        if photo.photoURL.isEmpty {
                            Image(systemName: "text.alignleft")
                                .font(.title2)
                                .foregroundStyle(NesticTheme.forest)
                                .frame(width: 104, height: 104)
                                .background(NesticTheme.lime.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                        } else {
                            NesticHealthPhotoView(entry: entry, photo: photo, size: 104)
                        }
                        VStack(alignment: .leading, spacing: 5) {
                            Text(photo.capturedAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.subheadline.weight(.semibold))
                            if let note = photo.note, !note.isEmpty {
                                Text(note)
                                    .font(.subheadline)
                                    .foregroundStyle(NesticTheme.ink)
                            } else if photo.photoURL.isEmpty {
                                Text("Text update")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text("Shared with your nest")
                                .font(.caption).foregroundStyle(.secondary)
                            if canEdit {
                                Button("Remove", role: .destructive) { onRemove(photo) }
                                    .font(.caption.weight(.semibold))
                                    .disabled(photoBusy)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                }
            } else {
                Text("Add a note or progress photo as the episode changes. Each update is timestamped and shared with the nest.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            if photoBusy { ProgressView("Saving update…") }
        }, header: {
            Text("Health updates")
        }, footer: {
            Text("Add a note, a photo, or both. Every update keeps its own recorded date and time and is shared with the nest.")
        })
    }
}

struct ActivityView: View {
    @EnvironmentObject private var store: NesticStore
    @State private var search = ""
    @State private var subjectFilter: UUID?
    @State private var selectedEntry: NestEntry?
    @State private var error: String?
    private var filtered: [NestEntry] {
        store.entries.filter { entry in
            guard subjectFilter == nil || entry.entityId == subjectFilter else { return false }
            guard !search.isEmpty else { return true }
            let subject = store.subject(id: entry.entityId)
            let tracker = store.tracker(id: entry.actionId)
            let searchableValues = [subject?.name, tracker?.name, entry.note, entry.valueText]
                .compactMap { $0 } + (entry.valueJSON.map { Array($0.values) } ?? [])
            return searchableValues.joined(separator: " ").localizedCaseInsensitiveContains(search)
        }
    }
    var body: some View {
        let matches = filtered
        let grouped = Dictionary(grouping: matches) { Calendar.current.startOfDay(for: $0.occurredAt) }
        let days = grouped.keys.sorted(by: >)
        return List {
            Section {
                HStack(spacing: 9) {
                    if store.isDemo { Text("Sample activity · this device only").font(.caption) }
                    Spacer()
                    Text("\(matches.count) updates").font(.caption).foregroundStyle(.secondary)
                }.listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 10, leading: 0, bottom: 10, trailing: 0))
            }
            if matches.isEmpty {
                EmptyNestView(symbol: search.isEmpty ? "clock.arrow.circlepath" : "magnifyingglass", title: search.isEmpty ? "Your shared story starts here" : "No matching updates", message: search.isEmpty ? "Log something from Home and it will appear in your nest’s activity." : "Try another search or change the filter.")
                    .listRowBackground(Color.clear)
            }
            ForEach(days, id: \.self) { day in
                Section(dayLabel(day)) {
                    ForEach(grouped[day] ?? []) { entry in
                        Button { selectedEntry = entry } label: { EntryRow(entry: entry).padding(.vertical, 6) }
                            .buttonStyle(.plain)
                            .accessibilityHint("Tap to edit or delete this update")
                    }
                }
            }
            if store.hasMoreEntries {
                Button {
                    Task {
                        do { try await store.loadOlderEntries() }
                        catch { self.error = error.localizedDescription }
                    }
                } label: {
                    HStack {
                        Spacer()
                        if store.isLoadingMoreEntries {
                            ProgressView("Loading older updates…")
                        } else {
                            Text("Load older updates")
                        }
                        Spacer()
                    }
                }
                .disabled(store.isLoadingMoreEntries)
                .listRowBackground(Color.clear)
            }
        }.formStyle().navigationTitle("Activity")
            .searchable(text: $search, prompt: "Search names, trackers, or notes")
            .onChange(of: store.selectedNestID) { _, _ in subjectFilter = nil; selectedEntry = nil }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Everything") { subjectFilter = nil }
                        ForEach(store.subjects) { subject in
                            Button("\(subject.emoji) \(subject.name)") { subjectFilter = subject.id }
                        }
                    } label: { Image(systemName: subjectFilter == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill") }
                        .accessibilityLabel("Filter activity")
                }
            }
            .refreshable { do { try await store.refresh() } catch { self.error = error.localizedDescription } }
            .sheet(item: $selectedEntry) { EntryDetailSheet(entry: $0) }
            .alert("Couldn’t refresh", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") { error = nil }
            } message: { Text(error ?? "") }
    }
    private func dayLabel(_ day: Date) -> String {
        if Calendar.current.isDateInToday(day) { return "Today" }
        if Calendar.current.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }
}

struct EntryDetailSheet: View {
    @EnvironmentObject private var store: NesticStore
    @Environment(\.dismiss) private var dismiss
    let entry: NestEntry
    @State private var confirmDelete = false
    @State private var editingEntry: NestEntry?
    @State private var showResolveSheet = false
    @State private var resolutionDate = Date()
    @State private var resolutionNote = ""
    @State private var busy = false
    @State private var photoBusy = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var healthUpdatePhotoData: Data?
    @State private var healthUpdateDate = Date()
    @State private var healthUpdateNote = ""
    @State private var showCamera = false
    @State private var photoToDelete: NestHealthPhoto?
    @State private var error: String?
    private var currentEntry: NestEntry {
        store.entries.first { $0.id == entry.id } ?? entry
    }
    private var canEdit: Bool {
        currentEntry.actorUserId == store.currentUser?.id || store.canManageNest
    }
    private var tracker: NestTracker? {
        store.trackers.first { $0.id == currentEntry.actionId }
    }
    private var isHealthEvent: Bool { tracker?.valueType == .health }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    EntryRow(entry: currentEntry).padding(.vertical, 12)
                    if tracker?.valueType == .photo || (tracker?.valueType == .health && currentEntry.photoURL != nil) {
                        NesticEntryPhotoView(entry: currentEntry, maxHeight: 420)
                    }
                }
                if isHealthEvent {
                    Section("Health episode") {
                        LabeledContent("Onset", value: healthDateText(currentEntry.occurredAt))
                        if let resolvedAt = currentEntry.resolvedAt {
                            LabeledContent("Resolution", value: healthDateText(resolvedAt))
                            LabeledContent("Duration", value: durationText(from: currentEntry.occurredAt, to: resolvedAt))
                            if let note = currentEntry.resolutionNote, !note.isEmpty {
                                Text("Resolution note: \(note)").font(.subheadline).foregroundStyle(.secondary)
                            }
                            if canEdit {
                                Button("Reopen episode", systemImage: "arrow.uturn.backward") { reopen() }
                                    .disabled(busy)
                            }
                        } else if canEdit {
                            Button("Mark resolved", systemImage: "checkmark.circle.fill") {
                                resolutionDate = Date()
                                resolutionNote = ""
                                showResolveSheet = true
                            }
                            .foregroundStyle(NesticTheme.forest)
                            .disabled(busy)
                        } else {
                            Label("Open episode", systemImage: "exclamationmark.circle.fill")
                                .foregroundStyle(.orange)
                        }
                    }
                    HealthPhotoUpdatesSection(entry: currentEntry, canEdit: canEdit, busy: busy,
                                              selectedPhotoItem: $selectedPhotoItem,
                                              draftPhotoData: $healthUpdatePhotoData,
                                              updateDate: $healthUpdateDate,
                                              updateNote: $healthUpdateNote,
                                              photoBusy: $photoBusy,
                                              onTakePhoto: { showCamera = true },
                                              onSave: saveHealthUpdate,
                                              onRemove: { photoToDelete = $0 })
                }
                Section("Recorded for") {
                    LabeledContent("Date", value: currentEntry.occurredAt.formatted(date: .abbreviated, time: .shortened))
                    LabeledContent("Nest", value: store.selectedNest?.name ?? "Your nest")
                    if currentEntry.isAccident {
                        Label("Marked as an accident", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                    if !currentEntry.shouldIncludeInPredictions {
                        Label("Excluded from predictive models", systemImage: "eye.slash")
                            .foregroundStyle(.secondary)
                    }
                }
                if canEdit {
                    Section {
                        Button("Edit update", systemImage: "pencil") { editingEntry = currentEntry }.disabled(busy)
                            .accessibilityIdentifier("entry.edit")
                        Button("Delete update", role: .destructive) { confirmDelete = true }.disabled(busy)
                            .accessibilityIdentifier("entry.delete")
                    } footer: {
                        Text("Changes are shared with everyone in your nest.")
                    }
                }
                if busy {
                    Section { HStack(spacing: 10) { ProgressView(); Text("Working…").foregroundStyle(.secondary) } }
                }
                if let error { Text(error).foregroundStyle(.red) }
            }.formStyle().navigationTitle("Update details").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.disabled(busy) } }
                .alert("Delete this update?", isPresented: $confirmDelete) {
                    Button("Delete update", role: .destructive) {
                        busy = true
                        Task {
                            defer { busy = false }
                            do { try await store.deleteEntry(currentEntry); dismiss() }
                            catch { self.error = error.localizedDescription }
                        }
                    }
                    Button("Cancel", role: .cancel) { confirmDelete = false }
                } message: { Text("Everyone in your nest will see the updated history.") }
                .sheet(item: $editingEntry) { editedEntry in
                    if let subject = store.subjects.first(where: { $0.id == editedEntry.entityId }),
                       let tracker = store.trackers.first(where: { $0.id == editedEntry.actionId }) {
                        LogEntrySheet(subject: subject, tracker: tracker, editingEntry: editedEntry)
                    } else {
                        Text("This tracker is no longer available.")
                    }
                }
                .sheet(isPresented: $showResolveSheet) {
                    NavigationStack {
                        Form {
                            DatePicker("Resolution", selection: $resolutionDate,
                                       in: currentEntry.occurredAt...Date(), displayedComponents: [.date, .hourAndMinute])
                            TextField("What changed? · optional", text: $resolutionNote, axis: .vertical)
                                .lineLimit(3...6)
                        }
                        .formStyle()
                        .navigationTitle("Resolve episode")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Cancel") { showResolveSheet = false }
                            }
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Mark resolved") { resolve() }.disabled(busy)
                            }
                        }
                    }
                    .presentationDetents([.medium])
                }
                .sheet(isPresented: $showCamera) {
                    NesticCameraCaptureView { image in
                        guard let data = image.jpegData(compressionQuality: 0.92) else { return }
                        healthUpdatePhotoData = try? NesticEntryPhotoStore.jpegData(from: data)
                    }
                    .ignoresSafeArea()
                }
                .alert("Remove this health update?", item: $photoToDelete) { photo in
                    Button("Remove update", role: .destructive) { removeHealthPhoto(photo) }
                    Button("Cancel", role: .cancel) { photoToDelete = nil }
                } message: { _ in
                    Text("This shared health update will be removed from the episode for everyone in your nest.")
                }
                .onChange(of: selectedPhotoItem) { _, item in
                    guard let item else { return }
                    photoBusy = true
                    Task { @MainActor in
                        defer {
                            photoBusy = false
                            selectedPhotoItem = nil
                        }
                        do {
                            if let data = try await item.loadTransferable(type: Data.self) {
                                healthUpdatePhotoData = try NesticEntryPhotoStore.jpegData(from: data)
                            } else {
                                error = "That photo could not be loaded. Please choose another one."
                            }
                        } catch {
                            self.error = error.localizedDescription
                        }
                    }
                }
                .onAppear { resetHealthUpdateDraft() }
                .interactiveDismissDisabled(busy)
        }
    }

    private func resolve() {
        busy = true
        Task {
            defer { busy = false }
            do {
                _ = try await store.resolveHealthEntry(currentEntry, at: resolutionDate, note: resolutionNote)
                showResolveSheet = false
            } catch let resolveError { self.error = resolveError.localizedDescription }
        }
    }

    private func reopen() {
        busy = true
        Task {
            defer { busy = false }
            do { _ = try await store.reopenHealthEntry(currentEntry) }
            catch let reopenError { self.error = reopenError.localizedDescription }
        }
    }

    private func saveHealthUpdate() {
        guard !photoBusy else { return }
        photoBusy = true
        let photoData = healthUpdatePhotoData
        let date = healthUpdateDate
        let note = healthUpdateNote
        Task {
            defer { photoBusy = false }
            do {
                if let photoData {
                    _ = try await store.addHealthPhoto(photoData, to: currentEntry, at: date, note: note)
                } else {
                    _ = try await store.addHealthUpdate(to: currentEntry, at: date, note: note)
                }
                resetHealthUpdateDraft()
            } catch let updateError { self.error = updateError.localizedDescription }
        }
    }

    private func resetHealthUpdateDraft() {
        healthUpdatePhotoData = nil
        selectedPhotoItem = nil
        healthUpdateDate = Date()
        healthUpdateNote = ""
    }

    private func removeHealthPhoto(_ photo: NestHealthPhoto) {
        photoBusy = true
        Task {
            defer {
                photoBusy = false
                photoToDelete = nil
            }
            do { _ = try await store.removeHealthPhoto(photo, from: currentEntry) }
            catch let photoError { self.error = photoError.localizedDescription }
        }
    }

    private func durationText(from onset: Date, to resolution: Date) -> String {
        let hours = max(0, resolution.timeIntervalSince(onset) / 3600)
        if hours < 1 { return "< 1 hour" }
        if hours < 48 { return "\(hours.formatted(.number.precision(.fractionLength(0...1)))) hr" }
        return "\((hours / 24).formatted(.number.precision(.fractionLength(0...1)))) days"
    }

    private func healthDateText(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }
}
