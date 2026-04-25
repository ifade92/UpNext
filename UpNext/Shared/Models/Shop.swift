//
//  Shop.swift
//  UpNext
//
//  Represents a barbershop using UpNext.
//  This is the top-level document in Firestore — everything else (barbers, services, queue)
//  lives as a subcollection under a shop document.
//

import Foundation
import FirebaseFirestore

// MARK: - Shop

struct Shop: Identifiable, Codable {

    // Firestore document ID — generated on signup
    @DocumentID var id: String?

    // --- Basic Info ---
    var name: String                           // e.g. "Fademasters Barbershop"
    var address: String
    var logoUrl: String?                       // Used on kiosk welcome screen
    var ownerId: String                        // Firebase Auth UID of the shop owner

    // --- Hours ---
    // Keyed by lowercase day name: "monday", "tuesday", etc.
    var hours: [String: DayHours]

    // --- Settings ---
    var settings: ShopSettings

    // --- Subscription ---
    var subscriptionStatus: SubscriptionStatus
    var subscriptionTier: SubscriptionTier

    // --- Stripe (Web Subscriptions) ---
    // Set by the Stripe webhook Cloud Function when a customer subscribes via the website.
    // These fields are nil for App Store subscribers (handled by RevenueCat instead).
    var stripeCustomerId: String?
    var stripeSubscriptionId: String?
    var stripeEmail: String?

    // MARK: - Computed Properties

    // Is the shop currently accepting walk-ins? (Simple check — could be expanded in Phase 2)
    var isOpen: Bool {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        let today = formatter.string(from: Date()).lowercased()
        return hours[today]?.isOpen ?? false
    }
}

// MARK: - DayHours

// Stores open/close times for a single day of the week
struct DayHours: Codable {
    var open: String     // 24hr format, e.g. "09:00"
    var close: String    // 24hr format, e.g. "19:00"
    var isOpen: Bool     // False = closed that day (e.g. Sunday)
}

// MARK: - ShopSettings

// Owner-configurable settings that control kiosk behavior and notifications
struct ShopSettings: Codable {

    // Should prices be shown on the kiosk service selection screen?
    var showPricesOnKiosk: Bool

    // How many positions away should we notify the customer?
    // e.g. 2 = send "almost up" SMS when they're 2nd in line
    var notifyWhenPositionAway: Int

    // How the queue position is shown to customers
    var queueDisplayMode: QueueDisplayMode

    // SMS message templates — owner can customize these in Settings
    // Supports placeholders: {name}, {position}, {wait}
    var almostUpSmsTemplate: String      // e.g. "Hey {name}, you're almost up! Get ready."
    var youreUpSmsTemplate: String       // e.g. "Hey {name}, it's your turn! Head on over."

    // Auto-close time — "HH:MM" in 24hr format, e.g. "21:00"
    // At this time every night, all barbers are automatically taken offline.
    // nil = disabled (owner manages availability manually)
    var autoCloseTime: String?

    // MARK: - Default Settings
    // Used when a new shop signs up — sensible out-of-the-box experience
    static var defaults: ShopSettings {
        ShopSettings(
            showPricesOnKiosk: true,
            notifyWhenPositionAway: 2,
            queueDisplayMode: .both,
            almostUpSmsTemplate: "Hey {name}, you're almost up at {shop}! Get ready.",
            youreUpSmsTemplate: "Hey {name}, it's your turn! Head on over to {shop}.",
            autoCloseTime: nil
        )
    }
}

// MARK: - QueueDisplayMode

// Controls how wait info is shown to customers on the kiosk confirmation screen
enum QueueDisplayMode: String, Codable {
    case position = "position"   // "You're #3 in line"
    case waitTime = "wait_time"  // "~15 min wait"
    case both     = "both"       // "You're #3 in line · ~15 min wait"
}

// MARK: - SubscriptionStatus

enum SubscriptionStatus: String, Codable {
    case active    = "active"     // Paying, all good
    case pastDue   = "past_due"   // Payment failed, grace period
    case cancelled = "cancelled"  // Subscription ended or never started

    // Legacy — kept so old Firestore docs with "trial" status still decode
    case trial     = "trial"
}

// MARK: - SubscriptionTier

// Pricing tiers — determines feature limits and monthly cost
//
// Base ($49.99/mo): Unlimited barbers, single location
// Multi-Location ($79.99/mo): Everything in Base + multi-location management
//
// Legacy tiers (starter, pro, enterprise) are kept for backward compatibility
// with any existing Firestore documents. New signups always get "base" or "multi".
enum SubscriptionTier: String, Codable {
    case base       = "base"        // Unlimited barbers, 1 location, $49.99/mo
    case multi      = "multi"       // Unlimited barbers, multi-location, $79.99/mo

    // Legacy tiers — kept so old Firestore docs still decode without crashing
    case starter    = "starter"
    case pro        = "pro"
    case enterprise = "enterprise"

    var maxBarbers: Int {
        // All tiers now have unlimited barbers
        return Int.max
    }

    /// Whether this tier supports managing multiple shop locations
    var supportsMultiLocation: Bool {
        switch self {
        case .multi, .enterprise: return true
        default: return false
        }
    }

    var monthlyPrice: Double {
        switch self {
        case .base, .starter:           return 49.99
        case .multi, .pro:              return 79.99
        case .enterprise:               return 129
        }
    }

    var displayName: String {
        switch self {
        case .base, .starter:           return "Base"
        case .multi, .pro:              return "Multi-Location"
        case .enterprise:               return "Enterprise"
        }
    }
}
