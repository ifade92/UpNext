//
//  ShopSettingsView.swift
//  UpNext
//
//  Settings hub — accessed from the ⚙️ icon in the dashboard header.
//  Opens a NavigationStack with 4 sections:
//
//    Account  — password reset, booking link
//    Barbers  — add, edit (name + type), delete, reorder
//    Services — add, edit (name + duration + price), toggle active, delete
//    Shop     — auto-close schedule
//

import SwiftUI
import CoreImage.CIFilterBuiltins
import FirebaseAuth

// MARK: - ShopSettingsView (Hub)

struct ShopSettingsView: View {

    @StateObject var viewModel: ShopSettingsViewModel
    @Environment(\.dismiss) private var dismiss

    // When shown as a tab (not a sheet), hide the Done button
    var showDismissButton: Bool = true

    // Sign out action — passed in from the parent
    var onSignOut: (() -> Void)? = nil

    // The logged-in user's barber ID — used to load their booking link in Account
    var barberId: String? = nil

    // The logged-in AppUser — passed to AccountSettingsView for notification prefs
    var appUser: AppUser? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                Color.brandNearBlack.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {

                        // ── Four settings sections ─────────────────────────
                        VStack(spacing: 0) {
                            navRow(
                                icon: "person.circle.fill",
                                title: "Account",
                                subtitle: "Password & booking link",
                                destination: AnyView(
                                    AccountSettingsView(viewModel: viewModel, barberId: barberId, appUser: appUser)
                                )
                            )
                            rowDivider
                            navRow(
                                icon: "person.2.fill",
                                title: "Barbers",
                                subtitle: "Add, edit, reorder",
                                destination: AnyView(
                                    BarberSettingsView(viewModel: viewModel)
                                )
                            )
                            rowDivider
                            navRow(
                                icon: "scissors",
                                title: "Services",
                                subtitle: "Menu, pricing, availability",
                                destination: AnyView(
                                    ServiceSettingsView(viewModel: viewModel)
                                )
                            )
                            rowDivider
                            navRow(
                                icon: "clock.fill",
                                title: "Shop",
                                subtitle: "Auto-close, schedule",
                                destination: AnyView(
                                    ShopConfigView(viewModel: viewModel)
                                )
                            )
                            rowDivider
                            navRow(
                                icon: "calendar.badge.clock",
                                title: "History",
                                subtitle: "Browse any past day's walk-in sheet",
                                destination: AnyView(
                                    HistoryView(shopId: viewModel.shopId)
                                )
                            )
                        }
                        .background(Color.brandInput)
                        .cornerRadius(14)

                        // ── Sign Out ───────────────────────────────────────
                        if let signOut = onSignOut {
                            Button(action: signOut) {
                                HStack(spacing: 8) {
                                    Image(systemName: "rectangle.portrait.and.arrow.right")
                                    Text("Sign Out")
                                }
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(.red.opacity(0.8))
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                                .background(Color.red.opacity(0.08))
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.red.opacity(0.2), lineWidth: 1)
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                if showDismissButton {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                            .foregroundColor(.accent)
                    }
                }
            }
        }
        .onAppear  { viewModel.onAppear()    }
        .onDisappear { viewModel.onDisappear() }
        .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") { viewModel.clearError() }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    // MARK: - Nav Row

    private func navRow(icon: String, title: String, subtitle: String, destination: AnyView) -> some View {
        NavigationLink(destination: destination) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.accent.opacity(0.12))
                        .frame(width: 36, height: 36)
                    Image(systemName: icon)
                        .font(.system(size: 15))
                        .foregroundColor(.accent)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.gray)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.gray.opacity(0.4))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var rowDivider: some View {
        Divider()
            .background(Color.gray.opacity(0.15))
            .padding(.leading, 62)
    }
}


// MARK: - Account Settings

struct AccountSettingsView: View {

    @ObservedObject var viewModel: ShopSettingsViewModel

    // Logged-in user's barber ID — used to pre-fill and save their booking link
    var barberId: String?

    // The logged-in AppUser — passed in so we can read/update notification prefs
    var appUser: AppUser?

    @State private var bookingUrl: String = ""
    @State private var bookingLinkSaved = false

    // Notification preference — initialized from appUser, updated locally on toggle
    @State private var notificationsEnabled: Bool = true

    // Subscription state — drives the SUBSCRIPTION section's labels and
    // the App Store vs Stripe branching for the Manage button.
    // Pattern mirrors PaywallView.
    @StateObject private var subscriptionManager = SubscriptionManager.shared
    @EnvironmentObject var authViewModel: AuthViewModel

    // Password reset state
    @State private var showResetAlert: Bool = false
    @State private var resetEmail: String = ""
    @State private var resetEmailSent: Bool = false

    // Look up the current user's barber doc to pre-fill booking URL
    private var myBarber: Barber? {
        guard let bid = barberId else { return nil }
        return viewModel.barbers.first(where: { $0.id == bid })
    }

