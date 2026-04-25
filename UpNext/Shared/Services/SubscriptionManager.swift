//
//  SubscriptionManager.swift
//  UpNext
//
//  Central hub for all subscription logic via RevenueCat.
//
//  How it works:
//    1. RevenueCat is configured once in AppDelegate with your API key.
//    2. This manager checks entitlements to know if the shop owner is subscribed.
//    3. It exposes Offerings (base monthly + multi-location packages) for the paywall.
//    4. purchase() and restorePurchases() are the two actions a user can trigger.
//
//  Entitlement names (must match RevenueCat dashboard exactly):
//    - "UpNext Pro"   → Base tier ($49.99/mo) — unlocks all single-location features
//    - "UpNext Multi" → Multi-Location tier ($79.99/mo) — adds multi-location management
//
//  Offering identifier: "default" → RevenueCat's default offering
//  Package identifiers:
//    - Monthly (built-in) → upnext_base_monthly
//    - multi_monthly (custom) → upnext_multi_monthly
//
//  NOTE: When RevenueCat is not yet added as a Swift Package, this file compiles
//  as a lightweight stub so the rest of the app builds normally.
//

import Foundation
import Combine

#if canImport(RevenueCat)
import RevenueCat

@MainActor
class SubscriptionManager: ObservableObject {

    // MARK: - Singleton
    static let shared = SubscriptionManager()

    // MARK: - Published State

    /// True if the owner has any active subscription (Base or Multi-Location)
    @Published var isSubscribed: Bool = false

    /// True if the owner has the Multi-Location tier specifically
    @Published var isMultiLocation: Bool = false

    /// True while we're checking subscription status on launch
    @Published var isLoading: Bool = true

    /// The current offerings fetched from RevenueCat (base + multi-location packages)
    @Published var offerings: Offerings? = nil

    /// Non-nil if a purchase or restore operation fails
    @Published var errorMessage: String? = nil

    /// True while a purchase or restore is in flight
    @Published var isPurchasing: Bool = false

    // MARK: - Configure

    /// Call this once in AppDelegate after FirebaseApp.configure().
    static func configure(apiKey: String) {
        Purchases.logLevel = .error
        Purchases.configure(withAPIKey: apiKey)
    }

    // MARK: - Fetch Status

    func fetchSubscriptionStatus() async {
        isLoading = true
        do {
            let customerInfo = try await Purchases.shared.customerInfo()
            updateSubscriptionState(from: customerInfo)
        } catch {
            print("RevenueCat: Failed to fetch customer info — \(error.localizedDescription)")
            isSubscribed = false
            isMultiLocation = false
        }
        isLoading = false
    }

    // MARK: - Fetch Offerings

    func fetchOfferings() async {
        do {
            offerings = try await Purchases.shared.offerings()
        } catch {
            print("RevenueCat: Failed to fetch offerings — \(error.localizedDescription)")
        }
    }

    // MARK: - Package Helpers

    /// The base monthly package ($49.99/mo) — uses RevenueCat's built-in "Monthly" identifier
    var basePackage: Package? {
        offerings?.current?.monthly
    }

    /// The multi-location package ($79.99/mo) — uses our custom "multi_monthly" identifier
    var multiPackage: Package? {
        offerings?.current?.package(identifier: "multi_monthly")
    }

    // MARK: - Purchase

    func purchase(package: Package) async {
        isPurchasing = true
        errorMessage = nil
        do {
            let result = try await Purchases.shared.purchase(package: package)
            updateSubscriptionState(from: result.customerInfo)
        } catch let error as ErrorCode {
            if error != .purchaseCancelledError {
                errorMessage = error.localizedDescription
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isPurchasing = false
    }

    // MARK: - Restore

    func restorePurchases() async {
        isPurchasing = true
        errorMessage = nil
        do {
            let customerInfo = try await Purchases.shared.restorePurchases()
            updateSubscriptionState(from: customerInfo)
            if !isSubscribed {
                errorMessage = "No active subscription found to restore."
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isPurchasing = false
    }

    // MARK: - Log In / Out

    func logIn(userId: String) {
        Purchases.shared.logIn(userId) { _, _, error in
            if let error { print("RevenueCat logIn error: \(error.localizedDescription)") }
        }
    }

    func logOut() {
        Purchases.shared.logOut { _, error in
            if let error { print("RevenueCat logOut error: \(error.localizedDescription)") }
        }
    }

    // MARK: - Private Helpers

    /// Single place to update both subscription flags from RevenueCat customer info.
    /// "UpNext Pro" is attached to BOTH products, so it's true for any subscriber.
    /// "UpNext Multi" is only attached to the multi-location product.
    private func updateSubscriptionState(from customerInfo: CustomerInfo) {
        isSubscribed = customerInfo.entitlements["UpNext Pro"]?.isActive == true
        isMultiLocation = customerInfo.entitlements["UpNext Multi"]?.isActive == true
    }
}

#else

// ── STUB ── RevenueCat SDK not yet added as a Swift Package.
// All methods are no-ops. The paywall is bypassed in ContentView (paywallBypassed = true)
// so this stub lets the rest of the app build and run normally.

@MainActor
class SubscriptionManager: ObservableObject {

    static let shared = SubscriptionManager()

    @Published var isSubscribed:    Bool    = false
    @Published var isMultiLocation: Bool    = false
    @Published var isLoading:       Bool    = false
    @Published var offerings:       Any?    = nil
    @Published var errorMessage:    String? = nil
    @Published var isPurchasing:    Bool    = false

    static func configure(apiKey: String) { }

    func fetchSubscriptionStatus() async { isLoading = false }
    func fetchOfferings()          async { }
    func restorePurchases()        async { }
    func logIn(userId: String)           { }
    func logOut()                        { }
}

#endif
