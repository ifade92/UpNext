//
//  AuthViewModel.swift
//  UpNext
//
//  Manages everything related to authentication:
//  - Listening for Firebase Auth session changes (already logged in? skip the login screen)
//  - Email + password sign in
//  - Email + password sign up (barbers use shop code + email to verify they belong to the shop)
//  - Password reset via email
//  - Sign out + full cleanup
//  - Fetching the AppUser profile from Firestore after login
//
//  Lives at the root of the app so every screen can read the current user.
//
//  Auth flow overview:
//  ┌──────────────────────────────────────────────────────────────────────┐
//  │  Sign In: email + password → signed in                              │
//  │  Sign Up: shop code + email + password → verify barber exists       │
//  │           → create Firebase Auth account → create AppUser doc       │
//  └──────────────────────────────────────────────────────────────────────┘
//

import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore

@MainActor
class AuthViewModel: ObservableObject {

    // MARK: - Published State

    /// The logged-in user's Firestore profile. nil = not logged in.
    @Published var appUser: AppUser?

    /// The owner's shop document — loaded after login to check subscription status.
    /// nil for barbers (they don't need it) or before login.
    @Published var shop: Shop?

    /// True while a network operation is in flight.
    @Published var isLoading: Bool = false

    /// Set when something goes wrong — displayed in the UI.
    @Published var errorMessage: String?

    // MARK: - Stripe Subscription Helper

    /// True if the shop has an active subscription via Stripe (web checkout).
    /// Stripe subscribers pay through the website — their subscription status
    /// is synced to Firestore by the stripeWebhook Cloud Function.
    /// We also grant access during past_due (grace period) so the shop
    /// doesn't go dark while a payment retry is in progress.
    var isSubscribedViaStripe: Bool {
        guard let status = shop?.subscriptionStatus else { return false }
        return status == .active || status == .pastDue
    }

    // MARK: - Private State

    private let db = Firestore.firestore()

    /// Tracks the Firebase Auth listener so we can detach it on deinit.
    private var authStateHandle: AuthStateDidChangeListenerHandle?

    // MARK: - Init

    init() {
        listenToAuthState()
    }

    deinit {
        if let handle = authStateHandle {
            Auth.auth().removeStateDidChangeListener(handle)
        }
    }

    // MARK: - Auth State Listener

    /// Attaches a Firebase Auth listener that fires immediately on launch.
    /// If there's already a logged-in session, this skips the login screen automatically.
    private func listenToAuthState() {
        isLoading = true

        authStateHandle = Auth.auth().addStateDidChangeListener { [weak self] _, firebaseUser in
            Task { @MainActor in
                if let firebaseUser = firebaseUser {
                    // User already logged in — load their Firestore profile
                    await self?.loadAppUser(userId: firebaseUser.uid)
                } else {
                    // No session — show the login screen
                    self?.appUser = nil
                    self?.isLoading = false
                }
            }
        }
    }

    // MARK: - Sign In

    /// Sign in with email and password.
    func signIn(email: String, password: String) async {
        let trimmedEmail = email.trimmingCharacters(in: .whitespaces)

        guard !trimmedEmail.isEmpty, !password.isEmpty else {
            errorMessage = "Please enter your email and password."
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            let result = try await Auth.auth().signIn(withEmail: trimmedEmail, password: password)
            // loadAppUser sets appUser, which routes ContentView to the right screen
            await loadAppUser(userId: result.user.uid)
        } catch {
            isLoading = false
            errorMessage = friendlyAuthError(error)
        }
    }

    // MARK: - Sign Up (Barbers)

    /// Barbers sign up with a shop code + email + password.
    /// The owner must have pre-added their email in Shop Settings first.
    ///
    /// Flow:
    ///   1. Check that the email matches a barber in the given shop
    ///   2. Create a Firebase Auth account with the email + password
    ///   3. Write an AppUser document to Firestore (links auth UID → shop + barber)
    ///   4. Link the UID back to the barber document
    func signUp(email: String, password: String, shopId: String) async {
        let trimmedEmail = email.trimmingCharacters(in: .whitespaces)
        let trimmedShopId = shopId.trimmingCharacters(in: .whitespaces)

        guard !trimmedEmail.isEmpty, !password.isEmpty, !trimmedShopId.isEmpty else {
            errorMessage = "Please fill in all fields."
            return
        }
        guard password.count >= 6 else {
            errorMessage = "Password must be at least 6 characters."
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            let firebase = FirebaseService.shared

            // Step 1: Make sure this email belongs to a barber in this shop
            guard let barber = try await firebase.findBarberByEmail(
                shopId: trimmedShopId,
                email: trimmedEmail
            ) else {
                errorMessage = "Email not found for this shop. Ask your owner to add you in Settings first."
                isLoading = false
                return
            }

            guard let barberId = barber.id else {
                errorMessage = "Barber profile error. Contact your shop owner."
                isLoading = false
                return
            }

            // Step 2: Create the Firebase Auth account
            let result = try await Auth.auth().createUser(withEmail: trimmedEmail, password: password)
            let userId = result.user.uid

            // Step 3: Write the AppUser doc to Firestore
            try await firebase.createBarberUser(
                userId: userId,
                email: trimmedEmail,
                shopId: trimmedShopId,
                barberId: barberId,
                displayName: barber.name
            )

            // Step 4: Link the auth UID back to the barber document
            try await firebase.linkUserToBarber(shopId: trimmedShopId, barberId: barberId, userId: userId)

            // Load profile — routes ContentView to BarberTabView
            await loadAppUser(userId: userId)

        } catch {
            isLoading = false
            errorMessage = friendlyAuthError(error)
        }
    }

    // MARK: - Owner Sign Up

