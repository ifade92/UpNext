//
//  PaywallView.swift
//  UpNext
//
//  The subscription paywall shown to shop owners who haven't subscribed yet.
//  Two tiers: Base ($49.99/mo) and Multi-Location ($79.99/mo).
//
//  NOTE: When RevenueCat is not yet linked as a Swift Package, this file compiles
//  as a simple placeholder. Add RevenueCat via SPM and the full paywall
//  implementation will automatically activate via #if canImport(RevenueCat).
//

import SwiftUI

#if canImport(RevenueCat)
import RevenueCat

struct PaywallView: View {

    @StateObject private var manager = SubscriptionManager.shared
    @EnvironmentObject var authViewModel: AuthViewModel
    @State private var showError = false

    /// Which plan the user has selected — defaults to base
    @State private var selectedPlan: PlanOption = .base

    enum PlanOption { case base, multi }

    var body: some View {
        ZStack {
            Color.brandNearBlack.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    logoSection
                        .padding(.top, 52)
                        .padding(.bottom, 32)

                    featureList
                        .padding(.horizontal, 24)
                        .padding(.bottom, 28)

                    planCards
                        .padding(.horizontal, 24)
                        .padding(.bottom, 20)

                    subscribeButton
                        .padding(.horizontal, 24)
                        .padding(.bottom, 16)

                    guaranteeBadge
                        .padding(.horizontal, 24)
                        .padding(.bottom, 24)

                    footerSection
                        .padding(.bottom, 40)
                }
            }

