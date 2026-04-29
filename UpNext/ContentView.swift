//
//  ContentView.swift
//  UpNext
//
//  Root view — decides which screen to show based on auth + subscription state.
//
//  Flow:
//    Not logged in                              → LoginView
//    Logged in as owner, no subscription        → PaywallView
//    Logged in as owner, subscribed             → OwnerTabView
//    Logged in as barber                        → BarberTabView (no paywall — owner pays)
//    Loading                                    → Splash/loading screen
//
//  Why only gate owners?
//    Barbers are hired staff — the owner's subscription covers the whole shop.
//    Locking out barbers would break the shop's daily operations.
//
//  The AuthViewModel and SubscriptionManager both live here and are passed
//  down via @EnvironmentObject so any child view can access them.
//

import SwiftUI

// Paywall bypass — only active in DEBUG builds (Xcode previews & simulators).
// Release builds compiled for the App Store always enforce the paywall.
#if DEBUG
private let paywallBypassed = false  // Set to true to skip paywall during development
#else
private let paywallBypassed = false
#endif

struct ContentView: View {

    @StateObject private var authViewModel = AuthViewModel()
    @StateObject private var subscriptionManager = SubscriptionManager.shared

    var body: some View {
        Group {
            if authViewModel.isLoading || subscriptionManager.isLoading {
                // Shown briefly on launch while Firebase checks auth state
                // and RevenueCat checks subscription status simultaneously
                splashView

            } else if authViewModel.appUser == nil {
                // Not logged in — show the login screen
                LoginView()
                    .environmentObject(authViewModel)

            } else if authViewModel.appUser?.isOwner == true {
                // Owner path — grant access if ANY of these are true:
                //   1. DEBUG paywall bypass (development only)
                //   2. Active RevenueCat subscription (App Store subscriber)
                //   3. Active Stripe subscription (web subscriber — synced to Firestore by webhook)
                if paywallBypassed
                    || subscriptionManager.isSubscribed
                    || authViewModel.isSubscribedViaStripe {
                    OwnerTabView()
                        .environmentObject(authViewModel)
                } else {
                    // No active subscription → paywall
                    PaywallView()
                        .environmentObject(authViewModel)
                }

            } else {
                // Barber — their personal queue view (no subscription gate)
                BarberTabView()
                    .environmentObject(authViewModel)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: authViewModel.appUser == nil)
        .animation(.easeInOut(duration: 0.3), value: subscriptionManager.isSubscribed)
        .animation(.easeInOut(duration: 0.3), value: authViewModel.isSubscribedViaStripe)
        .task {
            // Kick off subscription check as soon as the app loads.
            // Runs in parallel with Firebase auth check.
            await subscriptionManager.fetchSubscriptionStatus()
        }
        .onChange(of: authViewModel.appUser?.id) { _, id in
            // When a user logs in, link their Firebase UID to RevenueCat.
            // This ensures purchase history follows the user across devices.
            if let id {
                subscriptionManager.logIn(userId: id)
            } else {
                subscriptionManager.logOut()
            }
        }
    }

    // MARK: - Splash / Loading

    private var splashView: some View {
        ZStack {
            Color.brandNearBlack.ignoresSafeArea()
            VStack(spacing: 16) {
                // UpNext dot mark — matches the app icon
                VStack(alignment: .leading, spacing: 6) {
                    Circle()
                        .fill(Color.brandDotBg)
                        .frame(width: 10, height: 10)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.accent)
                        .frame(width: 34, height: 10)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.brandDotBg)
                        .frame(width: 20, height: 10)
                }
                ProgressView()
                    .tint(.accent)
                    .padding(.top, 8)
            }
        }
    }
}

// MARK: - Owner Tab View

/// What the shop owner sees after login + successful subscription check.
/// Dashboard → Analytics → Kiosk launcher
struct OwnerTabView: View {

    @EnvironmentObject var authViewModel: AuthViewModel

    // Tracks when kiosk mode is presented full-screen.
    // While true, the tab bar is completely hidden so customers can't navigate
    // to the dashboard or analytics. Guided Access keeps them inside the app;
    // this keeps them inside the kiosk.
    @State private var kioskModeActive = false

    // Use the real shopId from the logged-in user
    private var shopId: String {
        authViewModel.appUser?.shopId ?? ""
    }