    var body: some View {
        ZStack {
            Color.brandNearBlack.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {

                    // ── Account ───────────────────────────────────────────
                    sectionLabel("ACCOUNT")

                    VStack(spacing: 0) {
                        // Reset Password
                        Button(action: { showResetAlert = true }) {
                            HStack(spacing: 14) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.accent.opacity(0.12))
                                        .frame(width: 36, height: 36)
                                    Image(systemName: "key.fill")
                                        .font(.system(size: 14))
                                        .foregroundColor(.accent)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Reset Password")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.white)
                                    Text("Send a reset link to your email")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.gray.opacity(0.4))
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .background(Color.brandInput)
                    .cornerRadius(14)

                    // ── Subscription ──────────────────────────────────────
                    // Hidden for non-subscribers (defensive — section only makes
                    // sense for users who actually have an active subscription).
                    subscriptionSection

                    // ── Notifications ─────────────────────────────────────
                    sectionLabel("NOTIFICATIONS")

                    VStack(spacing: 0) {
                        HStack(spacing: 14) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.accent.opacity(0.12))
                                    .frame(width: 36, height: 36)
                                Image(systemName: "bell.fill")
                                    .font(.system(size: 14))
                                    .foregroundColor(.accent)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Walk-In Alerts")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                                Text("Get notified when a customer checks in")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                            Spacer()
                            Toggle("", isOn: $notificationsEnabled)
                                .tint(.accent)
                                .labelsHidden()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                    }
                    .background(Color.brandInput)
                    .cornerRadius(14)

                    // ── Booking Link ──────────────────────────────────────
                    sectionLabel("BOOKING LINK")

                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 10) {
                            Image(systemName: "link")
                                .font(.system(size: 15))
                                .foregroundColor(.accent)
                                .frame(width: 28)

                            VStack(alignment: .leading, spacing: 3) {
                                Text("Your Booking Link")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                                Text("Shown as a QR on the kiosk when you're offline")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                        }

                        TextField("https://square.site/...", text: $bookingUrl)
                            .textFieldStyle(BrandTextFieldStyle())
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()

                        Button(action: saveBookingLink) {
                            Text(bookingLinkSaved ? "✓ Saved" : "Save Booking Link")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.accent)
                                .cornerRadius(10)
                        }
                    }
                    .padding(14)
                    .background(Color.brandInput)
                    .cornerRadius(14)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
        }
        .navigationTitle("Account")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .onAppear {
            bookingUrl = myBarber?.bookingUrl ?? ""
            notificationsEnabled = appUser?.wantsNotifications ?? true
        }
        // Save notification preference when the toggle changes
        .onChange(of: notificationsEnabled) { _, newValue in
            guard let userId = appUser?.id else { return }
            Task {
                try? await FirebaseService.shared.updateNotificationPreference(
                    userId: userId,
                    enabled: newValue
                )
            }
        }
        // Password reset alert
        .alert("Reset Password", isPresented: $showResetAlert) {
            TextField("Your email address", text: $resetEmail)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
            Button("Send Reset Link") {
                Task {
                    try? await FirebaseAuth.Auth.auth().sendPasswordReset(
                        withEmail: resetEmail.trimmingCharacters(in: .whitespaces)
                    )
                    resetEmailSent = true
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("We'll send a password reset link to your email.")
        }
        .alert("Check Your Email", isPresented: $resetEmailSent) {
            Button("Got it", role: .cancel) {}
        } message: {
            Text("A reset link has been sent. Check your inbox.")
        }
    }

    private func saveBookingLink() {
        guard let bid = barberId else { return }
        viewModel.saveBookingLink(barberId: bid, url: bookingUrl)
        withAnimation { bookingLinkSaved = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            bookingLinkSaved = false
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        HStack {
            Text(text)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.gray)
                .tracking(1.2)
            Spacer()
        }
        .padding(.top, 4)
    }

    // MARK: - Subscription Section

    /// SUBSCRIPTION block. Always rendered for owners reaching this Settings
    /// screen — anyone here has bypassed the paywall (subscribed or DEBUG)
    /// and benefits from seeing their plan / Manage / Resubscribe path.
    /// We don't gate on `shop?.subscriptionStatus` because the Shop decoder
    /// can fail silently if a Firestore field is missing or unrecognized,
    /// which would leave this whole section invisible for no obvious reason.
    @ViewBuilder
    private var subscriptionSection: some View {
        sectionLabel("SUBSCRIPTION")

        VStack(spacing: 0) {
            // Plan label (read-only)
            infoRow(icon: "creditcard.fill", title: "Plan", value: planLabel)
            Divider().background(Color.gray.opacity(0.15)).padding(.leading, 62)

            // Status (read-only)
            infoRow(icon: "checkmark.seal.fill", title: "Status", value: statusLabel)
            Divider().background(Color.gray.opacity(0.15)).padding(.leading, 62)

            // Action row — Manage or Resubscribe depending on state
            actionRow
        }
        .background(Color.brandInput)
        .cornerRadius(14)

        // Refund / cross-platform note. Apple owns iOS refunds — we can't
        // process them ourselves, and the App Store rules require us to
        // direct iOS users to Apple for refunds.
        Text("Within 30 days of purchase? Email support@upnext-app.com for a refund. iOS purchases must be refunded via Apple.")
            .font(.caption2)
            .foregroundColor(.gray)
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 4)
            .padding(.top, 2)
    }

    /// True when the shop's Stripe subscription is in the cancelled terminal
    /// state — they need a Resubscribe path back into the funnel, not a
    /// Manage Subscription path. App Store-cancelled users don't reach this
    /// branch because they get paywalled before they can open Settings.
    private var isCancelledStripeShop: Bool {
        !subscriptionManager.isSubscribed
            && authViewModel.shop?.subscriptionStatus == .cancelled
    }

    /// Plan label — App Store path derives from RevenueCat (because the
    /// shop doc may be stale due to the iOS→Firestore sync gap). Stripe path
    /// reads straight from `shop.subscriptionTier`.
    private var planLabel: String {
        if subscriptionManager.isSubscribed {
            // App Store path
            let tierName = subscriptionManager.isMultiLocation ? "Multi-Location" : "Single Location"
            return "App Store · \(tierName)"
        }
        // Stripe path — pull from shop doc
        if let tier = authViewModel.shop?.subscriptionTier {
            let price = String(format: "$%.2f", tier.monthlyPrice)
            return "\(tier.displayName) · \(price)/month"
        }
        return "—"
    }

    /// Status label — App Store: always "Active" (we only render this section
    /// if `isSubscribed == true`, so by definition it's active). Stripe: read
    /// the live status off the shop doc.
    private var statusLabel: String {
        if subscriptionManager.isSubscribed {
            return "Active"
        }
        guard let status = authViewModel.shop?.subscriptionStatus else { return "—" }
        switch status {
        case .active:    return "Active"
        case .pastDue:   return "Past due"
        case .cancelled: return "Cancelled"
        case .trial:     return "Trial"
        }
    }

    /// Action row — branches on subscription state:
    ///   - Stripe cancelled → "Resubscribe" → opens web signup page
    ///   - App Store active → "Manage" via Apple's native sheet (preferred when both flags set)
    ///   - Stripe active / trial / pastDue → "Manage" via web (Stripe portal)
    @ViewBuilder
    private var actionRow: some View {
        if isCancelledStripeShop {
            // Cancelled Stripe sub → fresh resubscribe via web. The Stripe
            // Customer Portal doesn't reliably offer "renew" once a sub is
            // fully ended, so we route to the same signup flow they used
            // originally.
            Button(action: {
                if let url = URL(string: "https://upnext-app.com/signup.html") {
                    UIApplication.shared.open(url)
                }
            }) {
                manageRowContent(
                    icon: "arrow.clockwise.circle.fill",
                    title: "Resubscribe",
                    subtitle: "Reactivate your subscription on the web"
                )
            }
            .buttonStyle(PlainButtonStyle())
        } else if subscriptionManager.isSubscribed {
            // App Store path → Apple's native sheet
            Button(action: {
                Task { await subscriptionManager.manageAppStoreSubscription() }
            }) {
                manageRowContent(
                    icon: "creditcard.fill",
                    title: "Manage Subscription",
                    subtitle: "Cancel or change plan via Apple"
                )
            }
            .buttonStyle(PlainButtonStyle())
        } else {
            // Stripe active / trial / pastDue → bounce to web for portal
            Button(action: {
                if let url = URL(string: "https://upnext-app.com/barber.html") {
                    UIApplication.shared.open(url)
                }
            }) {
                manageRowContent(
                    icon: "globe",
                    title: "Manage Subscription",
                    subtitle: "Your subscription is managed on the web"
                )
            }
            .buttonStyle(PlainButtonStyle())
        }
    }

    /// Shared row layout for the Manage action — keeps both branches visually
    /// identical to the other tappable rows in this view (e.g. Reset Password).
    private func manageRowContent(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.accent.opacity(0.12))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(.accent)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.gray.opacity(0.4))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    /// Read-only info row used for Plan / Status display.
    private func infoRow(icon: String, title: String, value: String) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.accent.opacity(0.12))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(.accent)
            }
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.white)
            Spacer()
            Text(value)
                .font(.caption)
                .foregroundColor(.gray)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}


