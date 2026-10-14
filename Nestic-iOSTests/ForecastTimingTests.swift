import Foundation
import Testing
@testable import Nestic_iOS

struct ForecastTimingTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func result(_ offset: Double, delta: Double, captured: Double = -3600) -> ForecastTimingInsight.Result {
        let actual = now.addingTimeInterval(offset)
        return .init(actualAt: actual, predictedAt: actual.addingTimeInterval(-delta), capturedAt: actual.addingTimeInterval(captured))
    }
    @Test func earlierLaterAndNearPredictionAreSignedCorrectly() throws {
        for (delta, text) in [(-1200.0, "20 min earlier"), (1800.0, "30 min later"), (60.0, "within 5 min")] {
            let row = result(0, delta: delta)
            let insight = try #require(ForecastTimingInsight.build(name: "Walk", results: [row], eventDates: [now], now: now))
            #expect(insight.headline.contains(text))
        }
    }
    @Test func futureRetroactiveAndRemovedEventsCannotBeScored() {
        #expect(ForecastTimingInsight.build(name: "Walk", results: [result(0, delta: 1200, captured: 10)], eventDates: [now], now: now) == nil)
        #expect(ForecastTimingInsight.build(name: "Walk", results: [result(10, delta: 1200)], eventDates: [now.addingTimeInterval(10)], now: now) == nil)
        #expect(ForecastTimingInsight.build(name: "Walk", results: [result(0, delta: 1200)], eventDates: [], now: now) == nil)
    }
    @Test func consistentTrendDeduplicatesEventsAndMixedErrorsDoNotCancel() throws {
        let rows = [-7200.0, -3600.0, 0.0].map { result($0, delta: 1200) }
        let insight = try #require(ForecastTimingInsight.build(name: "Walk", results: rows + [rows[0]], eventDates: rows.map(\.actualAt), now: now))
        #expect(insight.detail.contains("20 min later") && insight.detail.contains("3 scored updates"))
        let mixed = [result(-7200, delta: -3600), result(-3600, delta: 3600), result(0, delta: 0)]
        let variable = try #require(ForecastTimingInsight.build(name: "Walk", results: mixed, eventDates: mixed.map(\.actualAt), now: now))
        #expect(variable.detail.contains("average 40 min") && !variable.detail.contains("tends to happen"))
    }
    @Test func usualTimingUsesOnlyEarlierIntervalsAndDoesNotClaimForecastAccuracy() throws {
        let dates = [-15_000.0, -11_400, -7_800, -4_200, 0].map { now.addingTimeInterval($0) }
        let insight = try #require(ForecastTimingInsight.build(name: "Walk", results: [], eventDates: dates, now: now))
        #expect(insight.headline.contains("10 min later than usual"))
        #expect(insight.detail.contains("3 previous intervals") && insight.detail.contains("no saved forecast"))
        #expect(ForecastTimingInsight.build(name: "Walk", results: [], eventDates: Array(dates.prefix(4)), now: now) == nil)
    }
}
