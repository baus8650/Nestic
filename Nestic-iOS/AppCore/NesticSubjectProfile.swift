import Foundation

struct NesticSubjectProfileDraft {
    var hasBirthday = false
    var birthday = Date()
    var weight = ""
    var unit = Locale.current.usesMetricSystem ? "kg" : "lb"
    init(_ subject: NestSubject? = nil) {
        let metadata = subject?.metadata ?? [:]
        if let raw = metadata["birthday"], let date = Self.formatter().date(from: raw) {
            hasBirthday = true; birthday = date
        }
        unit = metadata["weightUnit"] == "lb" ? "lb" : metadata["weightUnit"] == "kg" ? "kg" : unit
        if let kg = metadata["weightKg"].flatMap(Double.init), kg.isFinite, kg > 0 {
            weight = String(format: "%g", unit == "lb" ? kg / 0.45359237 : kg)
        }
    }
    static func formatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter
    }
    func metadata(merging existing: [String: String]) throws -> [String: String] {
        var result = existing
        if hasBirthday {
            guard Calendar.current.startOfDay(for: birthday) <= Calendar.current.startOfDay(for: Date()) else {
                throw NesticError.message("Birthday must be today or earlier.")
            }
            result["birthday"] = Self.formatter().string(from: birthday)
        } else { result.removeValue(forKey: "birthday") }
        let text = weight.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            result.removeValue(forKey: "weightKg"); result.removeValue(forKey: "weightUnit")
        } else {
            guard ["kg", "lb"].contains(unit), let value = Double(text.replacingOccurrences(of: ",", with: ".")), value.isFinite, value > 0, value <= 1_000_000 else {
                throw NesticError.message("Enter a positive weight, or leave it blank.")
            }
            result["weightKg"] = String(unit == "lb" ? value * 0.45359237 : value)
            result["weightUnit"] = unit
        }
        return result
    }
    mutating func changeUnit(from old: String) {
        guard let value = Double(weight.replacingOccurrences(of: ",", with: ".")), old != unit else { return }
        weight = String(format: "%g", unit == "kg" ? value * 0.45359237 : value / 0.45359237)
    }
}
