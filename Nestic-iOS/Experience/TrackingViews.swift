import Charts
import PhotosUI
import SwiftUI
import UIKit
import AVFoundation

struct NesticCameraCaptureView: View {
    let onCapture: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var authorized: Bool?

    var body: some View {
        Group {
            if authorized == true {
                NesticCameraPicker(onCapture: onCapture)
            } else {
                NavigationStack {
                    Group {
                        if authorized == nil { ProgressView("Preparing camera…") }
                        else {
                            ContentUnavailableView {
                                Label("Camera access is off", systemImage: "camera")
                            } description: {
                                Text("Allow camera access in Settings to take a progress photo, or select a photo from your library instead.")
                            } actions: {
                                Link("Open Settings", destination: URL(string: UIApplication.openSettingsURLString)!)
                            }
                        }
                    }
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
                }
            }
        }
        .task {
            guard UIImagePickerController.isSourceTypeAvailable(.camera) else { authorized = false; return }
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized: authorized = true
            case .notDetermined: authorized = await AVCaptureDevice.requestAccess(for: .video)
            default: authorized = false
            }
        }
    }
}

struct NesticCameraPicker: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let parent: NesticCameraPicker

        init(_ parent: NesticCameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onCapture(image) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

struct NesticHealthPhotoView: View {
    @EnvironmentObject private var store: NesticStore
    let entry: NestEntry
    let photo: NestHealthPhoto
    let size: CGFloat?
    @State private var image: UIImage?

    init(entry: NestEntry, photo: NestHealthPhoto, size: CGFloat? = nil) {
        self.entry = entry
        self.photo = photo
        self.size = size
        _image = State(initialValue: NesticEntryPhotoStore.image(forPhotoID: photo.id))
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                ProgressView()
            }
        }
        .frame(width: size, height: size)
        .frame(maxWidth: size == nil ? .infinity : nil, minHeight: size == nil ? 180 : nil)
        .background(NesticTheme.lime.opacity(0.12), in: RoundedRectangle(cornerRadius: size == nil ? 18 : 12))
        .clipShape(RoundedRectangle(cornerRadius: size == nil ? 18 : 12))
        .task(id: photo.id) {
            guard image == nil else { return }
            if let data = try? await store.healthPhotoData(photo, for: entry) {
                image = UIImage(data: data)
            }
        }
    }
}

struct SubjectPhotoPicker: View {
    @Binding var photoData: String?
    let emoji: String
    let size: CGFloat
    @State private var selectedItem: PhotosPickerItem?
    @State private var isLoading = false