// MARK: - Barber Settings

struct BarberSettingsView: View {

    @ObservedObject var viewModel: ShopSettingsViewModel

    var body: some View {
        ZStack {
            Color.brandNearBlack.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 12) {
                    sectionHeader(
                        title: "Barbers (\(viewModel.barbers.count))",
                        buttonLabel: "Add Barber",
                        action: { viewModel.showAddBarber = true }
                    )

                    if viewModel.barbers.isEmpty {
                        emptyState(
                            icon: "person.badge.plus",
                            message: "No barbers yet.\nTap \"Add Barber\" to get started."
                        )
                    } else {
                        ForEach(Array(viewModel.barbers.enumerated()), id: \.element.id) { index, barber in
                            barberRow(barber, index: index, total: viewModel.barbers.count)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
        }
        .navigationTitle("Barbers")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .sheet(isPresented: $viewModel.showAddBarber) {
            AddBarberSheet(viewModel: viewModel)
        }
        .sheet(item: $viewModel.editingBarber) { barber in
            EditBarberSheet(barber: barber, viewModel: viewModel)
        }
    }

    // MARK: - Barber Row

    private func barberRow(_ barber: Barber, index: Int, total: Int) -> some View {
        HStack(spacing: 12) {
            // Avatar circle
            ZStack {
                Circle()
                    .fill(barber.goLive ? Color.accent : Color.brandDotBg)
                    .frame(width: 42, height: 42)
                Text(String(barber.name.prefix(1)).uppercased())
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(barber.goLive ? .black : .gray)
            }

            // Name + type badge
            VStack(alignment: .leading, spacing: 3) {
                Text(barber.name)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)

                HStack(spacing: 6) {
                    Text(barber.goLive ? "Live" : "Offline")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(barber.goLive ? .accent : .gray)
                }
            }

            Spacer()

            // Reorder buttons
            VStack(spacing: 4) {
                Button(action: {
                    guard index > 0 else { return }
                    viewModel.moveBarbers(from: IndexSet(integer: index), to: index - 1)
                }) {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(index == 0 ? .gray.opacity(0.2) : .gray)
                }
                .disabled(index == 0)

                Button(action: {
                    guard index < total - 1 else { return }
                    viewModel.moveBarbers(from: IndexSet(integer: index), to: index + 2)
                }) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(index == total - 1 ? .gray.opacity(0.2) : .gray)
                }
                .disabled(index == total - 1)
            }
            .frame(width: 28)

            // Live / Offline toggle — owner can flip any barber on or off
            Button(action: { viewModel.toggleBarberLive(barber) }) {
                Text(barber.goLive ? "● Live" : "Offline")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(barber.goLive ? .black : .gray)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(barber.goLive ? Color.accent : Color.white.opacity(0.1))
                    .cornerRadius(20)
            }

            // Edit button
            Button(action: { viewModel.editingBarber = barber }) {
                Text("Edit")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.accent.opacity(0.12))
                    .cornerRadius(7)
            }

            // Delete button
            Button(role: .destructive, action: { viewModel.deleteBarber(barber) }) {
                Image(systemName: "trash")
                    .font(.system(size: 13))
                    .foregroundColor(.red.opacity(0.7))
            }
        }
        .padding(12)
        .background(Color.brandInput)
        .cornerRadius(12)
    }

    // MARK: - Shared Helpers

    private func sectionHeader(title: String, buttonLabel: String, action: @escaping () -> Void) -> some View {
        HStack {
            Text(title.uppercased())
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.gray)
                .tracking(1.2)
            Spacer()
            Button(action: action) {
                HStack(spacing: 5) {
                    Image(systemName: "plus").font(.system(size: 11, weight: .bold))
                    Text(buttonLabel).font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(.black)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Color.accent)
                .cornerRadius(8)
            }
        }
        .padding(.top, 8)
    }

    private func emptyState(icon: String, message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 32)).foregroundColor(.gray.opacity(0.4))
            Text(message).font(.subheadline).foregroundColor(.gray).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}


// MARK: - Service Settings

struct ServiceSettingsView: View {

    @ObservedObject var viewModel: ShopSettingsViewModel

    var body: some View {
        ZStack {
            Color.brandNearBlack.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 12) {
                    sectionHeader(
                        title: "Services (\(viewModel.services.count))",
                        buttonLabel: "Add Service",
                        action: { viewModel.showAddService = true }
                    )

                    if viewModel.services.isEmpty {
                        emptyState(
                            icon: "list.bullet.rectangle",
                            message: "No services yet.\nTap \"Add Service\" to get started."
                        )
                    } else {
                        ForEach(viewModel.services) { service in
                            serviceRow(service)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
        }
        .navigationTitle("Services")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .sheet(isPresented: $viewModel.showAddService) {
            AddServiceSheet(viewModel: viewModel)
        }
        .sheet(item: $viewModel.editingService) { service in
            EditServiceSheet(service: service, viewModel: viewModel)
        }
    }

    // MARK: - Service Row

    private func serviceRow(_ service: Service) -> some View {
        HStack(spacing: 14) {
            // Active/inactive indicator dot
            Circle()
                .fill(service.active ? Color.accent : Color.gray.opacity(0.4))
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 3) {
                Text(service.name)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(service.active ? .white : .gray)

                HStack(spacing: 8) {
                    Label(service.displayDuration, systemImage: "clock")
                        .font(.caption)
                        .foregroundColor(.gray)

                    if let _ = service.price {
                        Text("·").foregroundColor(.gray)
                        Text(service.displayPrice)
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
            }

            Spacer()

            // Active toggle
            Button(action: { viewModel.toggleServiceActive(service) }) {
                Text(service.active ? "Active" : "Hidden")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(service.active ? .accent : .gray)
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .background(service.active ? Color.accent.opacity(0.12) : Color.brandDotBg)
                    .cornerRadius(7)
            }

            // Edit button
            Button(action: { viewModel.editingService = service }) {
                Image(systemName: "pencil")
                    .font(.system(size: 14))
                    .foregroundColor(.accent)
                    .frame(width: 34, height: 34)
                    .background(Color.brandDotBg)
                    .cornerRadius(8)
            }

            // Delete button
            Button(role: .destructive, action: { viewModel.deleteService(service) }) {
                Image(systemName: "trash")
                    .font(.system(size: 14))
                    .foregroundColor(.red.opacity(0.8))
                    .frame(width: 34, height: 34)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(8)
            }
        }
        .padding(14)
        .background(Color.brandInput)
        .cornerRadius(14)
        .opacity(service.active ? 1.0 : 0.6)
    }

    // MARK: - Shared Helpers

    private func sectionHeader(title: String, buttonLabel: String, action: @escaping () -> Void) -> some View {
        HStack {
            Text(title.uppercased())
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.gray)
                .tracking(1.2)
            Spacer()
            Button(action: action) {
                HStack(spacing: 5) {
                    Image(systemName: "plus").font(.system(size: 11, weight: .bold))
                    Text(buttonLabel).font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(.black)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Color.accent)
                .cornerRadius(8)
            }
        }
        .padding(.top, 8)
    }

    private func emptyState(icon: String, message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 32)).foregroundColor(.gray.opacity(0.4))
            Text(message).font(.subheadline).foregroundColor(.gray).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}


// MARK: - Shop Config

struct ShopConfigView: View {

