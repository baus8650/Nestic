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
            let interval = "Every \(reminderIntervalLabel(reminder.intervalHours ?? 8)) after the last update"
            if let total = reminder.totalPills, (reminder.pillsTaken ?? 0) >= Double(total) { return "Course complete · \(total) pills" }
            let progress = reminder.totalPills.map { " · \(Int(reminder.pillsTaken ?? 0))/\($0) pills" } ?? ""
            return interval + progress + (reminder.lastDoseAt == nil && reminder.startFromFirstTracking != false ? " · Waiting for first update" : "")
        }
        if reminder.cadence == .afterMeal {
            let timing = reminder.delayMinutes == 0 ? "immediately" : "\(reminder.delayMinutes) minutes later"
            return "After \(reminder.linkedMealName ?? "a meal") · \(timing)"
        }
        let cadenceTitle = reminder.cadence == .everyOtherDay ? (reminder.recurrenceDays == 7 ? "Weekly" : "Every \(reminder.recurrenceDays ?? 2) days") : reminder.cadence.title
        return "\(cadenceTitle) · \(reminder.anchorDate.formatted(date: .omitted, time: .shortened))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
            Button(action: onEdit) {
                HStack(spacing: 12) {
                    Image(systemName: symbol)
                        .foregroundStyle(NesticTheme.forest)
                        .frame(width: 28, height: 28)
                        .background(NesticTheme.lime.opacity(0.3), in: Circle())
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(reminder.routineID == nil ? "" : "Routine · ")\(reminder.medicationName) · \(reminder.subjectName)")
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

            Toggle("Reminders for \(reminder.medicationName)", isOn: notificationBinding)
                .labelsHidden()
                .accessibilityIdentifier("reminder.notifications")
            }
            ReminderDeliveryPicker(selection: Binding(
                get: { reminder.deliveryMode ?? "notification" },
                set: { mode in
                    Task { do { try await store.setReminderDelivery(mode, for: reminder) } catch { store.errorMessage = error.localizedDescription } }
                }
            ))
            if reminder.wantsAlarm && alarmSupported {
                Button("Enable alarms on this device") {
                    Task { do { try await store.setReminderDelivery(reminder.deliveryMode ?? "alarm", for: reminder) } catch { store.errorMessage = error.localizedDescription } }
                }
                .font(.caption)
            }
        }
    }

    private var alarmSupported: Bool { if #available(iOS 26.0, *) { return true }; return false }

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


struct ReminderDeliveryPicker: View {
    @Binding var selection: String

    private var alarmSupported: Bool { if #available(iOS 26.0, *) { return true }; return false }
    private func title(_ mode: String) -> String {
        mode == "alarm" ? "Alarm" : mode == "both" ? "Alarm and notification" : "Notification"
    }
    private func symbol(_ mode: String) -> String {
        mode == "alarm" ? "alarm" : mode == "both" ? "bell.and.waves.left.and.right" : "bell.badge"
    }
    private var explanation: String {
        selection == "alarm" ? "An alarm rings on this device when the reminder is due." : selection == "both" ? "Receive a notification and a ringing alarm when the reminder is due." : "Receive a notification when the reminder is due. Sound follows your notification settings."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("How should we remind you?").font(.subheadline.weight(.semibold))
            Menu {
                ForEach(["notification", "alarm", "both"], id: \.self) { mode in
                    Button { selection = mode } label: {
                        Label(title(mode), systemImage: selection == mode ? "checkmark" : symbol(mode))
                    }
                    .disabled(mode != "notification" && !alarmSupported)
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: symbol(selection))
                    Text(title(selection)).font(.subheadline.weight(.medium))
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.up.chevron.down").font(.caption.weight(.semibold))
                }
                .foregroundStyle(NesticTheme.forest)
                .padding(12)
                .background(NesticTheme.forest.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(NesticTheme.forest.opacity(0.18)))
                .contentShape(Rectangle())
            }
            .accessibilityLabel("Reminder delivery")
            .accessibilityValue(title(selection))
            .accessibilityHint("Choose notification, alarm, or both")
            Text(explanation + " This choice applies only to you.")
                .font(.caption).foregroundStyle(.secondary)
            if !alarmSupported {
                Text("Alarm options require iOS 26 or later.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}


struct ReminderScheduleDraft {
    var schedule = "afterDose"
    var amount = "8"
    var unit = "hours"
    var days = "3"
    var firstLog = true
    var date = Date()
    var delivery = "notification"
    var triggerID: UUID?
    var delay = 5
    var total = ""
    var cadence: NesticReminderCadence { schedule == "weekly" || schedule == "custom" ? .everyOtherDay : NesticReminderCadence(rawValue: schedule) ?? .afterDose }
    var hours: Double? { Double(amount).map { $0 * (unit == "minutes" ? 1 / 60.0 : unit == "days" ? 24 : 1) } }
    var recurrenceDays: Int? { schedule == "weekly" ? 7 : schedule == "custom" ? Int(days) : cadence == .everyOtherDay ? 2 : nil }

    init(_ reminder: NesticReminder? = nil) {
        guard let reminder else { return }
        schedule = reminder.cadence == .everyOtherDay && reminder.recurrenceDays != nil && reminder.recurrenceDays != 2 ? (reminder.recurrenceDays == 7 ? "weekly" : "custom") : reminder.cadence.rawValue
        days = String(reminder.recurrenceDays ?? 3)
        let interval = reminder.intervalHours ?? 8
        unit = interval < 1 ? "minutes" : interval >= 24 && interval.truncatingRemainder(dividingBy: 24) == 0 ? "days" : "hours"
        amount = String(format: "%g", interval * (unit == "minutes" ? 60 : unit == "days" ? 1 / 24.0 : 1))
        firstLog = reminder.startFromFirstTracking != false
        date = reminder.anchorDate
        delivery = reminder.deliveryMode ?? "notification"
        triggerID = reminder.linkedMealTrackerID
        delay = reminder.delayMinutes
        total = reminder.totalPills.map(String.init) ?? ""
    }

    func makeReminder(nestID: UUID, subject: NestSubject, targetID: UUID, targetName: String, routineID: UUID? = nil, previous: NesticReminder? = nil) throws -> NesticReminder {
        if cadence == .afterDose { guard let hours, hours.isFinite, (1.0 / 60...720).contains(hours) else { throw NesticError.message("Choose an interval from 1 minute to 30 days.") } }
        if cadence == .everyOtherDay { guard let recurrenceDays, (1...365).contains(recurrenceDays) else { throw NesticError.message("Choose a whole number from 1 to 365 days.") } }
        if cadence == .afterMeal && triggerID == nil { throw NesticError.message("Choose a tracker that triggers this reminder.") }
        if !total.isEmpty && routineID == nil { guard let count = Int(total), (1...100_000).contains(count) else { throw NesticError.message("Choose a positive whole pill total.") } }
        let time = Calendar.current.dateComponents([.hour, .minute], from: date)
        return NesticReminder(id: previous?.id ?? UUID(), nestID: nestID, subjectID: subject.id, subjectName: subject.name, medicationTrackerID: targetID, medicationName: targetName, cadence: cadence, linkedMealTrackerID: cadence == .afterMeal ? triggerID : nil, delayMinutes: cadence == .afterMeal ? delay : 0, anchorDate: cadence == .afterDose && firstLog ? Date(timeIntervalSince1970: 0) : date, hour: time.hour ?? 9, minute: time.minute ?? 0, enabled: previous?.enabled ?? true, isShared: previous?.isShared, intervalHours: cadence == .afterDose ? hours : nil, totalPills: cadence == .afterDose && routineID == nil ? Int(total) : nil, lastDoseAt: previous?.lastDoseAt, deliveryMode: previous?.deliveryMode, routineID: routineID, recurrenceDays: recurrenceDays, startFromFirstTracking: cadence == .afterDose ? firstLog : nil)
    }
}

struct ReminderScheduleFields: View {
    @Binding var draft: ReminderScheduleDraft
    let trackers: [NestTracker]
    var allowsPillTotal = false
    var isRoutine = false
    var body: some View {
        Section("Reminder schedule") {
            Picker("Schedule", selection: $draft.schedule) {
                Text(isRoutine ? "Interval after logging the routine" : "Interval after each update").tag("afterDose")
                Text("After a tracker is logged").tag("afterMeal")
                Text("Every other day").tag("everyOtherDay")
                Text("Weekly").tag("weekly")
                Text("Monthly").tag("monthly")
                Text("Yearly").tag("yearly")
                Text("Custom · every X days").tag("custom")
            }
            if draft.cadence == .afterDose {
                VStack(alignment: .leading, spacing: 8) {
                    Text(isRoutine ? "Remind me after logging the routine" : "Remind me after each update").font(.subheadline.weight(.semibold))
                    HStack {
                        TextField("Amount (e.g. 8)", text: $draft.amount).keyboardType(.decimalPad)
                        Picker("Unit", selection: $draft.unit) { Text("Minutes").tag("minutes"); Text("Hours").tag("hours"); Text("Days").tag("days") }.labelsHidden().pickerStyle(.menu)
                    }
                }
                Picker("Start counting", selection: $draft.firstLog) { Text("First logged update").tag(true); Text("Choose a date and time").tag(false) }
                if !draft.firstLog { DatePicker("Start counting from", selection: $draft.date) }
                Text(isRoutine ? "Logging the whole routine resets the countdown. Individual tracker updates do not reset it." : "Each logged update resets the countdown. Choose 1 minute to 30 days.").font(.caption).foregroundStyle(.secondary)
                if allowsPillTotal { TextField("Medication pill total · optional", text: $draft.total).keyboardType(.numberPad) }
            } else if draft.cadence == .afterMeal {
                Picker("After this tracker is logged", selection: $draft.triggerID) { Text("Choose a tracker").tag(UUID?.none); ForEach(trackers) { Text($0.name).tag(Optional($0.id)) } }
                Stepper("Delay: \(draft.delay) minutes", value: $draft.delay, in: 0...1440)
            } else {
                if draft.schedule == "custom" { HStack { Text("Repeat every"); TextField("Days", text: $draft.days).keyboardType(.numberPad); Text("days") } }
                DatePicker("First reminder", selection: $draft.date)
            }
            ReminderDeliveryPicker(selection: $draft.delivery)
        }
    }
}
