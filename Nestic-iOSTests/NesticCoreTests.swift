import Foundation
import Testing
@testable import Nestic_iOS

@MainActor
struct NesticCoreTests {
    @Test func routineLoggingKeepsChosenTimeAcrossAllTargets() async throws {
        let defaults = UserDefaults(suiteName: "routine-time-\(UUID())")!
        let store = NesticStore(defaults: defaults)
        store.enterDemo(reset: true)
        let targets = store.subjects.compactMap { subject -> NestRoutineTarget? in
            guard let tracker = store.trackers(for: subject).first(where: { $0.valueType == .none }) else { return nil }
            return NestRoutineTarget(entityID: subject.id, items: [NestRoutineItem(trackerID: tracker.id)])
        }
        #expect(!targets.isEmpty)
        let routine = try await store.createRoutine(name: "Backdated routine", targets: targets)
        let originalIDs = Set(store.entries.map(\.id))
        let recordedAt = Date().addingTimeInterval(-3600)
        try await store.logRoutine(routine, date: recordedAt, note: "Forgot earlier")
        let added = store.entries.filter { !originalIDs.contains($0.id) }
        #expect(added.count == targets.count)
        #expect(added.allSatisfy { $0.occurredAt == recordedAt && $0.note == "Forgot earlier" })
    }

    @Test func routineReminderSupportsSchedulesAndKeepsItsTarget() throws {
        let subject = NestSubject(id: UUID(), nestId: UUID(), name: "Me", kind: .person, emoji: "🙂")
        let routineID = UUID()
        var draft = ReminderScheduleDraft()
        draft.schedule = "weekly"
        var reminder = try draft.makeReminder(nestID: subject.nestId, subject: subject, targetID: routineID, targetName: "Morning", routineID: routineID)
        #expect(reminder.routineID == routineID)
        #expect(reminder.recurrenceDays == 7)
        draft.schedule = "custom"; draft.days = "13"
        reminder = try draft.makeReminder(nestID: subject.nestId, subject: subject, targetID: routineID, targetName: "Morning", routineID: routineID)
        #expect(reminder.recurrenceDays == 13)
        let restored = try NestCoding.decoder().decode(NesticReminder.self, from: NestCoding.encoder().encode(reminder))
        #expect(restored.routineID == routineID)
        draft.schedule = "afterDose"; draft.amount = "30"; draft.unit = "minutes"
        reminder = try draft.makeReminder(nestID: subject.nestId, subject: subject, targetID: routineID, targetName: "Morning", routineID: routineID)
        #expect(reminder.nextDoseAt == nil)
        reminder.lastDoseAt = Date(timeIntervalSince1970: 1_780_000_000)
        #expect(reminder.nextDoseAt == reminder.lastDoseAt?.addingTimeInterval(1800))
        #expect(reminder.totalPills == nil)
    }

    @Test func reminderStartAndCustomDaysSurviveSaving() throws {
        let start = Date(timeIntervalSince1970: 1_780_000_000)
        var r = NesticReminder(id: UUID(), nestID: UUID(), subjectID: UUID(), subjectName: "Me", medicationTrackerID: UUID(), medicationName: "Check", cadence: .afterDose, delayMinutes: 0, anchorDate: start, hour: 9, minute: 0, intervalHours: 8, startFromFirstTracking: true)
        #expect(r.nextDoseAt == nil)
        r.startFromFirstTracking = false
        #expect(r.nextDoseAt == start.addingTimeInterval(8 * 3600))
        r.lastDoseAt = start.addingTimeInterval(3600)
        #expect(r.nextDoseAt == start.addingTimeInterval(9 * 3600))
        r.cadence = .everyOtherDay
        r.recurrenceDays = 7
        let saved = try NestCoding.decoder().decode(NesticReminder.self, from: NestCoding.encoder().encode(r))
        #expect(saved.recurrenceDays == 7)
        #expect(saved.startFromFirstTracking == false)
        #expect(saved.nextDoseAt == nil)
        r.recurrenceDays = 13
        let custom = try NestCoding.decoder().decode(NesticReminder.self, from: NestCoding.encoder().encode(r))
        #expect(custom.recurrenceDays == 13)
    }

