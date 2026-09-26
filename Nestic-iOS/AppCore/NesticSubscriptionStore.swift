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

    init() {
        hasPredictionAccess = false
        updatesTask = Task { [weak self] in
            for await _ in Transaction.updates {
                await self?.refreshEntitlement()
            }
        }
    }

    deinit { updatesTask?.cancel() }

    var priceDescription: String { product?.displayPrice ?? "$4.99/month" }

    func load() async {
        do {
            product = try await Product.products(for: [Self.predictionProductID]).first
            await refreshEntitlement()
        } catch {
            errorMessage = "Predictions are not available for purchase yet."
        }
    }

    func purchase() async {
        guard let product else {
            errorMessage = "The predictions subscription is still being configured."
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await product.purchase()
            if case .success(let verification) = result {
                let transaction = try checkVerified(verification)
                await transaction.finish()
                await refreshEntitlement()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func restorePurchases() async {
        isLoading = true
        defer { isLoading = false }
        do {
            try await AppStore.sync()
            await refreshEntitlement()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Gives the sample nest a local preview path while App Store Connect is
    /// being configured. Production access still comes from StoreKit.
    func enableSamplePreview() {
        hasPredictionAccess = true
    }

    private func refreshEntitlement() async {
        var entitled = false
        for await result in Transaction.currentEntitlements {
            if let transaction = try? checkVerified(result), transaction.productID == Self.predictionProductID,
               transaction.revocationDate == nil {
                entitled = true
            }
        }
        hasPredictionAccess = entitled
    }

    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let value): return value
        case .unverified: throw NesticError.message("The App Store transaction could not be verified.")
        }
    }
}
