//
//  QueueEntry.swift
//  UpNext
//
//  Represents a single customer's position in the barbershop queue.
//  This is the core data model of the entire app — every check-in creates one of these.
//

import Foundation
import FirebaseFirestore

// MARK: - QueueEntry

struct QueueEntry: Identifiable, Codable {

    // Firestore auto-generates this ID when the document is created
    @DocumentID var id: String?

    // --- Customer Info ---
    var customerName: String
    var customerPhone: String          // Used to send SMS notifications via Twilio

    // --- Barber Assignment ---
    var barberId: String               // The barber the customer selected at the kiosk
    var assignedBarberId: String?      // May differ if owner reassigns them to another barber

    // --- Service ---
    // Optional — appointment check-ins from the web QR flow don't pick a service
    var serviceId: String?             // References a Service document in Firestore

    // --- Queue Status ---
    var status: QueueStatus            // Tracks where this customer is in the flow

    // --- Position & Timing ---
    // Optional because appointment check-ins from the web QR flow don't
    // calculate position or wait time — they go straight to the barber's queue.
    var position: Int?                 // Their spot in line (1 = next up)
    var checkInTime: Date              // When they signed in at the kiosk
    var notifiedTime: Date?            // When we sent "almost up" or "you're up" SMS
    var startTime: Date?               // When the barber actually started their cut
    var endTime: Date?                 // When the service was marked complete

    // --- Wait Time ---
    var estimatedWaitMinutes: Int?     // Shown to customer on kiosk confirmation screen

    // --- Party Size ---
    // How many people in the group who all need cuts.
    // Shown on the barber and owner views so barbers know what to expect.
    // NOTE: As of the group check-in fix, each person in a party gets their OWN
    // QueueEntry document. partySize is kept for backward compat with old entries.
    var partySize: Int?

    // --- Group Check-In ---
    // When multiple people check in together, each gets their own QueueEntry but
    // they share a groupId so the UI can group them visually and barbers know
    // they came in together. partyIndex (1-based) is their slot in the group.
    // nil on both means the customer checked in solo.
    var groupId: String?    = nil  // UUID shared by everyone who checked in together
    var partyIndex: Int?   = nil  // 1-based slot: 1 = primary, 2 = guest 2, etc.
    var groupSize: Int?    = nil  // Total people in this group (same for all members)

    // --- No Preference ---
    // Set to true when the customer selected "Next Available" instead of a specific barber.
    // barberId will be "__next__" — the TV queue and dashboard use this flag to label them.
    // In the sign-in sheet model, ALL walk-ins are no-preference — every check-in sets this true.
    var noPreference: Bool?

    // --- Appointment Flag ---
    // True when this entry was created via the QR check-in appointment flow.
    // The barber app shows a 📅 badge so they can distinguish appointment clients from walk-ins.
    var isAppointment: Bool?

    // --- Remote Check-In Flag ---
    // True when the customer checked in from the website wait-time page — meaning they
    // are NOT physically at the shop yet. Set to false (or nil = false) for all kiosk
    // check-ins. The barber app shows a 📍 badge so the barber knows to verify
    // the customer is actually in the building before seating them.
    //
    // HOW TO USE ON THE WEB SIDE:
    //   When creating the Firestore queue document from the website check-in flow,
    //   include the field:  isRemoteCheckIn: true
    //   If you want to disable web check-ins entirely, just remove the form from
    //   the website and leave this field unset — it defaults to false here in the app.
    var isRemoteCheckIn: Bool? = nil

    // --- Remote Arrival Status ---
    // Tracks where a remote customer is in the arrival process.
    // Values: "on_the_way" (just checked in remotely, not at shop yet)
    //         "arrived"    (tapped "I'm Here" on the queue tracker page)
    //         nil          (not a remote check-in, or legacy entry)
    // The barber app uses this to show "📍 On the Way" vs "✅ Arrived" badges.
    // A Cloud Function auto-removes entries stuck at "on_the_way" after 30 minutes.
    var remoteStatus: String? = nil

    // --- SMS Notification Flags ---
    // Tracked separately so we don't accidentally double-send texts
    var notifiedAlmostUp: Bool         // True once "you're almost up" SMS was sent
    var notifiedYoureUp: Bool          // True once "you're up, it's your turn" SMS was sent

    // MARK: - Computed Properties

    // Convenience: how long has this customer been waiting?
    var minutesWaiting: Int {
        let elapsed = Date().timeIntervalSince(checkInTime)
        return Int(elapsed / 60)
    }

    // Convenience: is this customer still actively in the queue?
    var isActive: Bool {
        status == .waiting || status == .inChair || status == .notified
    }
}

// MARK: - QueueStatus

// The full lifecycle of a customer from check-in to done
enum QueueStatus: String, Codable, CaseIterable {
    case waiting      = "waiting"      // Checked in, waiting their turn
    case notified     = "notified"     // Texted "almost up" or "you're up"
    case inChair      = "in_chair"     // Barber started the service
    case completed    = "completed"    // Service done, marked by barber
    case walkedOut    = "walked_out"   // Customer left before being seen
    case removed      = "removed"      // Manually removed by barber or owner

    // Human-readable label for display in the app
    var displayName: String {
        switch self {
        case .waiting:   return "Waiting"
        case .notified:  return "Notified"
        case .inChair:   return "In Chair"
        case .completed: return "Completed"
        case .walkedOut: return "Walked Out"
        case .removed:   return "Removed"
        }
    }
}
