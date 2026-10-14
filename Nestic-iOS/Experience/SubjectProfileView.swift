import SwiftUI

struct SubjectProfileFields: View {
    @Binding var draft: NesticSubjectProfileDraft
    var body: some View {
        Section("Optional details") {
            Toggle("Add birthday", isOn: $draft.hasBirthday)
            if draft.hasBirthday { DatePicker("Birthday", selection: $draft.birthday, in: ...Date(), displayedComponents: .date) }
            HStack {
                TextField("Weight · optional", text: $draft.weight).keyboardType(.decimalPad)
                Picker("Weight unit", selection: $draft.unit) { Text("kg").tag("kg"); Text("lb").tag("lb") }
                    .labelsHidden().pickerStyle(.menu)
                    .onChange(of: draft.unit) { old, _ in draft.changeUnit(from: old) }
            }
            Text("Leave either field blank. These details are shared with your nest. Turn off birthday or clear weight to remove them.")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }
}

struct SubjectProfileSheet: View {
    @EnvironmentObject private var store: NesticStore
    @Environment(\.dismiss) private var dismiss
    let subject: NestSubject
    @State private var draft: NesticSubjectProfileDraft
    @State private var busy = false
    @State private var error: String?
    init(subject: NestSubject) { self.subject = subject; _draft = State(initialValue: NesticSubjectProfileDraft(subject)) }
    var body: some View {
        NavigationStack {
            Form {
                SubjectProfileFields(draft: $draft)
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("Details for \(subject.name)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(busy) }
                ToolbarItem(placement: .confirmationAction) {
                    Button(busy ? "Saving…" : "Save") {
                        busy = true
                        Task {
                            defer { busy = false }
                            do { try await store.updateSubjectProfile(subject, profile: draft); dismiss() }
                            catch { self.error = error.localizedDescription }
                        }
                    }.disabled(busy)
                }
            }
        }
    }
}

struct SubjectProfileSummary: View {
    let subject: NestSubject
    private var draft: NesticSubjectProfileDraft { NesticSubjectProfileDraft(subject) }
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if draft.hasBirthday { Label(draft.birthday.formatted(date: .abbreviated, time: .omitted), systemImage: "birthday.cake") }
            if !draft.weight.isEmpty { Label("\(draft.weight) \(draft.unit)", systemImage: "scalemass") }
        }.font(.caption).foregroundStyle(.secondary)
    }
}
