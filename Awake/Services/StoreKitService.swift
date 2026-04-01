import StoreKit
import Foundation
import os

@MainActor
final class StoreKitService: ObservableObject {
    // Product IDs — must match App Store Connect exactly
    static let proProductID = "com.jasonculbertson.awake.ai.pro"
    static let monthlyProductID = "com.jasonculbertson.awake.ai.monthly"
    static let yearlyProductID = "com.jasonculbertson.awake.ai.yearly"

    @Published var proProduct: Product?
    @Published var monthlyProduct: Product?
    @Published var yearlyProduct: Product?
    @Published var hasPurchased: Bool = false
    @Published var isPurchasing: Bool = false
    @Published var purchaseError: String?

    private let logger = Logger(subsystem: Constants.appName, category: "StoreKit")
    private var listenerTask: Task<Void, Never>?

    init() {
        listenerTask = Task { await self.listenForTransactions() }
        Task {
            await loadProducts()
            await updatePurchaseStatus()
        }
    }

    deinit {
        listenerTask?.cancel()
    }

    // MARK: - Products

    func loadProducts() async {
        do {
            let products = try await Product.products(for: [
                Self.proProductID,
                Self.monthlyProductID,
                Self.yearlyProductID,
            ])
            for product in products {
                switch product.id {
                case Self.proProductID:      proProduct = product
                case Self.monthlyProductID:  monthlyProduct = product
                case Self.yearlyProductID:   yearlyProduct = product
                default: break
                }
            }
        } catch {
            logger.error("Failed to load products: \(error.localizedDescription)")
        }
    }

    // MARK: - Purchase

    func purchase(_ product: Product) async {
        isPurchasing = true
        purchaseError = nil

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    purchaseError = "Purchase could not be verified."
                    break
                }
                await transaction.finish()
                await updatePurchaseStatus()
            case .userCancelled:
                break
            case .pending:
                purchaseError = "Purchase is pending approval."
            @unknown default:
                break
            }
        } catch {
            purchaseError = error.localizedDescription
            logger.error("Purchase failed: \(error.localizedDescription)")
        }

        isPurchasing = false
    }

    func restorePurchases() async {
        isPurchasing = true
        do {
            try await AppStore.sync()
            await updatePurchaseStatus()
        } catch {
            purchaseError = "Restore failed: \(error.localizedDescription)"
        }
        isPurchasing = false
    }

    // MARK: - Status

    func updatePurchaseStatus() async {
        var purchased = false
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            guard transaction.revocationDate == nil else { continue }
            switch transaction.productID {
            case Self.proProductID, Self.monthlyProductID, Self.yearlyProductID:
                purchased = true
            default:
                break
            }
        }
        hasPurchased = purchased
    }

    /// AI is unlocked if the user has purchased any tier OR has their own API key
    func hasAIAccess(hasBYOK: Bool) -> Bool {
        hasBYOK || hasPurchased
    }

    // MARK: - Transaction listener

    private func listenForTransactions() async {
        for await result in Transaction.updates {
            guard case .verified(let transaction) = result else { continue }
            await updatePurchaseStatus()
            await transaction.finish()
        }
    }
}
