import SwiftUI

struct ActivityView: View {
    @EnvironmentObject private var store: NesticStore
    @State private var search = ""
    @State private var subjectFilter: UUID?
    @State private var selectedEntry: NestEntry?
    @State private var error: String?
    private var filtered: [NestEntry] {
        store.entries.filter { entry in
            let subject = store.subjects.first { $0.id == entry.entityId }
            let tracker = store.trackers.first { $0.id == entry.actionId }
            let matchesSearch = search.isEmpty || [subject?.name, tracker?.name, entry.note, entry.valueText].compactMap { $0 }.joined(separator: " ").localizedCaseInsensitiveContains(search)
            return (subjectFilter == nil || entry.entityId == subjectFilter) && matchesSearch
        }
    }
    private var days: [Date] {
        Array(Set(filtered.map { Calendar.current.startOfDay(for: $0.occurredAt) })).sorted(by: >)
    }
    var body: some View {
        List {
            Section {
                HStack(spacing: 9) {
                    Circle().fill(store.isDemo ? Color.orange : NesticTheme.forest).frame(width: 7, height: 7)
                    Text(store.isDemo ? "Sample activity · this device only" : store.connectionStatus).font(.caption)
                    Spacer()
                    Text("\(filtered.count) updates").font(.caption).foregroundStyle(.secondary)
                }.listRowBackground(Color.clear).listRowInsets(EdgeInsets(top: 10, leading: 0, bottom: 10, trailing: 0))
            }
            if filtered.isEmpty {
                EmptyNestView(symbol: search.isEmpty ? "clock.arrow.circlepath" : "magnifyingglass", title: search.isEmpty ? "Your shared story starts here" : "No matching updates", message: search.isEmpty ? "Log something from Home and it will appear in your nest’s activity." : "Try another search or change the filter.")
                    .listRowBackground(Color.clear)
            }
            ForEach(days, id: \.self) { day in
                Section(dayLabel(day)) {
                    ForEach(filtered.filter { Calendar.current.isDate($0.occurredAt, inSameDayAs: day) }) { entry in
                        Button { selectedEntry = entry } label: { EntryRow(entry: entry).padding(.vertical, 6) }
                            .buttonStyle(.plain)
                    }
                }
            }
            if store.entries.count >= 200 {
                Text("Showing the most recent 200 updates.").font(.caption).foregroundStyle(.secondary).listRowBackground(Color.clear)
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
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Section { EntryRow(entry: entry).padding(.vertical, 12) }
                Section("Recorded for") {
                    LabeledContent("Date", value: entry.occurredAt.formatted(date: .abbreviated, time: .shortened))
                    LabeledContent("Nest", value: store.selectedNest?.name ?? "Your nest")
                }
                if entry.actorUserId == store.currentUser?.id || store.canManageNest {
                    Section {
                        Button("Delete update", role: .destructive) { confirmDelete = true }.disabled(busy)
                            .accessibilityIdentifier("entry.delete")
                    } footer: { Text("Remove an update logged by mistake. This also removes it from your nest’s shared history.") }
                }
                if let error { Text(error).foregroundStyle(.red) }
            }.formStyle().navigationTitle("Update details").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.disabled(busy) } }
                .confirmationDialog("Delete this update?", isPresented: $confirmDelete, titleVisibility: .visible) {
                    Button("Delete update", role: .destructive) {
                        busy = true
                        Task {
                            defer { busy = false }
                            do { try await store.deleteEntry(entry); dismiss() }
                            catch { self.error = error.localizedDescription }
                        }
                    }
                } message: { Text("Everyone in your nest will see the updated history.") }
                .interactiveDismissDisabled(busy)
        }
    }
}
