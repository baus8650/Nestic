import SwiftUI

@main
struct Nestic_iOSApp: App {
    @StateObject private var store = NesticStore()
    @StateObject private var subscription = NesticSubscriptionStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            NesticRootView()
                .environmentObject(store)
                .environmentObject(subscription)
                .tint(NesticTheme.forest)
                .task {
                    if ProcessInfo.processInfo.arguments.contains("--demo") {
                        store.enterDemo(reset: ProcessInfo.processInfo.arguments.contains("--reset-demo"))
                    }
                    await store.start()
                    await subscription.load()
                }
                .onOpenURL { url in
                    Task { await store.handleDeepLink(url) }
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active && store.isAuthenticated {
                        Task { try? await store.refresh() }
                    }
                }
        }
    }
}