    @ObservedObject var viewModel: ShopSettingsViewModel
    @State private var showQRSheet = false
    @State private var inviteCopied = false
    @State private var waitLinkCopied = false

    var body: some View {
        ZStack {
            Color.brandNearBlack.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {

                    // ── Shop Code + QR + Live Queue ──────────────────────
                    shopCodeBanner

                    HStack {
                        Text("SCHEDULE")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.gray)
                            .tracking(1.2)
                        Spacer()
                    }
                    .padding(.top, 8)

                    // Auto-Close card
                    VStack(alignment: .leading, spacing: 14) {

                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Auto-Close Time")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                                Text("All barbers go offline automatically at this time every night. Individual barbers still control their own availability during the day.")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { viewModel.autoCloseEnabled },
                                set: { enabled in
                                    viewModel.autoCloseEnabled = enabled
                                    if enabled && viewModel.autoCloseTime == nil {
                                        var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
                                        comps.hour = 21; comps.minute = 0
                                        viewModel.autoCloseTime = Calendar.current.date(from: comps)
                                    }
                                    viewModel.saveAutoCloseTime()
                                }
                            ))
                            .tint(.accent)
                            .labelsHidden()
                        }

                        if viewModel.autoCloseEnabled {
                            Divider().background(Color.gray.opacity(0.2))

                            HStack {
                                Text("Close at")
                                    .font(.subheadline)
                                    .foregroundColor(.white)
                                Spacer()
                                DatePicker(
                                    "",
                                    selection: Binding(
                                        get: { viewModel.autoCloseTime ?? Date() },
                                        set: { newTime in
                                            viewModel.autoCloseTime = newTime
                                            viewModel.saveAutoCloseTime()
                                        }
                                    ),
                                    displayedComponents: .hourAndMinute
                                )
                                .datePickerStyle(.compact)
                                .labelsHidden()
                                .tint(.accent)
                                .colorScheme(.dark)
                            }

                            HStack(spacing: 6) {
                                Image(systemName: "moon.stars.fill").font(.caption2).foregroundColor(.accent)
                                Text("Every night at this time, all barbers will be taken offline and the walk-in list will show no availability.")
                                    .font(.caption2)
                                    .foregroundColor(.gray)
                            }
                            .padding(10)
                            .background(Color.accent.opacity(0.07))
                            .cornerRadius(8)
                        }
                    }
                    .padding(14)
                    .background(Color.brandInput)
                    .cornerRadius(14)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
        }
        .navigationTitle("Shop")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .sheet(isPresented: $showQRSheet) {
            ShopCheckInQRSheet(shopId: viewModel.shopId)
        }
    }

    // MARK: - Shop Code Banner

    private var shopCodeBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "key.fill")
                    .font(.caption)
                    .foregroundColor(.accent)
                Text("Shop Code")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.accent)
            }

            HStack {
                Text(viewModel.shopId)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button(action: { UIPasteboard.general.string = viewModel.shopId }) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 13))
                        .foregroundColor(.accent)
                }
            }

            Text("Share this code with your barbers so they can create their login in the app.")
                .font(.caption2)
                .foregroundColor(.gray)

            HStack(spacing: 10) {
                Button(action: { showQRSheet = true }) {
                    HStack(spacing: 6) {
                        Image(systemName: "qrcode").font(.system(size: 12))
                        Text("Check-In QR").font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.accent)
                    .cornerRadius(9)
                }

                Button(action: {
                    let urlString = "https://upnext-4ec7a.web.app/queue?shop=\(viewModel.shopId)"
                    if let url = URL(string: urlString) { UIApplication.shared.open(url) }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "tv").font(.system(size: 12))
                        Text("Live Queue").font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.accent.opacity(0.1))
                    .cornerRadius(9)
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.accent.opacity(0.3), lineWidth: 1))
                }
            }

            // Invite link — barbers tap this and land on /join with code pre-filled
            Button(action: {
                let inviteURL = "https://upnext-app.com/join?code=\(viewModel.shopId)"
                UIPasteboard.general.string = inviteURL
                inviteCopied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { inviteCopied = false }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: inviteCopied ? "checkmark" : "link")
                        .font(.system(size: 12))
                    Text(inviteCopied ? "Copied!" : "Copy Barber Invite Link")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(inviteCopied ? .green : .accent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.accent.opacity(0.05))
                .cornerRadius(9)
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.accent.opacity(0.2), lineWidth: 1))
            }

            // Wait time link — share with customers so they can check the wait before walking in
            Button(action: {
                let waitURL = "https://upnext-app.com/wait?shop=\(viewModel.shopId)"
                UIPasteboard.general.string = waitURL
                waitLinkCopied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { waitLinkCopied = false }
            }) {
                HStack(spacing: 6) {
                    Image(systemName: waitLinkCopied ? "checkmark" : "timer")
                        .font(.system(size: 12))
                    Text(waitLinkCopied ? "Copied!" : "Copy Wait Time Link")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(waitLinkCopied ? .green : Color.yellow.opacity(0.9))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.yellow.opacity(0.05))
                .cornerRadius(9)
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.yellow.opacity(0.2), lineWidth: 1))
            }
        }
        .padding(14)
        .background(Color.accent.opacity(0.07))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.accent.opacity(0.2), lineWidth: 1))
    }
}


// MARK: - Add Barber Sheet

struct AddBarberSheet: View {

    @ObservedObject var viewModel: ShopSettingsViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var email = ""
    @State private var barberType: BarberType = .walkin

    var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.brandNearBlack.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {

                        // Name field
                        VStack(alignment: .leading, spacing: 8) {
                            fieldLabel("Barber Name")
                            TextField("e.g. Marcus", text: $name)
                                .textFieldStyle(BrandTextFieldStyle())
                        }

                        // Email field — used for the barber's app login (Firebase email auth)
                        VStack(alignment: .leading, spacing: 8) {
                            fieldLabel("Email (for app login)")
                            TextField("barber@example.com", text: $email)
                                .textFieldStyle(BrandTextFieldStyle())
                                .keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()

                            Text("The barber will use this email + your Shop Code to create their own login.")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }

                        // Barber type picker
                        VStack(alignment: .leading, spacing: 8) {
                            fieldLabel("Barber Type")
                            barberTypePicker
                            typeDescription
                        }

                        Spacer(minLength: 20)

                        // Save button
                        Button(action: {
                            viewModel.addBarber(
                                name: name.trimmingCharacters(in: .whitespaces),
                                email: email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                                barberType: barberType
                            )
                            dismiss()
                        }) {
                            Text("Add Barber")
                                .font(.headline)
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(canSave ? Color.accent : Color.gray.opacity(0.3))
                                .cornerRadius(14)
                        }
                        .disabled(!canSave)
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Add Barber")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(.accent)
                }
            }
        }
    }

    private var barberTypePicker: some View {
        HStack(spacing: 0) {
            ForEach([BarberType.walkin, .hybrid, .appointmentOnly], id: \.self) { type in
                Button(action: { barberType = type }) {
                    Text(type == .appointmentOnly ? "Appt Only" : type.displayName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(barberType == type ? .black : .gray)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(barberType == type ? Color.accent : Color.brandInput)
                }
                if type != .appointmentOnly {
                    Divider().frame(height: 36).background(Color.gray.opacity(0.2))
                }
            }
        }
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.brandDotBg, lineWidth: 1))
    }

    private var typeDescription: some View {
        Text(typeDescriptionText)
            .font(.caption)
            .foregroundColor(.gray)
            .padding(.top, 2)
    }

    private var typeDescriptionText: String {
        switch barberType {
        case .walkin:          return "Always visible on the kiosk for walk-in customers."
        case .appointmentOnly: return "Hidden by default. Uses the Go Live toggle to accept walk-ins during open slots."
        case .hybrid:          return "Mix of appointments and walk-ins. Uses Go Live toggle to manage availability."
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundColor(.gray)
            .tracking(0.5)
    }
}


