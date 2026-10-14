import SwiftUI
import Charts

struct AdminAnalyticsView: View {
    @EnvironmentObject private var store: NesticStore
    @State private var days = 30
    @State private var metric = AdminTrafficMetric.pageViews
    @State private var data: NesticUsageDashboard?
    @State private var error: String?
    var body: some View {
        List {
            if store.currentUser?.isAdmin == true && !store.isDemo {
                Section {
                    Picker("Period",selection:$days) { Text("7 days").tag(7); Text("30 days").tag(30); Text("90 days").tag(90) }.pickerStyle(.segmented)
                    Text("Traffic counts are estimates, not unique people or confirmed App Store installs. Geography and device details cover visitors who opt in. Daily totals use UTC.").font(.caption).foregroundStyle(.secondary)
                }
                if let data {
                    Section("Traction") {
                        LabeledContent("Website page views",value:data.pageViews.formatted())
                        LabeledContent("App Store link clicks",value:data.appStoreClicks.formatted())
                        LabeledContent("Opted-in app opens",value:data.appOpens.formatted())
                        LabeledContent("Opted-in sessions",value:data.consentedSessions.formatted())
                        LabeledContent("New accounts",value:data.newAccounts.formatted())
                        LabeledContent("Recorded updates",value:data.recordedUpdates.formatted())
                    }
                    Section("Daily activity · UTC") {
                        Picker("Show in graph", selection: $metric) {
                            ForEach(AdminTrafficMetric.allCases) { metric in
                                Text(metric.rawValue).tag(metric)
                            }
                        }
                        .pickerStyle(.menu)
                        Chart(data.daily) { day in
                            BarMark(x: .value("Day", day.date), y: .value(metric.rawValue, metric.count(on: day)))
                                .foregroundStyle(NesticTheme.forest)
                        }
                        .chartXAxis(.hidden)
                        .frame(height: 200)
                        .accessibilityLabel("Daily \(metric.rawValue.lowercased()) over \(data.days) days, UTC")
                        HStack {
                            Text(data.daily.first?.date ?? "")
                            Spacer()
                            Text(data.daily.last?.date ?? "")
                        }
                        .font(.caption).foregroundStyle(.secondary)
                        DisclosureGroup("Daily totals · \(data.days) days") {
                            ForEach(data.daily.reversed()) { day in
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(day.date).font(.subheadline.weight(.semibold))
                                    Text("\(day.pageViews) views · \(day.appOpens) app opens · \(day.appStoreClicks) store clicks")
                                    Text("\(day.newAccounts) new accounts · \(day.recordedUpdates) recorded updates")
                                }
                                .font(.caption).foregroundStyle(.secondary)
                                .accessibilityElement(children: .combine)
                            }
                        }
                    }
                    breakdown("Countries · approximate",data.countries)
                    breakdown("Cities · approximate",data.cities)
                    breakdown("Devices",data.devices); breakdown("Browsers",data.browsers); breakdown("Operating systems",data.operatingSystems)
                    breakdown("Referral sites",data.referrers); breakdown("Campaigns",data.campaigns); breakdown("Pages",data.pages); breakdown("Time zones",data.timezones)
                    Section("Recent traffic") {
                        ForEach(data.recent) { visit in
                            VStack(alignment:.leading,spacing:4) {
                                Text("\(visit.source) · \(visit.kind.replacingOccurrences(of:"_",with:" ")) · \(visit.path)").font(.subheadline.weight(.semibold))
                                Text(visit.date.formatted(date:.abbreviated,time:.shortened)).font(.caption)
                                if visit.consented {
                                    Text([visit.country.map { Locale.current.localizedString(forRegionCode:$0) ?? $0 },visit.region,visit.city,visit.device,visit.browser,visit.os,visit.version,visit.timezone,visit.language,visit.referrer,visit.campaign].compactMap { $0 }.joined(separator:" · ")).font(.caption).foregroundStyle(.secondary)
                                } else { Text("Anonymous count only").font(.caption).foregroundStyle(.secondary) }
                            }
                        }
                    }
                    Section { Link("IP Geolocation by DB-IP",destination:URL(string:"https://db-ip.com")!); Text("Country, region and city estimates use offline DB-IP Lite databases. VPNs and relays can differ from the visitor’s actual location. Raw IPs and tracker content are not stored in analytics. Event retention: 90 days.").font(.caption).foregroundStyle(.secondary) }
                } else if let error {
                    Section {
                        Text("Couldn’t load analytics").font(.headline)
                        Text(error).font(.subheadline).foregroundStyle(.secondary)
                        Button("Try again") { Task { await refresh() } }
                    }
                } else { ProgressView("Loading analytics…") }
            } else { ContentUnavailableView("Administrator access required",systemImage:"lock") }
        }.formStyle().navigationTitle("Traffic & growth").task(id:days) { await refresh() }.refreshable { await refresh() }
    }
    private func refresh() async {
        guard store.currentUser?.isAdmin == true && !store.isDemo else { return }
        let requestedDays = days
        data = nil
        error = nil
        do {
            let result = try await store.loadUsageAnalytics(days: requestedDays)
            guard !Task.isCancelled, requestedDays == days else { return }
            data = result
        } catch {
            guard !Task.isCancelled, requestedDays == days else { return }
            self.error = error.localizedDescription
        }
    }
    @ViewBuilder private func breakdown(_ title: String,_ rows: [NesticUsageDimension]) -> some View {
        Section(title) {
            ForEach(rows.prefix(20)) { row in LabeledContent(title.hasPrefix("Countries") ? (Locale.current.localizedString(forRegionCode:row.name) ?? row.name) : row.name,value:row.count.formatted()) }
            if rows.isEmpty { Text("No opted-in data yet").foregroundStyle(.secondary) }
        }
    }
}


private enum AdminTrafficMetric: String, CaseIterable, Identifiable {
    case pageViews = "Website views"
    case appOpens = "App opens"
    case storeClicks = "App Store clicks"
    case accounts = "New accounts"
    case updates = "Recorded updates"
    var id: String { rawValue }
    func count(on day: NesticUsageDay) -> Int {
        switch self {
        case .pageViews: day.pageViews
        case .appOpens: day.appOpens
        case .storeClicks: day.appStoreClicks
        case .accounts: day.newAccounts
        case .updates: day.recordedUpdates
        }
    }
}