    var body: some View {
        TabView {
            // Main operations view — barber cards, queue management
            OwnerDashboardView(
                viewModel: OwnerDashboardViewModel(shopId: shopId)
            )
            .tabItem {
                Image(systemName: "square.grid.2x2")
                Text("Dashboard")
            }

            // Shop-wide analytics — walk-in counts, busiest day chart, leaderboard
            OwnerAnalyticsView(shopId: shopId)
            .tabItem {
                Image(systemName: "chart.bar.fill")
                Text("Analytics")
            }

            // Kiosk launcher — a single big button that flips kioskModeActive on,
            // which presents the real kiosk as a full-screen cover (no tab bar).
            KioskLauncherView(launch: { kioskModeActive = true })
                .tabItem {
                    Image(systemName: "ipad.landscape")
                    Text("Kiosk")
                }
        }
        .tint(.accent)
        // Full-screen cover hides the tab bar entirely — exactly what we want
        // for kiosk mode. Pair this with iOS Guided Access to fully lock down
        // the iPad for customer use.
        .fullScreenCover(isPresented: $kioskModeActive) {
            KioskModeContainer(shopId: shopId, isPresented: $kioskModeActive)
        }
    }
}

// MARK: - Kiosk Launcher

/// Shown on the Kiosk tab — a single button to enter full-screen kiosk mode.
/// Keeps the launch flow intentional so the owner doesn't accidentally hand
/// the iPad to a customer with the dashboard one tap away.
struct KioskLauncherView: View {
    let launch: () -> Void

    var body: some View {
        ZStack {
            Color.brandNearBlack.ignoresSafeArea()
            VStack(spacing: 24) {
                Image(systemName: "ipad.landscape")
                    .font(.system(size: 56))
                    .foregroundStyle(Color.accent)

                VStack(spacing: 6) {
                    Text("Kiosk Mode")
                        .font(.title.bold())
                        .foregroundStyle(.white)
                    Text("Hide the tab bar and lock this iPad to the customer check-in screen.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                Button(action: launch) {
                    Text("Launch Kiosk")
                        .font(.headline)
                        .foregroundStyle(.black)
                        .frame(maxWidth: 260)
                        .padding(.vertical, 14)
                        .background(Color.accent, in: RoundedRectangle(cornerRadius: 14))
                }
                .padding(.top, 8)

                // Quick reminder so you actually use Guided Access for full lockdown
                VStack(spacing: 4) {
                    Text("Tip: Triple-click the side button to start Guided Access")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.4))
                    Text("Settings → Accessibility → Guided Access")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.3))
                }
                .padding(.top, 12)
            }
        }
    }
}

// MARK: - Kiosk Mode Container

/// Wraps the kiosk view in full-screen and provides a discreet exit:
/// long-press the bottom-right corner for 2 seconds to bring up a PIN prompt.
struct KioskModeContainer: View {
    let shopId: String
    @Binding var isPresented: Bool

    @State private var showExitPrompt = false
    @State private var pinInput = ""
    @State private var pinError = false

    // Owner exit PIN — change this to anything memorable for you.
    // Living in code keeps it simple; could move to Firestore settings later.
    private let exitPIN = "1234"

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            KioskCheckInView(
                viewModel: KioskViewModel(shopId: shopId)
            )
            .ignoresSafeArea()

            // Invisible long-press target in the bottom-right corner.
            // Customers won't notice it; you know exactly where it is.
            Color.clear
                .frame(width: 60, height: 60)
                .contentShape(Rectangle())
                .onLongPressGesture(minimumDuration: 2.0) {
                    pinInput = ""
                    pinError = false
                    showExitPrompt = true
                }
        }
        .alert("Exit Kiosk Mode", isPresented: $showExitPrompt) {
            SecureField("PIN", text: $pinInput)
                .keyboardType(.numberPad)
            Button("Cancel", role: .cancel) { pinInput = "" }
            Button("Exit", role: .destructive) {
                if pinInput == exitPIN {
                    isPresented = false
                } else {
                    pinError = true
                }
                pinInput = ""
            }
        } message: {
            Text(pinError
                 ? "Wrong PIN — try again."
                 : "Enter your owner PIN to leave kiosk mode.")
        }
    }
}

// MARK: - Barber Tab View

/// What a barber sees after login — their queue + personal analytics.
struct BarberTabView: View {

    @EnvironmentObject var authViewModel: AuthViewModel

    private var shopId: String   { authViewModel.appUser?.shopId   ?? "" }
    private var barberId: String { authViewModel.appUser?.barberId ?? "" }
    // Full display name used in the rank banner ("Keep it up, Marcus!")
    private var barberName: String {
        authViewModel.appUser?.displayName
            ?? authViewModel.appUser?.firstName
            ?? "Barber"
    }

    var body: some View {
        TabView {
            // Their live queue — the main daily driver
            BarberQueueView(
                viewModel: BarberQueueViewModel(
                    shopId: shopId,
                    barberId: barberId
                )
            )
            .tabItem {
                Image(systemName: "list.number")
                Text("My Queue")
            }

            // Their personal stats — how many they've served today/week/month + busiest day
            BarberAnalyticsView(shopId: shopId, barberId: barberId, barberName: barberName)
            .tabItem {
                Image(systemName: "chart.bar.fill")
                Text("Analytics")
            }
        }
        .tint(.accent)
    }
}


// MARK: - Preview

#Preview {
    ContentView()
}
