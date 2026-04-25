//
//  AppUser.swift
//  UpNext
//
//  Represents a logged-in user's profile stored in Firestore at users/{userId}.
//  Firebase Auth handles the credentials (phone + SMS) — this document
//  stores everything else: their role, which shop they belong to, and for
//  barbers, which barber profile is theirs.
//
//  Why a separate model from Firebase's Auth.User?
//  Firebase only gives us phone number and UID. We need role, shopId, and barberId
//  to route the user to the right screen and load the right data.
//

import Foundation
import FirebaseFirestore

// MARK: - AppUser

struct AppUser: Identifiable, Codable {

    // The Firestore document ID matches the Firebase Auth UID exactly.
    // This makes lookups instant: db.collection("users").document(Auth.auth().currentUser!.uid)
    @DocumentID var id: String?

    // Phone number in E.164 format (+12545551234) — the barber's login identifier.
    // Optional so older Firestore docs (created before phone auth) still decode safely.
    var phoneNumber: String?

    // Kept for backward compat — older user documents may still have this field.
    var email: String?

    // Optional so older Firestore docs (e.g. created before this field existed) still decode
    var displayName: String?

    // Which role this user has — determines which screen they see after login
    var role: UserRole

    // Every user belongs to exactly one shop
    var shopId: String

    // Only set for barbers — links to the barbers/{barberId} subcollection
    // Owners don't have a barberId (unless they also cut hair)
    var barberId: String?

    // FCM token for push notifications — updated every time the user logs in.
    // The Cloud Function reads this to send "new walk-in" alerts to all staff.
    var fcmToken: String?

    // Whether this user wants to receive push notifications for walk-ins.
    // Defaults to true — older Firestore docs without this field are treated as enabled.
    var notificationsEnabled: Bool?

    // Convenience: true if notifications are on (nil treated as true for backward compat)
    var wantsNotifications: Bool { notificationsEnabled ?? true }

    // MARK: - Computed Properties

    var isOwner: Bool  { role == .owner  }
    var isBarber: Bool { role == .barber }

    /// The first name pulled from displayName — used in greeting messages
    var firstName: String {
        let name = displayName ?? "there"
        return name.components(separatedBy: " ").first ?? name
    }
}

// MARK: - UserRole

enum UserRole: String, Codable {
    case owner  = "owner"   // Shop owner — sees the full dashboard + settings
    case barber = "barber"  // Individual barber — sees only their own queue
}