// MARK: - Edit Barber Sheet

struct EditBarberSheet: View {

    @State var barber: Barber
    @ObservedObject var viewModel: ShopSettingsViewModel
    @Environment(\.dismiss) private var dismiss

    // Photo picker state
    @State private var showPhotoPicker = false
    @State private var selectedPhoto: UIImage? = nil
    @State private var isUploadingPhoto = false

    // Save state — drives the Save button spinner + inline error alert.
    // We hold these on the sheet (not the view model) so errors stay visible
    // BEFORE the sheet dismisses. Previously the sheet closed instantly and
    // any save error landed in the parent view where the user never saw it.
    @State private var isSaving = false
    @State private var saveError: String? = nil

    // Local text field state for the booking URL. We bind the TextField to a
    // plain @State String instead of a hand-rolled Binding(get:set:) on the
    // optional `barber.bookingUrl` — that manual binding pattern was unreliable
    // (the closures captured a snapshot of `self`, so edits didn't always
    // propagate to the saved barber struct). Initialized in .onAppear, written
    // back into `barber` at save time.
    @State private var bookingUrlField: String = ""

    // Binding helpers for optional String fields
    // Email is the barber's login identifier — what they use with Firebase Auth.
    // Phone is retained on the Barber model for backward compat but is no longer collected here.
    private var emailBinding: Binding<String> {
        Binding(get: { barber.email ?? "" }, set: { barber.email = $0.isEmpty ? nil : $0 })
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.brandNearBlack.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {

                        // --- Photo ---
                        photoSection

                        // --- Name ---
                        VStack(alignment: .leading, spacing: 8) {
                            fieldLabel("Barber Name")
                            TextField("Barber name", text: $barber.name)
                                .textFieldStyle(BrandTextFieldStyle())
                        }

                        // --- Email (for app login) ---
                        // Matched against the barber's Firebase Auth email when they sign in
                        // via the Barber app. Must be unique across the shop.
                        VStack(alignment: .leading, spacing: 8) {
                            fieldLabel("Email (for app login)")
                            TextField("barber@example.com", text: emailBinding)
                                .textFieldStyle(BrandTextFieldStyle())
                                .keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                            Text("The barber will use this email + your Shop Code to create their login.")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }

                        // --- Booking URL ---
                        // Bound to the local @State `bookingUrlField` (not directly
                        // to barber.bookingUrl) — see note on `bookingUrlField` above.
                        VStack(alignment: .leading, spacing: 8) {
                            fieldLabel("Booking Site URL (optional)")
                            TextField("https://square.site/...", text: $bookingUrlField)
                                .textFieldStyle(BrandTextFieldStyle())
                                .keyboardType(.URL)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                            Text("Shown as a QR code on the kiosk when this barber isn't accepting walk-ins.")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }

                        // --- Barber Type ---
                        VStack(alignment: .leading, spacing: 8) {
                            fieldLabel("Barber Type")
                            Picker("Barber Type", selection: $barber.barberType) {
                                Text("Walk-In").tag(BarberType.walkin)
                                Text("Hybrid").tag(BarberType.hybrid)
                                Text("Appt Only").tag(BarberType.appointmentOnly)
                            }
                            .pickerStyle(.segmented)
                        }

                        // --- Status ---
                        VStack(alignment: .leading, spacing: 8) {
                            fieldLabel("Status")
                            Picker("Status", selection: $barber.status) {
                                Text("Available").tag(BarberStatus.available)
                                Text("On Break").tag(BarberStatus.onBreak)
                                Text("Off").tag(BarberStatus.off)
                            }
                            .pickerStyle(.segmented)
                        }

                        // --- Go Live toggle (appointment/hybrid only) ---
                        if barber.barberType != .walkin {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Go Live")
                                        .font(.subheadline).fontWeight(.semibold).foregroundColor(.white)
                                    Text("Show on kiosk for walk-in customers")
                                        .font(.caption).foregroundColor(.gray)
                                }
                                Spacer()
                                Toggle("", isOn: $barber.goLive).tint(.accent)
                            }
                            .padding(14)
                            .background(Color.brandInput)
                            .cornerRadius(12)
                        }

                        Spacer(minLength: 20)

