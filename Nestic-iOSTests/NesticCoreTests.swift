import Foundation
import Testing
@testable import Nestic_iOS

@MainActor
struct NesticCoreTests {
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
        let pee = try #require(store.trackers(for: milo).first { $0.name == "Pee" })
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
                                text: type == .text ? "New leaves" : nil,
                                bool: type == .boolean ? false : nil,
                                json: type == .json ? ["soil": "damp"] : nil)
        }
        #expect(store.entries(for: garden).count == 5)
        #expect(store.entries(for: garden).contains { $0.valueBool == false })
        #expect(store.entries(for: garden).contains { $0.displayValue(unit: "liters") == "2.5 liters" })
    }

    @Test func trackersCanBeEditedAndDeletedWithTheirHistory() async throws {
        let store = NesticStore(defaults: isolatedDefaults(), restoreSession: false)
        store.enterDemo(reset: true)
        let milo = try #require(store.subjects.first { $0.name == "Milo" })
        let pee = try #require(store.trackers(for: milo).first { $0.name == "Pee" })
        try await store.log(subjectID: milo.id, trackerID: pee.id, date: Date(timeIntervalSince1970: 1_700_000_000))
        try await store.updateTracker(pee, name: "Bathroom", valueType: .boolean)
        let renamed = try #require(store.trackers.first { $0.id == pee.id })
        #expect(renamed.name == "Bathroom")
        #expect(renamed.valueType == .boolean)
        try await store.deleteTracker(renamed)
        #expect(!store.trackers.contains { $0.id == pee.id })
        #expect(!store.entries.contains { $0.actionId == pee.id })
        #expect(!store.subjects.contains { $0.pinnedActionIDs.contains(pee.id) })
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
        try NesticStore.validateValue(type: .boolean, number: nil, text: nil, bool: false, json: nil)
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
        #expect(result.predictedAt > now)
        #expect(result.confidence > 0)
    }

    @Test func predictionPreferencesPersistPerDemoNest() async throws {
        let defaults = isolatedDefaults()
        let store = NesticStore(defaults: defaults, restoreSession: false)
        store.enterDemo(reset: true)
        let milo = try #require(store.subjects.first { $0.name == "Milo" })
        let pee = try #require(store.trackers(for: milo).first { $0.name == "Pee" })
        let food = try #require(store.trackers(for: milo).first { $0.name == "Food" })
        store.updatePredictionPreferences(for: milo, inputTrackerIDs: [food.id], targetTrackerIDs: [pee.id])

        let reopened = NesticStore(defaults: defaults, restoreSession: false)
        reopened.enterDemo()
        let reopenedMilo = try #require(reopened.subjects.first { $0.name == "Milo" })
        #expect(reopened.preferences(for: reopenedMilo).inputTrackerIDs == [food.id])
        #expect(reopened.preferences(for: reopenedMilo).targetTrackerIDs == [pee.id])
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
