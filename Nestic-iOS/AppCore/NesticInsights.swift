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
    var includeAge = false
    var includeWeight = false
    enum CodingKeys: String, CodingKey { case inputTrackerIDs, targetTrackerIDs, includeAge, includeWeight }
    init(inputTrackerIDs: [UUID] = [], targetTrackerIDs: [UUID] = [], includeAge: Bool = false, includeWeight: Bool = false) {
        self.inputTrackerIDs = inputTrackerIDs; self.targetTrackerIDs = targetTrackerIDs
        self.includeAge = includeAge; self.includeWeight = includeWeight
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        inputTrackerIDs = try c.decodeIfPresent([UUID].self, forKey: .inputTrackerIDs) ?? []
        targetTrackerIDs = try c.decodeIfPresent([UUID].self, forKey: .targetTrackerIDs) ?? []
        includeAge = try c.decodeIfPresent(Bool.self, forKey: .includeAge) ?? false
        includeWeight = try c.decodeIfPresent(Bool.self, forKey: .includeWeight) ?? false
    }
}

/// A daily repeating quiet period. When the end is earlier than the start,
/// the period crosses midnight (for example, 23:00–06:00).
struct NestQuietHoursPeriod: Codable, Hashable, Sendable, Identifiable {
    var id: UUID
    var startMinute: Int
    var endMinute: Int

    init(id: UUID = UUID(), startMinute: Int, endMinute: Int) {
        self.id = id
        self.startMinute = min(1_439, max(0, startMinute))
        self.endMinute = min(1_439, max(0, endMinute))
    }

    func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        guard startMinute != endMinute else { return false }
        let minute = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        if startMinute < endMinute {
            return minute >= startMinute && minute < endMinute
        }
        return minute >= startMinute || minute < endMinute
    }
}

struct NestQuietHoursPreferences: Codable, Hashable, Sendable {
    var periods: [NestQuietHoursPeriod]
    var confidenceThresholdPercent: Int

    init(periods: [NestQuietHoursPeriod] = [], confidenceThresholdPercent: Int = 80) {
        self.periods = periods
        self.confidenceThresholdPercent = min(100, max(0, confidenceThresholdPercent))
    }

    func shouldSuppress(predictedAt: Date, confidence: Double, calendar: Calendar = .current) -> Bool {
        guard confidence < Double(confidenceThresholdPercent) / 100 else { return false }
        return periods.contains { $0.contains(predictedAt, calendar: calendar) }
    }

    /// Keeps a low-confidence forecast visible while respecting quiet hours.
    /// If the next modeled occurrence is quiet, advance by the learned cadence
    /// until the next modeled occurrence outside quiet hours is found. This
    /// preserves the forecast's timing pattern instead of moving it to the
    /// end of a quiet period.
    func nextForecastDate(predictedAt: Date, confidence: Double, intervalHours: Double,
                          calendar: Calendar = .current) -> Date {
        guard shouldSuppress(predictedAt: predictedAt, confidence: confidence, calendar: calendar),
              !periods.isEmpty else { return predictedAt }

        let cadenceHours = max(0.25, intervalHours)
        let cadence = cadenceHours * 3600
        let attemptCount = max(1, Int(ceil((14 * 24) / cadenceHours)) + 1)
        var candidate = predictedAt
        for _ in 0..<attemptCount {
            candidate = candidate.addingTimeInterval(cadence)
            if !periods.contains(where: { $0.contains(candidate, calendar: calendar) }) {
                return candidate
            }
        }

        // If the cadence lands inside quiet hours indefinitely (for example,
        // an exactly daily forecast at 2:00 AM), keep the model's real time
        // rather than inventing a misleading quiet-hours boundary.
        return predictedAt
    }
}

enum ForecastModelKind: String, Codable, Hashable, Sendable {
    case baseline
    case contextual

    var title: String {
        switch self {
        case .baseline: "baseline"
        case .contextual: "context model"
        }
    }
}