    @Test func selectedForecastInputsRespectEveryReader() throws {
        let owner = UUID(), reader = UUID(), nest = UUID()
        let target = NestTracker(id: UUID(), nestId: nest, name: "Selected", valueType: .none, privateOwnerId: owner, allowedMemberIDs: [reader])
        let onlyMe = NestTracker(id: UUID(), nestId: nest, name: "Secret", valueType: .none, privateOwnerId: owner)
        let shared = NestTracker(id: UUID(), nestId: nest, name: "Shared", valueType: .none)
        #expect(!onlyMe.canContribute(to: target))
        #expect(shared.canContribute(to: target))
        #expect(target.canContribute(to: onlyMe))
        #expect(!target.canContribute(to: shared))
        let decoded = try NestCoding.decoder().decode(NestTracker.self, from: NestCoding.encoder().encode(target))
        #expect(decoded.allowedMemberIDs == [reader])
        #expect(decoded.privacyLabel == "Selected members")
    }
    @Test func doseReminderResetsAndStopsAtCourseTotal() throws {
        let last = Date(timeIntervalSince1970: 1_780_000_000)
        var r = NesticReminder(id: UUID(), nestID: UUID(), subjectID: UUID(), subjectName: "Me", medicationTrackerID: UUID(), medicationName: "Pill", cadence: .afterDose, delayMinutes: 0, anchorDate: last, hour: 0, minute: 0, intervalHours: 8, totalPills: 3)
        #expect(r.nextDoseAt == nil)
        r.lastDoseAt = last; r.pillsTaken = 1
        #expect(r.nextDoseAt == last.addingTimeInterval(8 * 3600))
        r.lastDoseAt = last.addingTimeInterval(15 * 3600); r.pillsTaken = 2
        #expect(r.nextDoseAt == last.addingTimeInterval(23 * 3600))
        r.pillsTaken = 3
        #expect(r.nextDoseAt == nil)
        r.totalPills = nil
        #expect(r.nextDoseAt != nil)
        let restored = try NestCoding.decoder().decode(NesticReminder.self, from: NestCoding.encoder().encode(r))
        #expect(restored.nextDoseAt == r.nextDoseAt)
        r.deliveryMode = "alarm"
        #expect(r.wantsAlarm && !r.wantsNotification)
        r.deliveryMode = "both"
        #expect(r.wantsAlarm && r.wantsNotification)
        #expect(try NestCoding.decoder().decode(NesticReminder.self, from: NestCoding.encoder().encode(r)).deliveryMode == "both")
        r.intervalHours = 1.0 / 60.0
        #expect(r.nextDoseAt == r.lastDoseAt?.addingTimeInterval(60))
        #expect(reminderIntervalLabel(1.0 / 60.0) == "1 minute")
        #expect(reminderIntervalLabel(0.5) == "30 minutes")
        #expect(reminderIntervalLabel(48) == "2 days")
    }
    @Test func privateTrackerKeepsItsOwnerWhenEditedAndStored() async throws {
        let store = NesticStore(defaults: isolatedDefaults(), restoreSession: false)
        store.enterDemo(reset: true)
        let subject = try #require(store.subjects.first)
        try await store.createTracker(subjectID: subject.id, name: "Private check-in", valueType: .none, isPrivate: true)
        let tracker = try #require(store.trackers.first { $0.name == "Private check-in" })
        #expect(tracker.isPrivate)
        #expect(tracker.privateOwnerId == store.currentUser?.id)
        try await store.updateTracker(tracker, name: "Private update", valueType: .none)
        let edited = try #require(store.trackers.first { $0.id == tracker.id })
        #expect(edited.privateOwnerId == tracker.privateOwnerId)
        let reader = UUID()
        try await store.setTrackerSharing(edited, members: [reader])
        let selected = try #require(store.trackers.first { $0.id == edited.id })
        #expect(selected.name == edited.name)
        #expect(selected.allowedMemberIDs == [reader])
        let restored = try NestCoding.decoder().decode(NestTracker.self, from: NestCoding.encoder().encode(selected))
        #expect(restored.isPrivate)
        #expect(restored.allowedMemberIDs == [reader])
        try await store.setTrackerSharing(selected, members: [])
        #expect(store.trackers.first { $0.id == edited.id }?.allowedMemberIDs?.isEmpty == true)
        try await store.createRoutine(name: "Only me routine", targets: [NestRoutineTarget(entityID: subject.id, items: [NestRoutineItem(trackerID: edited.id)])])
        let routine = try #require(store.routines.first { $0.name == "Only me routine" })
        #expect(routine.isPrivate)
        #expect(routine.privateOwnerId == store.currentUser?.id)
        try await store.logRoutine(routine)
        #expect(store.entries.contains { $0.actionId == edited.id })
        try await store.updateRoutine(routine, name: "Edited private routine", targets: routine.targets)
        let saved = try #require(store.routines.first { $0.id == routine.id })
        #expect(saved.privateOwnerId == routine.privateOwnerId)
        let decoded = try NestCoding.decoder().decode(NestRoutine.self, from: NestCoding.encoder().encode(saved))
        #expect(decoded.isPrivate)
        try await store.clearTrackerHistory(edited)
        #expect(!store.entries.contains { $0.actionId == edited.id })
        #expect(store.trackers.contains { $0.id == edited.id })
        #expect(store.subjects.first { $0.id == subject.id }?.pinnedActionIDs.contains(edited.id) == true)
        #expect(store.routines.contains { $0.id == saved.id })
        #expect(store.tracker(id: edited.id)?.privateOwnerId == store.currentUser?.id)
        try await store.logRoutine(saved)
        try await store.deleteRoutine(saved)
        try await store.deleteTracker(edited)
        #expect(!store.trackers.contains { $0.id == tracker.id })
        #expect(store.tracker(id: tracker.id)?.isArchived == true)
        let archivedRoundTrip = try NestCoding.decoder().decode(NestTracker.self, from: NestCoding.encoder().encode(store.tracker(id: tracker.id)!))
        #expect(archivedRoundTrip.isArchived == true)
        #expect(store.entries.contains { $0.actionId == tracker.id })
        try await store.restoreTracker(store.tracker(id: tracker.id)!, subject: subject)
        #expect(store.trackers(for: store.subjects.first { $0.id == subject.id }!).contains { $0.id == tracker.id })
        #expect(store.entries.contains { $0.actionId == tracker.id })
        _ = try await store.log(subjectID: subject.id, trackerID: tracker.id)
        try await store.permanentlyDeleteTracker(store.tracker(id: tracker.id)!)
        #expect(store.tracker(id: tracker.id) == nil)
        #expect(!store.entries.contains { $0.actionId == tracker.id })
        #expect(!store.subjects.contains { $0.pinnedActionIDs.contains(tracker.id) })


    }

    @Test func widgetDetailLinkOpensFormWithoutRecordingAnEmptyEvent() async throws {
        let store = NesticStore(defaults: isolatedDefaults(), restoreSession: false)
        store.enterDemo(reset: true)
        let subject = try #require(store.subjects.first)
        let tracker = try #require(store.trackers(for: subject).first)
        let count = store.entries.count
        let url = try #require(URL(string: "nestic://record?subjectID=\(subject.id.uuidString)&trackerID=\(tracker.id.uuidString)"))
        await store.handleDeepLink(url)
        #expect(store.entries.count == count)
        #expect(store.consumePendingNavigation() == .record(subjectID: subject.id, trackerID: tracker.id))
    }

