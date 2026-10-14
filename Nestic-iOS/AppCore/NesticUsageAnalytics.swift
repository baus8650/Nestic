import Foundation
import UIKit

struct NesticUsageDimension: Decodable, Identifiable { var id: String { name }; let name: String; let count: Int }
struct NesticUsageDay: Decodable, Identifiable { var id: String { date }; let date: String; let pageViews: Int; let appOpens: Int; let appStoreClicks: Int; let newAccounts: Int; let recordedUpdates: Int }
struct NesticUsageVisit: Decodable, Identifiable {
    let id: UUID; let date: Date; let source: String; let kind: String; let path: String; let consented: Bool
    let country: String?; let region: String?; let city: String?; let device: String?; let browser: String?; let os: String?; let version: String?; let language: String?; let timezone: String?; let referrer: String?; let campaign: String?
}
struct NesticUsageDashboard: Decodable {
    let days: Int; let pageViews: Int; let appOpens: Int; let appStoreClicks: Int; let consentedSessions: Int; let detailedEvents: Int; let newAccounts: Int; let recordedUpdates: Int
    let daily: [NesticUsageDay]; let countries: [NesticUsageDimension]; let cities: [NesticUsageDimension]; let devices: [NesticUsageDimension]; let browsers: [NesticUsageDimension]; let operatingSystems: [NesticUsageDimension]; let referrers: [NesticUsageDimension]; let pages: [NesticUsageDimension]; let campaigns: [NesticUsageDimension]; let timezones: [NesticUsageDimension]; let recent: [NesticUsageVisit]
}
@MainActor enum NesticUsageAnalytics {
    static let preferenceKey = "nestic.shareUsageAnalytics"
    private static let sessionID = UUID()
    private static var lastSent = Date.distantPast
    static func send(serverURL: String, path: String = "home") async {
        guard UserDefaults.standard.bool(forKey: preferenceKey), let base = URL(string: serverURL), Date().timeIntervalSince(lastSent) > 10 else { return }
        lastSent = Date()
        let body: [String:Any] = ["id":UUID().uuidString,"sessionID":sessionID.uuidString,"source":"ios","kind":"app_open","path":path,"consented":true,"device":UIDevice.current.model,"os":"iOS " + UIDevice.current.systemVersion,"version":Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "Unknown","language":Locale.preferredLanguages.first ?? "Unknown","timezone":TimeZone.current.identifier]
        var request = URLRequest(url:base.appendingPathComponent("analytics/events")); request.httpMethod = "POST"; request.timeoutInterval = 8
        request.setValue("application/json",forHTTPHeaderField:"Content-Type"); request.httpBody = try? JSONSerialization.data(withJSONObject:body)
        _ = try? await URLSession.shared.data(for:request)
    }
}
