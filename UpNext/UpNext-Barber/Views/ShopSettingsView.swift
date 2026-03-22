//
//  ShopSettingsView.swift
//  UpNext
//
//  The owner's setup screen — manage barbers and services without touching Firestore.
//  Two tabs: Barbers and Services.
//
//  Barbers tab:  add, edit (name + type), delete
//  Services tab: add, edit (name + duration + price), toggle active, delete
//

import SwiftUI
import CoreImage.CIFilterBuiltins

// MARK: - ShopSettingsView

struct ShopSettingsView: View {

    @StateObject var viewModel: ShopSettingsViewModel
    @Environment(\.dismiss) private var dismiss

    // When used as a tab (not a modal sheet), hide the back button
    var showDismissButton: Bool = true

    // Sign out action — passed in from the parent so this view doesn't
    // need to hold an AuthViewModel reference directly
    var onSignOut: (() -> Void)? = nil

    // Which tab is selected — 0 = Barbers, 1 = Services
    @State private var selectedTab = 0

    // Controls the check-in QR sheet
    @State private var showQRSheet = false

    // Reset Password alert states
    @State private var showResetPasswordConfirm = false   // "Are you sure?" prompt
    @State private var showResetPasswordSuccess = false   // Confirmation toast

    var body: some View {
        ZStack {
            Color.brandNearBlack.ignoresSafeArea()

            VStack(spacing: 0) {
                headerBar
                tabPicker

                if viewModel.isLoading {
                    loadingView
                } else {
                    TabView(selection: $selectedTab) {
                        barbersTab.tag(0)
                        servicesTab.tag(1)
                        shopTab.tag(2)
                    }
                    // Use page style so swiping between tabs feels native
                    .tabViewStyle(.page(indexDisplayMode: .never))
                }
            }
        }
        .onAppear { viewModel.onAppear() }
        .onDisappear { viewModel.onDisappear() }
        // Add Barber sheet
        .sheet(isPresented: $viewModel.showAddBarber) {
            AddBarberSheet(viewModel: viewModel)
        }
        // Edit Barber sheet — triggered when editingBarber is set
        .sheet(item: $viewModel.editingBarber) { barber in
            EditBarberSheet(barber: barber, viewModel: viewModel)
        }
        // Add Service sheet
        .sheet(isPresented: $viewModel.showAddService) {
            AddServiceSheet(viewModel: viewModel)
        }
        // Edit Service sheet — triggered when editingService is set
        .sheet(item: $viewModel.editingService) { service in
            EditServiceSheet(service: service, viewModel: viewModel)
        }
        .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") { viewModel.clearError() }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        // Shop check-in QR code sheet
        .sheet(isPresented: $showQRSheet) {
            ShopCheckInQRSheet(shopId: viewModel.shopId)
        }
        // Reset password — confirmation prompt
        .alert("Reset Password?", isPresented: $showResetPasswordConfirm) {
            Button("Send Reset Email", role: .destructive) { viewModel.resetPassword() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("We'll send a password reset link to your email address.")
        }
        // Reset password — success confirmation
        .alert("Check Your Email", isPresented: $viewModel.resetPasswordSent) {
            Button("OK") { viewModel.resetPasswordSent = false }
        } message: {
            Text("A password reset link has been sent to your email. Follow the link to set a new password.")
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack {
            // Only show back button when used as a modal sheet, not as a tab
            if showDismissButton {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.accent)
                }
            } else {
                // Invisible placeholder so title stays centered
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .opacity(0)
            }

            Spacer()

            Text("Settings")
                .font(.brandHeadline)
                .foregroundColor(.white)

            Spacer()

            // Invisible spacer to keep title centered
            Image(systemName: "chevron.left")
                .font(.system(size: 16, weight: .semibold))
                .opacity(0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - Tab Picker

    private var tabPicker: some View {
        HStack(spacing: 0) {
            tabButton(title: "Barbers",  icon: "person.2",  index: 0)
            tabButton(title: "Services", icon: "scissors",  index: 1)
            tabButton(title: "Shop",     icon: "clock",     index: 2)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private func tabButton(title: String, icon: String, index: Int) -> some View {
        Button(action: { withAnimation { selectedTab = index } }) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            .foregroundColor(selectedTab == index ? .black : .gray)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(selectedTab == index ? Color.accent : Color.brandInput)
            .cornerRadius(10)
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Barbers Tab

    private var barbersTab: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Section header with add button
                // Shop Code banner — owner shares this with their barbers so they can sign up
                shopCodeBanner

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
                    // Pass index so the row can show ↑/↓ order buttons
                    ForEach(Array(viewModel.barbers.enumerated()), id: \.element.id) { index, barber in
                        barberRow(barber, index: index, total: viewModel.barbers.count)
                    }
                }

                // Sign Out — only show when rendered as a tab (not modal sheet)
                if !showDismissButton, let signOut = onSignOut {
                    signOutButton(action: signOut)
                        .padding(.top, 16)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
    }

    /// A single row in the barbers list showing name, type badge, status, order controls, and edit/delete actions.
    /// index and total are used to disable the ↑/↓ buttons at the edges of the list.
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
            VStack(alignment: .leading, spacing: 4) {
                Text(barber.name)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)

                HStack(spacing: 6) {
                    Text(barber.barberType.displayName)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.gray)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.brandDotBg)
                        .cornerRadius(5)

                    if barber.goLive {
                        Text("LIVE")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.accent)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accent.opacity(0.15))
                            .cornerRadius(4)
                    }
                }
            }

