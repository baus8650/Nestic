import SwiftUI
import Combine
import AppIntents
import UserNotifications
import BackgroundTasks
import AlarmKit

@main
struct Nestic_iOSApp: App {
    @StateObject private var reminders: NesticReminderStore
    @StateObject private var store: NesticStore
    @StateObject private var subscription = NesticSubscriptionStore()
    @AppStorage(NesticAppearanceMode.storageKey) private var appearance = NesticAppearanceMode.system.rawValue
    @Environment(\.scenePhase) private var scenePhase

    init() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--reset-tutorial") {
            UserDefaults.standard.removeObject(forKey: NesticOnboarding.tutorialViewedKey)
        }
        #endif
        NesticSiriShortcuts.updateAppShortcutParameters()
        let reminders = NesticReminderStore()
        _reminders = StateObject(wrappedValue: reminders)
        _store = StateObject(wrappedValue: NesticStore(reminderStore: reminders))
    }

    var body: some Scene {
        WindowGroup {
            NesticRootView()
                .environmentObject(store)
                .environmentObject(subscription)
                .environmentObject(reminders)
                .tint(NesticTheme.forest)
                .preferredColorScheme(NesticAppearanceMode(rawValue: appearance)?.colorScheme)
                .task {
                    if !ProcessInfo.processInfo.arguments.contains("--demo") { Task { await NesticUsageAnalytics.send(serverURL:store.serverURL) } }
                    NesticWidgetActionStore.store = store
                    NesticWatchBridge.shared.start()
                    let notificationCenter = UNUserNotificationCenter.current()
                    notificationCenter.delegate = NesticNotificationDelegate.shared
                    notificationCenter.setNotificationCategories([
                        UNNotificationCategory(
                            identifier: "NESTIC_REMINDER",
                            actions: [
                                UNNotificationAction(
                                    identifier: NesticReminderStore.logActionIdentifier,
                                    title: "Log now",
                                    options: []
                                )
                            ],
                            intentIdentifiers: [],
                            options: []
                        )
                    ])
                    NesticNotificationDelegate.shared.onLogAction = { subjectID, trackerID in
                        Task { @MainActor in
                            await store.logFromReminder(subjectID: subjectID, trackerID: trackerID)
                        }
                    }
                    reminders.onChange = {
                        store.markSettingsChanged()
                    }
                    if ProcessInfo.processInfo.arguments.contains("--demo") {
                        store.enterDemo(reset: ProcessInfo.processInfo.arguments.contains("--reset-demo"))
                    }

                    // Publish the locally cached snapshot before waiting for
                    // a network refresh. A physical Watch should get the
                    // trackers immediately even when the API is unavailable
                    // or slow to respond.
                    NesticWatchBridge.shared.setLogRequestHandler { request in
                        Task { @MainActor in
                            if await store.logFromWatch(request) {
                                NesticWatchBridge.shared.acknowledgeLogRequest(request.id)
                            }
                        }
                    }
                    NesticWatchBridge.shared.setRoutineLogRequestHandler { request in
                        Task { @MainActor in
                            if await store.logRoutineFromWatch(request) {
                                NesticWatchBridge.shared.acknowledgeLogRequest(request.id)
                            }
                        }
                    }
                    store.publishWatchSnapshot()
                    await store.start()
                    store.publishWatchSnapshot()
                    await subscription.load()
                    subscription.setManualProOverride(store.currentUser?.manualPro == true)
                    store.setPredictionAccess(subscription.hasPredictionAccess)
                    await reminders.sync()
                }
                .onOpenURL { url in
                    Task { await store.handleDeepLink(url) }
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active && store.isAuthenticated {
                        Task {
                            if !store.isDemo { await NesticUsageAnalytics.send(serverURL:store.serverURL) }
                            await store.appDidBecomeActive()
                            await reminders.sync()
                        }
                    } else if phase == .background {
                        store.appDidEnterBackground()
                        NesticWidgetBackgroundRefresh.schedule()
                    }
                }
                .onChange(of: subscription.hasPredictionAccess) { _, hasAccess in
                    store.setPredictionAccess(hasAccess)
                }
                .onChange(of: store.currentUser?.manualPro) { _, manualPro in
                    subscription.setManualProOverride(manualPro == true)
                }
        }
        .backgroundTask(.appRefresh(NesticWidgetBackgroundRefresh.identifier)) {
            NesticWidgetBackgroundRefresh.schedule()
            do { try await store.refresh(presentConnectionError: false, force: true) }
            catch { /* Retain the last successful widget snapshot while offline. */ }
        }
    }
}