            // Processing overlay
            if manager.isPurchasing {
                Color.black.opacity(0.5).ignoresSafeArea()
                ProgressView("Processing...")
                    .tint(.white)
                    .foregroundColor(.white)
                    .padding(24)
                    .background(.ultraThinMaterial)
                    .cornerRadius(16)
            }
        }
        .task {
            await manager.fetchOfferings()
        }
        .alert("Something went wrong", isPresented: $showError, actions: {
            Button("OK") { manager.errorMessage = nil }
        }, message: {
            Text(manager.errorMessage ?? "Please try again.")
        })
        .onChange(of: manager.errorMessage) { _, msg in
            showError = msg != nil
        }
    }

    // MARK: - Logo Section

    private var logoSection: some View {
        VStack(spacing: 20) {
            // UpNext dot mark
            VStack(alignment: .leading, spacing: 6) {
                Circle()
                    .fill(Color.brandDotBg)
                    .frame(width: 12, height: 12)
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.accent)
                    .frame(width: 40, height: 12)
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.brandDotBg)
                    .frame(width: 24, height: 12)
            }

            VStack(spacing: 8) {
                Text("Run your shop smarter.")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)

                Text("Built by a barbershop owner,\nfor barbershop owners.")
                    .font(.system(size: 15))
                    .foregroundColor(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
        }
    }

    // MARK: - Feature List

    private var featureList: some View {
        VStack(spacing: 14) {
            featureRow(icon: "list.number",       text: "Live queue management with unlimited barbers")
            featureRow(icon: "chart.bar.fill",    text: "Analytics — daily, weekly, monthly breakdowns")
            featureRow(icon: "qrcode",            text: "QR code check-in — clients scan and sign in")
            featureRow(icon: "antenna.radiowaves.left.and.right", text: "Remote check-in — join the queue from anywhere")
            featureRow(icon: "person.badge.plus", text: "Barber invite links — no manual setup")
            featureRow(icon: "ipad.landscape",    text: "Walk-in kiosk mode for your iPad")
            featureRow(icon: "bell.fill",         text: "Push notifications — know the moment a walk-in signs in")
        }
        .padding(20)
        .background(Color.white.opacity(0.05))
        .cornerRadius(16)
    }

    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.accent)
                .frame(width: 24)
            Text(text)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
    }

    // MARK: - Plan Cards
    //
    // Multi-Location plan is built and ready but hidden until the feature ships.
    // To show it: set showMultiLocationPlan = true below.

    /// Flip this to true once multi-location features are built and ready to sell.
    private let showMultiLocationPlan = false

    private var planCards: some View {
        VStack(spacing: 12) {
            // --- Base Plan Card ---
            planCard(
                plan: .base,
                title: "Base",
                subtitle: "Everything you need to run your shop",
                package: manager.basePackage,
                features: [
                    "Unlimited barbers",
                    "Queue + kiosk + analytics",
                    "QR code + remote check-in",
                    "Push notifications"
                ]
            )

            // --- Multi-Location Plan Card (hidden until feature ships) ---
            if showMultiLocationPlan {
                planCard(
                    plan: .multi,
                    title: "Multi-Location",
                    subtitle: "For shops with more than one location",
                    package: manager.multiPackage,
                    features: [
                        "Everything in Base",
                        "Unlimited locations",
                        "Cross-location analytics",
                        "Location switcher"
                    ],
                    badge: "Best Value"
                )
            }
        }
    }

    /// A single selectable plan card
    private func planCard(
        plan: PlanOption,
        title: String,
        subtitle: String,
        package: Package?,
        features: [String],
        badge: String? = nil
    ) -> some View {
        let isSelected = selectedPlan == plan

        return Button { selectedPlan = plan } label: {
            VStack(alignment: .leading, spacing: 12) {
                // Header row: plan name + price
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(title)
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(.white)
                            if let badge {
                                Text(badge)
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(.brandNearBlack)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Color.accent)
                                    .cornerRadius(6)
                            }
                        }
                        Text(subtitle)
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.5))
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        if let package {
                            // Live price from RevenueCat
                            Text(package.localizedPriceString)
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(.white)
                        } else {
                            // Fallback price when RevenueCat hasn't loaded yet
                            // (e.g. simulator, no network, first launch)
                            Text(plan == .base ? "$49.99" : "$79.99")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(.white)
                        }
                        Text("/month")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.4))
                    }
                }

                // Feature checklist
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(features, id: \.self) { feature in
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.accent)
                            Text(feature)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.white.opacity(0.75))
                        }
                    }
                }
                .padding(.top, 4)
            }
            .padding(18)
            .background(Color.white.opacity(isSelected ? 0.08 : 0.03))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? Color.accent : Color.white.opacity(0.08), lineWidth: isSelected ? 2 : 1)
            )
            .cornerRadius(16)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Subscribe Button

    private var subscribeButton: some View {
        let activePackage: Package? = selectedPlan == .base ? manager.basePackage : manager.multiPackage
        let planName = selectedPlan == .base ? "Base" : "Multi-Location"

        return Button {
            guard let package = activePackage else { return }
            Task { await manager.purchase(package: package) }
        } label: {
            HStack {
                Spacer()
                if manager.isPurchasing {
                    ProgressView().tint(.brandNearBlack)
                } else {
                    Text("Subscribe to \(planName)")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.brandNearBlack)
                }
                Spacer()
            }
            .frame(height: 54)
            .background(activePackage != nil ? Color.accent : Color.gray.opacity(0.3))
            .cornerRadius(14)
        }
        .disabled(manager.isPurchasing || activePackage == nil)
    }

    // MARK: - 30-Day Money-Back Guarantee

    private var guaranteeBadge: some View {
        HStack(spacing: 10) {
            Image(systemName: "shield.checkered")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("30-day money-back guarantee")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white.opacity(0.85))
                Text("Not for you? Email support@upnext-app.com for a full refund.")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.45))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accent.opacity(0.07))
        .cornerRadius(12)
    }

    // MARK: - Footer

    private var footerSection: some View {
        VStack(spacing: 12) {
            Button("Restore Purchases") {
                Task { await manager.restorePurchases() }
            }
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(.white.opacity(0.4))

            Text("Subscription automatically renews. Cancel anytime in Settings > Apple ID > Subscriptions. Payment is charged to your Apple ID account at confirmation of purchase.")
                .font(.system(size: 10))
                .foregroundColor(.white.opacity(0.25))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }
}

#else

// ── STUB ── RevenueCat not yet linked. PaywallView is never shown anyway
// because paywallBypassed = true in ContentView. This placeholder satisfies
// the type reference so everything else compiles.
struct PaywallView: View {
    @EnvironmentObject var authViewModel: AuthViewModel
    var body: some View {
        ZStack {
            Color.brandNearBlack.ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView().tint(.accent)
                Text("Subscription setup coming soon.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
    }
}

#endif

#Preview {
    PaywallView()
        .environmentObject(AuthViewModel())
}
