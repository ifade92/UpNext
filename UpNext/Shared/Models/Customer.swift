//
//  Customer.swift
//  UpNext
//
//  Represents a return customer recognized by their phone number.
//  The document ID in Firestore IS the phone number — this makes lookups instant
//  and naturally prevents duplicate records for the same customer.
//
//  Note: First-time customers don't get a document until after their first visit.
//  The kiosk creates/updates this record when they check in.
//

import Foundation
import FirebaseFirestore

// MARK: - Customer

struct Customer: Identifiable, Codable {

    // In Firestore, the document ID is the customer's phone number (e.g. "+12547891234")
    // This makes it easy to look up returning customers by phone at check-in
    @DocumentID var id: String?

    // --- Identity ---
    var name: String
    var phoneNumber: String            // Stored in E.164 format for Twilio compatibility

    // --- Visit History ---
    var visitCount: Int                // Total number of completed visits
    var lastVisitDate: Date?           // Used to greet returning customers ("Welcome back!")

    // --- Preferences ---
    // Remembered from previous visits — pre-selects these on the kiosk for faster check-in
    var preferredBarberId: String?
    var preferredServiceId: String?

    // MARK: - Computed Properties

    // Is this a returning customer we can greet by name?
    var isReturning: Bool {
        visitCount > 0
    }

    // Friendly display name for kiosk greeting
    var firstName: String {
        name.components(separatedBy: " ").first ?? name
    }
}