enum NesticWidgetBackgroundRefresh {
    static let identifier = "com.bausch.Nestic-iOS.widget-refresh"

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        // iOS chooses the actual execution time and may defer it substantially.
        request.earliestBeginDate = Date().addingTimeInterval(15 * 60)
        do { try BGTaskScheduler.shared.submit(request) }
        catch { /* Foreground changes and widget actions still refresh widgets. */ }
    }
}

enum NesticReminderCadence: String, Codable, CaseIterable, Identifiable, Sendable {
    case afterDose
    case afterMeal
    case everyOtherDay
    case monthly
    case yearly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .afterDose: "Interval after the last update"
        case .afterMeal: "After a meal is logged"
        case .everyOtherDay: "Every other day"
        case .monthly: "Monthly"
        case .yearly: "Yearly"
        }
    }
}

struct NesticReminder: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var nestID: UUID
    var subjectID: UUID
    var subjectName: String
    var medicationTrackerID: UUID
    var medicationName: String
    var cadence: NesticReminderCadence
    var linkedMealTrackerID: UUID?
    var linkedMealName: String?
    var delayMinutes: Int
    var anchorDate: Date
    var hour: Int
    var minute: Int
    var enabled: Bool = true
    /// Present for reminders shared by another nest member. Older, personal
    /// reminders decode without it during the server migration.
    var createdByName: String?
    /// `nil` identifies a legacy, per-account reminder. Shared schedules are
    /// marked explicitly so a first sync never erases reminders created by an
    /// older app version.
    var isShared: Bool?
    var intervalHours: Double?
    var totalPills: Int?
    var lastDoseAt: Date?
    var pillsTaken: Double?
    var deliveryMode: String?
    var routineID: UUID?
    var recurrenceDays: Int?
    var startFromFirstTracking: Bool?
    var wantsAlarm: Bool { deliveryMode == "alarm" || deliveryMode == "both" }
    var wantsNotification: Bool { deliveryMode != "alarm" }

    var nextDoseAt: Date? {
        guard cadence == .afterDose, let base = lastDoseAt ?? (startFromFirstTracking == false ? anchorDate : nil), let hours = intervalHours, hours > 0,
              totalPills == nil || (pillsTaken ?? 0) < Double(totalPills!) else { return nil }
        return base.addingTimeInterval(hours * 3600)
    }
}

enum NesticReminderError: LocalizedError {
    case notificationsDisabled

    var errorDescription: String? {
        switch self {
        case .notificationsDisabled:
            "Notifications are turned off for Nestic. Enable them in Settings to receive reminders."
        }
    }
}

@MainActor
final class NesticReminderStore: ObservableObject {
    nonisolated static let logActionIdentifier = "NESTIC_REMINDER_LOG"
    private static let storageKey = "nestic.reminders.v1"
    private static let requestPrefix = "nestic-reminder-"