    @Test func widgetRoutineButtonLogsEverySavedTargetAndPublishesRoutineChoices() async throws {
        let store = NesticStore(defaults: isolatedDefaults(), restoreSession: false)
        store.enterDemo(reset: true)
        let milo = try #require(store.subjects.first { $0.name == "Milo" })
        let home = try #require(store.subjects.first { $0.name == "Home" })
        let meal = try #require(store.trackers(for: milo).first { $0.name == "Meal" })
        let water = try #require(store.trackers(for: home).first { $0.name == "Water plants" })
        try await store.createRoutine(name: "Widget morning", targets: [
            NestRoutineTarget(entityID: milo.id, items: [NestRoutineItem(trackerID: meal.id, valueNumber: 1.5)]),
            NestRoutineTarget(entityID: home.id, items: [NestRoutineItem(trackerID: water.id)])
        ])
        let routine = try #require(store.routines.first { $0.name == "Widget morning" })
        let data = try #require(UserDefaults(suiteName: NesticWidgetBridge.appGroup)?.data(forKey: NesticWidgetBridge.dataKey))
        let payload = try JSONDecoder().decode(NesticWidgetStoreData.self, from: data)
        for subject in [milo, home] {
            let action = try #require(payload.subjects.first { $0.id == subject.id }?.metrics.first { $0.routineID == routine.id })
            #expect(action.routineTrackerCount == 2)
            #expect(action.routineSubjectCount == 2)
            #expect(action.supportsQuickLog == true)
        }
        let oldIDs = Set(store.entries.map(\.id))
        let previous = NesticWidgetActionStore.store
        NesticWidgetActionStore.store = store
        defer { NesticWidgetActionStore.store = previous }
        _ = try await NesticWidgetLogRoutineIntent(subjectID: milo.id, routineID: routine.id).perform()
        let logged = store.entries.filter { !oldIDs.contains($0.id) }
        #expect(logged.count == 2)
        #expect(logged.first { $0.entityId == milo.id && $0.actionId == meal.id }?.valueNumber == 1.5)
        #expect(logged.contains { $0.entityId == home.id && $0.actionId == water.id })
        #expect(Set(logged.map(\.occurredAt)).count == 1)

        // A stale widget selection must fail without creating any events.
        let count = store.entries.count
        try await store.deleteRoutine(routine)
        await #expect(throws: (any Error).self) {
            _ = try await NesticWidgetLogRoutineIntent(subjectID: milo.id, routineID: routine.id).perform()
        }
        #expect(store.entries.count == count)
    }

    @Test func widgetRoutinesRemainDiscoverableWhileAccessIsRestoring() async throws {
        let store = NesticStore(defaults: isolatedDefaults(), restoreSession: false)
        store.enterDemo(reset: true)
        let subject = try #require(store.subjects.first { $0.name == "Milo" })
        let tracker = try #require(store.trackers(for: subject).first { $0.valueType == .none })
        try await store.createRoutine(subjectID: subject.id, name: "Visible routine", items: [NestRoutineItem(trackerID: tracker.id)])
        let routine = try #require(store.routines.first { $0.name == "Visible routine" })
        NesticWidgetBridge.refresh(defaultSubject: subject, subjects: store.subjects, trackers: store.trackers,
                                   entries: store.entries, routines: store.routines, predictions: [:], hasPredictionAccess: false)
        let data = try #require(UserDefaults(suiteName: NesticWidgetBridge.appGroup)?.data(forKey: NesticWidgetBridge.dataKey))
        let payload = try JSONDecoder().decode(NesticWidgetStoreData.self, from: data)
        #expect(payload.hasPredictionAccess == false)
        #expect(payload.subjects.first { $0.id == subject.id }?.metrics.contains { $0.routineID == routine.id } == true)
    }

    private func isolatedDefaults() -> UserDefaults {
        UserDefaults(suiteName: "NesticTests.\(UUID().uuidString)")!
    }

    @Test func demoPersistsLogsAndIsNeverImplicit() async throws {
        let defaults = isolatedDefaults()
        let store = NesticStore(defaults: defaults, restoreSession: false)
        #expect(!store.isAuthenticated)
        #expect(!store.isDemo)
        store.enterDemo(reset: true)
        let milo = try #require(store.subjects.first { $0.name == "Milo" })
        let pee = try #require(store.trackers(for: milo).first { $0.name == "Daily check-in" })
        let initialCount = store.entries.count
        try await store.log(subjectID: milo.id, trackerID: pee.id, note: "Backyard")
        #expect(store.entries.count == initialCount + 1)
        let entryID = try #require(store.entries.first).id
        let reopened = NesticStore(defaults: defaults, restoreSession: false)
        #expect(!reopened.isAuthenticated)
        reopened.enterDemo()
        #expect(reopened.entries.contains { $0.id == entryID && $0.note == "Backyard" })
        #expect(reopened.subjects.first?.id == milo.id)
        try await reopened.deleteEntry(try #require(reopened.entries.first { $0.id == entryID }))
        #expect(!reopened.entries.contains { $0.id == entryID })
    }

    @Test func routineLogsSavedMealAndMedicationValuesTogether() async throws {
        let defaults = isolatedDefaults()
        let store = NesticStore(defaults: defaults, restoreSession: false)
        store.enterDemo(reset: true)
        let milo = try #require(store.subjects.first { $0.name == "Milo" })
        let food = try #require(store.trackers(for: milo).first { $0.name == "Meal" })
        try await store.createTracker(subjectID: milo.id, name: "Morning medicine", valueType: .none,
                                      symbol: "pills.fill", groupName: "Medication")
        try await store.createTracker(subjectID: milo.id, name: "Evening medicine", valueType: .none,
                                      symbol: "pills.fill", groupName: "Medication")
        let morningMedicine = try #require(store.trackers(for: milo).first { $0.name == "Morning medicine" })
        let eveningMedicine = try #require(store.trackers(for: milo).first { $0.name == "Evening medicine" })
        let routineItems = [
            NestRoutineItem(trackerID: food.id, valueNumber: 1.5),
            NestRoutineItem(trackerID: morningMedicine.id),
            NestRoutineItem(trackerID: eveningMedicine.id)
        ]

        try await store.createRoutine(subjectID: milo.id, name: "Morning feeding", items: routineItems)
        let routine = try #require(store.routines(for: milo).first)
        let initialCount = store.entries(for: milo).count
        let recordedAt = Date().addingTimeInterval(-120)
        try await store.logRoutine(routine, date: recordedAt)

        #expect(store.entries(for: milo).count == initialCount + 3)
        #expect(store.latestEntry(for: food, subject: milo)?.valueNumber == 1.5)
        #expect(store.entries(for: milo).filter { $0.occurredAt == recordedAt }.count == 3)

        let reopened = NesticStore(defaults: defaults, restoreSession: false)
        reopened.enterDemo()
        let reopenedMilo = try #require(reopened.subjects.first { $0.name == "Milo" })
        #expect(reopened.routines(for: reopenedMilo).first?.name == "Morning feeding")
        #expect(reopened.entries(for: reopenedMilo).filter { abs($0.occurredAt.timeIntervalSince(recordedAt)) < 1 }.count == 3)
    }

    @Test func nestRoutineLogsTrackersForMultipleEntities() async throws {
        let store = NesticStore(defaults: isolatedDefaults(), restoreSession: false)
        store.enterDemo(reset: true)
        let milo = try #require(store.subjects.first { $0.name == "Milo" })
        let home = try #require(store.subjects.first { $0.name == "Home" })
        let pee = try #require(store.trackers(for: milo).first { $0.name == "Daily check-in" })
        let water = try #require(store.trackers(for: home).first { $0.name == "Water plants" })

        try await store.createRoutine(name: "Morning reset", targets: [
            NestRoutineTarget(entityID: milo.id, items: [NestRoutineItem(trackerID: pee.id)]),
            NestRoutineTarget(entityID: home.id, items: [NestRoutineItem(trackerID: water.id)])
        ])
        let routine = try #require(store.routines.first)
        let recordedAt = Date().addingTimeInterval(-120)
        try await store.logRoutine(routine, date: recordedAt)

        #expect(store.entries(for: milo).contains { $0.actionId == pee.id && $0.occurredAt == recordedAt })
        #expect(store.entries(for: home).contains { $0.actionId == water.id && $0.occurredAt == recordedAt })
        #expect(store.routines(for: milo).count == 1)
        #expect(store.routines(for: home).count == 1)

        try await store.deleteSubject(home)
        #expect(store.routines(for: milo).count == 1)
        #expect(store.routines.first?.targets.map(\.entityID) == [milo.id])
    }

    @Test func customSubjectsAndEveryValueTypeWork() async throws {
        let store = NesticStore(defaults: isolatedDefaults(), restoreSession: false)
        store.enterDemo(reset: true)
        try await store.createSubject(name: "Garden", kind: .thing, emoji: "🌱", trackerTemplates: [])
        let garden = try #require(store.subjects.first { $0.name == "Garden" })
        for type in NestValueType.allCases {
            try await store.createTracker(subjectID: garden.id, name: "Test \(type.rawValue)", valueType: type, unit: type == .number ? "liters" : nil)
            let tracker = try #require(store.trackers.first { $0.name == "Test \(type.rawValue)" })
            try await store.log(subjectID: garden.id, trackerID: tracker.id,
                                number: type == .number ? 2.5 : nil,
                                text: type == .text || type == .health ? "New leaves" : nil,
                                bool: type == .boolean ? false : nil,
                                json: type == .json ? ["soil": "damp"] : nil)
        }
        #expect(store.entries(for: garden).count == NestValueType.allCases.count)
        #expect(store.entries(for: garden).contains { $0.valueBool == false })
        #expect(store.entries(for: garden).contains { $0.displayValue(unit: "liters") == "2.5 liters" })
    }

    @Test func eventMetadataMarksAccidentsAndControlsPredictions() async throws {
        let store = NesticStore(defaults: isolatedDefaults(), restoreSession: false)
        store.enterDemo(reset: true)
        let milo = try #require(store.subjects.first { $0.name == "Milo" })
        let pee = try #require(store.trackers(for: milo).first { $0.name == "Daily check-in" })

        try await store.log(subjectID: milo.id, trackerID: pee.id, note: "Unexpected timing",
                            wasAccident: true, includeInPredictions: false)
        let accident = try #require(store.entries.first { $0.note == "Unexpected timing" })
        #expect(accident.isAccident)
        #expect(!accident.shouldIncludeInPredictions)

        let nestID = UUID()
        let subjectID = UUID()
        let target = NestTracker(id: UUID(), nestId: nestID, name: "Check-in", valueType: .none)
        let subject = NestSubject(id: subjectID, nestId: nestID, name: "Project", kind: .thing, emoji: "📌")
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let excludedEntries = [
            NestEntry(id: UUID(), nestId: nestID, entityId: subjectID, actionId: target.id,
                      occurredAt: now.addingTimeInterval(-24 * 3600), includeInPredictions: false),
            NestEntry(id: UUID(), nestId: nestID, entityId: subjectID, actionId: target.id,
                      occurredAt: now.addingTimeInterval(-12 * 3600), includeInPredictions: false)
        ]
        #expect(EventPredictionEngine.predict(
            subject: subject, trackers: [target], entries: excludedEntries,
            preferences: NestPredictionPreferences(targetTrackerIDs: [target.id]), now: now
        ) == nil)
    }

    @Test func quietHoursSupportMidnightAndConfidenceThreshold() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let period = NestQuietHoursPeriod(startMinute: 23 * 60, endMinute: 6 * 60)
        let lateNight = calendar.date(from: DateComponents(year: 2026, month: 10, day: 4, hour: 23, minute: 30))!
        let earlyMorning = calendar.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 5, minute: 59))!
        let daytime = calendar.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 12))!
        let preferences = NestQuietHoursPreferences(periods: [period], confidenceThresholdPercent: 80)

        #expect(period.contains(lateNight, calendar: calendar))
        #expect(period.contains(earlyMorning, calendar: calendar))
        #expect(!period.contains(daytime, calendar: calendar))
        #expect(preferences.shouldSuppress(predictedAt: lateNight, confidence: 0.79, calendar: calendar))
        #expect(!preferences.shouldSuppress(predictedAt: lateNight, confidence: 0.80, calendar: calendar))
        #expect(!preferences.shouldSuppress(predictedAt: daytime, confidence: 0.20, calendar: calendar))

        let nextModeledOccurrence = preferences.nextForecastDate(
            predictedAt: lateNight, confidence: 0.79, intervalHours: 8, calendar: calendar
        )
        #expect(nextModeledOccurrence == calendar.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 7, minute: 30)))
        #expect(preferences.nextForecastDate(
            predictedAt: lateNight, confidence: 0.80, intervalHours: 8, calendar: calendar
        ) == lateNight)

        let overlapping = NestQuietHoursPreferences(
            periods: [
                NestQuietHoursPeriod(startMinute: 23 * 60, endMinute: 2 * 60),
                NestQuietHoursPeriod(startMinute: 1 * 60, endMinute: 7 * 60)
            ], confidenceThresholdPercent: 80
        )
        #expect(overlapping.nextForecastDate(
            predictedAt: lateNight, confidence: 0.20, intervalHours: 2.5, calendar: calendar
        ) == calendar.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 7)))
    }

    @Test func quietHoursPersistPerDemoNest() async throws {
        let defaults = isolatedDefaults()
        let store = NesticStore(defaults: defaults, restoreSession: false)
        store.enterDemo(reset: true)
        let period = NestQuietHoursPeriod(startMinute: 22 * 60, endMinute: 7 * 60)
        store.updateQuietHours(periods: [period], confidenceThresholdPercent: 90)

        let reopened = NesticStore(defaults: defaults, restoreSession: false)
        reopened.enterDemo()
        #expect(reopened.quietHoursPreferences.periods == [period])
        #expect(reopened.quietHoursPreferences.confidenceThresholdPercent == 90)
    }

    @Test func trackersCanBeEditedAndDeletedWithTheirHistory() async throws {
        let store = NesticStore(defaults: isolatedDefaults(), restoreSession: false)
        store.enterDemo(reset: true)
        let milo = try #require(store.subjects.first { $0.name == "Milo" })
        let pee = try #require(store.trackers(for: milo).first { $0.name == "Daily check-in" })
        try await store.log(subjectID: milo.id, trackerID: pee.id, date: Date(timeIntervalSince1970: 1_700_000_000))
        try await store.updateTracker(pee, name: "Bathroom", valueType: .boolean)
        let renamed = try #require(store.trackers.first { $0.id == pee.id })
        #expect(renamed.name == "Bathroom")
        #expect(renamed.valueType == .boolean)
        try await store.updateTracker(renamed, name: "Medicine", valueType: .boolean, groupName: "Medication")
        #expect(store.trackers.first { $0.id == pee.id }?.groupName == "Medication")
        try await store.updateTracker(store.trackers.first { $0.id == pee.id }!, name: "Medicine", valueType: .boolean, groupName: nil)
        #expect(store.trackers.first { $0.id == pee.id }?.groupName == nil)
        try await store.deleteTracker(renamed)
        #expect(!store.trackers.contains { $0.id == pee.id })
        #expect(store.entries.contains { $0.actionId == pee.id })
        #expect(store.tracker(id: pee.id)?.isArchived == true)
        #expect(!store.subjects.contains { $0.pinnedActionIDs.contains(pee.id) })
    }

    @Test func subjectsCanBeDeletedWithTheirHistoryAndRoutines() async throws {
        let store = NesticStore(defaults: isolatedDefaults(), restoreSession: false)
        store.enterDemo(reset: true)
        let milo = try #require(store.subjects.first { $0.name == "Milo" })
        let pee = try #require(store.trackers(for: milo).first { $0.name == "Daily check-in" })
        try await store.log(subjectID: milo.id, trackerID: pee.id)
        try await store.createRoutine(subjectID: milo.id, name: "Morning care", items: [NestRoutineItem(trackerID: pee.id)])
        #expect(!store.entries(for: milo).isEmpty)
        #expect(!store.routines(for: milo).isEmpty)

        try await store.deleteSubject(milo)

        #expect(!store.subjects.contains { $0.id == milo.id })
        #expect(store.entries.allSatisfy { $0.entityId != milo.id })
        #expect(store.routines.allSatisfy { $0.subjectID != milo.id })
        #expect(store.trackers.contains { $0.id == pee.id })
    }

    @Test func nestSwitchingKeepsDataIsolated() async throws {
        let store = NesticStore(defaults: isolatedDefaults(), restoreSession: false)
        store.enterDemo(reset: true)
        let original = try #require(store.selectedNest)
        let originalCount = store.entries.count
        try await store.createNest(name: "Weekend crew")
        #expect(store.selectedNest?.name == "Weekend crew")
        #expect(store.entries.isEmpty)
        #expect(store.subjects.isEmpty)
        try await store.addMember(email: "friend@example.com")
        #expect(store.members.count == 2)
        try await store.selectNest(original)
        #expect(store.entries.count == originalCount)
        #expect(!store.members.contains { $0.email == "friend@example.com" })
    }

    @Test func resetDemoClearsEditsAndSignOutClearsVisibleData() async throws {
        let store = NesticStore(defaults: isolatedDefaults(), restoreSession: false)
        store.enterDemo(reset: true)
        try await store.createNest(name: "Temporary")
        store.enterDemo(reset: true)
        #expect(store.nests.count == 1)
        #expect(!store.nests.contains { $0.name == "Temporary" })
        store.signOut()
        #expect(store.currentUser == nil)
        #expect(store.subjects.isEmpty && store.entries.isEmpty && store.members.isEmpty)
        #expect(store.selectedNestID == nil)
    }

    @Test func valueValidationRejectsWrongAndMissingValues() throws {
        #expect(throws: (any Error).self) {
            try NesticStore.validateValue(type: .number, number: .infinity, text: nil, bool: nil, json: nil)
        }
        #expect(throws: (any Error).self) {
            try NesticStore.validateValue(type: .none, number: 1, text: nil, bool: nil, json: nil)
        }
        #expect(throws: (any Error).self) {
            try NesticStore.validateValue(type: .text, number: nil, text: "  ", bool: nil, json: nil)
        }
        #expect(throws: (any Error).self) {
            try NesticStore.validateValue(type: .json, number: nil, text: nil, bool: nil, json: [:])
        }
        #expect(throws: (any Error).self) {
            try NesticStore.validateValue(type: .health, number: nil, text: "  ", bool: nil, json: nil)
        }
        try NesticStore.validateValue(type: .health, number: nil, text: "Limping after a walk", bool: nil, json: nil)
        try NesticStore.validateValue(type: .boolean, number: nil, text: nil, bool: false, json: nil)
    }

    @Test func healthEventsKeepOnsetAndResolutionTogether() async throws {
        let store = NesticStore(defaults: isolatedDefaults(), restoreSession: false)
        store.enterDemo(reset: true)
        let milo = try #require(store.subjects.first { $0.name == "Milo" })
        try await store.createTracker(subjectID: milo.id, name: "Limp", valueType: .health)
        let tracker = try #require(store.trackers(for: milo).first { $0.name == "Limp" })
        let onset = Date(timeIntervalSinceNow: -3_600)
        let entry = try await store.log(subjectID: milo.id, trackerID: tracker.id, date: onset,
                                        text: "Limping after a walk")
        #expect(entry.resolvedAt == nil)
        let resolution = onset.addingTimeInterval(1_800)
        let resolved = try await store.resolveHealthEntry(entry, at: resolution, note: "Walking normally")
        #expect(resolved.occurredAt == onset)
        #expect(resolved.resolvedAt == resolution)
        #expect(resolved.resolutionNote == "Walking normally")
        let reopened = try await store.reopenHealthEntry(resolved)
        #expect(reopened.resolvedAt == nil)
        #expect(reopened.resolutionNote == nil)
    }

    @Test func bathroomPredictionUsesOnlySelectedSignals() throws {
        let nestID = UUID()
        let subjectID = UUID()
        let pee = NestTracker(id: UUID(), nestId: nestID, name: "Pee", valueType: .none)
        let food = NestTracker(id: UUID(), nestId: nestID, name: "Food", valueType: .number, unit: "cups")
        let walk = NestTracker(id: UUID(), nestId: nestID, name: "Walk", valueType: .number, unit: "minutes")
        let subject = NestSubject(id: subjectID, nestId: nestID, name: "Milo", kind: .pet, emoji: "🐶",
                                  pinnedActionIDs: [pee.id, food.id, walk.id])
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var entries: [NestEntry] = []
        for index in 0..<4 {
            let pottyDate = now.addingTimeInterval(Double(index - 4) * 12 * 3600)
            entries.append(.init(id: UUID(), nestId: nestID, entityId: subjectID, actionId: pee.id, occurredAt: pottyDate))
            entries.append(.init(id: UUID(), nestId: nestID, entityId: subjectID, actionId: food.id,
                                 occurredAt: pottyDate.addingTimeInterval(-3600), valueNumber: 1 + Double(index) * 0.25))
            entries.append(.init(id: UUID(), nestId: nestID, entityId: subjectID, actionId: walk.id,
                                 occurredAt: pottyDate.addingTimeInterval(-1800), valueNumber: 20))
        }
        let result = try #require(BathroomPredictionEngine.predict(
            subject: subject,
            trackers: [pee, food, walk],
            entries: entries,
            preferences: NestPredictionPreferences(inputTrackerIDs: [food.id], targetTrackerIDs: [pee.id]),
            now: now
        ))
        #expect(result.sampleCount == 3)
        #expect(result.targetNames == ["Pee"])
        #expect(result.inputNames == ["Food"])
        #expect(result.learningSignals.map(\.trackerName) == ["Food"])
        #expect(result.learningSignals.first?.updatesInLast72Hours == 4)
        #expect(result.learningSignals.first?.latestLearnedValue != nil)
        #expect(result.predictedAt > now)
        #expect(result.confidence > 0)
    }

    @Test func predictionDefaultsToEveryNonTargetTracker() throws {
        let nestID = UUID()
        let subjectID = UUID()
        let pee = NestTracker(id: UUID(), nestId: nestID, name: "Pee", valueType: .none)
        let food = NestTracker(id: UUID(), nestId: nestID, name: "Food", valueType: .number)
        let walk = NestTracker(id: UUID(), nestId: nestID, name: "Walk", valueType: .none)
        let subject = NestSubject(id: subjectID, nestId: nestID, name: "Milo", kind: .pet, emoji: "🐶",
                                  pinnedActionIDs: [pee.id, food.id, walk.id])
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var entries: [NestEntry] = []
        for index in 0..<4 {
            let pottyDate = now.addingTimeInterval(Double(index - 4) * 12 * 3600)
            entries.append(.init(id: UUID(), nestId: nestID, entityId: subjectID, actionId: pee.id, occurredAt: pottyDate))
            entries.append(.init(id: UUID(), nestId: nestID, entityId: subjectID, actionId: food.id,
                                 occurredAt: pottyDate.addingTimeInterval(-3600), valueNumber: 1))
            entries.append(.init(id: UUID(), nestId: nestID, entityId: subjectID, actionId: walk.id,
                                 occurredAt: pottyDate.addingTimeInterval(-1800)))
        }
        let result = try #require(BathroomPredictionEngine.predict(
            subject: subject,
            trackers: [pee, food, walk],
            entries: entries,
            preferences: NestPredictionPreferences(targetTrackerIDs: [pee.id]),
            now: now
        ))
        #expect(result.inputNames == ["Food", "Walk"])
    }

    @Test func selectedForecastTargetsAreModeledIndependently() throws {
        let nestID = UUID()
        let subjectID = UUID()
        let pee = NestTracker(id: UUID(), nestId: nestID, name: "Pee", valueType: .none)
        let poop = NestTracker(id: UUID(), nestId: nestID, name: "Poop", valueType: .none)
        let food = NestTracker(id: UUID(), nestId: nestID, name: "Food", valueType: .number, unit: "cups")
        let subject = NestSubject(id: subjectID, nestId: nestID, name: "Milo", kind: .pet, emoji: "🐶")
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        var entries: [NestEntry] = []
        for index in 1...4 {
            let peeDate = now.addingTimeInterval(Double(index - 5) * 8 * 3600)
            let poopDate = now.addingTimeInterval(Double(index - 5) * 24 * 3600)
            entries.append(.init(id: UUID(), nestId: nestID, entityId: subjectID, actionId: pee.id, occurredAt: peeDate))
            entries.append(.init(id: UUID(), nestId: nestID, entityId: subjectID, actionId: poop.id, occurredAt: poopDate))
            entries.append(.init(id: UUID(), nestId: nestID, entityId: subjectID, actionId: food.id,
                                 occurredAt: peeDate.addingTimeInterval(-3600), valueNumber: 1))
        }
        let preferences = NestPredictionPreferences(targetTrackerIDs: [pee.id, poop.id])
        let peePrediction = try #require(EventPredictionEngine.predict(
            subject: subject, trackers: [pee, poop, food], entries: entries,
            preferences: preferences, targetTrackerIDs: [pee.id], now: now
        ))
        let poopPrediction = try #require(EventPredictionEngine.predict(
            subject: subject, trackers: [pee, poop, food], entries: entries,
            preferences: preferences, targetTrackerIDs: [poop.id], now: now
        ))

        #expect(peePrediction.targetNames == ["Pee"])
        #expect(poopPrediction.targetNames == ["Poop"])
        #expect(peePrediction.sampleCount == 3)
        #expect(poopPrediction.sampleCount == 3)
        #expect(peePrediction.inputNames == ["Food"])
        #expect(poopPrediction.inputNames == ["Food"])
        #expect(peePrediction.lastEventAt != poopPrediction.lastEventAt)
    }

    @Test func forecastIntervalIsAnchoredToTheLastMatchingEvent() throws {
        let nestID = UUID()
        let subjectID = UUID()
        let pee = NestTracker(id: UUID(), nestId: nestID, name: "Pee", valueType: .none)
        let subject = NestSubject(id: subjectID, nestId: nestID, name: "Milo", kind: .pet, emoji: "🐶")
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let firstPee = now.addingTimeInterval(-16 * 3600)
        let lastPee = now.addingTimeInterval(-6 * 3600)
        let prediction = try #require(EventPredictionEngine.predict(
            subject: subject,
            trackers: [pee],
            entries: [
                .init(id: UUID(), nestId: nestID, entityId: subjectID, actionId: pee.id, occurredAt: firstPee),
                .init(id: UUID(), nestId: nestID, entityId: subjectID, actionId: pee.id, occurredAt: lastPee)
            ],
            preferences: NestPredictionPreferences(targetTrackerIDs: [pee.id]),
            now: now
        ))

        #expect(abs(prediction.predictedAt.timeIntervalSince(now) - 4 * 3600) < 0.001)
    }

    @Test func contextualModelUsesSelectedSignalsBeforeValidation() throws {
        let nestID = UUID()
        let subjectID = UUID()
        let pee = NestTracker(id: UUID(), nestId: nestID, name: "Pee", valueType: .none)
        let food = NestTracker(id: UUID(), nestId: nestID, name: "Food", valueType: .number, unit: "cups")
        let subject = NestSubject(id: subjectID, nestId: nestID, name: "Milo", kind: .pet, emoji: "🐶")
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let peeOffsets: [Double] = [-43, -35, -25, -13, -6]
        let peeEntries = (0..<peeOffsets.count).map { index in
            NestEntry(id: UUID(), nestId: nestID, entityId: subjectID, actionId: pee.id,
                      occurredAt: now.addingTimeInterval(peeOffsets[index] * 3600))
        }
        let entries = peeEntries + (0..<peeOffsets.count).map { index in
            NestEntry(id: UUID(), nestId: nestID, entityId: subjectID, actionId: food.id,
                      occurredAt: now.addingTimeInterval((peeOffsets[index] + 4) * 3600),
                      valueNumber: Double(index + 1))
        }
        let lastEventAt = try #require(peeEntries.last?.occurredAt)
        var feedback: [ForecastSnapshot] = []
        for index in 0..<3 {
            feedback.append(ForecastSnapshot(
                id: UUID(), subjectID: subjectID, targetTrackerID: pee.id,
                lastEventAt: lastEventAt.addingTimeInterval(Double(index - 3) * 8 * 3600),
                createdAt: now.addingTimeInterval(Double(index - 3) * 24 * 3600),
                selectedModel: .baseline,
                selectedPredictedAt: now,
                baselinePredictedAt: now,
                contextualPredictedAt: now,
                actualEventAt: now,
                evaluatedAt: now.addingTimeInterval(Double(index - 3) * 24 * 3600),
                baselineErrorHours: 4,
                contextualErrorHours: 1,
                selectedErrorHours: 4
            ))
        }

        let prediction = try #require(EventPredictionEngine.predict(
            subject: subject,
            trackers: [pee, food],
            entries: entries,
            preferences: NestPredictionPreferences(inputTrackerIDs: [food.id], targetTrackerIDs: [pee.id]),
            feedback: feedback,
            now: now
        ))

        let diagnostics = try #require(prediction.diagnostics)
        let rawInterval = try #require(diagnostics.rawContextHours)
        #expect(abs(diagnostics.contributions.reduce(0) { $0 + $1.hours } - rawInterval) < 0.000001)
        #expect(diagnostics.contributions.map(\.name) == ["Model intercept", "Food", "Time of day + weekday"])
        #expect(abs(diagnostics.medianHours - 9) < 0.000001)
        #expect(abs(diagnostics.meanHours - 9.25) < 0.000001)
        #expect(diagnostics.minimumHours == 7)
        #expect(diagnostics.maximumHours == 12)
        #expect(diagnostics.excludedIntervalCount == 0)
        #expect(abs(prediction.intervalHours - min(72, max(0.25, rawInterval))) < 0.000001)
        #expect(prediction.model == ForecastModelKind.contextual)
        #expect(prediction.inputNames == ["Food"])
        #expect(prediction.contextualPredictedAt != prediction.baselinePredictedAt)
        #expect(prediction.validationSampleCount == 3)
        #expect(prediction.expectedErrorHours != nil)
        #expect(prediction.predictionWindowHours >= 1)
    }

    @Test func contextualModelFallsBackToBaselineWhenItDoesNotWinMeaningfully() throws {
        let nestID = UUID()
        let subjectID = UUID()
        let pee = NestTracker(id: UUID(), nestId: nestID, name: "Pee", valueType: .none)
        let subject = NestSubject(id: subjectID, nestId: nestID, name: "Milo", kind: .pet, emoji: "🐶")
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let entries = (0..<5).map { index in
            NestEntry(id: UUID(), nestId: nestID, entityId: subjectID, actionId: pee.id,
                      occurredAt: now.addingTimeInterval(Double(index - 5) * 8 * 3600))
        }
        let lastEventAt = try #require(entries.max(by: { $0.occurredAt < $1.occurredAt })).occurredAt
        var feedback: [ForecastSnapshot] = []
        for index in 0..<3 {
            feedback.append(ForecastSnapshot(
                id: UUID(), subjectID: subjectID, targetTrackerID: pee.id,
                lastEventAt: lastEventAt.addingTimeInterval(Double(index - 3) * 8 * 3600),
                createdAt: now.addingTimeInterval(Double(index - 3) * 24 * 3600),
                selectedModel: .contextual,
                selectedPredictedAt: now,
                baselinePredictedAt: now,
                contextualPredictedAt: now,
                actualEventAt: now,
                evaluatedAt: now.addingTimeInterval(Double(index - 3) * 24 * 3600),
                baselineErrorHours: 1,
                contextualErrorHours: 1.2,
                selectedErrorHours: 1.2
            ))
        }

        let prediction = try #require(EventPredictionEngine.predict(
            subject: subject,
            trackers: [pee],
            entries: entries,
            preferences: NestPredictionPreferences(targetTrackerIDs: [pee.id]),
            feedback: feedback,
            now: now
        ))

        #expect(prediction.model == ForecastModelKind.baseline)
    }

    @Test func forecastsReuseWorkUntilTimeOrInputsChange() async throws {
        let store = NesticStore(defaults: isolatedDefaults(), restoreSession: false)
        store.enterDemo(reset: true)
        let subject = try #require(store.subjects.first { $0.name == "Milo" })
        let target = try #require(store.trackers(for: subject).first { $0.name == "Daily check-in" })
        store.updatePredictionPreferences(for: subject, inputTrackerIDs: [], targetTrackerIDs: [target.id])
        let now = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970 / 60) * 60 + 130)
        let first = try #require(store.predictions(for: subject, now: now).first)
        let computedAt = try #require(first.diagnostics?.computedAt)
        #expect(computedAt == now)
        for second in 1...20 {
            #expect(store.predictions(for: subject, now: now.addingTimeInterval(Double(second))).first == first)
        }
        store.recordForecasts(for: subject, now: now.addingTimeInterval(21))
        #expect(store.predictions(for: subject, now: now.addingTimeInterval(22)).first == first)
        let nextMinute = try #require(store.predictions(for: subject, now: now.addingTimeInterval(60)).first)
        #expect(nextMinute.diagnostics?.computedAt == now.addingTimeInterval(60))

        let loggedAt = Date()
        let count = store.entries(for: subject).count
        try await store.log(subjectID: subject.id, trackerID: target.id, date: loggedAt)
        let afterLog = try #require(store.predictions(for: subject, now: now).first)
        #expect(afterLog.lastEventAt == loggedAt)
        #expect(store.entries(for: subject).count == count + 1)
        #expect(store.latestEntry(for: target, subject: subject)?.occurredAt == loggedAt)
        #expect(afterLog.validationSampleCount > first.validationSampleCount)

        store.updatePredictionPreferences(for: subject, inputTrackerIDs: [], targetTrackerIDs: [UUID()])
        #expect(store.predictions(for: subject, now: now).isEmpty)
        store.signOut()
        #expect(store.entries(for: subject).isEmpty)
        #expect(store.subject(id: subject.id) == nil)
        #expect(store.tracker(id: target.id) == nil)
        #expect(store.predictions(for: subject, now: now).isEmpty)
    }

    @Test func quietHoursInvalidateCachedForecasts() throws {
        let store = NesticStore(defaults: isolatedDefaults(), restoreSession: false)
        store.enterDemo(reset: true)
        let subject = try #require(store.subjects.first { $0.name == "Milo" })
        let target = try #require(store.trackers(for: subject).first { $0.name == "Daily check-in" })
        store.updatePredictionPreferences(for: subject, inputTrackerIDs: [], targetTrackerIDs: [target.id])
        let now = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970 / 60) * 60 + 130)
        _ = store.predictions(for: subject, now: now)
        store.updateQuietHours(periods: [], confidenceThresholdPercent: 90)
        let refreshed = try #require(store.predictions(for: subject, now: now.addingTimeInterval(1)).first)
        #expect(refreshed.diagnostics?.computedAt == now.addingTimeInterval(1))
    }

    @Test func predictionPreferencesPersistPerDemoNest() async throws {
        let defaults = isolatedDefaults()
        let store = NesticStore(defaults: defaults, restoreSession: false)
        store.enterDemo(reset: true)
        let milo = try #require(store.subjects.first { $0.name == "Milo" })
        let pee = try #require(store.trackers(for: milo).first { $0.name == "Daily check-in" })
        let food = try #require(store.trackers(for: milo).first { $0.name == "Meal" })
        store.updatePredictionPreferences(for: milo, inputTrackerIDs: [food.id], targetTrackerIDs: [pee.id])

        let reopened = NesticStore(defaults: defaults, restoreSession: false)
        reopened.enterDemo()
        let reopenedMilo = try #require(reopened.subjects.first { $0.name == "Milo" })
        #expect(reopened.preferences(for: reopenedMilo).inputTrackerIDs == [food.id])
        #expect(reopened.preferences(for: reopenedMilo).targetTrackerIDs == [pee.id])
    }

    @Test func forecastOutcomeIsScoredAndSurvivesRelaunch() async throws {
        let defaults = isolatedDefaults()
        let store = NesticStore(defaults: defaults, restoreSession: false)
        store.enterDemo(reset: true)
        let milo = try #require(store.subjects.first { $0.name == "Milo" })
        let pee = try #require(store.trackers(for: milo).first { $0.name == "Daily check-in" })
        store.updatePredictionPreferences(for: milo, inputTrackerIDs: [], targetTrackerIDs: [pee.id])

        store.recordForecasts(for: milo)
        try await store.log(subjectID: milo.id, trackerID: pee.id, date: Date())

        let reopened = NesticStore(defaults: defaults, restoreSession: false)
        reopened.enterDemo()
        let reopenedMilo = try #require(reopened.subjects.first { $0.id == milo.id })
        let prediction = try #require(reopened.predictions(for: reopenedMilo).first)

        #expect(prediction.validationSampleCount == 1)
        #expect(prediction.expectedErrorHours != nil)
    }

    @Test func datesDecodeBothServerFormatsAndValuesRoundTrip() throws {
        let id = UUID()
        for timestamp in ["2026-09-08T12:34:56Z", "2026-09-08T12:34:56.123Z"] {
            let json = """
            {"id":"\(id)","nestId":"\(id)","entityId":"\(id)","actionId":"\(id)","occurredAt":"\(timestamp)","valueBool":false,"valueJSON":{"detail":"test"}}
            """
            let event = try NestCoding.decoder().decode(NestEntry.self, from: Data(json.utf8))
            #expect(event.valueBool == false)
            #expect(event.valueJSON == ["detail": "test"])
            let roundTrip = try NestCoding.decoder().decode(NestEntry.self, from: NestCoding.encoder().encode(event))
            #expect(roundTrip.id == id)
            #expect(roundTrip.valueBool == false)
        }
    }

    @Test func amountParsingRejectsPartialInputAndSupportsDecimalLocales() {
        #expect(NestCoding.parseAmount("12abc", locale: Locale(identifier: "en_US")) == nil)
        #expect(NestCoding.parseAmount("1.2.3", locale: Locale(identifier: "en_US")) == nil)
        #expect(NestCoding.parseAmount(" 2.5 ", locale: Locale(identifier: "en_US")) == 2.5)
        #expect(NestCoding.parseAmount("2,5", locale: Locale(identifier: "de_DE")) == 2.5)
        #expect(NestCoding.parseAmount("0", locale: Locale(identifier: "en_US")) == 0)
    }

    @Test func serverNormalizationAndCacheNamespaces() throws {
        #expect(try NestCoding.validatedServer(" HTTPS://API.NESTIC-APP.COM/ ") == "https://api.nestic-app.com")
        #expect(throws: (any Error).self) { try NestCoding.validatedServer("ftp://example.com") }
        #expect(throws: (any Error).self) { try NestCoding.validatedServer("https://user:password@example.com") }
        #expect(throws: (any Error).self) { try NestCoding.validatedServer("https://example.com?token=secret") }
        #expect(NestCoding.serverKey("https://one.example") != NestCoding.serverKey("https://two.example"))
    }
}