            Spacer()

            // ↑ / ↓ order buttons — grayed out at the edges of the list
            HStack(spacing: 4) {
                Button(action: {
                    viewModel.moveBarbers(from: IndexSet(integer: index), to: index - 1)
                }) {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(index == 0 ? .gray.opacity(0.3) : .brandSecondary)
                        .frame(width: 28, height: 28)
                        .background(Color.brandDotBg)
                        .cornerRadius(6)
                }
                .disabled(index == 0)

                Button(action: {
                    viewModel.moveBarbers(from: IndexSet(integer: index), to: index + 2)
                }) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(index == total - 1 ? .gray.opacity(0.3) : .brandSecondary)
                        .frame(width: 28, height: 28)
                        .background(Color.brandDotBg)
                        .cornerRadius(6)
                }
                .disabled(index == total - 1)
            }

            // Edit button
            Button(action: { viewModel.editingBarber = barber }) {
                Image(systemName: "pencil")
                    .font(.system(size: 14))
                    .foregroundColor(.accent)
                    .frame(width: 34, height: 34)
                    .background(Color.brandDotBg)
                    .cornerRadius(8)
            }

            // Delete button
            Button(role: .destructive, action: { viewModel.deleteBarber(barber) }) {
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
    }

    // MARK: - Services Tab

    private var servicesTab: some View {
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

    /// A single row in the services list showing name, duration, price, active toggle.
    private func serviceRow(_ service: Service) -> some View {
        HStack(spacing: 14) {
            // Active/inactive indicator dot
            Circle()
                .fill(service.active ? Color.accent : Color.gray.opacity(0.4))
                .frame(width: 8, height: 8)

            // Service name + duration
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
                        Text("·")
                            .foregroundColor(.gray)
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
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
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

    // MARK: - Shop Tab (Schedule + Hours)

    private var shopTab: some View {
        ScrollView {
            VStack(spacing: 16) {

                // ── Section label ────────────────────────────────────────────
                HStack {
                    Text("SCHEDULE")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.gray)
                        .tracking(1.2)
                    Spacer()
                }
                .padding(.top, 8)

                // ── Auto-Close card ──────────────────────────────────────────
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
                        // Toggle switch — enables/disables auto-close
                        Toggle("", isOn: Binding(
                            get: { viewModel.autoCloseEnabled },
                            set: { enabled in
                                viewModel.autoCloseEnabled = enabled
                                if enabled && viewModel.autoCloseTime == nil {
                                    // Default to 9:00 PM when first enabled
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

                    // Time picker — only visible when enabled
                    if viewModel.autoCloseEnabled {
                        Divider().background(Color.gray.opacity(0.2))

                        HStack {
                            Text("Close at")
                                .font(.subheadline)
                                .foregroundColor(.white)
                            Spacer()
                            // Compact wheel-style time picker
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

                        // Friendly summary of what will happen
                        HStack(spacing: 6) {
                            Image(systemName: "moon.stars.fill")
                                .font(.caption2)
                                .foregroundColor(.accent)
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

                // ── Section label ────────────────────────────────────────────
                HStack {
                    Text("ACCOUNT")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.gray)
                        .tracking(1.2)
                    Spacer()
                }
                .padding(.top, 4)

                // ── Reset Password card ──────────────────────────────────────
                Button(action: { showResetPasswordConfirm = true }) {
                    HStack(spacing: 12) {
                        Image(systemName: "lock.rotation")
                            .font(.system(size: 16))
                            .foregroundColor(.accent)
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: 3) {
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
                            .font(.caption)
                            .foregroundColor(.gray.opacity(0.5))
                    }
                    .padding(14)
                    .background(Color.brandInput)
                    .cornerRadius(14)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
    }

    // MARK: - Shared UI Helpers

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
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                    Text(buttonLabel)
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(.black)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Color.accent)
                .cornerRadius(8)
            }
        }
        .padding(.top, 8)
    }

    /// Shows the shop's unique code with a copy button.
    /// Barbers need this code + their email to create their login in the Sign Up flow.
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

                // Copy to clipboard button
                Button(action: {
                    UIPasteboard.general.string = viewModel.shopId
                }) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 13))
                        .foregroundColor(.accent)
                }
            }

            Text("Share this code with your barbers so they can create their login in the app.")
                .font(.caption2)
                .foregroundColor(.gray)

            // Action buttons — side by side
            HStack(spacing: 10) {
                // Check-in QR sheet
                Button(action: { showQRSheet = true }) {
                    HStack(spacing: 6) {
                        Image(systemName: "qrcode")
                            .font(.system(size: 12))
                        Text("Check-In QR")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.accent)
                    .cornerRadius(9)
                }

                // Open live queue in browser (great for casting to a TV)
                Button(action: {
                    let urlString = "https://upnext-4ec7a.web.app/queue?shop=\(viewModel.shopId)"
                    if let url = URL(string: urlString) {
                        UIApplication.shared.open(url)
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "tv")
                            .font(.system(size: 12))
                        Text("Live Queue")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.accent.opacity(0.1))
                    .cornerRadius(9)
                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.accent.opacity(0.3), lineWidth: 1))
                }
            }
        }
        .padding(14)
        .background(Color.accent.opacity(0.07))
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.accent.opacity(0.2), lineWidth: 1))
    }

    private func signOutButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
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

    private func emptyState(icon: String, message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 32))
                .foregroundColor(.gray.opacity(0.4))
            Text(message)
                .font(.subheadline)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView().tint(.accent)
            Text("Loading settings...").font(.subheadline).foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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

                        // Email field — used for the barber's login invite
                        VStack(alignment: .leading, spacing: 8) {
                            fieldLabel("Email (for app login)")
                            TextField("barber@email.com", text: $email)
                                .textFieldStyle(BrandTextFieldStyle())
                                .keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()

                            // Explain what this email does
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
                                email: email.trimmingCharacters(in: .whitespaces).lowercased(),
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

    // Binding helpers for optional String fields
    private var emailBinding: Binding<String> {
        Binding(get: { barber.email ?? "" }, set: { barber.email = $0.isEmpty ? nil : $0 })
    }
    private var bookingUrlBinding: Binding<String> {
        Binding(get: { barber.bookingUrl ?? "" }, set: { barber.bookingUrl = $0.isEmpty ? nil : $0 })
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

                        // --- Email ---
                        VStack(alignment: .leading, spacing: 8) {
                            fieldLabel("Email (for app login)")
                            TextField("barber@email.com", text: emailBinding)
                                .textFieldStyle(BrandTextFieldStyle())
                                .keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                        }

                        // --- Booking URL ---
                        VStack(alignment: .leading, spacing: 8) {
                            fieldLabel("Booking Site URL (optional)")
                            TextField("https://square.site/...", text: bookingUrlBinding)
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

                        Button(action: {
                            viewModel.saveBarber(barber)
                            dismiss()
                        }) {
                            Text("Save Changes")
                                .font(.headline).foregroundColor(.black)
                                .frame(maxWidth: .infinity).padding(.vertical, 16)
                                .background(Color.accent).cornerRadius(14)
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Edit Barber")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundColor(.accent)
                }
            }
            // Photo picker sheet
            .sheet(isPresented: $showPhotoPicker) {
                BarberPhotoPicker(selectedImage: $selectedPhoto)
            }
            // Upload photo when one is selected
            .onChange(of: selectedPhoto) { image in
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
                    // Newly picked photo (not yet saved URL)
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 88, height: 88)
                        .clipShape(Circle())
                } else if let urlString = barber.photoUrl, let url = URL(string: urlString) {
                    // Existing photo from Firebase Storage
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        ProgressView().tint(.accent)
                    }
                    .frame(width: 88, height: 88)
                    .clipShape(Circle())
                } else {
                    // No photo yet — show initial
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

                    // Note about price visibility
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
                        // Convert price text back to Double? before saving
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
/// Use this on any TextField in the barber app.
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
        config.filter = .images           // Photos only — no videos
        config.selectionLimit = 1         // One photo per barber
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
/// Owners can screenshot or let customers scan it directly from the phone.
struct ShopCheckInQRSheet: View {

    let shopId: String
    @Environment(\.dismiss) private var dismiss

    private var checkInURL: String {
        "https://upnext-4ec7a.web.app/checkin?shop=\(shopId)"
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 28) {
                // Header
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

                // Logo
                HStack(spacing: 8) {
                    UpNextMark(size: 20)
                    HStack(spacing: 0) {
                        Text("Up").font(.custom("Outfit-Bold", size: 22)).foregroundColor(.white)
                        Text("Next").font(.custom("Outfit-Bold", size: 22)).foregroundColor(.accent)
                    }
                }

                // Title
                VStack(spacing: 6) {
                    Text("Check-In QR Code")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundColor(.white)
                    Text("Customers scan this to join your queue")
                        .font(.system(size: 14))
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                }

                // QR code
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

                // URL label
                Text(checkInURL)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                // Copy link button
                Button(action: { UIPasteboard.general.string = checkInURL }) {
                    HStack(spacing: 8) {
                        Image(systemName: "link")
                            .font(.system(size: 13))
                        Text("Copy Check-In Link")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .foregroundColor(.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color.accent.opacity(0.1))
                    .cornerRadius(12)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.accent.opacity(0.25), lineWidth: 1))
                }
                .padding(.horizontal, 32)

                Spacer()
            }
        }
    }

    /// Uses CoreImage to generate a QR code image from the given string.
    private func generateQR(from string: String) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "H"
        guard let output = filter.outputImage else { return nil }
        // Scale up so it renders sharply
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}


// MARK: - Preview

#Preview {
    ShopSettingsView(
        viewModel: ShopSettingsViewModel(shopId: "test-shop")
    )
}