/// A local-only audit record used to measure whether a forecast was useful.
/// It is intentionally kept out of the server model and contains no extra
/// personal data beyond the IDs and timestamps already needed for a forecast.
struct ForecastSnapshot: Codable, Hashable, Sendable, Identifiable {
    var id: UUID
    var subjectID: UUID
    var targetTrackerID: UUID
    var lastEventAt: Date
    var createdAt: Date
    var selectedModel: ForecastModelKind
    var selectedPredictedAt: Date
    var baselinePredictedAt: Date
    var contextualPredictedAt: Date?
    var actualEventAt: Date?
    var evaluatedAt: Date?
    var baselineErrorHours: Double?
    var contextualErrorHours: Double?
    var selectedErrorHours: Double?
}

/// A human-readable summary of the local inputs included in a forecast.
/// Values here deliberately mirror the timing, frequency, and numeric/boolean
/// features used by `EventPredictionEngine`; notes and free-form text are not
/// included in the model or exposed here.
struct ForecastLearningSignal: Hashable, Sendable, Identifiable {
    var trackerID: UUID
    var trackerName: String
    var lastLoggedAt: Date
    var hoursSinceLastUpdate: Double
    var updatesInLast24Hours: Int
    var updatesInLast72Hours: Int
    var latestLearnedValue: String?

    var id: UUID { trackerID }
}

struct ForecastContribution: Hashable, Sendable, Identifiable {
    let id: Int
    let name: String
    let hours: Double
}

struct ForecastDiagnostics: Hashable, Sendable {
    let computedAt: Date
    let medianHours: Double
    let meanHours: Double
    let standardDeviationHours: Double
    let minimumHours: Double
    let maximumHours: Double
    let excludedIntervalCount: Int
    let rawContextHours: Double?
    let contributions: [ForecastContribution]
    let selectionReason: String
}

struct EventPrediction: Hashable, Sendable {
    var targetTrackerID: UUID?
    var predictedAt: Date
    var baselinePredictedAt: Date
    var contextualPredictedAt: Date?
    var model: ForecastModelKind
    var intervalHours: Double
    var confidence: Double
    var sampleCount: Int
    var validationSampleCount: Int
    var expectedErrorHours: Double?
    var predictionWindowHours: Double
    var targetNames: [String]
    var inputNames: [String]
    var lastEventAt: Date
    var explanation: String
    var learningSignals: [ForecastLearningSignal] = []
    var diagnostics: ForecastDiagnostics? = nil

    var confidencePercent: Int { Int((confidence * 100).rounded()) }
}

/// A small, privacy-preserving on-device model. It learns the interval to the
/// next selected event from local time patterns and the subject's recorded
/// tracker history. Users can explicitly narrow the input trackers.
/// This is intentionally a pattern estimate, not a health or professional model.
enum EventPredictionEngine {
    static func inferredTargetIDs(trackers: [NestTracker]) -> [UUID] {
        trackers.filter { tracker in
            let name = tracker.name.lowercased()
            return name.contains("pee") || name.contains("poop") || name.contains("potty") ||
                name.contains("bathroom") || name.contains("elimination")
        }.map(\.id)
    }

    static func defaultInputIDs(trackers: [NestTracker], targetIDs: [UUID]) -> [UUID] {
        // The default model should see the complete context available for the
        // subject. Users can still narrow this list in Forecast settings.
        return trackers.filter { !targetIDs.contains($0.id) && $0.valueType != .photo && $0.valueType != .health }.map(\.id)
    }

