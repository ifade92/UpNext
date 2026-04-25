//
//  FirebaseService.swift
//  UpNext
//
//  The single source of truth for all Firestore database operations.
//  ViewModels call this service — views never touch Firebase directly.
//
//  Architecture note: This is a singleton (FirebaseService.shared) so the whole
//  app shares one instance and one set of real-time listeners.
//

import Foundation
import FirebaseFirestore
import FirebaseAuth
import FirebaseStorage
import Combine
import UIKit

// MARK: - FirebaseService

class FirebaseService: ObservableObject {

    // Shared singleton instance — use FirebaseService.shared everywhere
    static let shared = FirebaseService()

    // The Firestore database reference — entry point for all reads/writes
    private let db = Firestore.firestore()

    // Active Firestore listeners — stored so we can cancel them when needed
    // (e.g. when a barber logs out, we stop listening to their queue)
    private var listeners: [String: ListenerRegistration] = [:]

    private init() {}

    // MARK: - Firestore Path Helpers
    // Centralizing paths here means if Firestore structure ever changes,
    // we only update it in one place.

    private func shopRef(_ shopId: String) -> DocumentReference {
        db.collection("shops").document(shopId)
    }

    private func barbersRef(_ shopId: String) -> CollectionReference {
        shopRef(shopId).collection("barbers")
    }

    private func servicesRef(_ shopId: String) -> CollectionReference {
        shopRef(shopId).collection("services")
    }

    private func queueRef(_ shopId: String) -> CollectionReference {
        shopRef(shopId).collection("queue")
    }

    private func queueHistoryRef(_ shopId: String) -> CollectionReference {
        shopRef(shopId).collection("queueHistory")
    }

    private func customerRef(_ phoneNumber: String) -> DocumentReference {
        db.collection("customers").document(phoneNumber)
    }


    // MARK: - Shop

    /// Fetch the shop document once (not real-time).
    /// Called on app launch to load shop name, logo, settings, etc.
    func fetchShop(shopId: String) async throws -> Shop {
        let doc = try await shopRef(shopId).getDocument()
        guard let shop = try? doc.data(as: Shop.self) else {
            throw UpNextError.documentNotFound("Shop \(shopId) not found")
        }
        return shop
    }

    /// Update shop settings (e.g. SMS templates, kiosk display mode).
    /// Called from the owner's Settings screen.
    func updateShopSettings(shopId: String, settings: ShopSettings) async throws {
        let data = try Firestore.Encoder().encode(settings)
        try await shopRef(shopId).updateData(["settings": data])
    }


    // MARK: - Barbers (Real-Time)

