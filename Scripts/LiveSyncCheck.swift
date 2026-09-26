// Compiles alongside AppCore for a real two-account check against a local development API.
// Run with Scripts/check-live-sync.sh while the local server is running.
import Foundation

@main struct LiveSyncCheck {
    @MainActor static func main() async throws {
        let suffix = UUID().uuidString.lowercased()
        let ownerDefaults = UserDefaults(suiteName: "Nestic.LiveCheck.Owner.\(suffix)")!
        let memberDefaults = UserDefaults(suiteName: "Nestic.LiveCheck.Member.\(suffix)")!
        let owner = NesticStore(defaults: ownerDefaults, restoreSession: false)
        let member = NesticStore(defaults: memberDefaults, restoreSession: false)
        defer {
            owner.signOut(); member.signOut()
            ownerDefaults.removePersistentDomain(forName: "Nestic.LiveCheck.Owner.\(suffix)")
            memberDefaults.removePersistentDomain(forName: "Nestic.LiveCheck.Member.\(suffix)")
        }
        let ownerEmail = "live-owner-\(suffix)@example.com"
        let memberEmail = "live-member-\(suffix)@example.com"
        try await owner.register(name: "Live check owner", email: ownerEmail, password: "Test-only-\(suffix)")
        try await member.register(name: "Live check member", email: memberEmail, password: "Test-only-\(suffix)")
        try await owner.createNest(name: "Live check \(suffix)")
        try await owner.addMember(email: memberEmail)
        try await owner.createSubject(name: "Test dog", kind: .pet, emoji: "🐶", trackerTemplates: NestTrackerTemplate.dog)
        try await member.refresh()
        try await eventually("both clients subscribe") {
            owner.connectionStatus.hasPrefix("Live") && member.connectionStatus.hasPrefix("Live")
        }
        guard let dog = owner.subjects.first, let pee = owner.trackers(for: dog).first(where: { $0.name == "Pee" }) else {
            throw NesticError.message("Created subject or starter trackers missing")
        }
        try await member.log(subjectID: dog.id, trackerID: pee.id, note: "Shared bathroom update")
        try await eventually("owner receives member's update without manual refresh") {
            owner.entries.contains { $0.note == "Shared bathroom update" }
        }
        guard let entry = owner.entries.first(where: { $0.note == "Shared bathroom update" }) else { return }
        try await owner.deleteEntry(entry)
        try await eventually("member receives deletion without manual refresh") {
            !member.entries.contains { $0.id == entry.id }
        }
        try await owner.createTracker(subjectID: dog.id, name: "Outside?", valueType: .boolean)
        try await eventually("member receives a new custom tracker") {
            member.trackers.contains { $0.name == "Outside?" }
        }
        guard let boolean = owner.trackers.first(where: { $0.name == "Outside?" }) else { return }
        try await owner.log(subjectID: dog.id, trackerID: boolean.id, bool: false)
        try await eventually("boolean false survives the shared API") {
            member.entries.contains { $0.actionId == boolean.id && $0.valueBool == false }
        }
        try await owner.createNest(name: "Separate test nest")
        guard owner.entries.isEmpty, owner.subjects.isEmpty else { throw NesticError.message("Nest data leaked across switch") }
        print("PASS: registration, shared starter trackers, live log/deletion/custom tracker, boolean false, isolated nest switching")
        print("Local test data suffix: \(suffix)")
    }

    @MainActor static func eventually(_ label: String, condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw NesticError.message("Timed out: \(label)")
    }
}