    static func predict(
        subject: NestSubject,
        trackers: [NestTracker],
        entries: [NestEntry],
        preferences: NestPredictionPreferences,
        targetTrackerIDs overrideTargetIDs: [UUID]? = nil,
        feedback: [ForecastSnapshot] = [],
        now: Date = Date()
    ) -> EventPrediction? {
        let subjectEntries = entries
            .filter { $0.entityId == subject.id && $0.shouldIncludeInPredictions && $0.occurredAt <= now }
            .sorted { $0.occurredAt < $1.occurredAt }
        let entriesByTracker = Dictionary(grouping: subjectEntries, by: \.actionId)
        let configuredTargetIDs = preferences.targetTrackerIDs.isEmpty
            ? inferredTargetIDs(trackers: trackers)
            : preferences.targetTrackerIDs
        // A target override is used to build one forecast per selected target.
        // Keep all configured targets out of the context inputs so, for example,
        // Poop does not silently become a feature of the separate Pee model.
        let targetIDs = overrideTargetIDs ?? configuredTargetIDs
        let targetEntries = subjectEntries.filter { targetIDs.contains($0.actionId) }
        guard targetEntries.count >= 2 else { return nil }

        let availableTrackers = trackers.filter { $0.nestId == subject.nestId }
        let excludedInputIDs = Set(configuredTargetIDs).union(targetIDs)
        let inputIDs = preferences.inputTrackerIDs.isEmpty
            ? defaultInputIDs(trackers: availableTrackers, targetIDs: Array(excludedInputIDs))
            : preferences.inputTrackerIDs.filter { id in
                !excludedInputIDs.contains(id) && availableTrackers.contains { tracker in tracker.id == id }
            }
        // Empty trackers add no signal and only make the on-device fit larger.
        // Keep every selected metric that has actually been recorded for this
        // subject; metrics with no history can start contributing automatically
        // as soon as their first entry is logged.
        let inputTrackers = inputIDs.compactMap { id in availableTrackers.first { $0.id == id } }
            .filter { entriesByTracker[$0.id] != nil }
        let normalizers = valueNormalizers(for: inputTrackers, entriesByTracker: entriesByTracker)
        let intervals = zip(targetEntries, targetEntries.dropFirst()).compactMap { previous, next -> Double? in
            let hours = next.occurredAt.timeIntervalSince(previous.occurredAt) / 3600
            return hours > 0.15 && hours < 72 ? hours : nil
        }
        guard !intervals.isEmpty else { return nil }

        let profileDates = zip(targetEntries, targetEntries.dropFirst()).compactMap { previous, next -> Date? in
            let hours = next.occurredAt.timeIntervalSince(previous.occurredAt) / 3600
            return hours > 0.15 && hours < 72 ? next.occurredAt : nil
        }
        let profileInputs = ForecastProfileInputs(subject: subject, preferences: preferences, dates: profileDates, now: now)
        var samples: [(features: [Double], target: Double)] = []
        for index in 0..<(targetEntries.count - 1) {
            let previous = targetEntries[index]
            let next = targetEntries[index + 1]
            let hours = next.occurredAt.timeIntervalSince(previous.occurredAt) / 3600
            guard hours > 0.15 && hours < 72 else { continue }
            // Train on the same observation window that is available at live
            // prediction time: input activity since the previous target event
            // through the next target event. The old implementation trained
            // at `previous`, before that interval's food/medication/activity
            // had happened, while the live vector included it. That mismatch
            // made selected input trackers look as if they had no effect.
            samples.append((features: featureVector(at: next.occurredAt, since: previous.occurredAt,
                                                     inputTrackers: inputTrackers, entriesByTracker: entriesByTracker,
                                                     normalizers: normalizers) + profileInputs.features(at: next.occurredAt), target: hours))
        }

        let medianInterval = median(intervals)
        let currentFeatures = featureVector(at: now, since: targetEntries.last?.occurredAt,
                                            inputTrackers: inputTrackers, entriesByTracker: entriesByTracker,
                                            normalizers: normalizers) + profileInputs.features(at: now)
        let baselineInterval = min(72, max(0.25, medianInterval))
        let coefficients = samples.count >= 3 ? ridgeCoefficients(samples: samples) : nil
        let rawContextHours = coefficients.map { coefficients in
            zip(coefficients, currentFeatures).reduce(0) { $0 + $1.0 * $1.1 }
        }
        let contextualInterval = rawContextHours.map { min(72, max(0.25, $0)) }
        let targetID = targetIDs.count == 1 ? targetIDs[0] : nil
        let scoredFeedback = feedback
            .filter { snapshot in
                snapshot.subjectID == subject.id &&
                    snapshot.targetTrackerID == targetID &&
                    snapshot.actualEventAt != nil &&
                    snapshot.evaluatedAt != nil
            }
            .sorted { ($0.evaluatedAt ?? .distantPast) > ($1.evaluatedAt ?? .distantPast) }
        let selectedModel = modelToUse(from: scoredFeedback, hasContextualEstimate: contextualInterval != nil, now: now)
        let estimatedInterval = selectedModel == .contextual
            ? (contextualInterval ?? baselineInterval)
            : baselineInterval
        let targetNames = targetIDs.compactMap { id in trackers.first { $0.id == id }?.name }
        let inputNames = inputTrackers.map(\.name) + profileInputs.names
        let lastEventAt = targetEntries.last?.occurredAt ?? now
        // The model learns an interval between occurrences. Anchor that interval
        // to the last matching target so an already-overdue event is shown as
        // imminent rather than adding a full new interval from the current time.
        let baselinePredictedAt = predictedDate(interval: baselineInterval, lastEventAt: lastEventAt, now: now)
        let contextualPredictedAt = contextualInterval.map {
            predictedDate(interval: $0, lastEventAt: lastEventAt, now: now)
        }
        let predictedAt = selectedModel == .contextual
            ? (contextualPredictedAt ?? baselinePredictedAt)
            : baselinePredictedAt
        let validationErrorHours = validationError(for: selectedModel, feedback: scoredFeedback, now: now)
        let validationSampleCount = scoredFeedback.filter { snapshot in
            selectedModel == .contextual ? snapshot.contextualErrorHours != nil : snapshot.baselineErrorHours != nil
        }.count
        let inSampleError = meanAbsoluteError(targets: samples.map(\.target), estimate: estimatedInterval)
        let expectedErrorHours = validationErrorHours ?? inSampleError
        let predictionWindowHours = min(12, max(1, (expectedErrorHours ?? max(1, medianInterval * 0.15)) * 1.25))
        let confidence = confidence(for: samples.map(\.target), estimate: estimatedInterval,
                                    validationErrorHours: validationErrorHours,
                                    validationCount: validationSampleCount)
        let learningSignals = inputTrackers.compactMap { tracker -> ForecastLearningSignal? in
            let trackerEntries = (entriesByTracker[tracker.id] ?? []).filter { $0.occurredAt <= now }
            guard let latest = trackerEntries.last else { return nil }
            let latestLearnedValue: String?
            switch tracker.valueType {
            case .number where latest.valueNumber != nil, .boolean where latest.valueBool != nil:
                latestLearnedValue = latest.displayValue(unit: tracker.unit, trackerName: tracker.name)
            default:
                latestLearnedValue = nil
            }
            return ForecastLearningSignal(
                trackerID: tracker.id,
                trackerName: tracker.name,
                lastLoggedAt: latest.occurredAt,
                hoursSinceLastUpdate: max(0, now.timeIntervalSince(latest.occurredAt) / 3600),
                updatesInLast24Hours: trackerEntries.filter { $0.occurredAt >= now.addingTimeInterval(-24 * 3600) }.count,
                updatesInLast72Hours: trackerEntries.filter { $0.occurredAt >= now.addingTimeInterval(-72 * 3600) }.count,
                latestLearnedValue: latestLearnedValue
            )
        }
        var explanation: String
        let targetDescription = targetNames.count == 1 ? targetNames[0] : "selected events"
        if validationSampleCount >= 3, let validationErrorHours {
            explanation = "Validated the \(selectedModel.title) against \(validationSampleCount) recent forecasts; timing is typically within \(hoursDescription(validationErrorHours))."
        } else if samples.count >= 3 {
            let modelDescription = selectedModel == .contextual ? "is using" : "is building a baseline from"
            explanation = "\(modelDescription.capitalized) \(samples.count) \(targetDescription.lowercased()) intervals, time of day, and \(inputNames.count) recorded metric\(inputNames.count == 1 ? "" : "s")."
        } else {
            explanation = "Building a baseline from \(intervals.count) recent \(targetDescription.lowercased()) interval\(intervals.count == 1 ? "" : "s") plus time-of-day and metric history."
        }

        if preferences.includeWeight && !profileInputs.names.contains("Subject weight") {
            explanation += " Weight is waiting for at least three intervals with dated, changing weights; save weight in the subject’s details to begin."
        }
        if preferences.includeAge && !profileInputs.names.contains("Subject age") {
            explanation += " Age is waiting for a birthday and enough history."
        }

        // Decompose the linear estimate into intercept, tracker, and calendar
        // terms. These are model contributions, not causal effects.
        var contributions: [ForecastContribution] = []
        if let coefficients {
            let terms = zip(coefficients, currentFeatures).map { $0.0 * $0.1 }
            contributions.append(ForecastContribution(id: 0, name: "Model intercept", hours: terms[0]))
            for (index, tracker) in inputTrackers.enumerated() {
                let offset = 1 + index * 10
                contributions.append(ForecastContribution(id: index + 1, name: tracker.name,
                                                         hours: terms[offset..<(offset + 10)].reduce(0, +)))
            }
            contributions.append(ForecastContribution(id: inputTrackers.count + 1, name: "Time of day + weekday",
                                                     hours: terms[(1 + inputTrackers.count * 10)..<(6 + inputTrackers.count * 10)].reduce(0, +)))
            for (index, name) in profileInputs.names.enumerated() {
                contributions.append(ForecastContribution(id: inputTrackers.count + 3 + index, name: name,
                    hours: terms[6 + inputTrackers.count * 10 + index]))
            }
        }
        let mean = intervals.reduce(0, +) / Double(intervals.count)
        let deviation = sqrt(intervals.reduce(0) { $0 + pow($1 - mean, 2) } / Double(intervals.count))
        let hasComparison = scoredFeedback.filter { $0.baselineErrorHours != nil }.count >= 3 &&
            scoredFeedback.filter { $0.contextualErrorHours != nil }.count >= 3
        let selectionReason: String
        if contextualInterval == nil {
            selectionReason = "The baseline is used until at least three usable intervals are available and the context model can be fitted."
        } else if !hasComparison {
            selectionReason = "The context model is available and is used provisionally. At least three scored outcomes for each model are needed to compare their accuracy."
        } else if selectedModel == .contextual {
            selectionReason = "The context model's recency-weighted absolute timing error is at least 5% lower than the baseline's."
        } else {
            selectionReason = "The context model did not meet the required 5% improvement in recency-weighted absolute timing error, so the median baseline is used."
        }
        let diagnostics = ForecastDiagnostics(
            computedAt: now, medianHours: medianInterval, meanHours: mean,
            standardDeviationHours: deviation, minimumHours: intervals.min() ?? 0,
            maximumHours: intervals.max() ?? 0,
            excludedIntervalCount: targetEntries.count - 1 - intervals.count,
            rawContextHours: rawContextHours, contributions: contributions,
            selectionReason: selectionReason)

        return EventPrediction(targetTrackerID: targetIDs.count == 1 ? targetIDs[0] : nil,
                               predictedAt: predictedAt,
                               baselinePredictedAt: baselinePredictedAt,
                               contextualPredictedAt: contextualPredictedAt,
                               model: selectedModel,
                               intervalHours: estimatedInterval,
                               confidence: confidence, sampleCount: intervals.count,
                               validationSampleCount: validationSampleCount,
                               expectedErrorHours: expectedErrorHours,
                               predictionWindowHours: predictionWindowHours,
                               targetNames: targetNames, inputNames: inputNames,
                               lastEventAt: lastEventAt, explanation: explanation,
                               learningSignals: learningSignals, diagnostics: diagnostics)
    }

