//
//  UpNextApp.swift
//  UpNext
//
//  Created by Carlos Canales on 3/7/26.
//
//  App entry point. Firebase and RevenueCat are configured here before
//  anything else loads — they need to be the very first things that run.
//

import SwiftUI
import FirebaseCore
import FirebaseMessaging
import RevenueCat

// MARK: - RevenueCat API Keys
// DEBUG  → Sandbox key (test purchases only, no real charges)
// RELEASE → Production key (live App Store subscriptions)
#if DEBUG
private let revenueCatAPIKey = "test_XXhotbGXLwHaWrKfvhprjwOdRqK"
#else
private let revenueCatAPIKey = "appl_jJckDkuXmbYbMKyCyjkpNsSfEYh"
#endif

// AppDelegate handles third-party SDK setup.
// We use UIApplicationDelegate because these SDKs need to run before
// the SwiftUI lifecycle kicks in.
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Initialize Firebase — reads GoogleService-Info.plist automatically
        FirebaseApp.configure()

        // Register with APNs so Firebase Messaging can receive push notifications.
        // Without this call, FCM never gets a device token and notifications won't arrive.
        application.registerForRemoteNotifications()

        // Initialize RevenueCat — must happen after Firebase
        SubscriptionManager.configure(apiKey: revenueCatAPIKey)

        return true
    }

    // MARK: - APNs → Firebase Messaging Bridge
    //
    // These two methods hand off the APNs device token to Firebase Messaging (FCM).
    //
    // Why this matters:
    //   Firebase Messaging needs the raw APNs token to exchange it for an FCM token.
    //   Without this, FCM tokens are never activated, the token never gets saved to
    //   Firestore, and your Cloud Functions can't send push notifications to anyone.
    //
    // Note: Do NOT pass the token to Auth.auth().setAPNSToken() here — that was only
    // needed for Firebase Phone Auth (SMS verification), which we no longer use.

    /// Pass the raw APNs device token to Firebase Messaging.
    /// Firebase will exchange this for an FCM registration token automatically.
    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
    }

    /// Called if APNs registration fails (e.g. running on Simulator, no push entitlement).
    /// Logged here so you can spot it during development — safe to ignore on real devices.
    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("[APNs] Failed to register for remote notifications: \(error.localizedDescription)")
    }
}

@main
struct UpNextApp: App {

    // Connect the AppDelegate to the SwiftUI lifecycle
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate

    // Observe the scene lifecycle so we know when the app comes to the foreground
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        // Clear the badge the moment the app becomes active —
        // no number on the icon while the barber is looking at the app
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                NotificationManager.shared.clearBadge()
            }
        }
    }
}
