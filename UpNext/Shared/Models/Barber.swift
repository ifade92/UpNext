//
//  Barber.swift
//  UpNext
//
//  Represents a barber at the shop.
//  This drives what shows up on the kiosk (who's available for walk-ins)
//  and the queue management screen on the iPhone app.
//

import Foundation
import FirebaseFirestore

// MARK: - Barber

struct Barber: Identifiable, Codable {

    // Firestore document ID — typically matches the Firebase Auth UID for that barber
    @DocumentID var id: String?

    // --- Basic Info ---
    var name: String
    var photoUrl: String?              // Firebase Storage URL — shown on kiosk barber selection grid

    // --- Account / Invite ---
    // The phone number the owner enters when adding a barber. The barber uses this
    // number + the shop code to create their own login via SMS in the app.
    var phone: String?

    // Kept for backward compat — older barber documents may still have this field.
    // New sign-up flow uses phone instead.
    var email: String?

    // --- Booking ---
    // Optional link to the barber's external booking page (Square, Booksy, etc.)
    // Shown as a QR code on the kiosk when the barber isn't accepting walk-ins.
    var bookingUrl: String?

    // --- Availability ---
    var status: BarberStatus           // Current real-time status (available, on break, off)

    // --- Go Live (The Key Feature) ---
    // "Go Live" lets appointment-only barbers opt into walk-in traffic during slow periods.
    // When goLive is true, this barber shows up on the kiosk. When false, they're hidden.
    var goLive: Bool

    // Determines the barber's default behavior and how Go Live works for them
    var barberType: BarberType

    // --- Services & Queue ---
    var serviceIds: [String]           // Which services this barber offers (references Service docs)
    var avgServiceTime: Int            // Rolling average in minutes — used to calc wait times
    var currentClientId: String?       // QueueEntry ID of the person currently in their chair
    var order: Int?                    // Display order on the kiosk grid — optional so older barbers without this field still decode correctly

    // MARK: - Computed Properties

    // Should this barber appear on the customer-facing kiosk?
    // All barber types respect the goLive flag so the owner's auto-close timer
    // can take everyone offline at once by setting goLive = false.
    // Walk-in barbers default to goLive = true when added — they're live immediately.
    var isVisibleOnKiosk: Bool {
        guard status == .available else { return false }
        // Every type respects goLive — auto-close sets this to false for all barbers
        return goLive
    }

    // Convenience: is this barber actively working (not off or on break)?
    var isWorking: Bool {
        status != .off
    }

    // MARK: - Next Available Sentinel

    /// A synthetic "Next Available" barber used in the UI to represent
    /// no-preference check-ins. Never persisted to Firestore directly —
    /// the queue entry uses barberId = "__next__" and noPreference = true.
    static var nextAvailable: Barber {
        Barber(
            id: "__next__",
            name: "No Preference",
            photoUrl: nil,
            phone: nil,
            email: nil,
            bookingUrl: nil,
            status: .available,
            goLive: true,
            barberType: .walkin,
            serviceIds: [],
            avgServiceTime: 0,
            currentClientId: nil,
            order: nil
        )
    }

    var isNextAvailable: Bool {
        id == "__next__"
    }

    // MARK: - Resilient Codable Decoding
    //
    // Older barber documents in Firestore may be missing fields that were added later
    // (barberType, avgServiceTime, serviceIds, status, order).
    // Swift's default Codable throws an error for ANY missing required field, causing
    // the barber to be silently dropped from the compactMap in FirebaseService.
    //
    // This custom init uses decodeIfPresent + fallback defaults so every barber
    // document decodes successfully regardless of when it was created.

    // NOTE: `id` is intentionally excluded from CodingKeys.
    // @DocumentID is injected by Firestore's decoder through its own special mechanism —
    // including `id` here would interfere with that and cause all barbers to decode with id = nil,
    // making SwiftUI treat every row as the same item (duplicate names/photos in the list).
    enum CodingKeys: String, CodingKey {
        case name, photoUrl, phone, email, bookingUrl
        case status, goLive, barberType
        case serviceIds, avgServiceTime, currentClientId, order
    }