    private static func valueNormalizers(for trackers: [NestTracker], entriesByTracker: [UUID: [NestEntry]]) -> [UUID: Double] {
        Dictionary(uniqueKeysWithValues: trackers.map { tracker in
            let values = (entriesByTracker[tracker.id] ?? []).compactMap(\.valueNumber)
            return (tracker.id, max(values.map { abs($0) }.max() ?? 1, 1))
        })
    }

    private static func featureVector(at date: Date, since referenceDate: Date? = nil,
                                      inputTrackers: [NestTracker], entriesByTracker: [UUID: [NestEntry]],
                                      normalizers: [UUID: Double]) -> [Double] {
        var values: [Double] = [1]
        let calendar = Calendar.current
        for tracker in inputTrackers {
            let allTrackerEntries = (entriesByTracker[tracker.id] ?? []).filter { $0.occurredAt <= date }
            let windowEntries = referenceDate.map { reference in
                allTrackerEntries.filter { $0.occurredAt > reference }
            } ?? allTrackerEntries
            let latest = allTrackerEntries.last
            let latestWindowEntry = windowEntries.last
            let hoursSince = latest.map { date.timeIntervalSince($0.occurredAt) / 3600 } ?? 168
            values.append(min(168, max(0, hoursSince)) / 24)
            if let number = latest?.valueNumber {
                values.append(number / (normalizers[tracker.id] ?? 1))
            } else if let bool = latest?.valueBool {
                values.append(bool ? 1 : 0)
            } else {
                values.append(latest == nil ? 0 : 1)
            }

            // Capture the recent activity pattern, not just the last value.
            // This lets a walk, meal, medication, or any custom tracker affect
            // the estimate even when it was recorded more than once recently.
            for window in [6.0, 12.0, 24.0, 72.0] {
                let cutoff = date.addingTimeInterval(-window * 3600)
                let count = windowEntries.reduce(into: 0) { result, entry in
                    if entry.occurredAt >= cutoff { result += 1 }
                }
                values.append(min(1, Double(count) / max(1, window / 12)))
            }

            let recentNumbers = windowEntries
                .filter { $0.occurredAt >= date.addingTimeInterval(-7 * 24 * 3600) }
                .compactMap(\.valueNumber)
            let average = recentNumbers.isEmpty ? 0 : recentNumbers.reduce(0, +) / Double(recentNumbers.count)
            values.append(average / (normalizers[tracker.id] ?? 1))

            // Numeric trackers such as food need their amount to influence the
            // interval, not just their existence. Normalize the total amount
            // in the observation window so a larger meal can be distinguished
            // from a small one without making the feature unbounded.
            let total = recentNumbers.reduce(0, +) / (normalizers[tracker.id] ?? 1)
            values.append(min(4, max(-4, total)))

            // Also preserve when the input happened. A meal at 07:00 and one
            // at 22:00 are different signals even if their amounts match.
            if let latestWindowEntry {
                let minute = Double(calendar.component(.hour, from: latestWindowEntry.occurredAt) * 60 +
                                    calendar.component(.minute, from: latestWindowEntry.occurredAt))
                let angle = minute / (24 * 60) * 2 * .pi
                values.append(sin(angle))
                values.append(cos(angle))
            } else {
                values.append(0)
                values.append(0)
            }
        }

        // Model local time continuously, including minutes, instead of only
        // using the integer hour. Weekday/weekend patterns are useful for
        // routines that differ between weekdays and weekends.
        let minuteOfDay = Double(calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date))
        let timeAngle = minuteOfDay / (24 * 60) * 2 * .pi
        values.append(sin(timeAngle))
        values.append(cos(timeAngle))

