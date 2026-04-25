//
//  Service.swift
//  UpNext
//
//  Represents a service offered at the barbershop (e.g. Haircut, Beard Trim, Fade).
//  Services are shown on the kiosk so customers can pick what they want,
//  and the estimated duration feeds directly into wait time calculations.
//

import Foundation
import FirebaseFirestore

// MARK: - Service

struct Service: Identifiable, Codable {

    // Firestore document ID
    @DocumentID var id: String?

    // --- Service Details ---
    var name: String                   // e.g. "Fade", "Haircut & Beard", "Kids Cut"
    var estimatedMinutes: Int          // How long this service typically takes — drives wait time math
    var price: Double?                 // Optional — owner can choose to show or hide prices on kiosk
    var active: Bool                   // Inactive services are hidden from the kiosk
    var order: Int                     // Display order on the kiosk service selection screen

    // MARK: - Computed Properties

    // Formatted price string for display (e.g. "$25" or "—" if no price set)
    var displayPrice: String {
        guard let price = price else { return "—" }
        return String(format: "$%.0f", price)
    }

    // Formatted duration for display (e.g. "~30 min")
    var displayDuration: String {
        return "~\(estimatedMinutes) min"
    }
}
