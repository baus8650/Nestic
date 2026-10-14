import Foundation
import SwiftUI

/// The app and widget use the same daily ranges, including repeated DST hours.
enum NesticTimelineQuietHours {
    static func intervals(on date: Date, periods: [(startMinute: Int, endMinute: Int)], calendar: Calendar = .current) -> [DateInterval] {
        guard let day = calendar.dateInterval(of: .day, for: date), !periods.isEmpty else { return [] }
        var result: [DateInterval] = []
        var beginning: Date?
        var cursor = day.start
        while cursor < day.end {
            let minute = calendar.component(.hour, from: cursor) * 60 + calendar.component(.minute, from: cursor)
            let quiet = periods.contains { period in
                guard (0..<1440).contains(period.startMinute), (0..<1440).contains(period.endMinute),
                      period.startMinute != period.endMinute else { return false }
                return period.startMinute < period.endMinute
                    ? minute >= period.startMinute && minute < period.endMinute
                    : minute >= period.startMinute || minute < period.endMinute
            }
            if quiet, beginning == nil { beginning = cursor }
            if !quiet, let start = beginning {
                result.append(DateInterval(start: start, end: cursor))
                beginning = nil
            }
            cursor = min(day.end, cursor.addingTimeInterval(60))
        }
        if let start = beginning { result.append(DateInterval(start: start, end: day.end)) }
        return result
    }
}

/// Draw in the bar's own bounds, rather than offsetting smaller overlay views.
/// This gives every band an explicit full-bar coordinate space in WidgetKit too.
struct NesticQuietHoursBands: Shape {
    var intervals: [DateInterval]
    var day: DateInterval

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard day.duration > 0 else { return path }
        for interval in intervals {
            let start = max(0, min(1, interval.start.timeIntervalSince(day.start) / day.duration))
            let end = max(0, min(1, interval.end.timeIntervalSince(day.start) / day.duration))
            guard end > start else { continue }
            let band = CGRect(x: rect.minX + rect.width * start, y: rect.minY,
                              width: rect.width * (end - start), height: rect.height)
            let radius = min(band.width, band.height) / 2
            path.addRoundedRect(in: band, cornerSize: CGSize(width: radius, height: radius))
        }
        return path
    }
}