        let weekday = Double(max(0, calendar.component(.weekday, from: date) - 1))
        let weekdayAngle = weekday / 7 * 2 * .pi
        values.append(sin(weekdayAngle))
        values.append(cos(weekdayAngle))
        values.append(weekday >= 5 ? 1 : 0)
        return values
    }

    private static func ridgeCoefficients(samples: [(features: [Double], target: Double)]) -> [Double]? {
        guard let width = samples.first?.features.count else { return nil }
        if width > samples.count + 1 {
            // With many tracker features and relatively little history, solve
            // the equivalent ridge system in sample space. Centering keeps
            // the intercept unpenalized, just like the original feature-space
            // fit, while reducing the cubic solve from features to samples.
            let count = samples.count
            let targetMean = samples.reduce(0) { $0 + $1.target } / Double(count)
            var featureMeans = Array(repeating: 0.0, count: width)
            for sample in samples {
                for column in 1..<width { featureMeans[column] += sample.features[column] / Double(count) }
            }
            let centered = samples.map { sample in
                (1..<width).map { sample.features[$0] - featureMeans[$0] }
            }
            var dual = Array(repeating: Array(repeating: 0.0, count: count + 1), count: count)
            for row in 0..<count {
                for column in row..<count {
                    let product = zip(centered[row], centered[column]).reduce(0) { $0 + $1.0 * $1.1 }
                    dual[row][column] = product
                    dual[column][row] = product
                }
                dual[row][row] += 0.12
                dual[row][count] = samples[row].target - targetMean
            }
            guard let weights = gaussianSolve(dual) else { return nil }
            var coefficients = Array(repeating: 0.0, count: width)
            for column in 1..<width {
                for row in 0..<count { coefficients[column] += centered[row][column - 1] * weights[row] }
            }
            coefficients[0] = targetMean - zip(featureMeans, coefficients).reduce(0) { $0 + $1.0 * $1.1 }
            return coefficients
        }
        var matrix = Array(repeating: Array(repeating: 0.0, count: width + 1), count: width)
        for sample in samples {
            for row in 0..<width {
                for column in row..<width {
                    matrix[row][column] += sample.features[row] * sample.features[column]
                }
                matrix[row][width] += sample.features[row] * sample.target
            }
        }
        for row in 0..<width {
            for column in 0..<row { matrix[row][column] = matrix[column][row] }
        }
        let ridge = 0.12
        for index in 1..<width { matrix[index][index] += ridge }
        return gaussianSolve(matrix)
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

    private static func predictedDate(interval: Double, lastEventAt: Date, now: Date) -> Date {
        max(
            now.addingTimeInterval(0.25 * 3600),
            lastEventAt.addingTimeInterval(interval * 3600)
        )
    }

    private static func modelToUse(from feedback: [ForecastSnapshot], hasContextualEstimate: Bool,
                                   now: Date) -> ForecastModelKind {
        guard hasContextualEstimate else { return .baseline }
        let baselineValidationCount = feedback.filter { $0.baselineErrorHours != nil }.count
        let contextualValidationCount = feedback.filter { $0.contextualErrorHours != nil }.count
        // A selected input tracker should affect the forecast as soon as the
        // contextual fit exists. Validation still controls whether the richer
        // model is trusted over time, but it must not make the user's chosen
        // food, medication, or activity signal inert for the first forecasts.
        guard baselineValidationCount >= 3, contextualValidationCount >= 3 else {
            return .contextual
        }
        guard let baselineError = weightedError(for: feedback, keyPath: \.baselineErrorHours, now: now),
              let contextualError = weightedError(for: feedback, keyPath: \.contextualErrorHours, now: now) else {
            return .baseline
        }
        // Require a meaningful improvement before trusting the richer model;
        // this prevents a tiny, noisy win from changing the user's forecast.
        return contextualError <= baselineError * 0.95 ? .contextual : .baseline
    }

    private static func validationError(for model: ForecastModelKind,
                                        feedback: [ForecastSnapshot],
                                        now: Date) -> Double? {
        let keyPath: KeyPath<ForecastSnapshot, Double?> = model == .contextual
            ? \.contextualErrorHours
            : \.baselineErrorHours
        return weightedError(for: feedback, keyPath: keyPath, now: now)
    }

    private static func weightedError(for feedback: [ForecastSnapshot],
                                      keyPath: KeyPath<ForecastSnapshot, Double?>,
                                      now: Date = Date()) -> Double? {
        let weighted = feedback.compactMap { snapshot -> (error: Double, weight: Double)? in
            guard let error = snapshot[keyPath: keyPath], error.isFinite else { return nil }
            let ageDays = max(0, now.timeIntervalSince(snapshot.evaluatedAt ?? now) / 86_400)
            let weight = exp(-ageDays / 45)
            return (error, weight)
        }
        let totalWeight = weighted.reduce(0) { $0 + $1.weight }
        guard totalWeight > 0 else { return nil }
        return weighted.reduce(0) { $0 + ($1.error * $1.weight) } / totalWeight
    }

    private static func meanAbsoluteError(targets: [Double], estimate: Double) -> Double? {
        guard !targets.isEmpty else { return nil }
        return targets.map { abs($0 - estimate) }.reduce(0, +) / Double(targets.count)
    }

    private static func hoursDescription(_ hours: Double) -> String {
        if hours < 1 { return "under an hour" }
        return "\(Int(hours.rounded())) hour\(hours.rounded() == 1 ? "" : "s")"
    }

    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 4 }
        if sorted.count.isMultiple(of: 2) {
            return (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
        }
        return sorted[sorted.count / 2]
    }

    private static func confidence(for targets: [Double], estimate: Double,
                                   validationErrorHours: Double?, validationCount: Int) -> Double {
        guard !targets.isEmpty else { return 0.2 }
        let baseline = median(targets)
        let error = targets.map { abs($0 - estimate) }.reduce(0, +) / Double(targets.count)
        let fit = max(0, min(1, 1 - error / max(12, baseline * 2)))
        let baseConfidence = 0.22 + min(Double(targets.count), 20) * 0.018 + fit * 0.48
        guard validationCount >= 3, let validationErrorHours else {
            // Until real outcomes exist, avoid presenting a fit-to-history
            // score as if it were proven predictive accuracy.
            return max(0.24, min(0.72, baseConfidence))
        }
        let validatedFit = max(0, min(1, 1 - validationErrorHours / max(6, baseline * 0.75)))
        return max(0.24, min(0.94, baseConfidence * 0.45 + (0.28 + validatedFit * 0.58) * 0.55))
    }
}