                        // Save button — awaits the Firestore write so we can
                        // surface errors INLINE (alert below) before dismissing
                        // the sheet. The previous fire-and-forget version called
                        // dismiss() immediately, so any save error landed in the
                        // parent view's errorMessage and the user never saw it.
                        Button(action: saveTapped) {
                            HStack(spacing: 10) {
                                if isSaving {
                                    ProgressView().tint(.black)
                                }
                                Text(isSaving ? "Saving…" : "Save Changes")
                                    .font(.headline).foregroundColor(.black)
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 16)
                            .background(Color.accent).cornerRadius(14)
                        }
                        .disabled(isSaving)
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Edit Barber")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(.accent)
                        .disabled(isSaving)
                }
            }
            // Seed local field state from the barber when the sheet opens.
            // Doing this here (vs. an init) keeps @State the source of truth.
            .onAppear {
                bookingUrlField = barber.bookingUrl ?? ""
            }
            // Inline save-error alert — fires when saveTapped catches an error.
            .alert(
                "Couldn't save barber",
                isPresented: Binding(
                    get: { saveError != nil },
                    set: { if !$0 { saveError = nil } }
                )
            ) {
                Button("OK", role: .cancel) { saveError = nil }
            } message: {
                Text(saveError ?? "")
            }
            // Photo picker sheet
            .sheet(isPresented: $showPhotoPicker) {
                BarberPhotoPicker(selectedImage: $selectedPhoto)
            }
            // Upload photo when one is selected
            .onChange(of: selectedPhoto) { _, image in
                guard let image = image, let barberId = barber.id else { return }
                isUploadingPhoto = true
                Task {
                    do {
                        let url = try await FirebaseService.shared.uploadBarberPhoto(
                            shopId: viewModel.shopId,
                            barberId: barberId,
                            image: image
                        )
                        barber.photoUrl = url
                        try await FirebaseService.shared.updateBarberPhotoUrl(
                            shopId: viewModel.shopId,
                            barberId: barberId,
                            url: url
                        )
                    } catch {
                        viewModel.errorMessage = "Photo upload failed: \(error.localizedDescription)"
                    }
                    isUploadingPhoto = false
                }
            }
        }
    }

    // MARK: - Save

    /// Awaits the Firestore write and only dismisses on success.
    /// On failure, surfaces the error in the `saveError` alert so the
    /// user actually sees what went wrong (e.g. permissions, network).
    private func saveTapped() {
        guard !isSaving else { return }

        // Pull the latest text from the local field, trim whitespace,
        // and write it back into the barber struct before saving.
        // (Trimming matches what AccountSettingsView's saveBookingLink does
        //  so the kiosk doesn't choke on a leading/trailing space in the URL.)
        let trimmed = bookingUrlField.trimmingCharacters(in: .whitespacesAndNewlines)
        barber.bookingUrl = trimmed.isEmpty ? nil : trimmed

        isSaving = true
        Task {
            do {
                try await viewModel.updateBarber(barber)
                isSaving = false
                dismiss()
            } catch {
                isSaving = false
                saveError = error.localizedDescription
            }
        }
    }

    // MARK: - Photo Section

    private var photoSection: some View {
        VStack(spacing: 12) {
            // Photo circle — shows uploaded photo or initial avatar
            ZStack {
                Circle()
                    .fill(Color.brandDotBg)
                    .frame(width: 88, height: 88)

                if isUploadingPhoto {
                    ProgressView().tint(.accent)
                } else if let photo = selectedPhoto {
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 88, height: 88)
                        .clipShape(Circle())
                } else if let urlString = barber.photoUrl, let url = URL(string: urlString) {
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        ProgressView().tint(.accent)
                    }
                    .frame(width: 88, height: 88)
                    .clipShape(Circle())
                } else {
                    Text(String(barber.name.prefix(1)).uppercased())
                        .font(.system(size: 32, weight: .bold))
                        .foregroundColor(.gray)
                }

                // Camera icon overlay in bottom-right corner
                Button(action: { showPhotoPicker = true }) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.black)
                        .frame(width: 26, height: 26)
                        .background(Color.accent)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.brandNearBlack, lineWidth: 2))
                }
                .offset(x: 28, y: 28)
            }
            .frame(width: 88, height: 88)

            Text("Tap the camera to add a photo")
                .font(.caption)
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text).font(.caption).fontWeight(.semibold).foregroundColor(.gray).tracking(0.5)
    }
}


// MARK: - Add Service Sheet

struct AddServiceSheet: View {

    @ObservedObject var viewModel: ShopSettingsViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var minutes = "30"
    @State private var priceText = ""      // Empty = no price shown on kiosk

    var body: some View {
        NavigationStack {
            ZStack {
                Color.brandNearBlack.ignoresSafeArea()

                VStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        fieldLabel("Service Name")
                        TextField("e.g. Fade, Haircut & Beard", text: $name)
                            .textFieldStyle(BrandTextFieldStyle())
                    }

                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 8) {
                            fieldLabel("Duration (minutes)")
                            TextField("30", text: $minutes)
                                .textFieldStyle(BrandTextFieldStyle())
                                .keyboardType(.numberPad)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            fieldLabel("Price (optional)")
                            TextField("35", text: $priceText)
                                .textFieldStyle(BrandTextFieldStyle())
                                .keyboardType(.decimalPad)
                        }
                    }

                    Text("Leave price blank to hide pricing on the kiosk.")
                        .font(.caption)
                        .foregroundColor(.gray)

                    Spacer()

                    Button(action: {
                        let mins = Int(minutes) ?? 30
                        let price = Double(priceText)
                        viewModel.addService(
                            name: name.trimmingCharacters(in: .whitespaces),
                            estimatedMinutes: mins,
                            price: price
                        )
                        dismiss()
                    }) {
                        Text("Add Service")
                            .font(.headline)
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(name.isEmpty ? Color.gray.opacity(0.3) : Color.accent)
                            .cornerRadius(14)
                    }
                    .disabled(name.isEmpty)
                }
                .padding(20)
            }
            .navigationTitle("Add Service")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(.accent)
                }
            }
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundColor(.gray)
            .tracking(0.5)
    }
}


// MARK: - Edit Service Sheet

struct EditServiceSheet: View {

    @State var service: Service
    @ObservedObject var viewModel: ShopSettingsViewModel
    @Environment(\.dismiss) private var dismiss

    // Price is stored as Double? but we edit it as a string in the text field
    @State private var priceText: String = ""

    init(service: Service, viewModel: ShopSettingsViewModel) {
        _service = State(initialValue: service)
        self.viewModel = viewModel
        // Pre-fill price text if the service has a price
        _priceText = State(initialValue: service.price.map { String(format: "%.0f", $0) } ?? "")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.brandNearBlack.ignoresSafeArea()

                VStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        fieldLabel("Service Name")
                        TextField("Service name", text: $service.name)
                            .textFieldStyle(BrandTextFieldStyle())
                    }

                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 8) {
                            fieldLabel("Duration (minutes)")
                            TextField("30", value: $service.estimatedMinutes, format: .number)
                                .textFieldStyle(BrandTextFieldStyle())
                                .keyboardType(.numberPad)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            fieldLabel("Price (optional)")
                            TextField("35", text: $priceText)
                                .textFieldStyle(BrandTextFieldStyle())
                                .keyboardType(.decimalPad)
                        }
                    }

                    // Active toggle
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Show on Kiosk")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                            Text("Hide to temporarily remove from customer check-in")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        Spacer()
                        Toggle("", isOn: $service.active)
                            .tint(.accent)
                    }
                    .padding(14)
                    .background(Color.brandInput)
                    .cornerRadius(12)

                    Spacer()

                    Button(action: {
                        service.price = Double(priceText)
                        viewModel.saveService(service)
                        dismiss()
                    }) {
                        Text("Save Changes")
                            .font(.headline)
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.accent)
                            .cornerRadius(14)
                    }
                }
                .padding(20)
            }
            .navigationTitle("Edit Service")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(.accent)
                }
            }
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundColor(.gray)
            .tracking(0.5)
    }
}


// MARK: - Brand Text Field Style

/// Reusable text field styling that matches the UpNext dark theme.
struct BrandTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(14)
            .background(Color.brandInput)
            .cornerRadius(10)
            .foregroundColor(.white)
            .font(.subheadline)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.brandDotBg, lineWidth: 1)
            )
    }
}


// MARK: - Barber Photo Picker

/// Wraps PHPickerViewController (iOS native image picker) in a SwiftUI sheet.
/// Returns the selected UIImage via the selectedImage binding.
import PhotosUI

struct BarberPhotoPicker: UIViewControllerRepresentable {

    @Binding var selectedImage: UIImage?
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: BarberPhotoPicker

        init(_ parent: BarberPhotoPicker) {
            self.parent = parent
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)

