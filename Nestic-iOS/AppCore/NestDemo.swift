import Foundation

extension NesticStore {
    static func makeDemo(now: Date = Date()) -> NestArchive {
        let nest = NestSpace(id: UUID(), name: "Our little nest")
        let alex = NestPerson(id: UUID(), email: "alex@example.com", displayName: "Alex Morgan", role: "owner")
        let jamie = NestPerson(id: UUID(), email: "jamie@example.com", displayName: "Jamie Morgan", role: "member")
        let dogTrackers = NestTrackerTemplate.dog.map {
            NestTracker(id: UUID(), nestId: nest.id, name: $0.name, valueType: $0.valueType, unit: $0.unit)
        }
        let homeTrackers = NestTrackerTemplate.home.map {
            NestTracker(id: UUID(), nestId: nest.id, name: $0.name, valueType: $0.valueType, unit: $0.unit)
        }
        let milo = NestSubject(id: UUID(), nestId: nest.id, name: "Milo", kind: .pet, emoji: "🐶", pinnedActionIDs: dogTrackers.map(\.id))
        let home = NestSubject(id: UUID(), nestId: nest.id, name: "Home", kind: .thing, emoji: "🏡", pinnedActionIDs: homeTrackers.map(\.id))
        var events: [NestEntry] = [
            .init(id: UUID(), nestId: nest.id, entityId: milo.id, actionId: dogTrackers[0].id, actorUserId: jamie.id,
                  occurredAt: now.addingTimeInterval(-25 * 60), note: "A quick trip to the backyard."),
            .init(id: UUID(), nestId: nest.id, entityId: milo.id, actionId: dogTrackers[3].id, actorUserId: alex.id,
                  occurredAt: now.addingTimeInterval(-75 * 60), valueNumber: 25, note: "The long way around the park."),
            .init(id: UUID(), nestId: nest.id, entityId: milo.id, actionId: dogTrackers[1].id, actorUserId: alex.id,
                  occurredAt: now.addingTimeInterval(-80 * 60), note: "On our morning walk."),
            .init(id: UUID(), nestId: nest.id, entityId: home.id, actionId: homeTrackers[0].id, actorUserId: jamie.id,
                  occurredAt: now.addingTimeInterval(-130 * 60), note: "The kitchen herbs were thirsty."),
            .init(id: UUID(), nestId: nest.id, entityId: milo.id, actionId: dogTrackers[2].id, actorUserId: jamie.id,
                  occurredAt: now.addingTimeInterval(-160 * 60), valueNumber: 1, note: "Breakfast, all finished."),
            .init(id: UUID(), nestId: nest.id, entityId: home.id, actionId: homeTrackers[2].id, actorUserId: alex.id,
                  occurredAt: now.addingTimeInterval(-25 * 3600), valueText: "Milk, eggs, and dog treats"),
            .init(id: UUID(), nestId: nest.id, entityId: milo.id, actionId: dogTrackers[0].id, actorUserId: alex.id,
                  occurredAt: now.addingTimeInterval(-26 * 3600))
        ]
        // A little history makes the Insights chart and forecast useful on the
        // first demo launch while still looking like ordinary shared updates.
        for day in 1...4 {
            let dayOffset = Double(day) * 24 * 3600
            events.append(.init(id: UUID(), nestId: nest.id, entityId: milo.id, actionId: dogTrackers[0].id,
                                actorUserId: day.isMultiple(of: 2) ? alex.id : jamie.id,
                                occurredAt: now.addingTimeInterval(-dayOffset - 2.5 * 3600)))
            events.append(.init(id: UUID(), nestId: nest.id, entityId: milo.id, actionId: dogTrackers[1].id,
                                actorUserId: alex.id,
                                occurredAt: now.addingTimeInterval(-dayOffset - 7.0 * 3600), note: "A normal day for Milo."))
            events.append(.init(id: UUID(), nestId: nest.id, entityId: milo.id, actionId: dogTrackers[2].id,
                                actorUserId: jamie.id,
                                occurredAt: now.addingTimeInterval(-dayOffset - 8.0 * 3600), valueNumber: day.isMultiple(of: 2) ? 1.25 : 1.0))
            events.append(.init(id: UUID(), nestId: nest.id, entityId: milo.id, actionId: dogTrackers[3].id,
                                actorUserId: alex.id,
                                occurredAt: now.addingTimeInterval(-dayOffset - 9.0 * 3600), valueNumber: 20 + Double(day) * 5))
        }
        let snapshot = NestSnapshot(subjects: [milo, home], trackers: dogTrackers + homeTrackers,
                                    entries: events, members: [alex, jamie])
        return NestArchive(user: alex, nests: [nest], selectedNestID: nest.id, snapshots: [nest.id.uuidString: snapshot])
    }
}
