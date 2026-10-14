import SwiftUI
import Charts

struct AdminAnalyticsView: View {
    @EnvironmentObject private var store: NesticStore
    @State private var days = 30
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
                        Chart(data.daily) { day in
                            LineMark(x:.value("Day",day.date),y:.value("Page views",day.pageViews)).foregroundStyle(by:.value("Metric","Page views"))
                            LineMark(x:.value("Day",day.date),y:.value("App Store clicks",day.appStoreClicks)).foregroundStyle(by:.value("Metric","App Store clicks"))
                        }.frame(height:200)
                        ForEach(data.daily.reversed().prefix(14)) { day in
                            VStack(alignment:.leading) { Text(day.date).font(.subheadline.weight(.semibold)); Text("\(day.pageViews) views · \(day.appStoreClicks) store clicks · \(day.newAccounts) accounts · \(day.recordedUpdates) updates").font(.caption).foregroundStyle(.secondary) }
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
                } else if let error { Text(error).foregroundStyle(.red) } else { ProgressView("Loading analytics…") }
            } else { ContentUnavailableView("Administrator access required",systemImage:"lock") }
        }.formStyle().navigationTitle("Traffic & growth").task(id:days) { await refresh() }.refreshable { await refresh() }
    }
    private func refresh() async {
        guard store.currentUser?.isAdmin == true && !store.isDemo else { return }
        do { data = try await store.loadUsageAnalytics(days:days); error = nil } catch { self.error = error.localizedDescription }
    }
    @ViewBuilder private func breakdown(_ title: String,_ rows: [NesticUsageDimension]) -> some View {
        Section(title) {
            ForEach(rows.prefix(20)) { row in LabeledContent(title.hasPrefix("Countries") ? (Locale.current.localizedString(forRegionCode:row.name) ?? row.name) : row.name,value:row.count.formatted()) }
            if rows.isEmpty { Text("No opted-in data yet").foregroundStyle(.secondary) }
        }
    }
}