    @Published private(set) var reminders: [NesticReminder] = []
    var onChange: (() -> Void)?
    private let defaults: UserDefaults
    private let center = UNUserNotificationCenter.current()
    private var obsoleteReminders: [NesticReminder] = []

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.storageKey),
           let saved = try? NestCoding.decoder().decode([NesticReminder].self, from: data) {
            reminders = saved
        }
    }

    func save(_ reminder: NesticReminder) async throws {
        let linkedDates = linkedFireDates(reminder)
        if reminder.enabled { try await ensureAuthorization(reminder) }
        await removePendingRequests(prefix: requestPrefix(for: reminder))
        reminders.removeAll { $0.id == reminder.id }
        reminders.append(reminder)
        persist()
        notifyChanged()
        if reminder.enabled {
            if reminder.cadence != .afterMeal { try await scheduleRecurring(reminder) }
            else { for (identifier, date) in linkedDates { try await deliver(notificationRequest(reminder: reminder, identifier: identifier, date: date), reminder: reminder) } }
        }
    }

    func delete(_ reminder: NesticReminder) async {
        await removePendingRequests(prefix: requestPrefix(for: reminder))
        reminders.removeAll { $0.id == reminder.id }
        persist()
        notifyChanged()
    }

    func reminders(for nestID: UUID) -> [NesticReminder] {
        reminders.filter { $0.nestID == nestID }
    }

    func remindersForSync(nestID: UUID) -> [NesticReminder] {
        reminders.filter { $0.nestID == nestID }
    }

    func replaceReminders(_ remote: [NesticReminder], for nestID: UUID) {
        let remoteByID = Dictionary(uniqueKeysWithValues: remote.map { ($0.id, $0) })
        obsoleteReminders += reminders.filter { old in
            old.nestID == nestID && old.isShared == true &&
            (remoteByID[old.id] == nil || remoteByID[old.id]?.cadence != old.cadence || remoteByID[old.id]?.deliveryMode != old.deliveryMode)
        }
        reminders.removeAll { $0.nestID == nestID && $0.isShared == true }
        reminders.append(contentsOf: remote.map { reminder in
            var shared = reminder
            shared.isShared = true
            return shared
        })
        persist()
    }

    func setNotificationsEnabled(_ enabled: Bool, for reminder: NesticReminder) async throws {
        await removePendingRequests(prefix: requestPrefix(for: reminder))
        guard let index = reminders.firstIndex(where: { $0.id == reminder.id }) else { return }
        reminders[index].enabled = enabled
        persist()
        notifyChanged()
        if enabled, reminder.cadence != .afterMeal {
            try await ensureAuthorization(reminder)
            try await scheduleRecurring(reminders[index])
        }
    }

    func sync() async {
        let obsolete = obsoleteReminders
        obsoleteReminders.removeAll()
        for reminder in obsolete + reminders.filter({ !$0.enabled }) {
            let dates = linkedFireDates(reminder)
            await removePendingRequests(prefix: requestPrefix(for: reminder))
            if let replacement = reminders.first(where: { $0.id == reminder.id && $0.enabled && $0.cadence == .afterMeal }) {
                for (identifier, date) in dates { try? await deliver(notificationRequest(reminder: replacement, identifier: identifier, date: date), reminder: replacement) }
            }
        }
        for reminder in reminders where reminder.enabled && reminder.cadence != .afterMeal {
            if reminder.cadence == .afterDose, let due = reminder.nextDoseAt, due <= Date(),
               defaults.double(forKey: "nestic.doseReminder.\(reminder.id).lastScheduled") == due.timeIntervalSince1970 { continue }
            await removePendingRequests(prefix: requestPrefix(for: reminder))
            try? await scheduleRecurring(reminder)
        }
    }

    func clearAll() async {
        await removePendingRequests(prefix: Self.requestPrefix)
        let requests = await pendingRequests()
        center.removePendingNotificationRequests(withIdentifiers: requests.map(\.identifier))
        reminders.removeAll()
        persist()
    }

    func resetSchedules(referencing trackerID: UUID) async {
        for reminder in reminders where reminder.medicationTrackerID == trackerID || reminder.linkedMealTrackerID == trackerID {
            await removePendingRequests(prefix: requestPrefix(for: reminder))
        }
    }

    func removeReminders(referencing trackerID: UUID) async {
        let affected = reminders.filter {
            $0.medicationTrackerID == trackerID || $0.linkedMealTrackerID == trackerID
        }
        for reminder in affected {
            await delete(reminder)
        }
    }

    func removeReminders(for subjectID: UUID) async {
        let affected = reminders.filter { $0.subjectID == subjectID }
        for reminder in affected {
            await delete(reminder)
        }
    }

    func handleLoggedRoutine(_ id: UUID, at date: Date) async {
        for index in reminders.indices where reminders[index].routineID == id {
            if reminders[index].lastDoseAt == nil || date > reminders[index].lastDoseAt! { reminders[index].lastDoseAt = date }
        }
        persist()
        await sync()
    }

    func updateDoseReminders(entries: [NestEntry], nestID: UUID) async {
        for index in reminders.indices where reminders[index].nestID == nestID && reminders[index].cadence == .afterDose && reminders[index].routineID == nil {
            let r = reminders[index]
            let doses = entries.filter { $0.entityId == r.subjectID && $0.actionId == r.medicationTrackerID && $0.occurredAt >= r.anchorDate && $0.occurredAt <= Date() && (r.totalPills == nil || ($0.valueBool != false && ($0.valueNumber ?? 1) > 0)) }
            reminders[index].lastDoseAt = doses.map(\.occurredAt).max()
            reminders[index].pillsTaken = doses.reduce(0) { $0 + max(0, $1.valueNumber ?? 1) }
        }
        await reconcileLinkedReminders(entries: entries, nestID: nestID)
        persist()
        await sync()
    }

    func reconcileLinkedReminders(entries: [NestEntry], nestID: UUID) async {
        for reminder in reminders where reminder.nestID == nestID && reminder.cadence == .afterMeal {
            if !entries.contains(where: { $0.entityId == reminder.subjectID && $0.actionId == reminder.linkedMealTrackerID }) {
                await removePendingRequests(prefix: requestPrefix(for: reminder))
            }
        }
    }

    func handleLoggedEntry(_ entry: NestEntry) async {
        let matching = reminders.filter {
            $0.enabled &&
            $0.cadence == .afterMeal &&
            $0.subjectID == entry.entityId &&
            $0.linkedMealTrackerID == entry.actionId
        }
        for reminder in matching {
            let requestedFireDate = entry.occurredAt.addingTimeInterval(Double(reminder.delayMinutes) * 60)
            let fireDate = max(Date().addingTimeInterval(1), requestedFireDate)
            let request = notificationRequest(
                reminder: reminder,
                identifier: "\(requestPrefix(for: reminder))entry-\(entry.id.uuidString)",
                date: fireDate
            )
            try? await deliver(request, reminder: reminder)
        }
    }

    func handleUpdatedEntry(_ entry: NestEntry) async {
        let matching = reminders.filter {
            $0.enabled &&
            $0.cadence == .afterMeal &&
            $0.subjectID == entry.entityId &&
            $0.linkedMealTrackerID == entry.actionId
        }
        for reminder in matching {
            await removePendingRequests(prefix: "\(requestPrefix(for: reminder))entry-\(entry.id.uuidString)")
        }
        await handleLoggedEntry(entry)
    }

    func authorizeDelivery(for reminder: NesticReminder) async throws { try await ensureAuthorization(reminder) }

    private func ensureAuthorization(_ reminder: NesticReminder) async throws {
        if reminder.wantsAlarm {
            guard #available(iOS 26.0, *) else { throw NSError(domain: "Nestic", code: 26, userInfo: [NSLocalizedDescriptionKey: "Alarms require iOS 26 or later. Choose notifications on this device."]) }
            let manager = AlarmKit.AlarmManager.shared
            let state = manager.authorizationState == .notDetermined ? try await manager.requestAuthorization() : manager.authorizationState
            guard state == .authorized else { throw NSError(domain: "Nestic", code: 1, userInfo: [NSLocalizedDescriptionKey: "Enable Nestic alarms in Settings to use alarm delivery."]) }
        }
        guard reminder.wantsNotification else { return }

        let settings = await notificationSettings()
        switch settings.authorizationStatus {
        case .denied:
            throw NesticReminderError.notificationsDisabled
        case .notDetermined:
            let granted = try await requestAuthorization()
            guard granted else { throw NesticReminderError.notificationsDisabled }
        default:
            break
        }
    }

    private func scheduleRecurring(_ reminder: NesticReminder) async throws {
        switch reminder.cadence {
        case .everyOtherDay:
            try await scheduleEveryOtherDay(reminder)
        case .monthly:
            try await scheduleMonthly(reminder)
        case .yearly:
            try await scheduleYearly(reminder)
        case .afterDose:
            if let due = reminder.nextDoseAt {
                let key = "nestic.doseReminder.\(reminder.id).lastScheduled"
                let dose = due.timeIntervalSince1970
                if due <= Date(), defaults.double(forKey: key) == dose { return }
                let request = notificationRequest(reminder: reminder,
                    identifier: "\(requestPrefix(for: reminder))dose",
                    date: max(due, Date().addingTimeInterval(1)))
                try await deliver(request, reminder: reminder)
                defaults.set(dose, forKey: key)
            }
        case .afterMeal:
            break
        }
    }

    private func scheduleEveryOtherDay(_ reminder: NesticReminder) async throws {
        let calendar = Calendar.current
        let days = reminder.recurrenceDays ?? 2
        guard var next = calendar.date(
            bySettingHour: reminder.hour,
            minute: reminder.minute,
            second: 0,
            of: calendar.startOfDay(for: reminder.anchorDate)
        ) else { return }
        while next <= Date() {
            next = calendar.date(byAdding: .day, value: days, to: next) ?? next.addingTimeInterval(Double(days) * 86_400)
        }
        // iOS limits an app to 64 pending local notifications. Keep a
        // rolling window for each recurring reminder and divide that budget
        // across multiple every-other-day schedules.
        let occurrenceCount = recurringOccurrenceCount(maximum: 30)
        for index in 0..<occurrenceCount {
            let date = calendar.date(byAdding: .day, value: index * days, to: next) ?? next
            let request = notificationRequest(
                reminder: reminder,
                identifier: "\(requestPrefix(for: reminder))\(Int(date.timeIntervalSince1970))",
                date: date
            )
            try await deliver(request, reminder: reminder)
        }
    }

    private func scheduleMonthly(_ reminder: NesticReminder) async throws {
        let calendar = Calendar.current
        let desiredDay = calendar.component(.day, from: reminder.anchorDate)
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: reminder.anchorDate)) ?? reminder.anchorDate
        var next = monthlyDate(monthStart: monthStart, desiredDay: desiredDay, hour: reminder.hour, minute: reminder.minute, calendar: calendar)
        while next <= Date() {
            next = calendar.date(byAdding: .month, value: 1, to: calendar.date(from: calendar.dateComponents([.year, .month], from: next)) ?? next) ?? next.addingTimeInterval(31 * 86_400)
            next = monthlyDate(monthStart: next, desiredDay: desiredDay, hour: reminder.hour, minute: reminder.minute, calendar: calendar)
        }
        let occurrenceCount = recurringOccurrenceCount(maximum: 12)
        for index in 0..<occurrenceCount {
            let month = calendar.date(byAdding: .month, value: index, to: next) ?? next
            let date = monthlyDate(monthStart: month, desiredDay: desiredDay, hour: reminder.hour, minute: reminder.minute, calendar: calendar)
            let request = notificationRequest(reminder: reminder, identifier: "\(requestPrefix(for: reminder))\(Int(date.timeIntervalSince1970))", date: date)
            try await deliver(request, reminder: reminder)
        }
    }

    private func scheduleYearly(_ reminder: NesticReminder) async throws {
        let calendar = Calendar.current
        let desiredMonth = calendar.component(.month, from: reminder.anchorDate)
        let desiredDay = calendar.component(.day, from: reminder.anchorDate)
        let yearStart = calendar.date(from: DateComponents(year: calendar.component(.year, from: reminder.anchorDate), month: desiredMonth, day: 1)) ?? reminder.anchorDate
        var next = yearlyDate(yearStart: yearStart, desiredMonth: desiredMonth, desiredDay: desiredDay, hour: reminder.hour, minute: reminder.minute, calendar: calendar)
        while next <= Date() {
            next = calendar.date(byAdding: .year, value: 1, to: calendar.date(from: calendar.dateComponents([.year], from: next)) ?? next) ?? next.addingTimeInterval(366 * 86_400)
            next = yearlyDate(yearStart: next, desiredMonth: desiredMonth, desiredDay: desiredDay, hour: reminder.hour, minute: reminder.minute, calendar: calendar)
        }
        let occurrenceCount = recurringOccurrenceCount(maximum: 3)
        for index in 0..<occurrenceCount {
            let year = calendar.date(byAdding: .year, value: index, to: next) ?? next
            let date = yearlyDate(yearStart: year, desiredMonth: desiredMonth, desiredDay: desiredDay, hour: reminder.hour, minute: reminder.minute, calendar: calendar)
            let request = notificationRequest(reminder: reminder, identifier: "\(requestPrefix(for: reminder))\(Int(date.timeIntervalSince1970))", date: date)
            try await deliver(request, reminder: reminder)
        }
    }

    private func monthlyDate(monthStart: Date, desiredDay: Int, hour: Int, minute: Int, calendar: Calendar) -> Date {
        let components = calendar.dateComponents([.year, .month], from: monthStart)
        let firstDay = calendar.date(from: components) ?? monthStart
        let lastDay = calendar.range(of: .day, in: .month, for: firstDay)?.count ?? desiredDay
        return calendar.date(bySettingHour: hour, minute: minute, second: 0,
                             of: calendar.date(byAdding: .day, value: min(desiredDay, lastDay) - 1, to: firstDay) ?? firstDay) ?? firstDay
    }

    private func yearlyDate(yearStart: Date, desiredMonth: Int, desiredDay: Int, hour: Int, minute: Int, calendar: Calendar) -> Date {
        let year = calendar.component(.year, from: yearStart)
        let monthStart = calendar.date(from: DateComponents(year: year, month: desiredMonth, day: 1)) ?? yearStart
        return monthlyDate(monthStart: monthStart, desiredDay: desiredDay, hour: hour, minute: minute, calendar: calendar)
    }

    private func recurringOccurrenceCount(maximum: Int) -> Int {
        let recurringCount = max(1, reminders.filter { $0.enabled && $0.cadence != .afterMeal }.count)
        return max(1, min(maximum, 60 / recurringCount))
    }

    private func notificationRequest(reminder: NesticReminder, identifier: String, date: Date) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = "Nestic reminder"
        content.body = "Log \(reminder.medicationName) for \(reminder.subjectName)."
        content.sound = .default
        content.categoryIdentifier = "NESTIC_REMINDER"
        content.userInfo = [
            "subjectID": reminder.subjectID.uuidString,
            "trackerID": reminder.medicationTrackerID.uuidString,
            "reminderID": reminder.id.uuidString
        ]
        if reminder.cadence == .afterDose {
            return UNNotificationRequest(identifier: identifier, content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, date.timeIntervalSinceNow), repeats: false))
        }
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        )
    }

    private func requestPrefix(for reminder: NesticReminder) -> String {
        "\(Self.requestPrefix)\(reminder.id.uuidString)-"
    }

    private func persist() {
        guard let data = try? NestCoding.encoder().encode(reminders) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }

    private func notifyChanged() {
        onChange?()
    }

    private func notificationSettings() async -> UNNotificationSettings {
        await withCheckedContinuation { continuation in
            center.getNotificationSettings { continuation.resume(returning: $0) }
        }
    }

    private func requestAuthorization() async throws -> Bool {
        try await withCheckedThrowingContinuation { continuation in
            center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: granted) }
            }
        }
    }

    private func pendingRequests() async -> [UNNotificationRequest] {
        await withCheckedContinuation { continuation in
            center.getPendingNotificationRequests { continuation.resume(returning: $0) }
        }
    }

    private func linkedFireDates(_ reminder: NesticReminder) -> [String: Date] {
        guard reminder.cadence == .afterMeal else { return [:] }
        let dates = defaults.dictionary(forKey: "nestic.reminderFireDates") as? [String: Double] ?? [:]
        return dates.filter { $0.key.hasPrefix(requestPrefix(for: reminder)) && $0.value > Date().timeIntervalSince1970 }.mapValues { Date(timeIntervalSince1970: $0) }
    }

    private func deliver(_ request: UNNotificationRequest, reminder: NesticReminder) async throws {
        if reminder.wantsAlarm {
            let nextDate = (request.trigger as? UNTimeIntervalNotificationTrigger)?.nextTriggerDate() ?? (request.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate()
            guard #available(iOS 26.0, *), AlarmKit.AlarmManager.shared.authorizationState == .authorized,
                  let date = nextDate else {
                throw NSError(domain: "Nestic", code: 1, userInfo: [NSLocalizedDescriptionKey: "Alarm access is unavailable on this device."])
            }
            let id = UUID()
            let alert = AlarmPresentation.Alert(title: "Log \(reminder.medicationName) for \(reminder.subjectName)", stopButton: AlarmButton(text: "Stop", textColor: .white, systemImageName: "stop.fill"))
            let attributes = AlarmAttributes<NesticAlarmMetadata>(presentation: AlarmPresentation(alert: alert), metadata: NesticAlarmMetadata(), tintColor: .green)
            _ = try await AlarmKit.AlarmManager.shared.schedule(id: id, configuration: .alarm(schedule: .fixed(date), attributes: attributes))
            var ids = defaults.dictionary(forKey: "nestic.alarmIDs") as? [String: String] ?? [:]
            ids[request.identifier] = id.uuidString
            defaults.set(ids, forKey: "nestic.alarmIDs")
        }
        if reminder.wantsNotification { try await center.add(request) }
        if let date = (request.trigger as? UNTimeIntervalNotificationTrigger)?.nextTriggerDate() ?? (request.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate() {
            var dates = defaults.dictionary(forKey: "nestic.reminderFireDates") as? [String: Double] ?? [:]
            dates[request.identifier] = date.timeIntervalSince1970
            defaults.set(dates, forKey: "nestic.reminderFireDates")
        }
    }

    private func removePendingRequests(prefix: String) async {
        let dates = defaults.dictionary(forKey: "nestic.reminderFireDates") as? [String: Double] ?? [:]
        defaults.set(dates.filter { !$0.key.hasPrefix(prefix) }, forKey: "nestic.reminderFireDates")
        if #available(iOS 26.0, *) {
            var ids = defaults.dictionary(forKey: "nestic.alarmIDs") as? [String: String] ?? [:]
            for (key, value) in ids where key.hasPrefix(prefix) {
                if let id = UUID(uuidString: value) { try? AlarmKit.AlarmManager.shared.cancel(id: id) }
                ids.removeValue(forKey: key)
            }
            defaults.set(ids, forKey: "nestic.alarmIDs")
        }

        let requests = await pendingRequests()
        let identifiers = requests.map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }
}

final class NesticNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NesticNotificationDelegate()
    var onLogAction: ((UUID, UUID) -> Void)?

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        guard response.actionIdentifier == Self.logActionIdentifier,
              let subjectValue = response.notification.request.content.userInfo["subjectID"] as? String,
              let trackerValue = response.notification.request.content.userInfo["trackerID"] as? String,
              let subjectID = UUID(uuidString: subjectValue),
              let trackerID = UUID(uuidString: trackerValue) else {
            completionHandler()
            return
        }
        onLogAction?(subjectID, trackerID)
        completionHandler()
    }

    private static let logActionIdentifier = NesticReminderStore.logActionIdentifier
}

func reminderIntervalLabel(_ hours: Double) -> String {
    let value = hours < 1 ? hours * 60 : hours >= 24 && hours.truncatingRemainder(dividingBy: 24) == 0 ? hours / 24 : hours
    let unit = hours < 1 ? "minute" : hours >= 24 && hours.truncatingRemainder(dividingBy: 24) == 0 ? "day" : "hour"
    return "\(String(format: "%g", value)) \(unit)\(value == 1 ? "" : "s")"
}

@available(iOS 26.0, *)
private struct NesticAlarmMetadata: AlarmMetadata {}
