//
//  NotificationManager.swift
//  UpNext
//
//  Handles push notification permission and FCM token management for
//  owners and barbers. When someone logs in, we:
//    1. Ask for notification permission (once — iOS only shows the system dialog once)
//    2. Register with APNs so the device can receive pushes
//    3. Get the FCM token from Firebase Messaging
//    4. Save it to Firestore under their user document
//
//  The Cloud Function reads these tokens to send "new walk-in" alerts
//  to everyone on the team whenever a customer checks in.
//
//  We also implement UNUserNotificationCenterDelegate so notifications
//  display as banners even when the app is open in the foreground.
//
//  ── WHY THE TIMING FIX MATTERS ────────────────────────────────────────────
//  On launch, APNs registration is async. The auth listener fires almost
//  immediately, calling setup(userId:) — but didRegisterForRemoteNotifications
//  may not have fired yet, so FCM has no APNs token and token() calls fail
//  silently. The fix: store currentUserId internally so the MessagingDelegate
//  callback can save the token whenever it arrives, regardless of order.
//  ──────────────────────────────────────────────────────────────────────────
//
//  SETUP CHECKLIST (one-time):
//  ─────────────────────────────────────────────────────────────────────
//  1. Xcode → Add Package → firebase-ios-sdk → add "FirebaseMessaging" target
//  2. Xcode → Target → Signing & Capabilities → + Capability → Push Notifications
//  3. Xcode → Target → Signing & Capabilities → + Capability → Background Modes
//       → check "Remote notifications"
//  4. Firebase Console → Project Settings → Cloud Messaging → upload APNs Auth Key
//       (Apple Developer Portal → Keys → create key with "Apple Push Notifications Service")
//

import Foundation
import UIKit
import FirebaseFirestore
import FirebaseMessaging
import UserNotifications

@MainActor
final class NotificationManager: NSObject {

    static let shared = NotificationManager()
    private let db = Firestore.firestore()

    /// Stored when setup(userId:) is called so the MessagingDelegate callback
    /// can always save the token — even if it arrives before auth finishes loading.
    private var currentUserId: String?

    private override init() {
        super.init()
        // Tell Firebase Messaging to notify us when the FCM token refreshes
        Messaging.messaging().delegate = self

        // Set ourselves as the notification center delegate so we can show
        // banners while the app is in the foreground (iOS suppresses them by default)
        UNUserNotificationCenter.current().delegate = self
    }

    // MARK: - Setup (call right after a user logs in)

    /// Requests notification permission and saves the FCM token to Firestore.
    /// Safe to call every login — iOS only shows the permission dialog once.
    func setup(userId: String) async {
        // Store the userId so the MessagingDelegate can use it on token refresh
        currentUserId = userId

        await requestPermission()
        await refreshAndSaveToken(userId: userId)
    }

    /// Clears the FCM token from the current user's Firestore doc AND tells
    /// Firebase Messaging to invalidate the token on its side. Call this on
    /// sign-out BEFORE Auth.auth().signOut() — once we sign out of Auth, the
    /// user loses Firestore write permission and the cleanup will fail.
    ///
    /// Why both steps:
    ///   1. Deleting users/{userId}.fcmToken stops the backend from pushing
    ///      to this device under the old account's name.
    ///   2. deleteToken() forces FCM to issue a NEW token on next sign-in,
    ///      so the new account doesn't inherit the old token (which would
    ///      defeat the whole fix if the old user's doc somehow re-acquired it).
    ///
    /// Each step is wrapped independently so a network blip on one doesn't
    /// block the other or block sign-out itself.
    func clearTokenForCurrentUser() async {
        guard let userId = currentUserId else {
            return
        }

        do {
            try await db.collection("users").document(userId).updateData([
                "fcmToken": FieldValue.delete()
            ])
            print("[NotificationManager] FCM token cleared for user \(userId)")
        } catch {
            print("[NotificationManager] Failed to clear FCM token in Firestore: \(error.localizedDescription)")
        }

        do {
            try await Messaging.messaging().deleteToken()
            print("[NotificationManager] FCM token deleted on Messaging side")
        } catch {
            print("[NotificationManager] Failed to delete FCM token: \(error.localizedDescription)")
        }

        currentUserId = nil
    }

    // MARK: - Badge

    /// Clears the red badge number from the app icon.
    /// Call this whenever the app becomes active so the badge disappears
    /// as soon as a barber opens the app — no manual tapping required.
    func clearBadge() {
        // iOS 16+ API — the recommended way to reset the badge count
        UNUserNotificationCenter.current().setBadgeCount(0) { error in
            if let error = error {
                print("[NotificationManager] Failed to clear badge: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Permission

    private func requestPermission() async {
        let center = UNUserNotificationCenter.current()

        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            // First time — ask the user
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
                if granted {
                    await MainActor.run { UIApplication.shared.registerForRemoteNotifications() }
                }
            } catch {
                print("[NotificationManager] Permission request failed: \(error)")
            }
        case .authorized, .provisional, .ephemeral:
            // Already granted — make sure APNs is registered
            // (needed after reinstalls or on first launch after our fix)
            await MainActor.run { UIApplication.shared.registerForRemoteNotifications() }
        default:
            // Denied — nothing we can do, user has to go to iOS Settings
            break
        }
    }

    // MARK: - Token

    /// Gets the current FCM token and writes it to Firestore.
    /// May fail silently on first launch if APNs token isn't ready yet —
    /// the MessagingDelegate callback will handle it when the token arrives.
    private func refreshAndSaveToken(userId: String) async {
        do {
            let token = try await Messaging.messaging().token()
            try await saveToken(token, userId: userId)
        } catch {
            // This is expected on first launch — APNs registration is still in flight.
            // messaging(_:didReceiveRegistrationToken:) will fire and save the token
            // once Firebase Messaging has exchanged the APNs token for an FCM token.
            print("[NotificationManager] FCM token not ready yet — will save on delegate callback: \(error.localizedDescription)")
        }
    }

    /// Writes the FCM token to the user's Firestore document.
    /// Uses merge: true so only the fcmToken field is touched.
    private func saveToken(_ token: String, userId: String) async throws {
        try await db.collection("users").document(userId).setData(
            ["fcmToken": token],
            merge: true
        )
        print("[NotificationManager] FCM token saved for user \(userId)")
    }
}

// MARK: - MessagingDelegate

// Firebase calls this when the FCM token arrives or refreshes.
// This is the RELIABLE delivery point — it fires once Firebase Messaging
// has successfully exchanged the APNs device token for an FCM registration token.
// By using currentUserId here (set during setup), we don't depend on auth timing.
extension NotificationManager: MessagingDelegate {
    nonisolated func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let token = fcmToken else { return }
        print("[NotificationManager] FCM token received: \(token)")

        Task { @MainActor in
            // Use the stored userId — this works even if auth hasn't finished loading
            guard let userId = self.currentUserId else {
                print("[NotificationManager] Token arrived but no userId stored yet — will retry on next login")
                return
            }
            try? await self.saveToken(token, userId: userId)
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate

// Without this, iOS silently suppresses notifications when the app is open.
// These methods make banners appear in-app, just like when the app is closed.
extension NotificationManager: UNUserNotificationCenterDelegate {

    /// Called when a notification arrives while the app is in the foreground.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show as a banner with sound even while the app is open
        completionHandler([.banner, .sound, .badge])
    }

    /// Called when the user taps a notification.
    /// Add deep-link navigation logic here in the future if needed.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        print("[NotificationManager] Notification tapped: \(response.notification.request.identifier)")
        completionHandler()
    }
}
