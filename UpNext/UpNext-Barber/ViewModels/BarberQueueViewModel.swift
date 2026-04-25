//
//  BarberQueueViewModel.swift
//  UpNext
//
//  The brain behind the barber's iPhone queue screen.
//  This ViewModel subscribes to real-time Firestore data and exposes
//  clean, ready-to-display properties to the SwiftUI view.
//
//  Architecture note: Views never call FirebaseService directly —
//  they only talk to this ViewModel. This keeps views dumb and testable.
//

import Foundation
import Combine
import FirebaseFirestore

// @MainActor ensures all @Published property updates happen on the main thread,
// which is required for SwiftUI to safely update the UI.
@MainActor
class BarberQueueViewModel: ObservableObject {

    // MARK: - Published Properties
    // Any view observing this ViewModel will automatically re-render when these change.

    // The barber whose queue we're managing
    @Published var barber: Barber?

    // All barbers in the shop — lets barbers see each other's queues in the full shop view
    @Published var allBarbers: [Barber] = []

    // Full shop queue — all active entries across every barber.
    // Own queue, pool entries, and other barbers' entries are all computed from this.
    @Published var allShopQueue: [QueueEntry] = []

    // Today's archived entries (completed, walked out, removed) — fetched from queueHistory.
    // Combined with allShopQueue this gives the barber the same full-day list as the owner.
    @Published var todayArchived: [QueueEntry] = []

    // All services the shop offers (needed to display service names in the queue)
    @Published var services: [Service] = []

    // Go Live toggle state — bound directly to the UI toggle
    @Published var isGoLive: Bool = false

    // Loading and error states for the UI to react to
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    // MARK: - Private Properties

    private let firebase = FirebaseService.shared
    private var cancellables = Set<AnyCancellable>()  // Stores active Combine subscriptions

    // These are set on init and never change during the session
    private let shopId: String
    let barberId: String  // Internal so views can read it for "isMe" card checks

    // Auto-close timer — fires once at the shop's configured close time to take this barber offline
    private var autoCloseTimer: Timer?

    // MARK: - Init

    init(shopId: String, barberId: String) {
        self.shopId = shopId
        self.barberId = barberId
    }

    // MARK: - Lifecycle

    /// Call this when the barber's queue screen appears.
    /// Starts all real-time listeners so the UI stays in sync with Firestore.
    func onAppear() {
        isLoading = true
        startListeningToQueue()
        startListeningToBarbers()
        Task {
            await loadServices()
            await fetchTodaysArchived()   // Load today's completed/walked-out entries
            await scheduleAutoClose()     // Check + set auto-close timer from shop settings
        }
    }

    /// Fetch today's archived entries (all statuses) from queueHistory.
    /// Called on appear — gives barbers the full day list including crossed-out clients.
    func fetchTodaysArchived() async {
        let startOfToday = Calendar.current.startOfDay(for: Date())
        do {
            todayArchived = try await firebase.fetchArchivedEntries(shopId: shopId, since: startOfToday)
        } catch {
            // Non-fatal — active queue still shows, archived section stays empty
        }
    }

    /// Call this when the barber logs out or the screen disappears permanently.
    /// Cleans up Firestore listeners so we're not paying for reads we don't need.
    func onDisappear() {
        firebase.removeAllListeners()
        cancellables.removeAll()
        autoCloseTimer?.invalidate()
        autoCloseTimer = nil
    }

    // MARK: - Real-Time Queue Listener

    /// Subscribes to the FULL shop queue (all barbers).
    /// Own queue, pool, and other barbers' entries are computed from this single source of truth.
    private func startListeningToQueue() {
        firebase.listenToQueue(shopId: shopId)
            .receive(on: DispatchQueue.main)  // Always update UI on main thread
            .sink(
                receiveCompletion: { [weak self] completion in
                    if case .failure(let error) = completion {
                        self?.errorMessage = error.localizedDescription
                    }
                },
                receiveValue: { [weak self] allEntries in
                    guard let self = self else { return }
                    self.allShopQueue = allEntries
                    self.isLoading = false
                }
            )
            .store(in: &cancellables)
    }