    var body: some View {
        PhotosPicker(selection: $selectedItem, matching: .images, photoLibrary: .shared()) {
            ZStack(alignment: .bottomTrailing) {
                SubjectAvatar(emoji: emoji, photoData: photoData, size: size)
                Image(systemName: photoData == nil ? "camera.fill" : "pencil")
                    .font(.system(size: max(11, size * 0.17), weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: max(24, size * 0.32), height: max(24, size * 0.32))
                    .background(NesticTheme.forest, in: Circle())
                    .overlay(Circle().stroke(NesticTheme.paper, lineWidth: 2))
                if isLoading {
                    RoundedRectangle(cornerRadius: size * 0.32)
                        .fill(NesticTheme.card.opacity(0.78))
                    ProgressView().tint(NesticTheme.forest)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .accessibilityLabel(photoData == nil ? "Add a photo" : "Change photo")
        .onChange(of: selectedItem) { _, item in
            guard let item else { return }
            isLoading = true
            Task {
                let data = try? await item.loadTransferable(type: Data.self)
                let encoded = data.flatMap { SubjectPhoto.encoded(from: $0) }
                await MainActor.run {
                    isLoading = false
                    if let encoded { photoData = encoded }
                }
            }
        }
    }
}

struct AddSubjectSheet: View {
    @EnvironmentObject private var store: NesticStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var kind: NestSubjectKind = .pet
    @State private var emoji = "🐶"
    @State private var photoData: String?
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
                    HStack(spacing: 16) {
                        SubjectPhotoPicker(photoData: $photoData, emoji: emoji, size: 84)
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Add a photo")
                                .font(.system(.title3, design: .rounded, weight: .bold))
                            Text("Use a real photo for this subject, or keep the fallback icon.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 16)
                    VStack(spacing: 12) {
                        Text("What are you tracking?")
                            .font(.system(.title3, design: .rounded, weight: .bold))
                        Text("A pet, a person, your home, or something else.").font(.subheadline).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity).padding(.vertical, 16)
                }.listRowBackground(Color.clear)
                Section(content: {
                    TextField("Name, e.g. Milo", text: $name).accessibilityIdentifier("subject.name")
                    Picker("Category", selection: $kind) {
                        ForEach(NestSubjectKind.allCases, id: \.self) { Text($0.title).tag($0) }
                    }.onChange(of: kind) { _, new in emoji = new.emoji }
                    HStack {
                        Text("Fallback icon")
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
                    Text("You can add your own trackers at any time: outings, meals, chores, and anything in between.")
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
                                    try await store.createSubject(name: name, kind: kind, emoji: emoji.isEmpty ? kind.emoji : emoji,
                                                                  photoData: photoData, trackerTemplates: templates)
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

struct SubjectPhotoEditor: View {
    @EnvironmentObject private var store: NesticStore
    @Environment(\.dismiss) private var dismiss
    let subject: NestSubject
    @State private var photoData: String?
    @State private var busy = false
    @State private var error: String?

    init(subject: NestSubject) {
        self.subject = subject
        _photoData = State(initialValue: subject.photoData)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 14) {
                        SubjectPhotoPicker(photoData: $photoData, emoji: subject.emoji, size: 132)
                        Text(photoData == nil ? "Using the fallback icon" : "This photo will appear across your nest")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                }
                if photoData != nil {
                    Section {
                        Button("Remove photo", role: .destructive) { photoData = nil }
                    }
                }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .formStyle()
            .navigationTitle("Photo for \(subject.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(busy)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(busy ? "Saving…" : "Save") {
                        busy = true
                        error = nil
                        Task {
                            defer { busy = false }
                            do {
                                try await store.updateSubjectPhoto(subject, photoData: photoData)
                                dismiss()
                            } catch { self.error = error.localizedDescription }
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(busy)
                }
            }
            .interactiveDismissDisabled(busy)
        }
    }
}

private enum TrackerIconMode: String, CaseIterable, Identifiable {
    case symbols
    case emoji

    var id: String { rawValue }
    var title: String {
        switch self {
        case .symbols: "Symbols"
        case .emoji: "Emoji"
        }
    }
}

struct TrackerIconPicker: View {
    @Binding var selection: String
    @State private var mode: TrackerIconMode = .symbols
    @State private var search = ""

    private var filteredSymbols: [String] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return TrackerIconCatalog.symbols }
        return TrackerIconCatalog.symbols.filter { $0.localizedCaseInsensitiveContains(query) }
    }

    private var filteredEmoji: [String] {
        // Emoji do not have a reliable platform-wide keyword index. Searching by
        // the character itself still makes it easy to find a pasted emoji.
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return TrackerIconCatalog.emojis }
        return TrackerIconCatalog.emojis.filter { $0.contains(query) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Icon type", selection: $mode) {
                ForEach(TrackerIconMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Icon type")

            TextField(mode == .symbols ? "Search symbols" : "Paste an emoji to filter", text: $search)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityLabel("Search icons")

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 8) {
                ForEach(mode == .symbols ? filteredSymbols : filteredEmoji, id: \.self) { value in
                    Button {
                        selection = value
                    } label: {
                        Group {
                            if mode == .emoji {
                                Text(value).font(.title2)
                            } else {
                                Image(systemName: value).font(.title3)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .foregroundStyle(selection == value ? NesticTheme.deepForest : NesticTheme.forest)
                        .background(selection == value ? NesticTheme.lime : NesticTheme.paper, in: RoundedRectangle(cornerRadius: 10))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(selection == value ? NesticTheme.forest : Color.secondary.opacity(0.16), lineWidth: selection == value ? 2 : 1)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(mode == .emoji ? "Choose emoji \(value)" : "Choose \(value.replacingOccurrences(of: ".", with: " ")) symbol")
                    .accessibilityAddTraits(selection == value ? .isSelected : [])
                }
            }
            if (mode == .symbols ? filteredSymbols : filteredEmoji).isEmpty {
                Text(mode == .symbols ? "No symbols match that search." : "No emoji match that search.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 4)
    }
}

struct TrackerColorPicker: View {
    @Binding var selection: String

    private var selectedColor: Color {
        Color(nesticHex: selection) ?? NesticTheme.forest
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 6), spacing: 10) {
                ForEach(TrackerColorCatalog.colors, id: \.hex) { option in
                    Button {
                        selection = option.hex
                    } label: {
                        Circle()
                            .fill(Color(nesticHex: option.hex) ?? NesticTheme.forest)
                            .frame(width: 34, height: 34)
                            .overlay {
                                if selection.caseInsensitiveCompare(option.hex) == .orderedSame {
                                    Image(systemName: "checkmark")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(.white)
                                }
                            }
                            .overlay(Circle().stroke(.primary.opacity(0.18), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Choose \(option.name) tracker color")
                    .accessibilityAddTraits(selection.caseInsensitiveCompare(option.hex) == .orderedSame ? .isSelected : [])
                }
            }
            ColorPicker("Choose any color", selection: Binding(
                get: { selectedColor },
                set: { selection = $0.nesticHex }
            ), supportsOpacity: false)
            .accessibilityLabel("Choose a custom tracker color")
        }
        .padding(.vertical, 4)
    }
}

enum SubjectDetailMode: String, Hashable {
    case record
    case insights
}

struct SubjectDetailView: View {
    @EnvironmentObject private var store: NesticStore
    @EnvironmentObject private var subscription: NesticSubscriptionStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let subject: NestSubject
    @State private var showAdd = false
    @State private var showAddMedication = false
    @State private var selection: LogSelection?
    @State private var editingTracker: NestTracker?
    @State private var deletingTracker: NestTracker?
    @State private var deletingTrackerBusy = false
    @State private var trackerError: String?
    @State private var selectedEntry: NestEntry?
    @State private var deletingEntry: NestEntry?
    @State private var deletingEntryBusy = false
    @State private var entryError: String?
    @State private var showPhotoEditor = false
    @State private var showProPaywall = false
    @State private var showRoutineEditor = false
    @State private var editingRoutine: NestRoutine?
    @State private var deletingRoutine: NestRoutine?
    @State private var routineBusyID: UUID?
    @State private var routineError: String?
    @State private var showDeleteSubject = false
    @State private var deletingSubjectBusy = false
    @State private var subjectError: String?
    @State private var selectedMode: SubjectDetailMode

    init(subject: NestSubject, initialMode: SubjectDetailMode = .record) {
        self.subject = subject
        _selectedMode = State(initialValue: initialMode)
    }

    private var currentSubject: NestSubject { store.subjects.first { $0.id == subject.id } ?? subject }
    private var isWideLayout: Bool { horizontalSizeClass == .regular }

    private var subjectTrackers: [NestTracker] {
        store.trackers(for: currentSubject)
    }

    private var medicationTrackers: [NestTracker] {
        subjectTrackers.filter { isMedication($0) }
    }

    private var otherTrackers: [NestTracker] {
        subjectTrackers.filter { !isMedication($0) }
    }

    private var subjectRoutines: [NestRoutine] {
        store.routines(for: currentSubject)
    }

    private var hasRoutineAccess: Bool {
        store.hasRoutineAccess
    }

    private func isMedication(_ tracker: NestTracker) -> Bool {
        guard let groupName = tracker.groupName else { return false }
        return groupName.caseInsensitiveCompare("Medication") == .orderedSame
    }

    private func canEditEntry(_ entry: NestEntry) -> Bool {
        store.canManageNest || (store.canLog && entry.actorUserId == store.currentUser?.id)
    }

    private func editRoutine(_ routine: NestRoutine? = nil) {
        guard hasRoutineAccess else {
            showProPaywall = true
            return
        }
        editingRoutine = routine
        showRoutineEditor = true
    }

    private func logRoutine(_ routine: NestRoutine) {
        guard hasRoutineAccess else {
            showProPaywall = true
            return
        }
        routineBusyID = routine.id
        Task {
            defer { routineBusyID = nil }
            do {
                try await store.logRoutine(routine)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } catch { routineError = error.localizedDescription }
        }
    }

    private func deleteSubject() {
        deletingSubjectBusy = true
        Task {
            defer { deletingSubjectBusy = false }
            do {
                try await store.deleteSubject(currentSubject)
                dismiss()
            } catch { subjectError = error.localizedDescription }
        }
    }

    @ViewBuilder
    private var routinesSection: some View {
        if hasRoutineAccess {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    SectionHeading(title: "Routines", detail: "ONE-TAP UPDATES")
                    Spacer()
                    if store.canLog {
                        Button { editRoutine() } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 14, weight: .semibold))
                                .frame(width: 32, height: 32)
                                .background(NesticTheme.forest.opacity(0.08), in: Circle())
                        }
                        .accessibilityLabel("Create a routine")
                    }
                }
                if subjectRoutines.isEmpty {
                    Text(store.canManageNest
                         ? "Bundle a meal, medications, or any set of updates you do together."
                         : "No routines have been set up for \(currentSubject.name) yet.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .nesticCard()
                    if store.canLog {
                        Button { editRoutine() } label: {
                            Label("Create a routine", systemImage: "square.stack.3d.up.fill")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding()
                        }
                    }
                } else {
                    ForEach(subjectRoutines) { routine in
                        routineRow(routine)
                    }
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "lock.fill").foregroundStyle(NesticTheme.forest)
                    Text("Routines").font(.system(.title3, design: .rounded, weight: .bold))
                    Spacer()
                    Text("PRO").font(.caption2.weight(.bold)).foregroundStyle(NesticTheme.forest)
                }
                Text("Bundle food, medication, and other updates into one tap for \(currentSubject.name).")
                    .font(.subheadline).foregroundStyle(.secondary)
                Button("Unlock Routines") { showProPaywall = true }
                    .font(.subheadline.weight(.semibold))
            }
            .nesticCard()
        }
    }

    private func routineRow(_ routine: NestRoutine) -> some View {
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
            .accessibilityLabel("Log \(routine.name) for \(currentSubject.name)")
            if store.canManageNest || (store.canLog && routine.isPrivate && routine.privateOwnerId == store.currentUser?.id) {
                Menu {
                    Button("Edit routine", systemImage: "pencil") { editRoutine(routine) }
                    Button("Delete routine", systemImage: "trash", role: .destructive) { deletingRoutine = routine }
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

    @ViewBuilder
    private var openHealthEventsSection: some View {
        if !openHealthEntries.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeading(title: "Open health events", detail: "QUICK UPDATES")
                ForEach(openHealthEntries) { entry in
                    Button { selectedEntry = entry } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "cross.case.fill")
                                .font(.title3)
                                .foregroundStyle(.orange)
                                .frame(width: 28, height: 28)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(store.trackers.first(where: { $0.id == entry.actionId })?.name ?? "Health event")
                                    .font(.headline)
                                    .foregroundStyle(NesticTheme.ink)
                                if let details = entry.valueText, !details.isEmpty {
                                    Text(details)
                                        .font(.subheadline)
                                        .foregroundStyle(NesticTheme.ink)
                                        .lineLimit(2)
                                }
                                Text("Open since \(entry.occurredAt.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                                Label("Tap to add a photo update or mark resolved", systemImage: "plus.circle")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(NesticTheme.forest)
                            }
                            Spacer(minLength: 4)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("subject.openHealth.\(entry.id.uuidString)")
                    .nesticCard()
                }
            }
        }
    }

    @ViewBuilder
    private func trackerRow(_ tracker: NestTracker) -> some View {
        HStack(spacing: 8) {
            Button { selection = LogSelection(subject: currentSubject, tracker: tracker) } label: {
                HStack(spacing: 14) {
                    TrackerIconView(tracker: tracker, size: .title3).frame(width: 26).foregroundStyle(trackerColor(tracker))
                    VStack(alignment: .leading, spacing: 5) {
                        Text(tracker.name).font(.headline).foregroundStyle(NesticTheme.ink)
                        if tracker.isPrivate { Label(tracker.privacyLabel, systemImage: "lock.fill").font(.caption).foregroundStyle(.secondary) }
                        if let last = store.latestEntry(for: tracker, subject: currentSubject) {
                            if tracker.valueType == .health {
                                Text(last.resolvedAt == nil ? "Open since \(last.occurredAt, format: .dateTime.month(.abbreviated).day())" : "Last episode resolved")
                                    .font(.caption).foregroundStyle(last.resolvedAt == nil ? .orange : .secondary)
                            } else {
                                Text(last.occurredAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        } else { Text("Ready for your first update").font(.caption).foregroundStyle(.secondary) }
                    }
                    Spacer()
                    Image(systemName: "plus.circle.fill").font(.title2).foregroundStyle(trackerColor(tracker))
                }
            }.buttonStyle(.plain)
                .accessibilityLabel("Quick log \(tracker.name) for \(currentSubject.name)")
            if tracker.isPrivate ? (store.canLog && tracker.privateOwnerId == store.currentUser?.id) : store.canManageNest {
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

    private var subjectHeader: some View {
        HStack(spacing: 18) {
            Button { showPhotoEditor = true } label: {
                ZStack(alignment: .bottomTrailing) {
                    SubjectAvatar(emoji: currentSubject.emoji, photoData: currentSubject.photoData, size: isWideLayout ? 112 : 82)
                    Image(systemName: "camera.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: isWideLayout ? 34 : 27, height: isWideLayout ? 34 : 27)
                        .background(NesticTheme.forest, in: Circle())
                        .overlay(Circle().stroke(NesticTheme.paper, lineWidth: 2))
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Change photo for \(currentSubject.name)")
            VStack(alignment: .leading, spacing: 6) {
                Text(currentSubject.name)
                    .font(.system(size: isWideLayout ? 40 : 34, weight: .bold, design: .rounded))
            }
        }
        .padding(.horizontal, isWideLayout ? 34 : 22)
        .padding(.top, isWideLayout ? 28 : 16)
        .padding(.bottom, isWideLayout ? 18 : 12)
    }

    private var recordView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 25) {
                if deletingSubjectBusy || deletingTrackerBusy || deletingEntryBusy {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text(deletingSubjectBusy ? "Deleting entity…" : (deletingTrackerBusy ? "Deleting tracker…" : "Deleting update…"))
                            .font(.subheadline).foregroundStyle(.secondary)
                        Spacer()
                    }.nesticCard()
                }
                openHealthEventsSection
                routinesSection
                if !medicationTrackers.isEmpty {
                    SectionHeading(title: "Medication", detail: "TAP TO LOG")
                    ForEach(medicationTrackers) { tracker in
                        trackerRow(tracker)
                    }
                    if store.canManageNest {
                        Button { showAddMedication = true } label: {
                            Label("Add another medicine", systemImage: "plus")
                                .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).padding()
                        }
                    }
                }
                if !otherTrackers.isEmpty {
                    SectionHeading(title: medicationTrackers.isEmpty ? "Trackers" : "Other trackers", detail: "TAP TO LOG")
                    ForEach(otherTrackers) { tracker in
                        trackerRow(tracker)
                    }
                }
                if store.canManageNest {
                    if medicationTrackers.isEmpty {
                        Button { showAddMedication = true } label: {
                            Label("Add a medication group", systemImage: "pills.fill")
                                .font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).padding()
                        }.accessibilityIdentifier("subject.addMedication")
                    }
                    Button { showAdd = true } label: {
                        Label("Add a custom tracker", systemImage: "plus").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity).padding()
                    }.accessibilityIdentifier("subject.addTracker")
                } else if store.canLog {
                    Button { showAdd = true } label: { Label("Add a private tracker", systemImage: "lock.fill").frame(maxWidth: .infinity).padding() }
                }
                SectionHeading(title: "Recent history", detail: "\(store.entries(for: currentSubject).count) UPDATES")
                if store.entries(for: currentSubject).isEmpty {
                    EmptyNestView(symbol: "clock", title: "A fresh start", message: "Log a tracker above to start building a shared history.")
                } else {
                    LazyVStack(spacing: 16) {
                        ForEach(store.entries(for: currentSubject)) { entry in
                            Button { selectedEntry = entry } label: {
                                EntryRow(entry: entry)
                                    .padding(.vertical, 6)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            .contentShape(Rectangle())
                            .accessibilityHint("Tap to edit or delete this update")
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                if canEditEntry(entry) {
                                    Button("Delete", systemImage: "trash", role: .destructive) { deletingEntry = entry }
                                        .accessibilityIdentifier("subject.entry.delete")
                                    Button("Edit", systemImage: "pencil") { selectedEntry = entry }
                                        .tint(NesticTheme.forest)
                                        .accessibilityIdentifier("subject.entry.edit")
                                }
                            }
                        }
                    }.nesticCard()
                }
            }
            .frame(maxWidth: isWideLayout ? 1280 : .infinity)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, isWideLayout ? 34 : 22)
            .padding(.vertical, isWideLayout ? 28 : 22)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            subjectHeader
            Picker("Subject view", selection: $selectedMode) {
                Text("Record").tag(SubjectDetailMode.record)
                Text("Insights").tag(SubjectDetailMode.insights)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, isWideLayout ? 34 : 22)
            .padding(.bottom, isWideLayout ? 18 : 12)
            .accessibilityIdentifier("subject.modePicker")

            if selectedMode == .record {
                recordView
            } else {
                AnalyticsView(embeddedSubjectID: currentSubject.id)
            }
        }
        .background(NesticTheme.paper)
        .navigationTitle(currentSubject.name)
        .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if store.canManageNest {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button("Delete \(currentSubject.name)", systemImage: "trash", role: .destructive) {
                                showDeleteSubject = true
                            }
                            .accessibilityIdentifier("subject.delete")
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .accessibilityLabel("Manage \(currentSubject.name)")
                        .disabled(deletingSubjectBusy)
                    }
                }
            }
            .sheet(isPresented: $showAdd) { AddTrackerSheet(subject: currentSubject) }
            .sheet(isPresented: $showAddMedication) { AddTrackerSheet(subject: currentSubject, initialGroupName: "Medication") }
            .sheet(isPresented: $showPhotoEditor) { SubjectPhotoEditor(subject: currentSubject) }
            .sheet(isPresented: $showRoutineEditor, onDismiss: { editingRoutine = nil }) {
                RoutineEditorSheet(subject: currentSubject, routine: editingRoutine)
            }
            .sheet(isPresented: $showProPaywall) { NesticProPaywall() }
            .sheet(item: $editingTracker) { tracker in AddTrackerSheet(subject: currentSubject, tracker: tracker) }
            .sheet(item: $selection) { LogEntrySheet(subject: $0.subject, tracker: $0.tracker, date: $0.date) }
            .sheet(item: $selectedEntry) { EntryDetailSheet(entry: $0) }
            .alert("Delete \(deletingTracker?.name ?? "this tracker")?", isPresented: Binding(get: { deletingTracker != nil }, set: { if !$0 { deletingTracker = nil } })) {
                Button("Delete tracker", role: .destructive) {
                    guard let tracker = deletingTracker else { return }
                    deletingTracker = nil
                    deletingTrackerBusy = true
                    Task {
                        defer { deletingTrackerBusy = false }
                        do { try await store.deleteTracker(tracker) }
                        catch { trackerError = error.localizedDescription }
                    }
                }
                Button("Cancel", role: .cancel) { deletingTracker = nil }
            } message: { Text("This also removes its history for \(currentSubject.name).") }
            .alert("Delete this update?", isPresented: Binding(get: { deletingEntry != nil }, set: { if !$0 { deletingEntry = nil } })) {
                Button("Delete update", role: .destructive) {
                    guard let entry = deletingEntry else { return }
                    deletingEntry = nil
                    deletingEntryBusy = true
                    Task {
                        defer { deletingEntryBusy = false }
                        do { try await store.deleteEntry(entry) }
                        catch { entryError = error.localizedDescription }
                    }
                }
                Button("Cancel", role: .cancel) { deletingEntry = nil }
            } message: { Text("Everyone in your nest will see this update removed from the shared history.") }
            .alert("Tracker change failed", isPresented: Binding(get: { trackerError != nil }, set: { if !$0 { trackerError = nil } })) {
                Button("OK") { trackerError = nil }
            } message: { Text(trackerError ?? "") }
            .alert("Update change failed", isPresented: Binding(get: { entryError != nil }, set: { if !$0 { entryError = nil } })) {
                Button("OK") { entryError = nil }
            } message: { Text(entryError ?? "") }
            .alert("Delete \(currentSubject.name)?", isPresented: $showDeleteSubject) {
                Button("Delete entity", role: .destructive) { deleteSubject() }
                Button("Cancel", role: .cancel) { showDeleteSubject = false }
            } message: {
                Text("This permanently removes \(currentSubject.name), its update history, routines, and scheduled reminders from this nest.")
            }
            .alert("Entity change failed", isPresented: Binding(get: { subjectError != nil }, set: { if !$0 { subjectError = nil } })) {
                Button("OK") { subjectError = nil }
            } message: { Text(subjectError ?? "") }
            .alert("Delete \(deletingRoutine?.name ?? "this routine")?", isPresented: Binding(get: { deletingRoutine != nil }, set: { if !$0 { deletingRoutine = nil } })) {
                Button("Delete routine", role: .destructive) {
                    guard let routine = deletingRoutine else { return }
                    deletingRoutine = nil
                    Task {
                        do { try await store.deleteRoutine(routine) }
                        catch { routineError = error.localizedDescription }
                    }
                }
                Button("Cancel", role: .cancel) { deletingRoutine = nil }
            } message: { Text("This removes the routine, but not the updates it has already logged.") }
            .alert("Routine change failed", isPresented: Binding(get: { routineError != nil }, set: { if !$0 { routineError = nil } })) {
                Button("OK") { routineError = nil }
            } message: { Text(routineError ?? "") }
    }

    private var openHealthEntries: [NestEntry] {
        healthEntries.filter { $0.resolvedAt == nil }
    }

    private var healthEntries: [NestEntry] {
        let healthTrackerIDs = Set(subjectTrackers.filter { $0.valueType == .health }.map(\.id))
        return store.entries(for: currentSubject).filter { healthTrackerIDs.contains($0.actionId) }
    }

}

private struct HealthReportEpisode: Identifiable {
    let entry: NestEntry
    let trackerName: String
    let durationHours: Double

    var id: UUID { entry.id }
    var label: String { trackerName + " · " + entry.occurredAt.formatted(.dateTime.month(.abbreviated).day()) }
}

private struct HealthReportTrackerHistory: Identifiable {
    let tracker: NestTracker
    let entries: [NestEntry]

    var id: UUID { tracker.id }
}

struct ReportsView: View {
    @EnvironmentObject private var store: NesticStore

    private var reportableSubjects: [NestSubject] { store.subjects }

    var body: some View {
        List {
            Section {
                Label("Reports", systemImage: "doc.text.magnifyingglass")
                    .font(.headline)
                Text("Choose a person, pet, or anything else in your nest. Select exactly the trackers you want, then share or export the resulting history.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section("Choose someone or something") {
                if reportableSubjects.isEmpty {
                    ContentUnavailableView("Nothing to report yet",
                                           systemImage: "doc.text.magnifyingglass",
                                           description: Text("Add someone or something to your nest, then choose the trackers you want to export."))
                } else {
                    ForEach(reportableSubjects) { subject in
                        NavigationLink {
                            HealthReportView(subject: subject)
                        } label: {
                            HStack(spacing: 12) {
                                SubjectAvatar(emoji: subject.emoji, photoData: subject.photoData, size: 42)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(subject.name).font(.body.weight(.semibold))
                                    Text(reportSummary(for: subject))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .accessibilityIdentifier("reports.subject.\(subject.id.uuidString)")
                    }
                }
            }
        }
        .navigationTitle("Reports")
        .accessibilityIdentifier("reports.root")
    }

    private func reportSummary(for subject: NestSubject) -> String {
        let trackerCount = store.trackers(for: subject).count
        let updateCount = store.entries(for: subject).count
        return "\(trackerCount) \(trackerCount == 1 ? "tracker" : "trackers") · \(updateCount) \(updateCount == 1 ? "update" : "updates")"
    }
}

struct HealthReportView: View {
    @EnvironmentObject private var store: NesticStore
    @Environment(\.dismiss) private var dismiss
    let subject: NestSubject
    @State private var showTrackerPicker = false
    @State private var selectedTrackerIDs: Set<UUID> = []

    private var episodes: [HealthReportEpisode] {
        let healthTrackers = store.trackers(for: subject).filter { $0.valueType == .health }
        let names = Dictionary(uniqueKeysWithValues: healthTrackers.map { ($0.id, $0.name) })
        return store.entries(for: subject)
            .filter { names[$0.actionId] != nil }
            .sorted { $0.occurredAt < $1.occurredAt }
            .map { entry in
                HealthReportEpisode(entry: entry, trackerName: names[entry.actionId] ?? "Health event",
                                    durationHours: max(0, (entry.resolvedAt ?? Date()).timeIntervalSince(entry.occurredAt) / 3600))
            }
    }

    private var openCount: Int { episodes.filter { $0.entry.resolvedAt == nil }.count }
    private var resolvedEpisodes: [HealthReportEpisode] { episodes.filter { $0.entry.resolvedAt != nil } }
    private var averageResolvedHours: Double {
        guard !resolvedEpisodes.isEmpty else { return 0 }
        return resolvedEpisodes.map(\.durationHours).reduce(0, +) / Double(resolvedEpisodes.count)
    }

    private var additionalTrackers: [NestTracker] {
        store.trackers(for: subject).filter { $0.valueType != .health }
    }

    private var selectedTrackers: [NestTracker] {
        additionalTrackers.filter { selectedTrackerIDs.contains($0.id) }
    }

    private var additionalTrackerHistories: [HealthReportTrackerHistory] {
        let grouped = Dictionary(grouping: store.entries(for: subject).reversed(), by: \.actionId)
        return selectedTrackers.map { HealthReportTrackerHistory(tracker: $0, entries: grouped[$0.id] ?? []) }
    }

    private var reportTitle: String { episodes.isEmpty ? "Report" : "Health report" }
    private var reportDescription: String {
        episodes.isEmpty
            ? "Choose trackers to build a shareable history for \(subject.name)."
            : "A shareable onset and resolution summary for \(subject.name), with any selected tracker history."
    }

    var body: some View {
        let episodes = self.episodes
        let resolvedEpisodes = episodes.filter { $0.entry.resolvedAt != nil }
        let openCount = episodes.count - resolvedEpisodes.count
        let averageResolvedHours = resolvedEpisodes.isEmpty ? 0 : resolvedEpisodes.reduce(0) { $0 + $1.durationHours } / Double(resolvedEpisodes.count)
        let selectedTrackers = self.selectedTrackers
        let additionalTrackerHistories = self.additionalTrackerHistories
        let entryCounts = store.entries(for: subject).reduce(into: [UUID: Int]()) { $0[$1.actionId, default: 0] += 1 }
        return ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(reportTitle).font(.system(.largeTitle, design: .rounded, weight: .bold))
                        Text(reportDescription)
                            .font(.subheadline).foregroundStyle(.secondary)
                        Text("Generated \(Date(), format: .dateTime.month(.abbreviated).day().year().hour().minute())")
                            .font(.caption).foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("Included trackers").font(.headline)
                            Spacer()
                            Button("Choose", systemImage: "slider.horizontal.3") {
                                showTrackerPicker = true
                            }
                            .font(.subheadline.weight(.semibold))
                        }
                        Text("Health episodes are included when present. Choose any other trackers to include in this report.")
                            .font(.subheadline).foregroundStyle(.secondary)
                        if selectedTrackers.isEmpty {
                            Label(episodes.isEmpty ? "Choose trackers to include" : "Health episodes only", systemImage: "cross.case")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(NesticTheme.forest)
                        } else {
                            ForEach(selectedTrackers) { tracker in
                                HStack(spacing: 8) {
                                    TrackerIconView(tracker: tracker, size: .subheadline)
                                        .foregroundStyle(trackerColor(tracker))
                                    Text(tracker.name)
                                        .font(.subheadline.weight(.medium))
                                    Spacer()
                                    Text("\(entryCounts[tracker.id] ?? 0) updates")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .nesticCard()

                    if !episodes.isEmpty {
                        HStack(spacing: 10) {
                            reportMetric(title: "Episodes", value: "\(episodes.count)", tint: NesticTheme.forest)
                            reportMetric(title: "Open", value: "\(openCount)", tint: .orange)
                            reportMetric(title: "Avg. resolved", value: resolvedEpisodes.isEmpty ? "—" : durationText(averageResolvedHours), tint: .blue)
                        }
                    }

                    if !episodes.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Episode duration").font(.headline)
                            Text("Open episodes run through the time this report was generated.")
                                .font(.caption).foregroundStyle(.secondary)
                            Chart(episodes) { episode in
                                BarMark(
                                    x: .value("Hours", max(0.25, episode.durationHours)),
                                    y: .value("Episode", episode.label)
                                )
                                .foregroundStyle(episode.entry.resolvedAt == nil ? Color.orange : NesticTheme.forest)
                            }
                            .chartXAxisLabel("Hours")
                            .frame(height: max(180, CGFloat(episodes.count) * 42))
                        }
                        .nesticCard()

                        VStack(alignment: .leading, spacing: 12) {
                            Text("Episode details").font(.headline)
                            ForEach(episodes) { episode in
                                healthReportRow(episode)
                                if episode.id != episodes.last?.id { Divider() }
                            }
                        }
                        .nesticCard()
                    } else if selectedTrackers.isEmpty {
                        EmptyNestView(symbol: "slider.horizontal.3", title: "Choose what to include", message: "Select one or more trackers above to build this report.")
                    }

                    if !selectedTrackers.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Additional tracker history").font(.headline)
                            ForEach(additionalTrackerHistories) { history in
                                additionalTrackerHistory(history)
                                if history.id != additionalTrackerHistories.last?.id { Divider() }
                            }
                        }
                        .nesticCard()
                    }

                    VStack(spacing: 10) {
                        ShareLink(item: reportText(),
                                  subject: Text("Report for \(subject.name)"),
                                  message: Text("Nestic tracking history for \(subject.name)")) {
                            Label("Share report", systemImage: "square.and.arrow.up")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(NesticTheme.forest)
                        .accessibilityIdentifier("reports.health.share")

                        if let url = reportURL() {
                            ShareLink(item: url) {
                                Label("Export report (CSV)", systemImage: "tablecells")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding()
                            }
                            .buttonStyle(.bordered)
                            .tint(NesticTheme.forest)
                            .accessibilityIdentifier("reports.health.csv")
                        }
                    }
                }
                .padding(22)
            }
            .background(NesticTheme.paper)
            .navigationTitle(reportTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .sheet(isPresented: $showTrackerPicker) {
                HealthReportTrackerPicker(trackers: additionalTrackers, selectedIDs: $selectedTrackerIDs)
            }
    }

    private func reportMetric(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value).font(.system(.title2, design: .rounded, weight: .bold)).foregroundStyle(tint)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .nesticCard()
    }

    private func healthReportRow(_ episode: HealthReportEpisode) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                Text(episode.trackerName).font(.subheadline.weight(.semibold))
                Spacer()
                Text(episode.entry.resolvedAt == nil ? "Open" : "Resolved")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(episode.entry.resolvedAt == nil ? .orange : NesticTheme.forest)
            }
            LabeledContent("Onset", value: episode.entry.occurredAt.formatted(date: .abbreviated, time: .shortened))
            if let resolvedAt = episode.entry.resolvedAt {
                LabeledContent("Resolution", value: resolvedAt.formatted(date: .abbreviated, time: .shortened))
            }
            LabeledContent("Duration", value: durationText(episode.durationHours))
            if let details = episode.entry.valueText, !details.isEmpty {
                Text(details).font(.subheadline).foregroundStyle(NesticTheme.ink)
            }
            if let note = episode.entry.note, !note.isEmpty {
                Text("Note: \(note)").font(.caption).foregroundStyle(.secondary)
            }
            if let resolutionNote = episode.entry.resolutionNote, !resolutionNote.isEmpty {
                Text("Resolution note: \(resolutionNote)").font(.caption).foregroundStyle(.secondary)
            }
            if episode.entry.photoURL != nil {
                NesticEntryPhotoView(entry: episode.entry, size: 92)
                Label("Onset photo", systemImage: "photo")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let updates = episode.entry.photoUpdates, !updates.isEmpty {
                Text("Health updates")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(updates.sorted { $0.capturedAt < $1.capturedAt }) { photo in
                            VStack(alignment: .leading, spacing: 4) {
                                if photo.photoURL.isEmpty {
                                    Image(systemName: "text.alignleft")
                                        .font(.title3)
                                        .foregroundStyle(NesticTheme.forest)
                                        .frame(width: 84, height: 84)
                                        .background(NesticTheme.lime.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                                } else {
                                    NesticHealthPhotoView(entry: episode.entry, photo: photo, size: 84)
                                }
                                if let note = photo.note, !note.isEmpty {
                                    Text(note)
                                        .font(.caption)
                                        .foregroundStyle(NesticTheme.ink)
                                        .lineLimit(3)
                                }
                                Text(photo.capturedAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    private func additionalTrackerHistory(_ history: HealthReportTrackerHistory) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TrackerIconView(tracker: history.tracker, size: .subheadline)
                    .foregroundStyle(trackerColor(history.tracker))
                Text(history.tracker.name)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(history.entries.count) updates")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if history.entries.isEmpty {
                Text("No updates recorded for this tracker.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(history.entries) { entry in
                    HStack(alignment: .top, spacing: 10) {
                        Text(entry.occurredAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 116, alignment: .leading)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(entry.displayValue(unit: history.tracker.unit, trackerName: history.tracker.name))
                                .font(.subheadline.weight(.medium))
                            if let note = entry.note, !note.isEmpty {
                                Text(note)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    private func durationText(_ hours: Double) -> String {
        if hours < 1 { return "< 1 hour" }
        if hours < 48 { return "\(hours.formatted(.number.precision(.fractionLength(0...1)))) hr" }
        return "\((hours / 24).formatted(.number.precision(.fractionLength(0...1)))) days"
    }

    private func reportText() -> String {
        var lines = [
            "Nestic report — \(subject.name)",
            "User-recorded tracking history, not a diagnosis or treatment recommendation.",
            "Generated: \(Date().formatted(date: .long, time: .shortened))",
            "Episodes: \(episodes.count)",
            "Open episodes: \(openCount)",
            "Average resolved duration: \(resolvedEpisodes.isEmpty ? "—" : durationText(averageResolvedHours))",
            ""
        ]

        if episodes.isEmpty {
            lines.append("No health events recorded.")
        } else {
            lines.append("EPISODES")
            for episode in episodes {
                let entry = episode.entry
                lines.append("\(episode.trackerName) — \(entry.resolvedAt == nil ? "Open" : "Resolved")")
                lines.append("Onset: \(entry.occurredAt.formatted(date: .abbreviated, time: .shortened))")
                if let resolvedAt = entry.resolvedAt {
                    lines.append("Resolution: \(resolvedAt.formatted(date: .abbreviated, time: .shortened))")
                }
                lines.append("Duration: \(durationText(episode.durationHours))")
                if let details = entry.valueText, !details.isEmpty { lines.append("Details: \(details)") }
                if let note = entry.note, !note.isEmpty { lines.append("Note: \(note)") }
                if let resolutionNote = entry.resolutionNote, !resolutionNote.isEmpty {
                    lines.append("Resolution note: \(resolutionNote)")
                }
                if entry.photoURL != nil { lines.append("Onset photo: attached") }
                if let updates = entry.photoUpdates, !updates.isEmpty {
                    lines.append("Updates:")
                    for update in updates.sorted(by: { $0.capturedAt < $1.capturedAt }) {
                        let kind = update.photoURL.isEmpty ? "Note" : "Photo"
                        let note = update.note.flatMap { $0.isEmpty ? nil : ": \($0)" } ?? ""
                        lines.append("- \(kind), \(update.capturedAt.formatted(date: .abbreviated, time: .shortened))\(note)")
                    }
                }
                lines.append("")
            }
        }
        if !additionalTrackerHistories.isEmpty {
            lines.append("ADDITIONAL TRACKER HISTORY")
            for history in additionalTrackerHistories {
                lines.append(history.tracker.name)
                if history.entries.isEmpty {
                    lines.append("No updates recorded.")
                } else {
                    for entry in history.entries {
                        var line = "- \(entry.occurredAt.formatted(date: .abbreviated, time: .shortened)): \(entry.displayValue(unit: history.tracker.unit, trackerName: history.tracker.name))"
                        if let note = entry.note, !note.isEmpty { line += " — \(note)" }
                        lines.append(line)
                    }
                }
                lines.append("")
            }
        }
        return lines.joined(separator: "\n")
    }

    private func reportURL() -> URL? {
        let safeName = subject.name.replacingOccurrences(of: "[^A-Za-z0-9]+", with: "-", options: .regularExpression)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Nestic-\(safeName)-health-report.csv")
        let formatter = ISO8601DateFormatter()
        var rows = ["subject,tracker,status,onset,resolution,duration_hours,details,note,resolution_note,onset_photo_attached,health_update_count,health_update_details"]
        rows += episodes.map { episode in
            let entry = episode.entry
            let updateDetails = (entry.photoUpdates ?? []).map { update in
                let kind = update.photoURL.isEmpty ? "note" : "photo"
                let note = update.note ?? ""
                return "\(formatter.string(from: update.capturedAt)) [\(kind)] \(note)"
            }.joined(separator: " | ")
            return [subject.name, episode.trackerName, entry.resolvedAt == nil ? "open" : "resolved",
                    formatter.string(from: entry.occurredAt), entry.resolvedAt.map { formatter.string(from: $0) } ?? "",
                    episode.durationHours.formatted(.number.precision(.fractionLength(0...2))), entry.valueText ?? "",
                    entry.note ?? "", entry.resolutionNote ?? "", entry.photoURL == nil ? "no" : "yes",
                    String(entry.photoUpdates?.count ?? 0), updateDetails]
                .map(csvField)
                .joined(separator: ",")
        }
        for history in additionalTrackerHistories {
            for entry in history.entries {
                rows.append([
                    subject.name,
                    history.tracker.name,
                    "recorded",
                    formatter.string(from: entry.occurredAt),
                    "",
                    "",
                    entry.displayValue(unit: history.tracker.unit, trackerName: history.tracker.name),
                    entry.note ?? "",
                    "",
                    entry.photoURL == nil ? "no" : "yes",
                    String(entry.photoUpdates?.count ?? 0),
                    ""
                ].map(csvField).joined(separator: ","))
            }
        }
        do {
            try rows.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    private func csvField(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}

private struct HealthReportTrackerPicker: View {
    @Environment(\.dismiss) private var dismiss
    let trackers: [NestTracker]
    @Binding var selectedIDs: Set<UUID>

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Health episodes are included when present. Select any other trackers you want to add to the report.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Section("Trackers to include") {
                    if trackers.isEmpty {
                        Text("No trackers are available for this item.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(trackers) { tracker in
                            Button {
                                if selectedIDs.contains(tracker.id) {
                                    selectedIDs.remove(tracker.id)
                                } else {
                                    selectedIDs.insert(tracker.id)
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    TrackerIconView(tracker: tracker, size: .body)
                                        .foregroundStyle(trackerColor(tracker))
                                    Text(tracker.name)
                                    Spacer()
                                    Image(systemName: selectedIDs.contains(tracker.id) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(selectedIDs.contains(tracker.id) ? NesticTheme.forest : .secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("Report trackers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct AddTrackerSheet: View {
    @EnvironmentObject private var store: NesticStore
    @Environment(\.dismiss) private var dismiss
    let subject: NestSubject
    let editingTracker: NestTracker?
    let initialGroupName: String?
    @State private var name = ""
    @State private var valueType: NestValueType = .none
    @State private var unit = ""
    @State private var symbol = "checkmark.circle.fill"
    @State private var color = TrackerColorCatalog.defaultColor(for: "", valueType: .none)
    @State private var groupName = ""
    @State private var isPrivate = false
    @State private var selectedMembers: Set<UUID> = []
    @State private var busy = false
    @State private var error: String?
    init(subject: NestSubject, tracker: NestTracker? = nil, initialGroupName: String? = nil) {
        self.subject = subject
        self.editingTracker = tracker
        self.initialGroupName = initialGroupName
        _name = State(initialValue: tracker?.name ?? "")
        _valueType = State(initialValue: tracker?.valueType ?? .none)
        _unit = State(initialValue: tracker?.unit ?? "")
        _symbol = State(initialValue: tracker.map(trackerIconValue) ?? TrackerIconCatalog.defaultSymbol(for: "", valueType: .none))
        _color = State(initialValue: tracker.map(trackerColorValue) ?? TrackerColorCatalog.defaultColor(for: "", valueType: .none))
        _selectedMembers = State(initialValue: Set(tracker?.allowedMemberIDs ?? []))
        _groupName = State(initialValue: tracker?.groupName ?? initialGroupName ?? "")
    }
    var body: some View {
        NavigationStack {
            Form {
                Section(content: {
                    if editingTracker == nil {
                        Toggle("Restricted tracker", isOn: $isPrivate).disabled(!store.canManageNest)
                        Text("Choose who can see and log this tracker. Select nobody to keep it Only me. Only you can change sharing. Everyone access is fixed when created.").font(.caption).foregroundStyle(.secondary)
                    } else if editingTracker?.isPrivate == true { Label(editingTracker?.privacyLabel ?? "Restricted tracker", systemImage: "lock.fill") }
                    if isPrivate || editingTracker?.isPrivate == true {
                        ForEach(store.members.filter { $0.id != store.currentUser?.id && $0.role != "viewer" }) { member in
                            Toggle(member.displayName, isOn: Binding(get: { selectedMembers.contains(member.id) }, set: { value in if value { selectedMembers.insert(member.id) } else { selectedMembers.remove(member.id) } }))
                        }
                        Text("Selected members can view history and log updates. Removing access also hides this tracker's history, photos, reminders and forecasts after their next sync.").font(.caption).foregroundStyle(.secondary)
                    }
                    TextField(groupName == "Medication" ? "Medicine name, e.g. Breakfast pill" : "Tracker name, e.g. Outdoor time", text: $name).accessibilityIdentifier("tracker.name")
                    Picker("What to record", selection: $valueType) {
                        ForEach(NestValueType.allCases.filter { editingTracker != nil || $0 != .json }, id: \.self) { Text($0.title).tag($0) }
                    }.accessibilityIdentifier("tracker.type")
                    if valueType == .number {
                        VStack(alignment: .leading, spacing: 9) {
                            TextField("Unit (optional)", text: $unit)
                                .accessibilityIdentifier("tracker.unit")
                            Text("Common choices")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(TrackerUnitCatalog.suggestions(for: name), id: \.self) { suggestion in
                                        Button(suggestion) { unit = suggestion }
                                            .font(.caption.weight(.semibold))
                                            .buttonStyle(.bordered)
                                            .tint(unit.caseInsensitiveCompare(suggestion) == .orderedSame ? NesticTheme.forest : .secondary)
                                    }
                                }
                            }
                        }
                    }
                }, header: {
                    Text(editingTracker == nil ? "Tracking for \(subject.name)" : "Edit tracker for \(subject.name)")
                }, footer: {
                    Text(valueType == .photo
                         ? "Photos are stored securely with this tracker and follow its visibility."
                         : valueType == .health
                         ? "Health events record onset, details, optional photos, and resolution. Photos and history follow this tracker’s visibility."
                         : groupName == "Medication"
                         ? "Each medicine stays independent so it can have its own history, forecast, and reminder."
                         : "A simple check-in records that something happened. Choose a number, text, or yes/no when you want more detail.")
                })
                Section {
                    Picker("Group", selection: $groupName) {
                        Text("No group").tag("")
                        Text("Medication").tag("Medication")
                    }
                } header: {
                    Text("Organize")
                } footer: {
                    Text("Group related trackers together. Medication trackers can still be logged separately.")
                }
                Section {
                    TrackerIconPicker(selection: $symbol)
                } header: {
                    Text("Icon")
                } footer: {
                    Text("Choose a symbol or emoji that makes this tracker easy to recognize.")
                }
                Section {
                    TrackerColorPicker(selection: $color)
                } header: {
                    Text("Color")
                } footer: {
                    Text("This color appears beside the tracker and in your widgets.")
                }
                if let error { Text(error).foregroundStyle(.red) }
            }.formStyle().onAppear { if !store.canManageNest && editingTracker == nil { isPrivate = true } }
            .navigationTitle(editingTracker == nil ? "New tracker" : "Edit tracker").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(busy) }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(busy ? "Saving…" : (editingTracker == nil ? "Add" : "Save")) {
                            busy = true
                            Task {
                                defer { busy = false }
                                do {
                                    if let editingTracker {
                                        try await store.updateTracker(editingTracker, name: name, valueType: valueType, unit: unit, symbol: symbol, color: color, groupName: groupName)
                                        if editingTracker.isPrivate { try await store.setTrackerSharing(editingTracker, members: Array(selectedMembers)) }
                                    } else {
                                        try await store.createTracker(subjectID: subject.id, name: name, valueType: valueType, unit: unit, symbol: symbol, color: color, groupName: groupName, isPrivate: isPrivate)
                                        if isPrivate, !selectedMembers.isEmpty, let created = store.trackers.first(where: { $0.name == name.trimmingCharacters(in: .whitespacesAndNewlines) && $0.privateOwnerId == store.currentUser?.id }) {
                                            try await store.setTrackerSharing(created, members: Array(selectedMembers))
                                        }
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
    let editingEntry: NestEntry?
    @State private var occurredAt: Date
    @State private var number = ""
    @State private var text = ""
    @State private var yes = true
    @State private var note = ""
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var photoBusy = false
    @State private var wasAccident = false
    @State private var includeInPredictions = true
    @State private var busy = false
    @State private var error: String?
    init(subject: NestSubject, tracker: NestTracker, date: Date = Date(), editingEntry: NestEntry? = nil) {
        self.subject = subject
        self.tracker = tracker
        self.editingEntry = editingEntry
        let initialDate = editingEntry?.occurredAt ?? date
        self.initialDate = initialDate
        _occurredAt = State(initialValue: initialDate)
        _number = State(initialValue: editingEntry.flatMap { entry in
            entry.valueNumber.map { String($0) }
        } ?? "")
        _text = State(initialValue: editingEntry?.valueText ?? "")
        _yes = State(initialValue: editingEntry?.valueBool ?? true)
        if let valueJSON = editingEntry?.valueJSON,
           let data = try? JSONEncoder().encode(valueJSON),
           let value = String(data: data, encoding: .utf8) {
            _text = State(initialValue: value)
        }
        _photoData = State(initialValue: editingEntry.flatMap { NesticEntryPhotoStore.data(for: $0.id) })
        _note = State(initialValue: editingEntry?.note ?? "")
        _wasAccident = State(initialValue: editingEntry?.isAccident ?? false)
        _includeInPredictions = State(initialValue: editingEntry?.shouldIncludeInPredictions ?? true)
    }
    private var canLog: Bool {
        store.canLog
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 15) {
                        SubjectAvatar(emoji: subject.emoji, photoData: subject.photoData, size: 62)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(tracker.name).font(.system(.title2, design: .rounded, weight: .bold))
                            Text(editingEntry == nil ? "An update for \(subject.name)" : "Edit an update for \(subject.name)")
                                .font(.subheadline).foregroundStyle(.secondary)
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
                    case .health:
                        TextField("What happened or what are you seeing?", text: $text, axis: .vertical)
                            .lineLimit(3...7)
                            .accessibilityIdentifier("log.healthDetails")
                        photoPickerSection(required: false)
                    case .photo:
                        photoPickerSection(required: true)
                    }
                    DatePicker(tracker.valueType == .health ? "Onset" : "When", selection: $occurredAt, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                }, header: {
                    Text("The little details")
                })
                Section(content: {
                    TextField("Anything your nest should know?", text: $note, axis: .vertical).lineLimit(3...6).accessibilityIdentifier("log.note")
                }, header: {
                    Text("Note · optional")
                })
                Section {
                    Toggle("Was this an accident?", isOn: $wasAccident)
                    Toggle("Include in predictive models", isOn: $includeInPredictions)
                } header: {
                    Text("Event context")
                } footer: {
                    Text("Accident events can be kept out of forecasts without removing them from your shared history.")
                }
                if let error { Text(error).foregroundStyle(.red) }
                if !canLog { Text("You have view-only access to this nest. Ask an owner or admin if you need to log updates.").foregroundStyle(.secondary) }
                Section {
                    PrimaryButton(title: editingEntry == nil ? (store.isDemo ? "Save update" : "Share update") : "Save changes", symbol: "checkmark", busy: busy) { save() }
                        .disabled(!canLog || photoBusy).accessibilityIdentifier("log.save")
                } footer: {
                    Text(editingEntry == nil
                         ? (store.isDemo ? "This sample update stays on this device." : "Everyone in \(store.selectedNest?.name ?? "your nest") will see this update.")
                         : "Everyone in \(store.selectedNest?.name ?? "your nest") will see these changes.")
                }.listRowBackground(Color.clear).listRowInsets(EdgeInsets())
            }.formStyle().navigationTitle("A little update").navigationBarTitleDisplayMode(.inline)
                .scrollDismissesKeyboard(.interactively)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(busy || photoBusy) }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(busy ? "Saving…" : (editingEntry == nil ? "Save" : "Save changes")) { save() }
                            .fontWeight(.semibold).disabled(busy || !canLog)
                            .accessibilityIdentifier("log.saveToolbar")
                    }
                }
                .interactiveDismissDisabled(busy || photoBusy)
                .onChange(of: selectedPhotoItem) { _, item in
                    guard let item else { return }
                    photoBusy = true
                    Task { @MainActor in
                        do {
                            let loadedData = try await item.loadTransferable(type: Data.self)
                            if let loadedData {
                                photoData = try NesticEntryPhotoStore.jpegData(from: loadedData)
                            } else {
                                error = "That photo could not be loaded. Please choose another one."
                            }
                        } catch {
                            let nsError = error as NSError
                            self.error = nsError.domain == "NesticEntryPhotoStore"
                                ? nsError.localizedDescription
                                : "That photo could not be loaded. Please choose another one."
                        }
                        photoBusy = false
                    }
                }
                .task(id: editingEntry?.photoURL) {
                    guard (tracker.valueType == .photo || tracker.valueType == .health), photoData == nil,
                          let editingEntry, editingEntry.photoURL != nil else { return }
                    if let data = try? await store.entryPhotoData(for: editingEntry) {
                        photoData = data
                    }
                }
        }
    }

    @ViewBuilder
    private func photoPickerSection(required: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let selectedPhotoData = photoData, let image = UIImage(data: selectedPhotoData) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                HStack {
                    PhotosPicker(selection: $selectedPhotoItem, matching: .images, photoLibrary: .shared()) {
                        Label("Replace photo", systemImage: "arrow.triangle.2.circlepath.camera")
                    }
                    .buttonStyle(.bordered)
                    Button("Remove", role: .destructive) {
                        photoData = nil
                        selectedPhotoItem = nil
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                PhotosPicker(selection: $selectedPhotoItem, matching: .images, photoLibrary: .shared()) {
                    Label(required ? "Choose a photo" : "Add a photo · optional", systemImage: "photo.badge.plus")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
            }
            if photoBusy {
                ProgressView("Loading photo…")
            }
            Text(required
                 ? "This photo is shared with your nest and stored in its private photo storage."
                 : "Optional photos are shared with your nest and stored in its private photo storage.")
                .font(.caption)
                .foregroundStyle(.secondary)
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
        if tracker.valueType == .health && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            error = "Describe the health event before saving."; return
        }
        if tracker.valueType == .json {
            guard let data = text.data(using: .utf8), let object = try? JSONDecoder().decode([String: String].self, from: data), !object.isEmpty else {
                error = "Enter a valid JSON object with text keys and values."; return
            }
            parsedJSON = object
        }
        if tracker.valueType == .photo && photoData == nil && editingEntry == nil {
            error = "Choose a photo before saving."
            return
        }
        busy = true
        Task {
            defer { busy = false }
            do {
                var savedEntry: NestEntry
                if let editingEntry {
                    savedEntry = try await store.updateEntry(editingEntry, date: occurredAt, number: parsedNumber,
                                                             text: (tracker.valueType == .text || tracker.valueType == .health) ? text : nil,
                                                             bool: tracker.valueType == .boolean ? yes : nil,
                                                             json: parsedJSON, note: note,
                                                             wasAccident: wasAccident,
                                                             includeInPredictions: includeInPredictions)
                } else {
                    savedEntry = try await store.log(subjectID: subject.id, trackerID: tracker.id, date: occurredAt, number: parsedNumber,
                                                     text: (tracker.valueType == .text || tracker.valueType == .health) ? text : nil,
                                                     bool: tracker.valueType == .boolean ? yes : nil,
                                                     json: parsedJSON, note: note,
                                                     wasAccident: wasAccident,
                                                     includeInPredictions: includeInPredictions)
                }
                if tracker.valueType == .photo || tracker.valueType == .health {
                    if let photoData {
                        savedEntry = try await store.uploadEntryPhoto(photoData, for: savedEntry)
                    } else if savedEntry.photoURL != nil {
                        savedEntry = try await store.removeEntryPhoto(savedEntry)
                    }
                }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                dismiss()
            } catch { self.error = error.localizedDescription }
        }
    }
}

private struct RoutineValueKey: Hashable {
    let entityID: UUID
    let trackerID: UUID
}

struct RoutineEditorSheet: View {
    @EnvironmentObject private var store: NesticStore
    @Environment(\.dismiss) private var dismiss
    let routine: NestRoutine?
    @State private var name: String
    @State private var selectedEntityIDs: Set<UUID>
    @State private var selectedTrackerIDs: [UUID: Set<UUID>]
    @State private var numberValues: [RoutineValueKey: String]
    @State private var textValues: [RoutineValueKey: String]
    @State private var boolValues: [RoutineValueKey: Bool]
    @State private var jsonValues: [RoutineValueKey: String]
    @State private var busy = false
    @State private var error: String?

    init(subject: NestSubject? = nil, routine: NestRoutine? = nil) {
        self.routine = routine
        let targets = routine?.targets ?? subject.map { [NestRoutineTarget(entityID: $0.id, items: [])] } ?? []
        _name = State(initialValue: routine?.name ?? "")
        _selectedEntityIDs = State(initialValue: Set(targets.map(\.entityID)))
        _selectedTrackerIDs = State(initialValue: Dictionary(uniqueKeysWithValues: targets.map { ($0.entityID, Set($0.items.map(\.trackerID))) }))
        _numberValues = State(initialValue: Dictionary(uniqueKeysWithValues: targets.flatMap { target in
            target.items.compactMap { item in item.valueNumber.map { (RoutineValueKey(entityID: target.entityID, trackerID: item.trackerID), String($0)) } }
        }))
        _textValues = State(initialValue: Dictionary(uniqueKeysWithValues: targets.flatMap { target in
            target.items.compactMap { item in item.valueText.map { (RoutineValueKey(entityID: target.entityID, trackerID: item.trackerID), $0) } }
        }))
        _boolValues = State(initialValue: Dictionary(uniqueKeysWithValues: targets.flatMap { target in
            target.items.compactMap { item in item.valueBool.map { (RoutineValueKey(entityID: target.entityID, trackerID: item.trackerID), $0) } }
        }))
        _jsonValues = State(initialValue: Dictionary(uniqueKeysWithValues: targets.flatMap { target in
            target.items.compactMap { item in
                guard let valueJSON = item.valueJSON,
                      let data = try? JSONEncoder().encode(valueJSON),
                      let value = String(data: data, encoding: .utf8) else { return nil }
                return (RoutineValueKey(entityID: target.entityID, trackerID: item.trackerID), value)
            }
        }))
    }

    private var availableSubjects: [NestSubject] { store.subjects }

    var body: some View {
        NavigationStack {
            Form {
                Text("Including a private tracker makes this routine Only me. Updates for shared trackers remain shared.").font(.caption).foregroundStyle(.secondary)
                Section {
                    TextField("Routine name", text: $name)
                        .accessibilityIdentifier("routine.name")
                    Text("Save the values you use together, then log every selected tracker with one tap.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Name your routine")
                }

                Section {
                    ForEach(availableSubjects) { subject in
                        VStack(alignment: .leading, spacing: 10) {
                            Toggle(isOn: selectedEntityBinding(for: subject)) {
                                HStack(spacing: 10) {
                                    SubjectAvatar(emoji: subject.emoji, photoData: subject.photoData, size: 30)
                                    Text(subject.name).font(.body.weight(.semibold))
                                }
                            }
                            if selectedEntityIDs.contains(subject.id) {
                                trackerSection(for: subject)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    if availableSubjects.isEmpty {
                        Text("Add an entity before creating a routine.").foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Who should one tap update?")
                } footer: {
                    Text("Select one or more entities, then choose the trackers and saved values for each one.")
                }

                if let error { Text(error).foregroundStyle(.red) }

                Section {
                    PrimaryButton(title: busy ? "Saving…" : (routine == nil ? "Create routine" : "Save routine"),
                                  symbol: "checkmark", busy: busy) { save() }
                        .disabled(busy)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            .formStyle()
            .navigationTitle(routine == nil ? "New routine" : "Edit routine")
            .navigationBarTitleDisplayMode(.inline)
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(busy)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(busy ? "Saving…" : "Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(busy)
                        .accessibilityIdentifier("routine.saveToolbar")
                }
            }
            .interactiveDismissDisabled(busy)
        }
    }

    @ViewBuilder
    private func trackerSection(for subject: NestSubject) -> some View {
        let trackers = store.trackers(for: subject).filter { $0.valueType != .photo && $0.valueType != .health }
        ForEach(trackers) { tracker in
            VStack(alignment: .leading, spacing: 10) {
                Toggle(isOn: selectedTrackerBinding(for: subject, tracker: tracker)) {
                    HStack(spacing: 10) {
                        TrackerIconView(tracker: tracker, size: .body)
                            .frame(width: 22)
                            .foregroundStyle(trackerColor(tracker))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tracker.name).font(.body.weight(.semibold))
                            if let unit = tracker.unit, tracker.valueType == .number {
                                Text(unit).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                if selectedTrackerIDs[subject.id, default: []].contains(tracker.id) {
                    routineValueEditor(for: tracker, subjectID: subject.id)
                        .padding(.leading, 32)
                }
            }
            .padding(.leading, 34)
            .padding(.vertical, 3)
        }
        if trackers.isEmpty {
            Text("Add a tracker for \(subject.name) before including this entity.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 34)
        }
    }

    @ViewBuilder
    private func routineValueEditor(for tracker: NestTracker, subjectID: UUID) -> some View {
        let key = RoutineValueKey(entityID: subjectID, trackerID: tracker.id)
        switch tracker.valueType {
        case .none:
            Label("Marks \(tracker.name) as done", systemImage: "checkmark.circle")
                .font(.caption)
                .foregroundStyle(NesticTheme.forest)
        case .number:
            HStack {
                TextField("Amount", text: valueBinding(for: key, in: $numberValues))
                    .keyboardType(.decimalPad)
                    .accessibilityIdentifier("routine.amount.\(tracker.name)")
                if let unit = tracker.unit { Text(unit).foregroundStyle(.secondary) }
            }
        case .text:
            TextField("Value", text: valueBinding(for: key, in: $textValues), axis: .vertical)
                .lineLimit(2...4)
        case .boolean:
            Toggle("Yes", isOn: boolBinding(for: key))
        case .json:
            TextField("{\"detail\": \"value\"}", text: valueBinding(for: key, in: $jsonValues), axis: .vertical)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.system(.body, design: .monospaced))
        case .photo:
            Label("Photo trackers are logged individually on iPhone", systemImage: "photo")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .health:
            Label("Health events are logged individually on iPhone", systemImage: "cross.case")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func selectedEntityBinding(for subject: NestSubject) -> Binding<Bool> {
        Binding(
            get: { selectedEntityIDs.contains(subject.id) },
            set: { selected in
                if selected { selectedEntityIDs.insert(subject.id) }
                else { selectedEntityIDs.remove(subject.id) }
            }
        )
    }

    private func selectedTrackerBinding(for subject: NestSubject, tracker: NestTracker) -> Binding<Bool> {
        Binding(
            get: { selectedTrackerIDs[subject.id, default: []].contains(tracker.id) },
            set: { selected in
                var ids = selectedTrackerIDs[subject.id, default: []]
                if selected { ids.insert(tracker.id) } else { ids.remove(tracker.id) }
                selectedTrackerIDs[subject.id] = ids
            }
        )
    }

    private func valueBinding(for key: RoutineValueKey, in values: Binding<[RoutineValueKey: String]>) -> Binding<String> {
        Binding(
            get: { values.wrappedValue[key] ?? "" },
            set: { values.wrappedValue[key] = $0 }
        )
    }

    private func boolBinding(for key: RoutineValueKey) -> Binding<Bool> {
        Binding(
            get: { boolValues[key] ?? true },
            set: { boolValues[key] = $0 }
        )
    }

    private func save() {
        error = nil
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { error = "Give your routine a name."; return }

        var targets: [NestRoutineTarget] = []
        for subject in availableSubjects where selectedEntityIDs.contains(subject.id) {
            let selectedIDs = selectedTrackerIDs[subject.id, default: []]
            guard !selectedIDs.isEmpty else {
                error = "Choose at least one tracker for \(subject.name)."
                return
            }
            var items: [NestRoutineItem] = []
            for tracker in store.trackers(for: subject) where selectedIDs.contains(tracker.id) {
                let key = RoutineValueKey(entityID: subject.id, trackerID: tracker.id)
                switch tracker.valueType {
                case .none:
                    items.append(.init(trackerID: tracker.id))
                case .number:
                    guard let value = NestCoding.parseAmount(numberValues[key] ?? "") else {
                        error = "Enter a valid amount for \(tracker.name)."
                        return
                    }
                    items.append(.init(trackerID: tracker.id, valueNumber: value))
                case .text:
                    let value = textValues[key, default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !value.isEmpty else { error = "Add a value for \(tracker.name)."; return }
                    items.append(.init(trackerID: tracker.id, valueText: value))
                case .boolean:
                    items.append(.init(trackerID: tracker.id, valueBool: boolValues[key] ?? true))
                case .json:
                    let raw = jsonValues[key, default: ""]
                    guard let data = raw.data(using: .utf8),
                          let value = try? JSONDecoder().decode([String: String].self, from: data),
                          !value.isEmpty else {
                        error = "Enter a valid JSON object for \(tracker.name)."
                        return
                    }
                    items.append(.init(trackerID: tracker.id, valueJSON: value))
                case .photo:
                    error = "Photo trackers cannot be included in a routine."
                    return
                case .health:
                    error = "Health-event trackers cannot be included in a routine."
                    return
                }
            }
            targets.append(NestRoutineTarget(entityID: subject.id, items: items))
        }
        guard !targets.isEmpty else { error = "Select at least one entity."; return }

        busy = true
        Task {
            defer { busy = false }
            do {
                if let routine {
                    try await store.updateRoutine(routine, name: cleanName, targets: targets)
                } else {
                    try await store.createRoutine(name: cleanName, targets: targets)
                }
                dismiss()
            } catch { self.error = error.localizedDescription }
        }
    }
}
