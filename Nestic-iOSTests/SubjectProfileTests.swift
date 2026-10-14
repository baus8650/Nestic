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