            guard let result = results.first else { return }

            result.itemProvider.loadObject(ofClass: UIImage.self) { object, _ in
                DispatchQueue.main.async {
                    self.parent.selectedImage = object as? UIImage
                }
            }
        }
    }
}


// MARK: - Shop Check-In QR Sheet

/// Full-screen sheet showing the QR code for this shop's check-in page.
struct ShopCheckInQRSheet: View {

    let shopId: String
    @Environment(\.dismiss) private var dismiss

    // Loaded async when the sheet appears so the printable poster can
    // include the shop's actual name. Falls back to a generic subtitle.
    @State private var shopName: String = ""

    // Drives the system share sheet used for saving / printing the PDF.
    @State private var posterURL: URL? = nil
    @State private var showShareSheet: Bool = false
    @State private var isBuildingPoster: Bool = false

    private var checkInURL: String {
        "https://upnext-4ec7a.web.app/checkin?shop=\(shopId)&source=qr"
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 28) {
                HStack {
                    Spacer()
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 26))
                            .foregroundColor(.gray)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)

                Spacer()

                HStack(spacing: 8) {
                    UpNextMark(size: 20)
                    HStack(spacing: 0) {
                        Text("Up").font(.custom("Outfit-Bold", size: 22)).foregroundColor(.white)
                        Text("Next").font(.custom("Outfit-Bold", size: 22)).foregroundColor(.accent)
                    }
                }

                VStack(spacing: 6) {
                    Text("Check-In QR Code")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.white)
                    Text("Customers scan this to join your queue")
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                }

                if let qrImage = generateQR(from: checkInURL) {
                    Image(uiImage: qrImage)
                        .interpolation(.none)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 240, height: 240)
                        .padding(20)
                        .background(Color.white)
                        .cornerRadius(20)
                } else {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 240, height: 240)
                }

                Text(checkInURL)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Button(action: { UIPasteboard.general.string = checkInURL }) {
                    HStack(spacing: 8) {
                        Image(systemName: "link").font(.system(size: 13))
                        Text("Copy Check-In Link").font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.accent.opacity(0.1))
                    .cornerRadius(12)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.accent.opacity(0.25), lineWidth: 1))
                }
                .padding(.horizontal, 32)

                // ── Printable Poster ────────────────────────────────────────
                // Generates a print-ready US-Letter PDF with this shop's QR
                // plus "Scan to check in" headline. Owners can AirPrint it
                // directly or save it to Files to print at a shop later.
                Button(action: { buildAndSharePoster() }) {
                    HStack(spacing: 8) {
                        if isBuildingPoster {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .black))
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "printer.fill").font(.system(size: 13))
                        }
                        Text(isBuildingPoster ? "Preparing…" : "Download Printable Poster")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.accent)
                    .cornerRadius(12)
                }
                .disabled(isBuildingPoster)
                .padding(.horizontal, 32)

                Spacer()
            }
        }
        .task {
            // Grab the shop name once so we can stamp it on the poster.
            // Non-fatal if it fails — the generator handles an empty name.
            if shopName.isEmpty {
                if let shop = try? await FirebaseService.shared.fetchShop(shopId: shopId) {
                    shopName = shop.name
                }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = posterURL {
                ShareSheet(items: [url])
            }
        }
    }

    // MARK: - Poster

    /// Builds the PDF off the main thread (to keep the UI responsive while
    /// CoreImage renders the QR) then presents the system share sheet.
    private func buildAndSharePoster() {
        guard !isBuildingPoster else { return }
        isBuildingPoster = true

        let name = shopName
        let url = checkInURL

        Task.detached(priority: .userInitiated) {
            let pdfURL = CheckInPosterGenerator.makePDF(shopName: name, checkInURL: url)
            await MainActor.run {
                self.isBuildingPoster = false
                if let pdfURL {
                    self.posterURL = pdfURL
                    self.showShareSheet = true
                }
            }
        }
    }

    private func generateQR(from string: String) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "H"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}


// MARK: - Barber Settings Sheet
//
// The standalone settings screen for barbers (accessed from BarberQueueView).
// Owners have the full ShopSettingsView; barbers just need account + notifications + sign out.

struct BarberSettingsSheet: View {

    var barber: Barber?
    var appUser: AppUser?
    var onDone: () -> Void
    var onSignOut: () -> Void

    @State private var notificationsEnabled: Bool = true
    @State private var showResetAlert: Bool = false
    @State private var resetEmail: String = ""
    @State private var resetEmailSent: Bool = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.brandNearBlack.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {

                        // ── Account ───────────────────────────────────────
                        VStack(spacing: 0) {
                            if let barber {
                                HStack {
                                    Text("Name")
                                        .font(.subheadline)
                                        .foregroundColor(.white)
                                    Spacer()
                                    Text(barber.name)
                                        .font(.subheadline)
                                        .foregroundColor(.gray)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)

                                Divider().background(Color.gray.opacity(0.15)).padding(.leading, 14)
                            }

                            // Reset Password
                            Button(action: { showResetAlert = true }) {
                                HStack {
                                    Text("Reset Password")
                                        .font(.subheadline)
                                        .foregroundColor(.white)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(.gray.opacity(0.4))
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        .background(Color.brandInput)
                        .cornerRadius(14)

                        // ── Notifications ─────────────────────────────────
                        VStack(spacing: 0) {
                            HStack(spacing: 14) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.accent.opacity(0.12))
                                        .frame(width: 36, height: 36)
                                    Image(systemName: "bell.fill")
                                        .font(.system(size: 14))
                                        .foregroundColor(.accent)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Walk-In Alerts")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.white)
                                    Text("Get notified when a customer checks in")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }
                                Spacer()
                                Toggle("", isOn: $notificationsEnabled)
                                    .tint(.accent)
                                    .labelsHidden()
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                        }
                        .background(Color.brandInput)
                        .cornerRadius(14)

                        // ── Sign Out ──────────────────────────────────────
                        Button(action: onSignOut) {
                            HStack(spacing: 8) {
                                Image(systemName: "rectangle.portrait.and.arrow.right")
                                Text("Sign Out")
                            }
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.red.opacity(0.8))
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(Color.red.opacity(0.08))
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.red.opacity(0.2), lineWidth: 1)
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { onDone() }
                        .foregroundColor(.accent)
                }
            }
        }
        .onAppear {
            notificationsEnabled = appUser?.wantsNotifications ?? true
            resetEmail = appUser?.email ?? ""
        }
        .onChange(of: notificationsEnabled) { _, newValue in
            guard let userId = appUser?.id else { return }
            Task {
                try? await FirebaseService.shared.updateNotificationPreference(
                    userId: userId,
                    enabled: newValue
                )
            }
        }
        .alert("Reset Password", isPresented: $showResetAlert) {
            TextField("Your email address", text: $resetEmail)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
            Button("Send Reset Link") {
                Task {
                    try? await Auth.auth().sendPasswordReset(
                        withEmail: resetEmail.trimmingCharacters(in: .whitespaces)
                    )
                    resetEmailSent = true
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("We'll send a reset link to your email.")
        }
        .alert("Check Your Email", isPresented: $resetEmailSent) {
            Button("Got it", role: .cancel) {}
        } message: {
            Text("A reset link has been sent. Check your inbox.")
        }
    }
}