// Keep the old names available for existing integrations while the feature becomes generic.
typealias BathroomPrediction = EventPrediction
typealias BathroomPredictionEngine = EventPredictionEngine

/// Only observed, varying profile inputs enter the model. Missing historical
/// weights are not filled using today's weight, and extrapolation is bounded.
struct ForecastProfileInputs {
    struct WeightRecord: Decodable { let recordedAt: Double; let weightKg: Double? }
    struct Column { let name: String; let mean: Double; let scale: Double }
    let birthday: Date?
    let weights: [WeightRecord]
    var columns: [Column] = []
    var names: [String] { columns.map(\.name) }
    init(subject: NestSubject, preferences: NestPredictionPreferences, dates: [Date], now: Date) {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.calendar = Calendar(identifier: .gregorian); f.dateFormat = "yyyy-MM-dd"; f.isLenient = false
        birthday = subject.metadata?["birthday"].flatMap { f.date(from: $0) }
        weights = subject.metadata?["weightHistoryJSON"].flatMap { $0.data(using: .utf8) }.flatMap { try? JSONDecoder().decode([WeightRecord].self, from: $0) }?.sorted { $0.recordedAt < $1.recordedAt } ?? []
        for (name, enabled) in [("Subject age", preferences.includeAge), ("Subject weight", preferences.includeWeight)] where enabled {
            let values = dates.compactMap { value(name, at: $0) }
            guard values.count >= 3, value(name, at: now) != nil else { continue }
            let mean = values.reduce(0, +) / Double(values.count)
            let scale = sqrt(values.reduce(0) { $0 + pow($1 - mean, 2) } / Double(values.count))
            guard scale.isFinite && scale > 0.000001 else { continue }
            columns.append(Column(name: name, mean: mean, scale: scale))
        }
    }
    func value(_ name: String, at date: Date) -> Double? {
        if name == "Subject age" { return birthday.flatMap { date >= $0 ? date.timeIntervalSince($0) / (365.2425 * 86400) : nil } }
        return weights.last { $0.recordedAt <= date.timeIntervalSince1970 }?.weightKg.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
    }
    func features(at date: Date) -> [Double] {
        columns.map { c in value(c.name, at: date).map { min(3, max(-3, ($0 - c.mean) / c.scale)) } ?? 0 }
    }
}
