//
//  LoginView.swift
//  UpNext
//
//  Email + password sign-in / sign-up screen for barbers and shop owners.
//
//  Sign In: email + password → signed in
//  Sign Up: shop code + email + password → verified against barber list → account created
//

import SwiftUI

struct LoginView: View {

    @EnvironmentObject var authViewModel: AuthViewModel
    @State private var selectedTab: LoginTab = .signIn

    enum LoginTab { case signIn, signUp, ownerSignUp }

    var body: some View {
        ZStack {
            Color.brandNearBlack.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    logoSection
                        .padding(.top, 80)
                        .padding(.bottom, 40)

                    tabToggle
                        .padding(.horizontal, 32)
                        .padding(.bottom, 28)

                    Group {
                        switch selectedTab {
                        case .signIn:
                            SignInForm()
                                .environmentObject(authViewModel)
                                .padding(.horizontal, 32)
                        case .signUp:
                            SignUpForm()
                                .environmentObject(authViewModel)
                                .padding(.horizontal, 32)
                        case .ownerSignUp:
                            OwnerSignUpForm()
                                .environmentObject(authViewModel)
                                .padding(.horizontal, 32)
                        }
                    }

                    // Error message (shared across both forms)
                    if let error = authViewModel.errorMessage {
                        Text(error)
                            .font(.subheadline)
                            .foregroundColor(.red.opacity(0.9))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                            .padding(.top, 16)
                    }

                    Spacer(minLength: 40)
                }
            }
        }
        // Clear stale errors when switching tabs
        .onChange(of: selectedTab) { _, _ in authViewModel.clearError() }
    }

    // MARK: - Logo

    private var logoSection: some View {
        VStack(spacing: 20) {
            ZStack {
                RoundedRectangle(cornerRadius: 22)
                    .fill(Color.brandDotBg)
                    .frame(width: 88, height: 88)
                VStack(alignment: .leading, spacing: 8) {
                    Circle().fill(Color.accent.opacity(0.6)).frame(width: 14, height: 14)
                    RoundedRectangle(cornerRadius: 4).fill(Color.accent).frame(width: 48, height: 14)
                    RoundedRectangle(cornerRadius: 4).fill(Color.accent.opacity(0.6)).frame(width: 28, height: 14)
                }
            }

            VStack(spacing: 6) {
                HStack(spacing: 0) {
                    Text("Up").font(.custom("Outfit-Bold", size: 36)).foregroundColor(.white)
                    Text("Next").font(.custom("Outfit-Bold", size: 36)).foregroundColor(.brandSecondary)
                }
                Text("Queue management for barbers")
                    .font(.custom("Outfit-Regular", size: 15))
                    .foregroundColor(.brandSecondary)
            }
        }
    }

    // MARK: - Tab Toggle

    private var tabToggle: some View {
        HStack(spacing: 0) {
            tabButton("Sign In", tab: .signIn)
            tabButton("Barber", tab: .signUp)
            tabButton("Owner", tab: .ownerSignUp)
        }
        .background(Color.brandInput)
        .cornerRadius(10)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.brandDotBg, lineWidth: 1))
    }

    private func tabButton(_ label: String, tab: LoginTab) -> some View {
        Button(action: { withAnimation(.easeInOut(duration: 0.2)) { selectedTab = tab } }) {
            Text(label)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(selectedTab == tab ? .black : .gray)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(selectedTab == tab ? Color.accent : Color.clear)
                .cornerRadius(9)
        }
        .padding(2)
    }
}

// MARK: - Sign In Form

private struct SignInForm: View {

    @EnvironmentObject var authViewModel: AuthViewModel
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var showResetAlert: Bool = false
    @State private var resetEmailSent: Bool = false
    @FocusState private var focused: Field?

    enum Field { case email, password }

    private var canSubmit: Bool {
        !email.trimmingCharacters(in: .whitespaces).isEmpty && !password.isEmpty
    }