// MARK: - Preview

#Preview {
    ShopSettingsView(
        viewModel: ShopSettingsViewModel(shopId: "test-shop")
    )
}


// MARK: - History View

/// Browse any past day's full sign-in sheet — walk-ins and appointments, who served whom.
/// Reads from the queueHistory collection, which stores all archived (completed/removed) entries.
struct HistoryView: View {

    let shopId: String

    // Selected date — defaults to yesterday so there's something to look at on first open
    @State private var selectedDate: Date = Calendar.current.date(
        byAdding: .day, value: -1, to: Calendar.current.startOfDay(for: Date())
    ) ?? Date()

    @State private var entries:  [QueueEntry] = []
    @State private var barbers:  [Barber]     = []
    @State private var isLoading = false
    @State private var errorMsg: String?      = nil

    private let firebase = FirebaseService.shared

    var body: some View {
        ZStack {
            Color.brandNearBlack.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {

                    // Date picker
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Select a date")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.45))
                        DatePicker(
                            "",
                            selection: $selectedDate,
                            in: ...Calendar.current.startOfDay(for: Date()),
                            displayedComponents: .date
                        )
                        .datePickerStyle(.compact)
                        .labelsHidden()
                        .colorScheme(.dark)
                        .onChange(of: selectedDate) { _, _ in
                            Task { await loadEntries() }
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))

                    // Summary + list
                    if isLoading {
                        ProgressView().tint(.white).padding(.top, 40)

                    } else if let err = errorMsg {
                        Text(err)
                            .font(.subheadline)
                            .foregroundStyle(.red.opacity(0.7))
                            .padding(.top, 40)

                    } else if entries.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "calendar.badge.exclamationmark")
                                .font(.system(size: 36))
                                .foregroundStyle(.white.opacity(0.2))
                            Text("No entries for this day")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.35))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)

                    } else {
                        // Stats summary row
                        let done    = entries.filter { $0.status == .completed }.count
                        let left    = entries.filter { $0.status == .walkedOut || $0.status == .removed }.count
                        HStack(spacing: 12) {
                            summaryPill("\(entries.count) Total",  color: .white.opacity(0.5))
                            summaryPill("\(done) Served",         color: Color.accent)
                            if left > 0 {
                                summaryPill("\(left) Left",       color: .red.opacity(0.7))
                            }
                        }

                        // Entry list
                        VStack(spacing: 0) {
                            ForEach(Array(entries.enumerated()), id: \.element.id) { idx, entry in
                                historyRow(entry: entry, rowIndex: idx)
                                if idx < entries.count - 1 {
                                    Divider()
                                        .background(Color.white.opacity(0.07))
                                        .padding(.leading, 56)
                                }
                            }
                        }
                        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
                        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.1), lineWidth: 1))
                    }
                }
                .padding(16)
            }
        }
        .navigationTitle(selectedDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.brandNearBlack, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .task { await loadEntries() }
    }

    // MARK: - Row

    @ViewBuilder
    private func historyRow(entry: QueueEntry, rowIndex: Int) -> some View {
        let isDone  = entry.status == .completed
        let isOut   = entry.status == .walkedOut || entry.status == .removed
        let fade    = isDone || isOut
        let barber  = barbers.first { $0.id == (entry.assignedBarberId ?? entry.barberId) }

        HStack(spacing: 12) {
            // Position
            Text("#\(rowIndex + 1)")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(fade ? .white.opacity(0.25) : .white.opacity(0.6))
                .frame(width: 36, alignment: .leading)

            // Name + detail
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(entry.customerName)
                        .font(.subheadline.weight(fade ? .regular : .semibold))
                        .strikethrough(fade)
                        .foregroundStyle(fade ? .white.opacity(0.3) : .white)
                    // Appointment badge
                    if entry.isAppointment == true {
                        Text("Appt")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.blue)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Color.blue.opacity(0.15), in: Capsule())
                    }
                    // Remote badge — shows arrival status for website check-ins
                    if entry.isRemoteCheckIn == true {
                        if entry.remoteStatus == "arrived" {
                            Text("✅ Arrived")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.green)
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(Color.green.opacity(0.15), in: Capsule())
                        } else {
                            Text("📍 On the Way")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.orange)
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(Color.orange.opacity(0.15), in: Capsule())
                        }
                    }
                }

                Group {
                    if isDone, let b = barber {
                        Label("Served by \(b.name)", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(Color.accent.opacity(0.8))
                    } else if isOut {
                        Label("Walked out", systemImage: "person.fill.xmark")
                            .foregroundStyle(.red.opacity(0.6))
                    } else {
                        Text(entry.checkInTime, format: .dateTime.hour().minute())
                            .foregroundStyle(.white.opacity(0.35))
                    }
                }
                .font(.caption)
            }

            Spacer()

            // Status chip
            statusChip(for: entry.status)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .opacity(isOut ? 0.5 : 1.0)
    }

    private func summaryPill(_ label: String, color: Color) -> some View {
        Text(label)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(color.opacity(0.1), in: Capsule())
    }

    @ViewBuilder
    private func statusChip(for status: QueueStatus) -> some View {
        switch status {
        case .completed:
            chipView("Done",    color: .gray)
        case .walkedOut:
            chipView("Left",    color: .red)
        case .removed:
            chipView("Removed", color: .red)
        case .inChair:
            chipView("In Chair", color: Color.accent)
        case .waiting:
            chipView("Waiting", color: .orange)
        case .notified:
            chipView("Notified", color: .blue)
        }
    }

    private func chipView(_ label: String, color: Color) -> some View {
        Text(label)
            .font(.caption2.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
    }

    // MARK: - Data Loading

    private func loadEntries() async {
        isLoading = true
        errorMsg  = nil

        let start = Calendar.current.startOfDay(for: selectedDate)
        let end   = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start

        do {
            // Fetch barbers once for name attribution
            if barbers.isEmpty {
                barbers = try await firebase.fetchAllBarbers(shopId: shopId)
            }

            // Pull all archived entries for the selected day
            let all = try await firebase.fetchArchivedEntries(shopId: shopId, since: start)
            entries = all
                .filter { $0.checkInTime < end }   // Cap at end of selected day
                .sorted { $0.checkInTime < $1.checkInTime }
        } catch {
            errorMsg = "Couldn't load history. Check your connection."
        }

        isLoading = false
    }
}

// MARK: - Phone Formatting Helper

/// Convert a user-typed phone number to E.164 format (+1XXXXXXXXXX).
/// Used in AddBarberSheet so the number stored in Firestore matches
/// exactly what the barber will type when logging in.
private func formatPhoneE164(_ number: String) -> String {
    let digits = number.filter { $0.isNumber }
    if digits.count == 10 {
        return "+1\(digits)"
    } else if digits.count == 11 && digits.hasPrefix("1") {
        return "+\(digits)"
    }
    return number  // Already formatted or international — pass through
}
