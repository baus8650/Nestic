import Foundation

enum NesticAnalyticsRange: String, CaseIterable, Identifiable, Sendable {
    case today
    case week
    case month

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: "Today"
        case .week: "7 days"
        case .month: "30 days"
        }
    }

    var dayCount: Int {
        switch self {
        case .today: 1
        case .week: 7
        case .month: 30
        }
    }

    var calendarComponent: Calendar.Component {
        self == .today ? .hour : .day
    }
}

struct NestPredictionPreferences: Codable, Hashable, Sendable {
    var inputTrackerIDs: [UUID] = []
    var targetTrackerIDs: [UUID] = []
}

struct BathroomPrediction: Hashable, Sendable {
    var predictedAt: Date
    var confidence: Double
    var sampleCount: Int
    var targetNames: [String]
    var inputNames: [String]
    var lastBathroomAt: Date
    var explanation: String

    var confidencePercent: Int { Int((confidence * 100).rounded()) }
}

/// A small, privacy-preserving on-device model. It learns the interval to the
/// next bathroom event from the trackers the user explicitly selects as inputs.
/// This is intentionally a pattern estimate, not a medical or veterinary model.
enum BathroomPredictionEngine {
    static func inferredTargetIDs(trackers: [NestTracker]) -> [UUID] {
        trackers.filter { tracker in
            let name = tracker.name.lowercased()
            return name.contains("pee") || name.contains("poop") || name.contains("potty") ||
                name.contains("bathroom") || name.contains("elimination")
        }.map(\.id)
    }

    static func defaultInputIDs(trackers: [NestTracker], targetIDs: [UUID]) -> [UUID] {
        let preferredWords = ["food", "feed", "water", "walk", "exercise", "sleep", "medication"]
        let preferred = trackers.filter { tracker in
            guard !targetIDs.contains(tracker.id) else { return false }
            let name = tracker.name.lowercased()
            return preferredWords.contains { name.contains($0) }
        }
        if !preferred.isEmpty { return preferred.map(\.id) }
        return trackers.filter { !targetIDs.contains($0.id) }.prefix(3).map(\.id)
    }

    static func predict(
        subject: NestSubject,
        trackers: [NestTracker],
        entries: [NestEntry],
        preferences: NestPredictionPreferences,
        now: Date = Date()
    ) -> BathroomPrediction? {
        let subjectEntries = entries
            .filter { $0.entityId == subject.id }
            .sorted { $0.occurredAt < $1.occurredAt }
        let targetIDs = preferences.targetTrackerIDs.isEmpty
            ? inferredTargetIDs(trackers: trackers)
            : preferences.targetTrackerIDs
        let targetEntries = subjectEntries.filter { targetIDs.contains($0.actionId) }
        guard targetEntries.count >= 2 else { return nil }

        let availableTrackers = trackers.filter { $0.nestId == subject.nestId }
        let inputIDs = preferences.inputTrackerIDs.isEmpty
            ? defaultInputIDs(trackers: availableTrackers, targetIDs: targetIDs)
            : preferences.inputTrackerIDs.filter { id in availableTrackers.contains { tracker in tracker.id == id } }
        let inputTrackers = inputIDs.compactMap { id in availableTrackers.first { $0.id == id } }
        let normalizers = valueNormalizers(for: inputTrackers, entries: subjectEntries)
        let intervals = zip(targetEntries, targetEntries.dropFirst()).compactMap { previous, next -> Double? in
            let hours = next.occurredAt.timeIntervalSince(previous.occurredAt) / 3600
            return hours > 0.15 && hours < 72 ? hours : nil
        }
        guard !intervals.isEmpty else { return nil }

        var samples: [(features: [Double], target: Double)] = []
        for index in 0..<(targetEntries.count - 1) {
            let previous = targetEntries[index]
            let next = targetEntries[index + 1]
            let hours = next.occurredAt.timeIntervalSince(previous.occurredAt) / 3600
            guard hours > 0.15 && hours < 72 else { continue }
            samples.append((features: featureVector(at: previous.occurredAt, inputTrackers: inputTrackers,
                                                     entries: subjectEntries, normalizers: normalizers), target: hours))
        }

        let medianInterval = median(intervals)
        let currentFeatures = featureVector(at: now, inputTrackers: inputTrackers,
                                            entries: subjectEntries, normalizers: normalizers)
        let estimate = samples.count >= 3
            ? ridgePrediction(samples: samples, features: currentFeatures) ?? medianInterval
            : medianInterval
        let hoursUntilNext = min(72, max(0.25, estimate))
        let confidence = confidence(for: samples.map(\.target), estimate: hoursUntilNext)
        let targetNames = targetIDs.compactMap { id in trackers.first { $0.id == id }?.name }
        let inputNames = inputTrackers.map(\.name)
        let lastBathroomAt = targetEntries.last?.occurredAt ?? now
        let explanation: String
        if samples.count >= 3 {
            explanation = "Learned from \(samples.count) potty intervals and \(inputNames.count) selected signal\(inputNames.count == 1 ? "" : "s")."
        } else {
            explanation = "Building a baseline from \(intervals.count) recent potty interval\(intervals.count == 1 ? "" : "s")."
        }

        return BathroomPrediction(predictedAt: now.addingTimeInterval(hoursUntilNext * 3600),
                                   confidence: confidence, sampleCount: intervals.count,
                                   targetNames: targetNames, inputNames: inputNames,
                                   lastBathroomAt: lastBathroomAt, explanation: explanation)
    }

