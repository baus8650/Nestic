import Foundation
import Combine
import StoreKit

@MainActor
final class NesticSubscriptionStore: ObservableObject {
    static let predictionProductID = "com.nestic.predictions.monthly"

    @Published private(set) var product: Product?
    @Published private(set) var hasPredictionAccess: Bool
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private var updatesTask: Task<Void, Never>?
    private var storeKitEntitlement = false
    private var manualProOverride = false

    init() {
        hasPredictionAccess = false
        updatesTask = Task { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let transaction) = result,
                   transaction.productID == Self.predictionProductID {
                    await transaction.finish()
                }
                await self?.refreshEntitlement()
            }
        }
    }

    deinit { updatesTask?.cancel() }

    var priceDescription: String {
        guard let product else { return "See subscription options" }
        guard let period = product.subscription?.subscriptionPeriod else { return product.displayPrice }
        let unit: String
        switch period.unit {
        case .day: unit = period.value == 1 ? "day" : "days"
        case .week: unit = period.value == 1 ? "week" : "weeks"
        case .month: unit = period.value == 1 ? "month" : "months"
        case .year: unit = period.value == 1 ? "year" : "years"
        @unknown default: return product.displayPrice
        }
        return "\(product.displayPrice) / \(period.value == 1 ? "" : "\(period.value) ")\(unit)"
    }

    func load() async {
        errorMessage = nil
        do {
            product = try await Product.products(for: [Self.predictionProductID]).first
            await refreshEntitlement()
            if product == nil { errorMessage = "Subscriptions are temporarily unavailable. Please try again." }
        } catch {
            errorMessage = "Couldn’t load subscriptions. Check your connection and try again."
        }
    }

    func purchase() async {
        guard let product else {
            errorMessage = "Subscriptions are temporarily unavailable. Please try again."
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let result = try await product.purchase()
            if case .success(let verification) = result {
                let transaction = try checkVerified(verification)
                await transaction.finish()
                await refreshEntitlement()
            } else if case .pending = result {
                errorMessage = "Your purchase is pending approval. Pro will unlock when the App Store confirms it."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func restorePurchases() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            try await AppStore.sync()
            await refreshEntitlement()
            if !hasPredictionAccess { errorMessage = "No active Nestic Pro subscription was found for this Apple account." }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Gives the sample nest a local preview path while App Store Connect is
    /// being configured. Production access still comes from StoreKit.
    func enableSamplePreview() {
        hasPredictionAccess = true
    }

    func setManualProOverride(_ enabled: Bool) {
        manualProOverride = enabled
        hasPredictionAccess = storeKitEntitlement || manualProOverride
    }

    func refreshAccessForBackgroundAction(manualPro: Bool) async {
        setManualProOverride(manualPro)
        await refreshEntitlement()
    }

    private func refreshEntitlement() async {
        var entitled = false
        for await result in Transaction.currentEntitlements {
            if let transaction = try? checkVerified(result), transaction.productID == Self.predictionProductID,
               transaction.revocationDate == nil {
                entitled = true
            }
        }
        storeKitEntitlement = entitled
        hasPredictionAccess = storeKitEntitlement || manualProOverride
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let value): return value
        case .unverified: throw NesticError.message("The App Store transaction could not be verified.")
        }
    }
}