    /// Listen to the barbers collection in real time.
    /// Returns a publisher that emits a fresh [Barber] array whenever anything changes.
    /// Use this in your BarberViewModel to keep the UI always in sync.
    func listenToBarbers(shopId: String) -> AnyPublisher<[Barber], Error> {
        let subject = PassthroughSubject<[Barber], Error>()

        // Attach a Firestore snapshot listener — fires immediately with current data,
        // then again any time a barber document is added, changed, or removed.
        let listener = barbersRef(shopId)
            // NOTE: Do NOT use .order(by: "order") here — Firestore excludes documents
            // that are missing the field entirely, which drops older barbers.
            // Sorting is done client-side after decode so every barber document is returned.
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    subject.send(completion: .failure(error))
                    return
                }
                // Decode each Firestore document into a Barber struct, sort by order client-side
                let barbers = (snapshot?.documents.compactMap {
                    try? $0.data(as: Barber.self)
                } ?? []).sorted { ($0.order ?? 99) < ($1.order ?? 99) }
                subject.send(barbers)
            }

        // Store the listener so we can remove it later when no longer needed
        listeners["barbers_\(shopId)"] = listener
        return subject.eraseToAnyPublisher()
    }

    /// Add a new barber to the shop. Called from the owner's Settings screen.
    /// Returns the newly created Barber with its Firestore-assigned ID.
    func addBarber(shopId: String, barber: Barber) async throws -> Barber {
        let ref = barbersRef(shopId).document()
        var newBarber = barber
        let data = try Firestore.Encoder().encode(newBarber)
        try await ref.setData(data)
        newBarber.id = ref.documentID
        return newBarber
    }

    /// Update an existing barber's profile info (name, type, services, order).
    func updateBarber(shopId: String, barber: Barber) async throws {
        guard let id = barber.id else {
            throw UpNextError.missingId("Barber has no ID — cannot update")
        }
        let data = try Firestore.Encoder().encode(barber)
        try await barbersRef(shopId).document(id).setData(data, merge: true)
    }

    /// Delete a barber from the shop.
    /// Note: does not delete their existing queue entries — archive first if needed.
    func deleteBarber(shopId: String, barberId: String) async throws {
        try await barbersRef(shopId).document(barberId).delete()
    }

    /// Toggle a barber's Go Live status on or off.
    /// This is THE core feature — flipping this shows/hides the barber on the kiosk.
    func setGoLive(shopId: String, barberId: String, goLive: Bool) async throws {
        try await barbersRef(shopId).document(barberId).updateData([
            "goLive": goLive
        ])
    }

    /// Take every barber in the shop offline at once.
    /// Called by the auto-close timer — fires once a night at the owner's set close time.
    /// Each barber's own app will still show the correct state when they reopen.
    func closeAllBarbers(shopId: String) async throws {
        let snapshot = try await barbersRef(shopId).getDocuments()
        // Run all updates concurrently rather than one at a time
        try await withThrowingTaskGroup(of: Void.self) { group in
            for doc in snapshot.documents {
                let barberId = doc.documentID
                group.addTask {
                    try await self.barbersRef(shopId).document(barberId).updateData([
                        "goLive": false
                    ])
                }
            }
            try await group.waitForAll()
        }
    }

    /// Update a barber's availability status (available / on break / off).
    func updateBarberStatus(shopId: String, barberId: String, status: BarberStatus) async throws {
        try await barbersRef(shopId).document(barberId).updateData([
            "status": status.rawValue
        ])
    }

    /// Update the barber's current client reference.
    /// Called when a barber taps "Start" on a queue entry.
    func updateCurrentClient(shopId: String, barberId: String, clientId: String?) async throws {
        try await barbersRef(shopId).document(barberId).updateData([
            "currentClientId": clientId as Any
        ])
    }


    // MARK: - Owner Signup

    /// Create a brand-new shop document with default settings.
    /// Called from the owner in-app signup flow.
    /// New shops start as "cancelled" (no active subscription) — the owner
    /// subscribes via the in-app paywall (RevenueCat) or the website (Stripe).
    /// Local shops can use the WACO promo code for a free first month.
    /// Returns the new Shop with its Firestore-assigned ID.
    func createShop(name: String, address: String, ownerId: String) async throws -> Shop {
        let ref = db.collection("shops").document()

        // Default business hours — Monday–Saturday open, Sunday closed.
        // Owner can customize these later in Settings.
        let defaultHours: [String: DayHours] = [
            "monday":    DayHours(open: "09:00", close: "19:00", isOpen: true),
            "tuesday":   DayHours(open: "09:00", close: "19:00", isOpen: true),
            "wednesday": DayHours(open: "09:00", close: "19:00", isOpen: true),
            "thursday":  DayHours(open: "09:00", close: "19:00", isOpen: true),
            "friday":    DayHours(open: "09:00", close: "19:00", isOpen: true),
            "saturday":  DayHours(open: "09:00", close: "17:00", isOpen: true),
            "sunday":    DayHours(open: "10:00", close: "16:00", isOpen: false),
        ]

        let shop = Shop(
            id: ref.documentID,
            name: name,
            address: address,
            logoUrl: nil,
            ownerId: ownerId,
            hours: defaultHours,
            settings: ShopSettings.defaults,
            subscriptionStatus: .cancelled,
            subscriptionTier: .base
        )

        let data = try Firestore.Encoder().encode(shop)
        try await ref.setData(data)
        return shop
    }

    /// Create the AppUser document for a newly signed-up shop owner.
    func createOwnerUser(userId: String, email: String, shopId: String, displayName: String) async throws {
        let userData: [String: Any] = [
            "email": email,
            "displayName": displayName,
            "role": "owner",
            "shopId": shopId,
            "createdAt": Timestamp(date: Date())
        ]
        try await db.collection("users").document(userId).setData(userData)
    }


    // MARK: - Barber Invite / Signup

    /// Update whether a user wants to receive push notifications.
    /// The Cloud Function checks this flag before sending to their FCM token.
    func updateNotificationPreference(userId: String, enabled: Bool) async throws {
        try await db.collection("users").document(userId).updateData([
            "notificationsEnabled": enabled
        ])
    }

    /// Look up a barber by email address within a specific shop.
    /// Called during the sign-up flow — the owner pre-adds the barber's email in Settings,
    /// then we find their document here to confirm they belong to this shop.
    func findBarberByEmail(shopId: String, email: String) async throws -> Barber? {
        let snapshot = try await barbersRef(shopId)
            .whereField("email", isEqualTo: email)
            .getDocuments()
        return snapshot.documents.first.flatMap { try? $0.data(as: Barber.self) }
    }

    /// Look up a barber by phone number within a specific shop.
    /// Kept for backward compatibility — new sign-up flow uses findBarberByEmail instead.
    func findBarberByPhone(shopId: String, phone: String) async throws -> Barber? {
        let snapshot = try await barbersRef(shopId)
            .whereField("phone", isEqualTo: phone)
            .getDocuments()
        return snapshot.documents.first.flatMap { try? $0.data(as: Barber.self) }
    }

    /// Link a Firebase Auth UID to an existing barber document.
    /// Called after a barber successfully signs up — we store their userId so we
    /// can look them up on future logins.
    func linkUserToBarber(shopId: String, barberId: String, userId: String) async throws {
        try await barbersRef(shopId).document(barberId).updateData([
            "userId": userId
        ])
    }

    /// Create the AppUser document for a newly signed-up barber.
    /// displayName comes from the barber's existing profile in the barbers collection.
    func createBarberUser(userId: String, email: String, shopId: String, barberId: String, displayName: String) async throws {
        let userData: [String: Any] = [
            "email": email,
            "displayName": displayName,
            "role": "barber",
            "shopId": shopId,
            "barberId": barberId,
            "createdAt": Timestamp(date: Date())
        ]
        try await db.collection("users").document(userId).setData(userData)
    }

    // MARK: - Photo Upload (Firebase Storage)

    /// Upload a barber's profile photo and return the download URL.
    /// The image is compressed to JPEG before upload to keep Storage costs low.
    /// Path: barbers/{shopId}/{barberId}/profile.jpg
    func uploadBarberPhoto(shopId: String, barberId: String, image: UIImage) async throws -> String {
        let storageRef = Storage.storage().reference()
            .child("barbers/\(shopId)/\(barberId)/profile.jpg")

        // Compress to JPEG at 0.75 quality — good balance of quality vs file size
        guard let imageData = image.jpegData(compressionQuality: 0.75) else {
            throw UpNextError.encodingFailed("Could not convert image to JPEG")
        }

        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"

        // Upload the image data
        _ = try await storageRef.putDataAsync(imageData, metadata: metadata)

        // Get the public download URL and return it
        let downloadURL = try await storageRef.downloadURL()
        return downloadURL.absoluteString
    }

    /// Save a barber's photo URL back to their Firestore document after upload.
    func updateBarberPhotoUrl(shopId: String, barberId: String, url: String) async throws {
        try await barbersRef(shopId).document(barberId).updateData([
            "photoUrl": url
        ])
    }

    // MARK: - Services

    /// Fetch all active services for a shop once (services don't change in real time).
    /// Called when loading the kiosk service selection screen.
    ///
    /// Note: We fetch ALL documents and filter/sort client-side instead of using
    /// .whereField + .order(by) in Firestore. The compound query requires a composite
    /// index — fetching everything avoids that setup and is fine for a small services list.
    func fetchServices(shopId: String) async throws -> [Service] {
        let snapshot = try await servicesRef(shopId).getDocuments()
        return snapshot.documents
            .compactMap { try? $0.data(as: Service.self) }
            .filter { $0.active }
            .sorted { $0.order < $1.order }
    }


    /// Add a new service to the shop menu.
    func addService(shopId: String, service: Service) async throws -> Service {
        let ref = servicesRef(shopId).document()
        var newService = service
        let data = try Firestore.Encoder().encode(newService)
        try await ref.setData(data)
        newService.id = ref.documentID
        return newService
    }

    /// Update an existing service (name, duration, price, active state).
    func updateService(shopId: String, service: Service) async throws {
        guard let id = service.id else {
            throw UpNextError.missingId("Service has no ID — cannot update")
        }
        let data = try Firestore.Encoder().encode(service)
        try await servicesRef(shopId).document(id).setData(data, merge: true)
    }

    /// Delete a service from the shop menu.
    func deleteService(shopId: String, serviceId: String) async throws {
        try await servicesRef(shopId).document(serviceId).delete()
    }

    /// Fetch ALL services (including inactive) — used in settings so owner sees everything.
    func fetchAllServices(shopId: String) async throws -> [Service] {
        let snapshot = try await servicesRef(shopId)
            .order(by: "order")
            .getDocuments()
        return snapshot.documents.compactMap {
            try? $0.data(as: Service.self)
        }
    }

    // MARK: - Queue (Real-Time)

    /// Listen to the active queue in real time.
    /// This is the beating heart of the app — every check-in and status change
    /// flows through this listener to keep all screens in sync instantly.
    func listenToQueue(shopId: String) -> AnyPublisher<[QueueEntry], Error> {
        let subject = PassthroughSubject<[QueueEntry], Error>()

        // Only listen to active entries — completed/removed entries go to queueHistory
        let listener = queueRef(shopId)
            .whereField("status", in: [
                QueueStatus.waiting.rawValue,
                QueueStatus.notified.rawValue,
                QueueStatus.inChair.rawValue
            ])
            .order(by: "checkInTime")  // Oldest first = front of line
            .addSnapshotListener { snapshot, error in
                if let error = error {
                    subject.send(completion: .failure(error))
                    return
                }
                let entries = snapshot?.documents.compactMap {
                    try? $0.data(as: QueueEntry.self)
                } ?? []
                subject.send(entries)
            }

        listeners["queue_\(shopId)"] = listener
        return subject.eraseToAnyPublisher()
    }

    /// Add a new customer to the queue. Called when a customer finishes check-in on the kiosk.
    /// Returns the newly created QueueEntry with its Firestore-assigned ID.
    func addToQueue(shopId: String, entry: QueueEntry) async throws -> QueueEntry {
        // Encode the entry to a Firestore-compatible dictionary
        let ref = queueRef(shopId).document()
        var newEntry = entry
        // We use try/catch here so a failed encode doesn't silently drop data
        let data = try Firestore.Encoder().encode(newEntry)
        try await ref.setData(data)
        newEntry.id = ref.documentID
        return newEntry
    }

    /// Add a group of people who checked in together as SEPARATE queue entries.
    ///
    /// This is the correct way to handle party check-ins. Each person gets their own
    /// independent Firestore document so any barber can claim them individually —
    /// they are NOT all tied to whoever claims the first person in the group.
    ///
    /// All entries share a groupId so the UI can visually group them and barbers
    /// know they arrived together. Uses a Firestore batch write so all N entries
    /// are created atomically — if one fails, none are created.
    ///
    /// Returns all created entries with their Firestore-assigned IDs.
    func addGroupToQueue(shopId: String, entries: [QueueEntry]) async throws -> [QueueEntry] {
        let batch = db.batch()
        var createdEntries: [QueueEntry] = []

        for var entry in entries {
            let ref = queueRef(shopId).document()
            let data = try Firestore.Encoder().encode(entry)
            batch.setData(data, forDocument: ref)
            entry.id = ref.documentID
            createdEntries.append(entry)
        }

        // Commit all at once — atomic, no partial check-ins
        try await batch.commit()
        return createdEntries
    }

    /// Update an existing queue entry's status or data.
    /// Used for: starting a cut, marking done, reassigning, etc.
    func updateQueueEntry(shopId: String, entry: QueueEntry) async throws {
        guard let id = entry.id else {
            throw UpNextError.missingId("QueueEntry has no ID — cannot update")
        }
        let data = try Firestore.Encoder().encode(entry)
        try await queueRef(shopId).document(id).setData(data, merge: true)
    }

    /// Move a completed or removed entry to queueHistory and delete from active queue.
    /// This keeps the active queue lean — history is for analytics later (Phase 2).
    func archiveQueueEntry(shopId: String, entry: QueueEntry) async throws {
        guard let id = entry.id else {
            throw UpNextError.missingId("QueueEntry has no ID — cannot archive")
        }
        let data = try Firestore.Encoder().encode(entry)
        // Attempt to archive to history — non-fatal if Firestore rules don't cover it yet.
        // The critical step is the deletion from the active queue, which always runs.
        try? await queueHistoryRef(shopId).document(id).setData(data)
        try await queueRef(shopId).document(id).delete()
    }

    /// Convenience: mark a queue entry as started (barber tapped "Start").
    func startService(shopId: String, entry: QueueEntry) async throws {
        guard let id = entry.id else { return }
        try await queueRef(shopId).document(id).updateData([
            "status": QueueStatus.inChair.rawValue,
            "startTime": Timestamp(date: Date())
        ])
    }

    /// Convenience: mark a queue entry as complete and archive it.
    func completeService(shopId: String, entry: QueueEntry) async throws {
        var completed = entry
        completed.status = .completed
        completed.endTime = Date()
        try await archiveQueueEntry(shopId: shopId, entry: completed)
    }

    /// Convenience: remove a customer from the queue (barber/owner action).
    func removeFromQueue(shopId: String, entry: QueueEntry) async throws {
        var removed = entry
        removed.status = .removed
        try await archiveQueueEntry(shopId: shopId, entry: removed)
    }


    // MARK: - Analytics

    /// Fetch all barbers for a shop once (non-realtime). Used by Analytics to build the leaderboard.
    func fetchAllBarbers(shopId: String) async throws -> [Barber] {
        let snapshot = try await barbersRef(shopId).getDocuments()
        return snapshot.documents
            .compactMap { try? $0.data(as: Barber.self) }
            .sorted { ($0.order ?? 99) < ($1.order ?? 99) }
    }

    /// Fetch all completed entries from queueHistory since a given date.
    /// Used by AnalyticsViewModel to power the stats, chart, and leaderboard.
    /// Filters only by status (no composite index needed) — date filtering is done client-side
    /// in AnalyticsViewModel so Firestore doesn't require a multi-field index.
    func fetchCompletedEntries(shopId: String, since date: Date) async throws -> [QueueEntry] {
        let snapshot = try await queueHistoryRef(shopId)
            .whereField("status", isEqualTo: QueueStatus.completed.rawValue)
            .getDocuments()
        return snapshot.documents
            .compactMap { try? $0.data(as: QueueEntry.self) }
            .filter { $0.checkInTime >= date }
    }

    /// Fetch ALL archived entries from queueHistory since a given date — completed, walked out,
    /// and removed. Used to build the full sign-in sheet across all 4 dashboard views so the list
    /// is consistent regardless of who completed the client or from which platform.
    ///
    /// Uses a server-side Firestore filter so we only download today's entries — not the entire
    /// history collection. This is a single-field filter so no composite index is required.
    func fetchArchivedEntries(shopId: String, since date: Date) async throws -> [QueueEntry] {
        let snapshot = try await queueHistoryRef(shopId)
            .whereField("checkInTime", isGreaterThanOrEqualTo: Timestamp(date: date))
            .getDocuments()
        return snapshot.documents
            .compactMap { try? $0.data(as: QueueEntry.self) }
    }


    // MARK: - Customers

    /// Look up a returning customer by phone number.
    /// Returns nil if they've never been here before — that's fine, they're just new.
    func lookupCustomer(phoneNumber: String) async throws -> Customer? {
        let doc = try await customerRef(phoneNumber).getDocument()
        guard doc.exists else { return nil }
        return try? doc.data(as: Customer.self)
    }

    /// Create or update a customer record after a successful check-in.
    /// Uses merge: true so we don't overwrite existing visit history.
    func upsertCustomer(_ customer: Customer) async throws {
        let data = try Firestore.Encoder().encode(customer)
        try await customerRef(customer.phoneNumber).setData(data, merge: true)
    }

    /// Increment a customer's visit count after their service is completed.
    func incrementVisitCount(phoneNumber: String) async throws {
        try await customerRef(phoneNumber).updateData([
            "visitCount": FieldValue.increment(Int64(1)),
            "lastVisitDate": Timestamp(date: Date())
        ])
    }


    // MARK: - Listener Cleanup

    /// Remove a specific listener by key. Call this when leaving a screen.
    func removeListener(key: String) {
        listeners[key]?.remove()
        listeners.removeValue(forKey: key)
    }

    /// Remove ALL active listeners. Call this on logout.
    func removeAllListeners() {
        listeners.values.forEach { $0.remove() }
        listeners.removeAll()
    }
}


// MARK: - UpNextError

// Custom error types so we can give meaningful error messages in the UI
enum UpNextError: LocalizedError {
    case documentNotFound(String)
    case missingId(String)
    case encodingFailed(String)
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .documentNotFound(let msg): return "Not found: \(msg)"
        case .missingId(let msg):        return "Missing ID: \(msg)"
        case .encodingFailed(let msg):   return "Encoding error: \(msg)"
        case .unknown(let msg):          return "Unknown error: \(msg)"
        }
    }
}
