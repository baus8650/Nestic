import SwiftUI

struct SharedReminderRow: View {
    @EnvironmentObject private var store: NesticStore
    let reminder: NesticReminder
    let onEdit: () -> Void

    private var symbol: String {
        reminder.cadence == .afterMeal ? "fork.knife" : "calendar.badge.clock"
    }

    private var scheduleDescription: String {
        if reminder.cadence == .afterDose {
            let interval = "Every \(reminder.intervalHours ?? 8) hours after a dose"
            if let total = reminder.totalPills, (reminder.pillsTaken ?? 0) >= Double(total) { return "Course complete · \(total) pills" }
            let progress = reminder.totalPills.map { " · \(Int(reminder.pillsTaken ?? 0))/\($0) pills" } ?? ""
            return interval + progress + (reminder.lastDoseAt == nil ? " · Waiting for first dose" : "")
        }
        if reminder.cadence == .afterMeal {
            let timing = reminder.delayMinutes == 0 ? "immediately" : "\(reminder.delayMinutes) minutes later"
            return "After \(reminder.linkedMealName ?? "a meal") · \(timing)"
        }
        return "\(reminder.cadence.title) · \(reminder.anchorDate.formatted(date: .omitted, time: .shortened))"
    }

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onEdit) {
                HStack(spacing: 12) {
                    Image(systemName: symbol)
                        .foregroundStyle(NesticTheme.forest)
                        .frame(width: 28, height: 28)
                        .background(NesticTheme.lime.opacity(0.3), in: Circle())
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(reminder.medicationName) · \(reminder.subjectName)")
                            .font(.subheadline.weight(.semibold))
                        Text(scheduleDescription)
                            .font(.caption).foregroundStyle(.secondary)
                        if let creator = reminder.createdByName {
                            Text("Created by \(creator)")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold)).foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)

            Toggle("Notifications for \(reminder.medicationName)", isOn: notificationBinding)
                .labelsHidden()
                .accessibilityIdentifier("reminder.notifications")
        }
    }

    private var notificationBinding: Binding<Bool> {
        Binding(
            get: { reminder.enabled },
            set: { enabled in
                Task {
                    do {
                        try await store.setReminderNotifications(enabled, for: reminder)
                    } catch {
                        store.errorMessage = error.localizedDescription
                    }
                }
            }
        )
    }
}
