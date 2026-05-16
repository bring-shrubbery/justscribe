//
//  TipJarService.swift
//  justscribe
//
//  Tip jar / "Support the project" feature backed by StoreKit 2
//  consumable IAPs. Purchases unlock nothing — they only let users
//  thank the developer. Register the product IDs in App Store Connect:
//
//      com.quassum.justscribe.tip.small
//      com.quassum.justscribe.tip.medium
//      com.quassum.justscribe.tip.large
//      com.quassum.justscribe.tip.huge
//
//  For local testing without App Store Connect, add a StoreKit
//  Configuration file (File > New > File > StoreKit Configuration File)
//  and enable it in the scheme's Run > Options.
//

import Foundation
import StoreKit

@MainActor
@Observable
final class TipJarService {
    static let shared = TipJarService()

    /// Product identifiers as registered in App Store Connect.
    /// Ordered small → huge; sorted again by actual price after fetch.
    static let productIDs: [String] = [
        "com.quassum.justscribe.tip.small",
        "com.quassum.justscribe.tip.medium",
        "com.quassum.justscribe.tip.large",
        "com.quassum.justscribe.tip.huge",
    ]

    private static let totalCountKey = "tipJar.totalCount"

    private(set) var products: [Product] = []
    private(set) var isLoadingProducts: Bool = false
    private(set) var purchasingProductID: String?
    private(set) var totalTipsPurchased: Int = 0
    private(set) var lastError: String?

    private var transactionListener: Task<Void, Never>?

    private init() {
        totalTipsPurchased = UserDefaults.standard.integer(forKey: Self.totalCountKey)
        transactionListener = listenForTransactions()
    }

    // MARK: - Discovery

    func loadProducts() async {
        guard products.isEmpty, !isLoadingProducts else { return }
        isLoadingProducts = true
        defer { isLoadingProducts = false }

        do {
            let fetched = try await Product.products(for: Self.productIDs)
            products = fetched.sorted { $0.price < $1.price }
        } catch {
            lastError = "Couldn't load tip options: \(error.localizedDescription)"
            print("TipJarService load failed: \(error)")
        }
    }

    // MARK: - Purchase

    func purchase(_ product: Product) async {
        guard purchasingProductID == nil else { return }
        purchasingProductID = product.id
        lastError = nil
        defer { purchasingProductID = nil }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    recordTip()
                    await transaction.finish()
                case .unverified(_, let error):
                    lastError = "Transaction could not be verified: \(error.localizedDescription)"
                }
            case .userCancelled:
                break
            case .pending:
                lastError = "Purchase is pending approval."
            @unknown default:
                break
            }
        } catch {
            lastError = error.localizedDescription
            print("TipJarService purchase failed: \(error)")
        }
    }

    private func recordTip() {
        totalTipsPurchased += 1
        UserDefaults.standard.set(totalTipsPurchased, forKey: Self.totalCountKey)
    }

    // MARK: - Transaction Updates

    private func listenForTransactions() -> Task<Void, Never> {
        Task { [weak self] in
            for await update in Transaction.updates {
                if case .verified(let transaction) = update {
                    self?.recordTip()
                    await transaction.finish()
                }
            }
        }
    }
}