    init(from decoder: Decoder) throws {
        // @DocumentID decodes itself via Firestore's special decoder mechanism —
        // it reads the document ID from decoder.userInfo, not from a regular key.
        // Calling DocumentID(from: decoder) triggers that internal Firestore path.
        self._id = try DocumentID(from: decoder)

        let c = try decoder.container(keyedBy: CodingKeys.self)

        // Required — a barber without a name isn't useful, let this throw
        name = try c.decode(String.self, forKey: .name)

        // Optional fields that have always been optional
        photoUrl        = try c.decodeIfPresent(String.self, forKey: .photoUrl)
        phone           = try c.decodeIfPresent(String.self, forKey: .phone)
        email           = try c.decodeIfPresent(String.self, forKey: .email)
        bookingUrl      = try c.decodeIfPresent(String.self, forKey: .bookingUrl)
        currentClientId = try c.decodeIfPresent(String.self, forKey: .currentClientId)
        order           = try c.decodeIfPresent(Int.self,    forKey: .order)

        // Fields added later — fall back to sensible defaults if missing in older documents
        goLive         = (try? c.decode(Bool.self,         forKey: .goLive))      ?? false
        barberType     = (try? c.decode(BarberType.self,   forKey: .barberType))  ?? .walkin
        serviceIds     = (try? c.decode([String].self,     forKey: .serviceIds))  ?? []
        avgServiceTime = (try? c.decode(Int.self,          forKey: .avgServiceTime)) ?? 30
        status         = (try? c.decode(BarberStatus.self, forKey: .status))      ?? .available
    }

    // Explicit memberwise init so the rest of the codebase (ShopSettingsViewModel,
    // FirebaseService, static nextAvailable, etc.) can still construct Barber values directly.
    // @DocumentID uses property-wrapper syntax — initialize its backing store via _id.
    init(
        id: String? = nil,
        name: String,
        photoUrl: String? = nil,
        phone: String? = nil,
        email: String? = nil,
        bookingUrl: String? = nil,
        status: BarberStatus = .available,
        goLive: Bool = false,
        barberType: BarberType = .walkin,
        serviceIds: [String] = [],
        avgServiceTime: Int = 30,
        currentClientId: String? = nil,
        order: Int? = nil
    ) {
        self._id            = DocumentID(wrappedValue: id)
        self.name           = name
        self.photoUrl       = photoUrl
        self.phone          = phone
        self.email          = email
        self.bookingUrl     = bookingUrl
        self.status         = status
        self.goLive         = goLive
        self.barberType     = barberType
        self.serviceIds     = serviceIds
        self.avgServiceTime = avgServiceTime
        self.currentClientId = currentClientId
        self.order          = order
    }
}

// MARK: - BarberStatus

// Real-time availability state — updated by the barber from their iPhone app
enum BarberStatus: String, Codable {
    case available  = "available"    // Ready to take the next client
    case onBreak    = "on_break"     // Temporarily unavailable (lunch, etc.)
    case off        = "off"          // Not working today / logged off

    var displayName: String {
        switch self {
        case .available: return "Available"
        case .onBreak:   return "On Break"
        case .off:       return "Off"
        }
    }
}

// MARK: - BarberType

// Determines how this barber operates and their Go Live defaults.
// This is set once when the owner adds a barber — it can be changed in Settings.
enum BarberType: String, Codable {
    case walkin           = "walkin"            // Walk-in focused, always on kiosk when available
    case appointmentOnly  = "appointment_only"  // Normally hidden from walk-ins; uses Go Live toggle
    case hybrid           = "hybrid"            // Mix of both; uses Go Live toggle

    var displayName: String {
        switch self {
        case .walkin:          return "Walk-In"
        case .appointmentOnly: return "Appointment Only"
        case .hybrid:          return "Hybrid"
        }
    }
}