    /// Subscribes to all barbers so we can show the full shop view.
    /// Also keeps the logged-in barber's Go Live toggle in sync across devices.
    private func startListeningToBarbers() {
        firebase.listenToBarbers(shopId: shopId)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    if case .failure(let error) = completion {
                        self?.errorMessage = error.localizedDescription
                    }
                },
                receiveValue: { [weak self] barbers in
                    guard let self = self else { return }
                    // Sort by order field so the list matches what customers see on the kiosk
                    // Use ?? 99 so barbers without an order field sort to the end
                    self.allBarbers = barbers.sorted { ($0.order ?? 99) < ($1.order ?? 99) }
                    // Find this specific barber from the full list
                    if let currentBarber = barbers.first(where: { $0.id == self.barberId }) {
                        self.barber = currentBarber
                        self.isGoLive = currentBarber.goLive
                    }
                }
            )
            .store(in: &cancellables)
    }

    // MARK: - Services

    /// Loads services once on appear. Services rarely change so no real-time listener needed.
    private func loadServices() async {
        do {
            services = try await firebase.fetchServices(shopId: shopId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Go Live Toggle

    /// Called when the barber flips the Go Live toggle on their iPhone.
    /// Instantly shows or hides them on the customer kiosk.
    func toggleGoLive() {
        let newValue = !isGoLive
        isGoLive = newValue  // Optimistic update — update UI immediately, don't wait for Firestore

        Task {
            do {
                try await firebase.setGoLive(shopId: shopId, barberId: barberId, goLive: newValue)
            } catch {
                // If the update fails, roll back the toggle
                isGoLive = !newValue
                errorMessage = "Failed to update Go Live status. Try again."
            }
        }
    }

    // MARK: - Queue Actions

    /// Barber taps "Start" — moves client from waiting to in chair.
    func startService(entry: QueueEntry) {
        Task {
            do {
                try await firebase.startService(shopId: shopId, entry: entry)
                // Also update the barber's currentClientId so other views know who's in chair
                if let entryId = entry.id {
                    try await firebase.updateCurrentClient(shopId: shopId, barberId: barberId, clientId: entryId)
                }
            } catch {
                errorMessage = "Couldn't start service. Try again."
            }
        }
    }

    /// Barber taps "Done" — marks the service complete and archives the entry.
    func completeService(entry: QueueEntry) {
        Task {
            do {
                try await firebase.completeService(shopId: shopId, entry: entry)
                try await firebase.updateCurrentClient(shopId: shopId, barberId: barberId, clientId: nil)
                // Re-fetch archived so the completed entry appears in the sign-in sheet immediately
                await fetchTodaysArchived()
            } catch {
                errorMessage = "Couldn't complete service. Try again."
            }
        }
    }

    /// Removes someone from the queue (no-show, left early, etc.)
    func removeFromQueue(entry: QueueEntry) {
        Task {
            do {
                try await firebase.removeFromQueue(shopId: shopId, entry: entry)
                // Re-fetch so the removed entry appears crossed out in the sign-in sheet
                await fetchTodaysArchived()
            } catch {
                errorMessage = "Couldn't remove from queue. Try again."
            }
        }
    }

    /// Barber claims a next-available walk-in — moves them out of the pool into this barber's queue.
    /// Should only be called after showing the "are you ready right now?" confirmation.
    func claimPoolEntry(entry: QueueEntry) {
        var updated = entry
        updated.barberId = barberId   // Reassign from "__next__" to this barber
        updated.noPreference = false  // Remove from the next-available pool

        Task {
            do {
                try await firebase.updateQueueEntry(shopId: shopId, entry: updated)
            } catch {
                errorMessage = "Couldn't claim this customer. Try again."
            }
        }
    }

    /// Claim the NEXT person in line (oldest check-in time) and immediately seat them.
    /// This is the primary action in the sign-in sheet model — one tap, they're in the chair.
    func claimNext() {
        // Take the oldest waiting pool entry — strict FIFO, no skipping
        guard let next = poolEntries.first else { return }
        var updated = next
        updated.barberId        = barberId      // This barber owns the entry now
        updated.assignedBarberId = barberId
        updated.noPreference    = false         // Remove from the shared pool
        updated.status          = .inChair      // Seat them immediately
        updated.startTime       = Date()

        Task {
            do {
                try await firebase.updateQueueEntry(shopId: shopId, entry: updated)
                // Pin them to this barber's "current client" slot
                if let entryId = next.id {
                    try await firebase.updateCurrentClient(
                        shopId: shopId, barberId: barberId, clientId: entryId
                    )
                }
            } catch {
                errorMessage = "Couldn't claim next client. Try again."
            }
        }
    }

    // MARK: - Group Check-In Helper

    /// Build the array of individual QueueEntry objects for a group check-in.
    ///
    /// Call this from the kiosk check-in flow when partySize > 1. Each person
    /// gets their own entry sharing a groupId — they're fully independent in
    /// Firestore so any barber can claim each one separately.
    ///
    /// - Parameters:
    ///   - name: The primary customer's name (guests will be labeled "name Guest 2", etc.)
    ///   - phone: Primary customer's phone number (guests get empty string)
    ///   - count: Total people in the group (must be >= 1)
    ///   - barberId: "__next__" for walk-ins (next available pool), or a specific barber ID
    ///   - basePosition: Starting position number in the queue
    ///   - avgServiceTime: Used to estimate each person's wait
    /// - Returns: Array of `count` QueueEntry objects ready to pass to `addGroupToQueue`
    static func buildGroupEntries(
        name: String,
        phone: String,
        count: Int,
        shopId: String,
        barberId: String = "__next__",
        basePosition: Int = 1,
        avgServiceTime: Int = 30
    ) -> [QueueEntry] {
        guard count >= 1 else { return [] }

        // Shared group ID links all entries visually without coupling their state
        let groupId = UUID().uuidString
        let now = Date()

        return (1...count).map { index in
            // Primary person keeps their real name; guests get a simple label
            let entryName = index == 1 ? name : "\(name) (guest \(index))"
            // Only the primary person has a phone number to notify
            let entryPhone = index == 1 ? phone : ""

            return QueueEntry(
                customerName: entryName,
                customerPhone: entryPhone,
                barberId: barberId,
                assignedBarberId: nil,
                serviceId: nil,
                status: .waiting,
                position: basePosition + index - 1,
                checkInTime: now,
                notifiedTime: nil,
                startTime: nil,
                endTime: nil,
                estimatedWaitMinutes: (basePosition + index - 2) * avgServiceTime,
                partySize: nil,       // Each entry is ONE person — no expansion needed
                groupId: groupId,     // Shared across the whole group for visual context
                partyIndex: index,    // 1-based: who in the group this person is
                groupSize: count,     // Total group size (same for all members)
                noPreference: true,   // Joins the shared pool — any barber can claim
                isAppointment: false,
                notifiedAlmostUp: false,
                notifiedYoureUp: false
            )
        }
    }

    /// Manually adds a walk-in directly to the shop-wide queue from the barber's phone.
    /// Goes into the shared pool (noPreference = true) so any barber can claim them,
    /// OR seats them immediately in this barber's chair if status == .inChair.
    ///
    /// When partySize > 1, each person gets their OWN independent Firestore entry
    /// so any barber can claim each one separately. They share a groupId for display.
    ///
    /// status: .waiting = joins the waiting list, .inChair = seat them right now.
    func addManualEntry(name: String, phone: String, partySize: Int? = nil, status: QueueStatus = .waiting) {
        let currentWaiting = waitingClients.count
        let avg = barber?.avgServiceTime ?? 30
        let isInChair = status == .inChair
        let assignedBarber = isInChair ? barberId : "__next__"
        let count = max(1, partySize ?? 1)

        if count > 1 {
            // Group check-in: create one independent entry per person.
            // Each can be claimed and served by any barber separately.
            var entries = BarberQueueViewModel.buildGroupEntries(
                name: name,
                phone: phone,
                count: count,
                shopId: shopId,
                barberId: assignedBarber,
                basePosition: currentWaiting + 1,
                avgServiceTime: avg
            )

            // If seating now, override status and assign to this barber
            if isInChair {
                entries = entries.map { entry in
                    var e = entry
                    e.status = .inChair
                    e.startTime = Date()
                    e.assignedBarberId = barberId
                    e.noPreference = false
                    return e
                }
            }

            Task {
                do {
                    let created = try await firebase.addGroupToQueue(shopId: shopId, entries: entries)
                    // If seating now, pin the first person as current client
                    if isInChair, let firstId = created.first?.id {
                        try await firebase.updateCurrentClient(
                            shopId: shopId, barberId: barberId, clientId: firstId
                        )
                    }
                } catch {
                    errorMessage = "Couldn't add group to queue. Try again."
                }
            }
        } else {
            // Solo check-in: single entry, existing behavior
            let entry = QueueEntry(
                customerName: name,
                customerPhone: phone,
                barberId: assignedBarber,
                assignedBarberId: isInChair ? barberId : nil,
                serviceId: nil,
                status: status,
                position: currentWaiting + 1,
                checkInTime: Date(),
                notifiedTime: nil,
                startTime: isInChair ? Date() : nil,
                endTime: nil,
                estimatedWaitMinutes: isInChair ? 0 : currentWaiting * avg,
                partySize: nil,
                groupId: nil,
                partyIndex: nil,
                groupSize: nil,
                noPreference: !isInChair,
                isAppointment: false,
                notifiedAlmostUp: false,
                notifiedYoureUp: false
            )

            Task {
                do {
                    let created = try await firebase.addToQueue(shopId: shopId, entry: entry)
                    if isInChair, let entryId = created.id {
                        try await firebase.updateCurrentClient(
                            shopId: shopId, barberId: barberId, clientId: entryId
                        )
                    }
                } catch {
                    errorMessage = "Couldn't add to queue. Try again."
                }
            }
        }
    }

    // MARK: - Computed Properties (own queue)

    /// Entries assigned to this barber only, sorted by check-in time.
    var queue: [QueueEntry] {
        allShopQueue
            .filter { $0.barberId == barberId || $0.assignedBarberId == barberId }
            .sorted { $0.checkInTime < $1.checkInTime }
    }

    /// The client currently in this barber's chair, if any.
    var currentClient: QueueEntry? {
        queue.first { $0.status == .inChair }
    }

    /// Clients waiting in this barber's queue (not yet in chair), in order.
    var waitingClients: [QueueEntry] {
        queue.filter { $0.status == .waiting || $0.status == .notified }
    }

    /// How many people are waiting in this barber's queue.
    var waitingCount: Int {
        waitingClients.count
    }

    /// Estimated total wait for the last person in line, in minutes.
    /// Uses nil-coalescing since estimatedWaitMinutes is optional for appointment check-ins.
    var totalEstimatedWait: Int {
        waitingClients.reduce(0) { $0 + ($1.estimatedWaitMinutes ?? 0) }
    }

    // MARK: - Computed Properties (shop-wide)

    /// Controls the sort direction of the notebook sheet.
    /// Ascending = oldest first (default — shows who's been waiting longest at the top).
    /// Descending = newest first (most recent sign-in at the top).
    @Published var sortAscending: Bool = true

    /// Full day sign-in sheet — today's walk-ins only (no appointments), mirroring the
    /// owner dashboard's Walk-Ins tab. Active entries are filtered to today so old lingering
    /// entries from previous days don't bleed through.
    var shopWideSignInSheet: [QueueEntry] {
        let startOfToday = Calendar.current.startOfDay(for: Date())

        // Active walk-ins from today only — excludes appointments and anything checked in before today
        let activeToday = allShopQueue.filter { entry in
            entry.isAppointment != true &&
            entry.checkInTime >= startOfToday
        }

        // Archived walk-ins from today (completed, walked out, removed)
        let archivedToday = todayArchived.filter { $0.isAppointment != true }

        // Deduplicate by ID in case an entry exists in both collections temporarily
        var seen = Set<String>()
        let merged = (activeToday + archivedToday).filter { entry in
            guard let id = entry.id else { return false }
            return seen.insert(id).inserted
        }

        return merged.sorted {
            sortAscending
                ? $0.checkInTime < $1.checkInTime
                : $0.checkInTime > $1.checkInTime
        }
    }

    /// Flips the sort direction of the notebook sheet.
    func toggleSortOrder() {
        sortAscending.toggle()
    }

    /// Count of barbers currently GoLive and available — shown on the barber view
    var liveBarberCount: Int {
        allBarbers.filter { $0.isVisibleOnKiosk }.count
    }

    /// Whether this barber currently has someone in the chair (blocks claiming next)
    var hasCurrentClient: Bool {
        currentClient != nil
    }

    /// Appointment clients who have checked in and are waiting for THIS barber specifically.
    /// These are NOT walk-ins — they booked ahead and the barber needs to seat them.
    var myWaitingAppointments: [QueueEntry] {
        allShopQueue
            .filter {
                $0.isAppointment == true &&
                ($0.barberId == barberId || $0.assignedBarberId == barberId) &&
                ($0.status == .waiting || $0.status == .notified)
            }
            .sorted { $0.checkInTime < $1.checkInTime }
    }

    /// All of today's appointments assigned to THIS barber — across every status
    /// (waiting, notified, in_chair, completed, walked_out, removed).
    /// Powers the dedicated "Appointments" tab on the barber view so appointment
    /// check-ins don't blend into the walk-in sheet anymore.
    var myTodayAppointments: [QueueEntry] {
        let startOfToday = Calendar.current.startOfDay(for: Date())

        // Active appointments from today only — assigned to me, regardless of status
        let activeToday = allShopQueue.filter { entry in
            entry.isAppointment == true &&
            (entry.barberId == barberId || entry.assignedBarberId == barberId) &&
            entry.checkInTime >= startOfToday
        }

        // Archived appointments from today (completed, walked out, removed) assigned to me
        let archivedToday = todayArchived.filter { entry in
            entry.isAppointment == true &&
            (entry.barberId == barberId || entry.assignedBarberId == barberId)
        }

        // Deduplicate by ID in case an entry exists in both collections temporarily
        var seen = Set<String>()
        let merged = (activeToday + archivedToday).filter { entry in
            guard let id = entry.id else { return false }
            return seen.insert(id).inserted
        }

        return merged.sorted {
            sortAscending
                ? $0.checkInTime < $1.checkInTime
                : $0.checkInTime > $1.checkInTime
        }
    }

    /// Seat an appointment client — they're already assigned to this barber, just mark them in chair.
    func seatAppointment(entry: QueueEntry) {
        var updated = entry
        updated.status    = .inChair
        updated.startTime = Date()
        Task {
            do {
                try await firebase.updateQueueEntry(shopId: shopId, entry: updated)
                if let entryId = entry.id {
                    try await firebase.updateCurrentClient(
                        shopId: shopId, barberId: barberId, clientId: entryId
                    )
                }
            } catch {
                errorMessage = "Couldn't seat appointment. Try again."
            }
        }
    }

    /// Walk-ins who checked in with "Next Available" — any barber can claim them.
    var poolEntries: [QueueEntry] {
        allShopQueue
            .filter {
                ($0.barberId == "__next__" || $0.noPreference == true) &&
                ($0.status == .waiting || $0.status == .notified)
            }
            .sorted { $0.checkInTime < $1.checkInTime }
    }

    /// All active entries for a given barber — used to render other barbers' read-only cards.
    func queueFor(barberId: String) -> [QueueEntry] {
        allShopQueue
            .filter { $0.barberId == barberId || $0.assignedBarberId == barberId }
            .filter { $0.status == .waiting || $0.status == .notified || $0.status == .inChair }
            .sorted { $0.checkInTime < $1.checkInTime }
    }

    /// Current in-chair client for any barber — used in the all-barbers section.
    func currentClientFor(barberId: String) -> QueueEntry? {
        queueFor(barberId: barberId).first { $0.status == .inChair }
    }

    /// Waiting clients for any barber — used in the all-barbers section.
    func waitingFor(barberId: String) -> [QueueEntry] {
        queueFor(barberId: barberId).filter { $0.status == .waiting || $0.status == .notified }
    }

    // MARK: - Auto-Close Timer

    /// Loads the shop's autoCloseTime setting and:
    ///   1. If current time is already past close time, goes offline immediately
    ///   2. Schedules a Timer to fire at close time if it hasn't passed yet
    ///
    /// This runs on each barber's device — they only take THEMSELVES offline.
    /// The owner's "Close All" is handled by closeAllBarbers() in FirebaseService.
    private func scheduleAutoClose() async {
        do {
            let shop = try await firebase.fetchShop(shopId: shopId)
            guard let timeStr = shop.settings.autoCloseTime else { return }  // Not configured

            // Parse "HH:MM" into today's date at that time
            let parts = timeStr.split(separator: ":").compactMap { Int($0) }
            guard parts.count == 2 else { return }

            var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
            comps.hour = parts[0]; comps.minute = parts[1]; comps.second = 0
            guard let closeDate = Calendar.current.date(from: comps) else { return }

            let now = Date()

            if closeDate <= now {
                // Already past close time today — take ourselves offline immediately if still live
                if isGoLive {
                    await goOfflineForAutoClose()
                }
            } else {
                // Schedule the timer to fire at the exact close time
                let interval = closeDate.timeIntervalSince(now)
                autoCloseTimer?.invalidate()
                autoCloseTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        await self?.goOfflineForAutoClose()
                    }
                }
            }
        } catch {
            // Non-fatal — if we can't load shop settings the barber just stays as-is
        }
    }

    /// Takes this barber offline as part of the auto-close.
    private func goOfflineForAutoClose() async {
        guard isGoLive else { return }  // Already offline, nothing to do
        do {
            try await firebase.setGoLive(shopId: shopId, barberId: barberId, goLive: false)
            // isGoLive will update automatically via the barbers listener
        } catch {
            // Silent failure — worst case the barber stays online, not a critical error
        }
    }

    // MARK: - Helpers

    /// Look up a service name by ID — used to display "Fade" instead of a raw ID in the UI.
    /// Returns "Appointment" when serviceId is nil (appointment check-ins don't pick a service).
    func serviceName(for serviceId: String?) -> String {
        guard let serviceId else { return "Appointment" }
        return services.first { $0.id == serviceId }?.name ?? "Service"
    }

    /// Clear any displayed error after the user sees it.
    func clearError() {
        errorMessage = nil
    }
}