    private static func valueNormalizers(for trackers: [NestTracker], entries: [NestEntry]) -> [UUID: Double] {
        Dictionary(uniqueKeysWithValues: trackers.map { tracker in
            let values = entries.filter { $0.actionId == tracker.id }.compactMap(\.valueNumber)
            return (tracker.id, max(values.map { abs($0) }.max() ?? 1, 1))
        })
    }

    private static func featureVector(at date: Date, inputTrackers: [NestTracker], entries: [NestEntry], normalizers: [UUID: Double]) -> [Double] {
        var values: [Double] = [1]
        for tracker in inputTrackers {
            let latest = entries.last { $0.actionId == tracker.id && $0.occurredAt <= date }
            let hoursSince = latest.map { date.timeIntervalSince($0.occurredAt) / 3600 } ?? 168
            values.append(min(168, max(0, hoursSince)) / 24)
            if let number = latest?.valueNumber {
                values.append(number / (normalizers[tracker.id] ?? 1))
            } else if let bool = latest?.valueBool {
                values.append(bool ? 1 : 0)
            } else {
                values.append(latest == nil ? 0 : 1)
            }
        }
        let hour = Calendar.current.component(.hour, from: date)
        let angle = Double(hour) / 24 * 2 * .pi
        values.append(sin(angle))
        values.append(cos(angle))
        return values
    }

    private static func ridgePrediction(samples: [(features: [Double], target: Double)], features: [Double]) -> Double? {
        guard let width = samples.first?.features.count, width == features.count else { return nil }
        var matrix = Array(repeating: Array(repeating: 0.0, count: width + 1), count: width)
        for sample in samples {
            for row in 0..<width {
                for column in 0..<width {
                    matrix[row][column] += sample.features[row] * sample.features[column]
                }
                matrix[row][width] += sample.features[row] * sample.target
            }
        }
        let ridge = 0.12
        for index in 1..<width { matrix[index][index] += ridge }
        guard let coefficients = gaussianSolve(matrix) else { return nil }
        return zip(coefficients, features).reduce(0) { $0 + ($1.0 * $1.1) }
    }

    private static func gaussianSolve(_ input: [[Double]]) -> [Double]? {
        var matrix = input
        let width = matrix.count
        for pivot in 0..<width {
            guard let best = (pivot..<width).max(by: { abs(matrix[$0][pivot]) < abs(matrix[$1][pivot]) }),
                  abs(matrix[best][pivot]) > 0.000001 else { return nil }
            matrix.swapAt(pivot, best)
            let divisor = matrix[pivot][pivot]
            for column in pivot..<(width + 1) { matrix[pivot][column] /= divisor }
            for row in 0..<width where row != pivot {
                let factor = matrix[row][pivot]
                for column in pivot..<(width + 1) { matrix[row][column] -= factor * matrix[pivot][column] }
            }
        }
        return matrix.map { $0[width] }
    }

    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 4 }
        if sorted.count.isMultiple(of: 2) {
            return (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
        }
        return sorted[sorted.count / 2]
    }

    private static func confidence(for targets: [Double], estimate: Double) -> Double {
        guard !targets.isEmpty else { return 0.2 }
        let baseline = median(targets)
        let error = targets.map { abs($0 - estimate) }.reduce(0, +) / Double(targets.count)
        let fit = max(0, min(1, 1 - error / max(12, baseline * 2)))
        return max(0.24, min(0.94, 0.22 + min(Double(targets.count), 20) * 0.018 + fit * 0.48))
    }
}