    /// Owners sign up with their name, shop name, email, and password.
    /// This creates everything from scratch:
    ///   1. Firebase Auth account
    ///   2. A new Shop document with default settings (no active subscription)
    ///   3. An AppUser document linking the auth UID → shop (role = owner)
    ///
    /// After this, ContentView routes them to the PaywallView to subscribe.
    func ownerSignUp(ownerName: String, shopName: String, shopAddress: String, email: String, password: String) async {
        let trimmedEmail = email.trimmingCharacters(in: .whitespaces)
        let trimmedOwnerName = ownerName.trimmingCharacters(in: .whitespaces)
        let trimmedShopName = shopName.trimmingCharacters(in: .whitespaces)

        guard !trimmedEmail.isEmpty, !password.isEmpty, !trimmedOwnerName.isEmpty, !trimmedShopName.isEmpty else {
            errorMessage = "Please fill in all fields."
            return
        }
        guard password.count >= 6 else {
            errorMessage = "Password must be at least 6 characters."
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            let firebase = FirebaseService.shared

            // Step 1: Create the Firebase Auth account
            let result = try await Auth.auth().createUser(withEmail: trimmedEmail, password: password)
            let userId = result.user.uid

            // Step 2: Create the shop document (default settings, no subscription yet)
            let shop = try await firebase.createShop(
                name: trimmedShopName,
                address: shopAddress.trimmingCharacters(in: .whitespaces),
                ownerId: userId
            )

            guard let shopId = shop.id else {
                errorMessage = "Failed to create shop. Please try again."
                isLoading = false
                return
            }

            // Step 3: Create the owner's AppUser document
            try await firebase.createOwnerUser(
                userId: userId,
                email: trimmedEmail,
                shopId: shopId,
                displayName: trimmedOwnerName
            )

            // Load profile — ContentView will route to PaywallView (no subscription yet)
            await loadAppUser(userId: userId)

        } catch {
            isLoading = false
            errorMessage = friendlyAuthError(error)
        }
    }


    // MARK: - Password Reset

    /// Sends a password reset email. Call this from the "Forgot password?" flow.
    func resetPassword(email: String) async {
        let trimmed = email.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            errorMessage = "Enter your email to reset your password."
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            try await Auth.auth().sendPasswordReset(withEmail: trimmed)
            isLoading = false
            // The view handles showing the success confirmation via resetEmailSent state
        } catch {
            isLoading = false
            errorMessage = friendlyAuthError(error)
        }
    }

    // MARK: - Sign Out

    func signOut() {
        do {
            FirebaseService.shared.removeAllListeners()
            NotificationManager.shared.teardown() // Clear stored userId on sign out
            try Auth.auth().signOut()
            appUser = nil
            shop = nil
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't sign out. Please try again."
        }
    }

    // MARK: - Load App User Profile

    /// Fetch the AppUser document from Firestore after Firebase Auth succeeds.
    /// Sets appUser — ContentView reacts to this and routes to the right screen.
    private func loadAppUser(userId: String) async {
        do {
            let doc = try await db.collection("users").document(userId).getDocument()

            guard doc.exists, let user = try? doc.data(as: AppUser.self) else {
                // Missing doc means the account was never fully set up
                errorMessage = "Account setup incomplete. Please contact your shop owner."
                isLoading = false
                try? Auth.auth().signOut()
                return
            }

            appUser = user

            // For owners, load their shop doc so we can check subscription status
            // (especially for Stripe web subscribers whose status lives in Firestore).
            // This runs before isLoading = false so ContentView has the info
            // before it decides which screen to show.
            if user.isOwner {
                await loadShop(shopId: user.shopId)
            }

            isLoading = false

            // Request push notification permission and save the FCM token to Firestore
            await NotificationManager.shared.setup(userId: userId)

        } catch {
            errorMessage = "Couldn't load your account. Check your connection."
            isLoading = false
        }
    }

    // MARK: - Load Shop

    /// Fetches the shop document from Firestore so we can check subscription status.
    /// Called once on owner login — the shop object is used by ContentView
    /// to decide whether to show the dashboard or paywall (covers Stripe subscribers).
    private func loadShop(shopId: String) async {
        do {
            let doc = try await db.collection("shops").document(shopId).getDocument()
            if let shop = try? doc.data(as: Shop.self) {
                self.shop = shop
            }
        } catch {
            print("Failed to load shop: \(error.localizedDescription)")
            // Non-fatal — worst case, owner sees the paywall and can subscribe normally
        }
    }

    // MARK: - Helpers

    /// Returns the current Firebase Auth UID, or nil if nobody is logged in.
    static func currentUserId() async -> String? {
        Auth.auth().currentUser?.uid
    }

    func clearError() {
        errorMessage = nil
    }

    // MARK: - Error Messages

    /// Maps Firebase Auth error codes to plain-English messages barbers will actually understand.
    private func friendlyAuthError(_ error: Error) -> String {
        let code = AuthErrorCode(rawValue: (error as NSError).code)
        switch code {
        case .invalidEmail:
            return "That doesn't look like a valid email address."
        case .wrongPassword, .invalidCredential:
            return "Wrong email or password. Double-check and try again."
        case .userNotFound:
            return "No account found with that email."
        case .emailAlreadyInUse:
            return "An account with that email already exists. Try signing in instead."
        case .weakPassword:
            return "Password is too weak. Use at least 6 characters."
        case .networkError:
            return "No internet connection. Check your network and try again."
        case .tooManyRequests:
            return "Too many attempts. Wait a minute and try again."
        case .userDisabled:
            return "This account has been disabled. Contact your shop owner."
        default:
            return "Something went wrong (\((error as NSError).code)). Please try again."
        }
    }
}
