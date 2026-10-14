import Foundation
import Testing
@testable import Nestic_iOS

struct SubjectProfileTests {
    @Test func optionalDetailsCanBeAddedAndRemovedWithoutLosingOtherMetadata() throws {
        var draft = NesticSubjectProfileDraft()
        draft.hasBirthday = true
        draft.birthday = try #require(NesticSubjectProfileDraft.formatter().date(from: "2000-02-29"))
        draft.unit = "lb"; draft.weight = "100"
        let added = try draft.metadata(merging: ["emoji": "🐶", "custom": "keep"])
        #expect(added["birthday"] == "2000-02-29")
        #expect(abs(try #require(added["weightKg"].flatMap(Double.init)) - 45.359237) < 1e-8)
        draft.hasBirthday = false; draft.weight = ""
        let removed = try draft.metadata(merging: added)
        #expect(removed["birthday"] == nil && removed["weightKg"] == nil && removed["weightUnit"] == nil)
        #expect(removed["emoji"] == "🐶" && removed["custom"] == "keep")
    }
    @Test func invalidWeightsAndFutureBirthdaysAreRejected() {
        for value in ["0", "-1", "NaN", "Infinity", "abc"] {
            var draft = NesticSubjectProfileDraft(); draft.weight = value
            #expect(throws: (any Error).self) { try draft.metadata(merging: [:]) }
        }
        var draft = NesticSubjectProfileDraft(); draft.hasBirthday = true
        draft.birthday = Date().addingTimeInterval(86400 * 10)
        #expect(throws: (any Error).self) { try draft.metadata(merging: [:]) }
    }
    @Test func changingWeightUnitsPreservesTheQuantity() throws {
        var draft = NesticSubjectProfileDraft(); draft.unit = "lb"; draft.weight = "100"
        draft.unit = "kg"; draft.changeUnit(from: "lb")
        #expect(abs(try #require(Double(draft.weight)) - 45.359237) < 0.0001)
        draft.unit = "lb"; draft.changeUnit(from: "kg")
        #expect(abs(try #require(Double(draft.weight)) - 100) < 0.001)
    }
}

struct ForecastProfileTests {
    func subject(_ metadata: [String: String]) -> NestSubject {
        NestSubject(id: UUID(), nestId: UUID(), name: "Milo", kind: .pet, emoji: "🐶", pinnedActionIDs: [], metadata: metadata)
    }
    @Test func oldPreferencesDecodeWithProfileInputsOff() throws {
        let preferences = try JSONDecoder().decode(NestPredictionPreferences.self, from: Data("{}".utf8))
        #expect(!preferences.includeAge && !preferences.includeWeight)
    }
    @Test func weightsAreDatedAndClearingDoesNotReviveEarlierWeight() {
        let model = ForecastProfileInputs(subject: subject(["weightHistoryJSON": "[{\"recordedAt\":100,\"weightKg\":10},{\"recordedAt\":200,\"weightKg\":20},{\"recordedAt\":300}]"]), preferences: .init(includeWeight: true), dates: [150,210,250].map { Date(timeIntervalSince1970: $0) }, now: Date(timeIntervalSince1970: 250))
        #expect(model.names == ["Subject weight"])
        #expect(model.value("Subject weight", at: Date(timeIntervalSince1970: 99)) == nil)
        #expect(model.value("Subject weight", at: Date(timeIntervalSince1970: 150)) == 10)
        #expect(model.value("Subject weight", at: Date(timeIntervalSince1970: 350)) == nil)
        #expect(model.features(at: Date(timeIntervalSince1970: 99)) == [0])
    }
    @Test func constantOrMissingWeightsAreNotReportedAsLearningInputs() {
        let dates = [150,200,250].map { Date(timeIntervalSince1970: $0) }
        let model = ForecastProfileInputs(subject: subject(["weightKg": "10", "weightHistoryJSON": "[{\"recordedAt\":100,\"weightKg\":10}]"]), preferences: .init(includeWeight: true), dates: dates, now: dates.last!)
        #expect(model.names.isEmpty)
    }
    @Test func ageUsesEventDateAndOptionsDefaultOff() throws {
        let birthday = try #require(NesticSubjectProfileDraft.formatter().date(from: "2020-01-01"))
        let dates = [10,20,30].map { birthday.addingTimeInterval(Double($0) * 86400) }
        let s = subject(["birthday": "2020-01-01"])
        let enabled = ForecastProfileInputs(subject: s, preferences: .init(includeAge: true), dates: dates, now: dates.last!)
        #expect(enabled.names == ["Subject age"])
        #expect(enabled.value("Subject age", at: dates[0])! < enabled.value("Subject age", at: dates[2])!)
        #expect(ForecastProfileInputs(subject: s, preferences: .init(), dates: dates, now: dates.last!).names.isEmpty)
    }
}