    var body: some View {
        VStack(spacing: 16) {

            infoBanner(icon: "lock.shield", text: "Sign in with your email and password.")

            // Email field
            loginField(label: "Email", icon: "envelope") {
                TextField("you@example.com", text: $email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .foregroundColor(.white)
                    .focused($focused, equals: .email)
                    .submitLabel(.next)
                    .onSubmit { focused = .password }
            }

            // Password field
            loginField(label: "Password", icon: "key") {
                SecureField("••••••••", text: $password)
                    .foregroundColor(.white)
                    .focused($focused, equals: .password)
                    .submitLabel(.go)
                    .onSubmit {
                        if canSubmit {
                            focused = nil
                            Task { await authViewModel.signIn(email: email, password: password) }
                        }
                    }
            }

            // Sign In button
            actionButton(
                label: "Sign In",
                isLoading: authViewModel.isLoading,
                isEnabled: canSubmit
            ) {
                focused = nil
                Task { await authViewModel.signIn(email: email, password: password) }
            }
            .padding(.top, 8)

            // Forgot password link
            Button("Forgot password?") {
                showResetAlert = true
            }
            .font(.system(size: 14))
            .foregroundColor(.accent.opacity(0.8))
            .underline()
            .padding(.top, 4)
        }
        .onAppear { focused = .email }
        // Step 1: Ask for their email
        .alert("Reset Password", isPresented: $showResetAlert) {
            TextField("Email address", text: $email)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
            Button("Send Reset Link") {
                Task {
                    await authViewModel.resetPassword(email: email)
                    if authViewModel.errorMessage == nil {
                        resetEmailSent = true
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("We'll send a password reset link to your email.")
        }
        // Step 2: Confirm the email was sent
        .alert("Check Your Email", isPresented: $resetEmailSent) {
            Button("Got it", role: .cancel) {}
        } message: {
            Text("A password reset link has been sent. Check your inbox.")
        }
    }
}

// MARK: - Sign Up Form

private struct SignUpForm: View {

    @EnvironmentObject var authViewModel: AuthViewModel
    @State private var shopCode: String = ""
    @State private var email: String = ""
    @State private var password: String = ""
    @FocusState private var focused: Field?

    enum Field { case shopCode, email, password }

    private var canSubmit: Bool {
        !shopCode.trimmingCharacters(in: .whitespaces).isEmpty &&
        !email.trimmingCharacters(in: .whitespaces).isEmpty &&
        password.count >= 6
    }

    var body: some View {
        VStack(spacing: 16) {

            infoBanner(
                icon: "info.circle",
                text: "Your shop owner adds your email in Settings first, then gives you the Shop Code to sign up."
            )

            // Shop Code
            loginField(label: "Shop Code", icon: "building.2") {
                TextField("e.g. fademasters-waco", text: $shopCode)
                    .foregroundColor(.white)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focused, equals: .shopCode)
                    .submitLabel(.next)
                    .onSubmit { focused = .email }
            }

            // Email
            loginField(label: "Your Email", icon: "envelope") {
                TextField("you@example.com", text: $email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .foregroundColor(.white)
                    .focused($focused, equals: .email)
                    .submitLabel(.next)
                    .onSubmit { focused = .password }
            }

            // Password
            loginField(label: "Create Password", icon: "key") {
                SecureField("At least 6 characters", text: $password)
                    .foregroundColor(.white)
                    .focused($focused, equals: .password)
                    .submitLabel(.go)
                    .onSubmit {
                        if canSubmit {
                            focused = nil
                            Task { await authViewModel.signUp(email: email, password: password, shopId: shopCode) }
                        }
                    }
            }

            // Create Account button
            actionButton(
                label: "Create Account",
                isLoading: authViewModel.isLoading,
                isEnabled: canSubmit
            ) {
                focused = nil
                Task { await authViewModel.signUp(email: email, password: password, shopId: shopCode) }
            }
            .padding(.top, 8)
        }
    }
}

// MARK: - Owner Sign Up Form

/// New shop owners create their account + shop in one flow.
/// This is required by the App Store — users must be able to sign up inside the app.
private struct OwnerSignUpForm: View {

    @EnvironmentObject var authViewModel: AuthViewModel
    @State private var ownerName: String = ""
    @State private var shopName: String = ""
    @State private var shopAddress: String = ""
    @State private var email: String = ""
    @State private var password: String = ""
    @FocusState private var focused: Field?

    enum Field { case ownerName, shopName, shopAddress, email, password }

    private var canSubmit: Bool {
        !ownerName.trimmingCharacters(in: .whitespaces).isEmpty &&
        !shopName.trimmingCharacters(in: .whitespaces).isEmpty &&
        !email.trimmingCharacters(in: .whitespaces).isEmpty &&
        password.count >= 6
    }

    var body: some View {
        VStack(spacing: 16) {

            infoBanner(
                icon: "storefront",
                text: "Create your shop and go live in minutes. 30-day money-back guarantee."
            )

            // Owner Name
            loginField(label: "Your Name", icon: "person") {
                TextField("e.g. Carlos Canales", text: $ownerName)
                    .foregroundColor(.white)
                    .textInputAutocapitalization(.words)
                    .focused($focused, equals: .ownerName)
                    .submitLabel(.next)
                    .onSubmit { focused = .shopName }
            }

            // Shop Name
            loginField(label: "Shop Name", icon: "scissors") {
                TextField("e.g. Fademasters Barbershop", text: $shopName)
                    .foregroundColor(.white)
                    .textInputAutocapitalization(.words)
                    .focused($focused, equals: .shopName)
                    .submitLabel(.next)
                    .onSubmit { focused = .shopAddress }
            }

            // Shop Address (optional but helpful)
            loginField(label: "Shop Address", icon: "mappin.and.ellipse") {
                TextField("123 Main St, Waco, TX (optional)", text: $shopAddress)
                    .foregroundColor(.white)
                    .textInputAutocapitalization(.words)
                    .focused($focused, equals: .shopAddress)
                    .submitLabel(.next)
                    .onSubmit { focused = .email }
            }

            // Email
            loginField(label: "Email", icon: "envelope") {
                TextField("you@example.com", text: $email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .foregroundColor(.white)
                    .focused($focused, equals: .email)
                    .submitLabel(.next)
                    .onSubmit { focused = .password }
            }

            // Password
            loginField(label: "Create Password", icon: "key") {
                SecureField("At least 6 characters", text: $password)
                    .foregroundColor(.white)
                    .focused($focused, equals: .password)
                    .submitLabel(.go)
                    .onSubmit {
                        if canSubmit {
                            focused = nil
                            submit()
                        }
                    }
            }

            // Create Shop button
            actionButton(
                label: "Create My Shop",
                isLoading: authViewModel.isLoading,
                isEnabled: canSubmit
            ) {
                focused = nil
                submit()
            }
            .padding(.top, 8)

            Text("30-day money-back guarantee · Cancel anytime")
                .font(.system(size: 12))
                .foregroundColor(.gray)
        }
    }

    private func submit() {
        Task {
            await authViewModel.ownerSignUp(
                ownerName: ownerName,
                shopName: shopName,
                shopAddress: shopAddress,
                email: email,
                password: password
            )
        }
    }
}


// MARK: - Shared UI Helpers

/// Labeled input field row used across both forms.
private func loginField<Content: View>(
    label: String,
    icon: String,
    @ViewBuilder content: () -> Content
) -> some View {
    VStack(alignment: .leading, spacing: 8) {
        Text(label)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundColor(.gray)
            .tracking(0.5)
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(.gray)
                .frame(width: 20)
            content()
        }
        .padding(14)
        .background(Color.brandInput)
        .cornerRadius(12)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.brandDotBg, lineWidth: 1))
    }
}

/// Tappable action button with loading state.
private func actionButton(
    label: String,
    isLoading: Bool,
    isEnabled: Bool,
    action: @escaping () -> Void
) -> some View {
    Button(action: action) {
        ZStack {
            if isLoading {
                ProgressView().tint(.black)
            } else {
                Text(label)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundColor(.black)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 52)
        .background(isEnabled ? Color.accent : Color.gray.opacity(0.3))
        .cornerRadius(14)
    }
    .disabled(!isEnabled || isLoading)
}

/// Informational banner with icon and explanatory text.
private func infoBanner(icon: String, text: String) -> some View {
    HStack(alignment: .top, spacing: 10) {
        Image(systemName: icon)
            .font(.system(size: 14))
            .foregroundColor(.accent)
            .padding(.top, 1)
        Text(text)
            .font(.caption)
            .foregroundColor(.gray)
            .fixedSize(horizontal: false, vertical: true)
    }
    .padding(12)
    .background(Color.accent.opacity(0.07))
    .cornerRadius(10)
}

// MARK: - Preview

#Preview {
    LoginView()
        .environmentObject(AuthViewModel())
}
