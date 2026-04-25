//
//  OwnerDashboardViewModel.swift
//  UpNext
//
//  The brain behind the shop owner's dashboard on the iPhone.
//  Listens to ALL barbers and the ENTIRE queue in real time — unlike the
//  BarberQueueViewModel which only shows one barber's entries.
//
//  The owner can see everyone's status, reassign customers, and take
//  quick actions from this single screen.
//

import Foundation
import Combine
import FirebaseFirestore

@MainActor
class OwnerDashboardViewModel: ObservableObject {

    // MARK: - Published Properties

    /// The shop info (name, settings, etc.)
    @Published var shop: Shop?

    /// All barbers at the shop, sorted by display order
    @Published var barbers: [Barber] = []

    /// All active queue entries across every barber
    @Published var allQueueEntries: [QueueEntry] = []

    /// Today's completed entries — fetched from queueHistory, refreshed on appear + pull-to-refresh.
    /// Combined with allQueueEntries this gives the owner the full sign-in sheet for today.
    @Published var todayCompleted: [QueueEntry] = []

    /// All services for looking up names
    @Published var services: [Service] = []

    /// Loading and error states
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    // MARK: - Private Properties

    private let firebase = FirebaseService.shared
    private var cancellables = Set<AnyCancellable>()
    // Internal (not private) so OwnerDashboardView can pass it to ShopSettingsView
    let shopId: String

    // Auto-complete: tracks IDs currently being processed so we don't double-fire
    // if both the queue listener and the fallback timer trigger simultaneously.
    private var autoCompletingIds = Set<String>()
    // 60-second fallback timer — catches gaps between Firestore updates
    private var autoCompleteTimer: Timer?

    // MARK: - Init

    init(shopId: String) {
        self.shopId = shopId
    }

    // MARK: - Lifecycle

    /// Start all listeners when the dashboard appears.
    func onAppear() {
        isLoading = true
        startListeningToBarbers()
        startListeningToQueue()
        Task {
            await loadShop()
            await loadServices()
            await fetchTodaysCompleted()
        }
        // Fallback timer — fires every 60s in case no queue updates arrive during
        // a 30-minute window (quiet shop, no other clients checking in)
        autoCompleteTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.autoCompleteExpiredAppointments()
            }
        }
    }

    /// Clean up when the owner leaves the dashboard.
    func onDisappear() {
        firebase.removeAllListeners()
        cancellables.removeAll()
        autoCompleteTimer?.invalidate()
        autoCompleteTimer = nil
    }

    // MARK: - Real-Time Listeners

    /// Listen to all barbers — the owner sees everyone.
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
                    self?.barbers = barbers
                    self?.isLoading = false
                }
            )
            .store(in: &cancellables)
    }

    /// Listen to the full queue — not filtered by barber.
    private func startListeningToQueue() {
        firebase.listenToQueue(shopId: shopId)
            .receive(on: DispatchQueue.main)
            .sink(
                receiveCompletion: { [weak self] completion in
                    if case .failure(let error) = completion {
                        self?.errorMessage = error.localizedDescription
                    }
                },
                receiveValue: { [weak self] entries in
                    self?.allQueueEntries = entries
                    self?.autoCompleteExpiredAppointments()
                }
            )
            .store(in: &cancellables)
    }

    // MARK: - One-Time Loads

    private func loadShop() async {
        do {
            shop = try await firebase.fetchShop(shopId: shopId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadServices() async {
        do {
            services = try await firebase.fetchServices(shopId: shopId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Fetch today's archived entries (completed + walked out + removed) from queueHistory.
    /// Called on appear and refresh — gives the full day picture including clients who left.
    func fetchTodaysCompleted() async {
        let startOfToday = Calendar.current.startOfDay(for: Date())
        do {
            todayCompleted = try await firebase.fetchArchivedEntries(shopId: shopId, since: startOfToday)
        } catch {
            // Non-fatal — active queue still shows, archived section just stays empty
        }
    }

    // MARK: - Auto-Manage Appointments

    /// Appointments are fully self-managing — no owner input needed.
    ///
    /// Step 1 — Auto-seat: any appointment that just checked in (.waiting)
    ///           is immediately moved to .inChair with their selected barber.
    ///
    /// Step 2 — Auto-complete: 30 minutes after startTime, archive as done.
    ///
    /// Called on every queue snapshot update AND by the 60-second fallback timer.
    private func autoCompleteExpiredAppointments() {
        // ── Appointments are self-managing: they stay "With [barber]" and ─────
        // ── auto-complete 1 hour after check-in. No auto-seat to inChair. ─────
        //
        // Old behavior (removed):
        //   Step 1 — appointments were immediately moved to .inChair on check-in.
        //   Step 2 — auto-completed 30 min after startTime.
        //
        // New behavior:
        //   Appointments stay in .waiting so the barber sees them as "With [barber]"
        //   in the queue view — not as an active "In Chair" cut.
        //   Auto-complete 1 hour after checkInTime with no manual action needed.
        //   They are excluded from the TV queue and daily analytics totals.

        let threshold: TimeInterval = 60 * 60   // 1 hour from check-in
        let now = Date()

        // Auto-complete appointments checked in more than 1 hour ago.
        // We check both .waiting and .inChair so previously-seated appointments
        // (from the old behavior) still get cleaned up correctly.
        let expiredAppts = allQueueEntries.filter {
            $0.isAppointment == true &&
            ($0.status == .waiting || $0.status == .inChair) &&
            !autoCompletingIds.contains($0.id ?? "") &&
            now.timeIntervalSince($0.checkInTime) >= threshold   // use checkInTime, not startTime
        }

        for entry in expiredAppts {
            guard let id = entry.id else { continue }
            autoCompletingIds.insert(id)
            Task {
                do {
                    try await firebase.completeService(shopId: shopId, entry: entry)
                    let barberId = entry.assignedBarberId ?? entry.barberId
                    if barberId != "__next__" {
                        try await firebase.updateCurrentClient(
                            shopId: shopId, barberId: barberId, clientId: nil
                        )
                    }
                    await fetchTodaysCompleted()
                } catch {
                    // Non-fatal — already archived by another client
                }
                autoCompletingIds.remove(id)
            }
        }
    }

    // MARK: - Computed Properties

    /// Entries for a specific barber — checks BOTH barberId and assignedBarberId
    /// so entries show up correctly regardless of whether they were reassigned.
    func queueFor(barberId: String) -> [QueueEntry] {
        allQueueEntries
            .filter { $0.barberId == barberId || $0.assignedBarberId == barberId }
            .sorted { $0.checkInTime < $1.checkInTime }
    }

    /// The client currently in a specific barber's chair.
    func currentClientFor(barberId: String) -> QueueEntry? {
        queueFor(barberId: barberId).first { $0.status == .inChair }
    }

    /// How many people are waiting for a specific barber.
    func waitingCountFor(barberId: String) -> Int {
        queueFor(barberId: barberId).filter { $0.status == .waiting || $0.status == .notified }.count
    }

    /// Total people in the entire shop queue right now.
    var totalWaiting: Int {
        allQueueEntries.filter { $0.status == .waiting || $0.status == .notified }.count
    }

    /// Total people being served right now (in chair across all barbers).
    var totalInChair: Int {
        allQueueEntries.filter { $0.status == .inChair }.count
    }

    /// Entries that don't match any known barber on EITHER barberId or assignedBarberId.
    /// These are true ghost entries — stale data that inflates the stats but can't be displayed.
    var orphanedEntries: [QueueEntry] {
        let knownIds = Set(barbers.compactMap { $0.id } + ["__next__"])
        return allQueueEntries.filter { entry in
            let primaryMatch  = knownIds.contains(entry.barberId)
            let assignedMatch = entry.assignedBarberId.map { knownIds.contains($0) } ?? false
            return !primaryMatch && !assignedMatch
        }
    }

    /// Look up a service name by ID.
    /// Returns "Appointment" when serviceId is nil (appointment check-ins don't pick a service).
    func serviceName(for serviceId: String?) -> String {
        guard let serviceId else { return "Appointment" }
        return services.first { $0.id == serviceId }?.name ?? "Service"
    }

    /// Look up a barber name by ID.
    func barberName(for barberId: String) -> String {
        barbers.first { $0.id == barberId }?.name ?? "Barber"
    }

    // MARK: - Owner Actions

    /// Start service for a customer (owner can do this for any barber).
    func startService(entry: QueueEntry) {
        Task {
            do {
                try await firebase.startService(shopId: shopId, entry: entry)
                let targetBarberId = entry.assignedBarberId ?? entry.barberId
                if let entryId = entry.id {
                    try await firebase.updateCurrentClient(
                        shopId: shopId, barberId: targetBarberId, clientId: entryId
                    )
                }
            } catch {
                errorMessage = "Couldn't start service. Try again."
            }
        }
    }

    /// Complete service for a customer.
    func completeService(entry: QueueEntry) {
        Task {
            do {
                try await firebase.completeService(shopId: shopId, entry: entry)
                let targetBarberId = entry.assignedBarberId ?? entry.barberId
                try await firebase.updateCurrentClient(
                    shopId: shopId, barberId: targetBarberId, clientId: nil
                )
                // Re-fetch so the completed entry appears crossed out in the sheet immediately
                await fetchTodaysCompleted()
            } catch {
                errorMessage = "Couldn't complete service. Try again."
            }
        }
    }

    /// Remove a customer from the queue.
    func removeFromQueue(entry: QueueEntry) {
        Task {
            do {
                try await firebase.removeFromQueue(shopId: shopId, entry: entry)
                // Re-fetch so the removed entry appears in the sheet immediately
                await fetchTodaysCompleted()
            } catch {
                errorMessage = "Couldn't remove from queue. Try again."
            }
        }
    }

    /// Owner manually adds a client to a specific barber's queue.
    /// status: .waiting = "On the Way", .inChair = "In Chair" (seated now).
    ///
    /// When partySize > 1, creates ONE independent Firestore entry per person
    /// so each can be claimed and served separately. They share a groupId for display.
    func addManualEntry(name: String, phone: String, serviceId: String, barberId: String, status: QueueStatus = .waiting, partySize: Int = 1) {
        let waiting = queueFor(barberId: barberId)
            .filter { $0.status == .waiting || $0.status == .notified }.count
        let avg = barbers.first { $0.id == barberId }?.avgServiceTime ?? 30
        let isInChair = status == .inChair
        let count = max(1, partySize)

        if count > 1 {
            // Group: create N independent entries sharing a groupId
            var entries = BarberQueueViewModel.buildGroupEntries(
                name: name,
                phone: phone,
                count: count,
                shopId: shopId,
                barberId: barberId,
                basePosition: waiting + 1,
                avgServiceTime: avg
            )
            // If seating now, assign to this specific barber and mark in chair
            if isInChair {
                entries = entries.map { entry in
                    var e = entry
                    e.status           = .inChair
                    e.startTime        = Date()
                    e.assignedBarberId = barberId
                    e.noPreference     = false
                    e.serviceId        = serviceId
                    return e
                }
            } else {
                // Waiting — assign to this barber but not in chair yet
                entries = entries.map { entry in
                    var e = entry
                    e.barberId    = barberId
                    e.noPreference = false
                    e.serviceId   = serviceId
                    return e
                }
            }
            Task {
                do {
                    let created = try await firebase.addGroupToQueue(shopId: shopId, entries: entries)
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
            // Solo: single entry, existing behavior
            let entry = QueueEntry(
                customerName: name,
                customerPhone: phone,
                barberId: barberId,
                assignedBarberId: nil,
                serviceId: serviceId,
                status: status,
                position: waiting + 1,
                checkInTime: Date(),
                notifiedTime: nil,
                startTime: isInChair ? Date() : nil,
                endTime: nil,
                estimatedWaitMinutes: isInChair ? 0 : waiting * avg,
                noPreference: false,
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


    /// Owner manually adds a walk-in to the "Next Available" pool — no barber preference.
    /// When partySize > 1, each person gets their own independent entry so any barber
    /// can claim each one separately. Shows up in the Next Available Pool for any barber.
    func addWalkInToNextAvailable(name: String, phone: String, serviceId: String, partySize: Int = 1) {
        let count = max(1, partySize)

        if count > 1 {
            // Group: N independent entries in the pool, each claimable separately
            let entries = BarberQueueViewModel.buildGroupEntries(
                name: name,
                phone: phone,
                count: count,
                shopId: shopId,
                barberId: "__next__",
                basePosition: totalWaiting + 1,
                avgServiceTime: 30
            ).map { entry -> QueueEntry in
                // Carry the serviceId through if the owner selected one
                var e = entry
                e.serviceId = serviceId.isEmpty ? nil : serviceId
                return e
            }
            Task {
                do {
                    _ = try await firebase.addGroupToQueue(shopId: shopId, entries: entries)
                } catch {
                    errorMessage = "Couldn't add group walk-in. Try again."
                }
            }
        } else {
            // Solo: single entry, existing behavior
            let entry = QueueEntry(
                customerName: name,
                customerPhone: phone,
                barberId: "__next__",       // Magic ID — routes to the next available pool
                assignedBarberId: nil,
                serviceId: serviceId.isEmpty ? nil : serviceId,
                status: .waiting,
                position: totalWaiting + 1,
                checkInTime: Date(),
                notifiedTime: nil,
                startTime: nil,
                endTime: nil,
                estimatedWaitMinutes: 0,
                noPreference: true,
                notifiedAlmostUp: false,
                notifiedYoureUp: false
            )
            Task {
                do {
                    _ = try await firebase.addToQueue(shopId: shopId, entry: entry)
                } catch {
                    errorMessage = "Couldn't add walk-in. Try again."
                }
            }
        }
    }

    /// Owner reassigns a waiting customer to a different barber's queue (stays waiting).
    func moveEntry(_ entry: QueueEntry, toBarberId: String) {
        var updated = entry
        updated.barberId = toBarberId
        updated.assignedBarberId = toBarberId
        updated.noPreference = false    // Remove from the Next Available pool filter
        Task {
            do {
                try await firebase.updateQueueEntry(shopId: shopId, entry: updated)
            } catch {
                errorMessage = "Couldn't move customer. Try again."
            }
        }
    }

    /// Owner sends a Next Available pool entry directly to a specific barber and starts service.
    /// This is the correct path for pool entries — avoids writing to the "__next__" phantom barber doc.
    /// Sets the real barberId, clears noPreference, marks status as inChair, and updates the
    /// barber's currentClientId so their card reflects the change immediately.
    func assignAndStartPoolEntry(entry: QueueEntry, toBarberId: String) {
        var updated = entry
        updated.barberId = toBarberId
        updated.assignedBarberId = toBarberId
        updated.noPreference = false        // Remove from pool filter
        updated.status = .inChair
        updated.startTime = Date()
        Task {
            do {
                try await firebase.updateQueueEntry(shopId: shopId, entry: updated)
                // Pin the client to the real barber's card
                if let entryId = entry.id {
                    try await firebase.updateCurrentClient(
                        shopId: shopId, barberId: toBarberId, clientId: entryId
                    )
                }
            } catch {
                errorMessage = "Couldn't assign client. Try again."
            }
        }
    }

    /// Splits one person out of a multi-person walk-in group and seats them with a specific barber.
    /// Creates a brand-new in-chair entry for that individual, then decrements the group's
    /// partySize by 1. When the original reaches partySize == 1, the next assign uses
    /// assignAndStartPoolEntry() instead (the last person moves as a normal single entry).
    func splitAndAssign(entry: QueueEntry, toBarberId: String) {
        Task {
            do {
                // 1. Copy the original entry and override just what changes for this split person.
                //    Using a copy means we don't have to re-specify every required field.
                var split              = entry
                split.id               = nil          // clear ID so Firestore generates a new one
                split.barberId         = toBarberId
                split.assignedBarberId = toBarberId
                split.status           = .inChair
                split.startTime        = Date()
                split.partySize        = 1            // just this one person
                split.noPreference     = false
                split.isAppointment    = false
                split.notifiedAlmostUp = false
                split.notifiedYoureUp  = false
                split.position         = nil

                // 2. Write the new entry and get its generated ID back
                let savedSplit = try await firebase.addToQueue(shopId: shopId, entry: split)

                // 3. Shrink the original group by one
                var shrunk = entry
                shrunk.partySize = max(1, (entry.partySize ?? 1) - 1)
                try await firebase.updateQueueEntry(shopId: shopId, entry: shrunk)

                // 4. Pin the split-off client to the barber's card
                if let newId = savedSplit.id {
                    try await firebase.updateCurrentClient(
                        shopId: shopId, barberId: toBarberId, clientId: newId
                    )
                }
            } catch {
                errorMessage = "Couldn't split group. Try again."
            }
        }
    }

    /// Toggle a barber's Go Live status — owner can flip any barber from the dashboard.
    func toggleGoLive(barber: Barber) {
        guard let barberId = barber.id else { return }
        let newValue = !barber.goLive
        Task {
            do {
                try await firebase.setGoLive(shopId: shopId, barberId: barberId, goLive: newValue)
            } catch {
                errorMessage = "Couldn't update live status. Try again."
            }
        }
    }

    // MARK: - Sign-In Sheet Computed Properties

    /// The full today's sign-in sheet — active entries + today's completed, sorted by check-in time.
    /// This is what the owner sees on the dashboard: the whole sheet, with completed entries still visible.
    var todayFullSheet: [QueueEntry] {
        let active    = allQueueEntries
        let completed = todayCompleted
        let all       = active + completed
        return all.sorted { $0.checkInTime < $1.checkInTime }
    }

    /// The barber who most recently started serving a client (active or completed today).
    /// Shown at the top of the owner dashboard so you instantly know who just took the last walk-in.
    var lastClaimingBarber: String? {
        let mostRecentActive = allQueueEntries
            .filter { $0.status == .inChair }
            .sorted { ($0.startTime ?? .distantPast) > ($1.startTime ?? .distantPast) }
            .first

        let mostRecentCompleted = todayCompleted
            .sorted { ($0.endTime ?? .distantPast) > ($1.endTime ?? .distantPast) }
            .first

        // Pick whichever is more recent
        let winner: QueueEntry?
        if let a = mostRecentActive, let c = mostRecentCompleted {
            winner = (a.startTime ?? .distantPast) > (c.endTime ?? .distantPast) ? a : c
        } else {
            winner = mostRecentActive ?? mostRecentCompleted
        }

        guard let entry = winner else { return nil }
        let barberId = entry.assignedBarberId ?? entry.barberId
        return barbers.first { $0.id == barberId }?.name
    }

    /// How many barbers are currently GoLive and available.
    var liveBarberCount: Int {
        barbers.filter { $0.isVisibleOnKiosk }.count
    }

    // MARK: - Appointment Computed Properties

    /// All appointment check-ins for today — active and completed — sorted by check-in time.
    /// Used in the Appointments tab on the owner dashboard.
    var todayAppointments: [QueueEntry] {
        let active    = allQueueEntries.filter  { $0.isAppointment == true }
        let completed = todayCompleted.filter   { $0.isAppointment == true }
        return (active + completed).sorted { $0.checkInTime < $1.checkInTime }
    }

    /// Appointments that have checked in but haven't been seated yet — these need attention.
    var waitingAppointments: [QueueEntry] {
        allQueueEntries.filter {
            $0.isAppointment == true &&
            ($0.status == .waiting || $0.status == .notified)
        }
        .sorted { $0.checkInTime < $1.checkInTime }
    }

    /// Completed walk-ins for today only — appointments excluded.
    /// This is what drives the "Done Today" stat card.
    /// Appointments auto-complete after 1 hour and shouldn't inflate the walk-in count.
    var completedWalkInsToday: [QueueEntry] {
        todayCompleted.filter { $0.isAppointment != true && $0.status == .completed }
    }

    /// Walk-ins only (no appointments) for the today sheet — keeps the two views cleanly separated.
    var todayWalkInsOnly: [QueueEntry] {
        let active    = allQueueEntries.filter { $0.isAppointment != true }
        let completed = todayCompleted.filter  { $0.isAppointment != true }
        return (active + completed).sorted { $0.checkInTime < $1.checkInTime }
    }

    // MARK: - Pull-to-Refresh

    /// Pull-to-refresh — restarts all listeners and reloads one-time data.
    func refresh() async {
        firebase.removeAllListeners()
        cancellables.removeAll()
        startListeningToBarbers()
        startListeningToQueue()
        await loadShop()
        await loadServices()
        await fetchTodaysCompleted()
    }

    /// Clear any displayed error.
    func clearError() {
        errorMessage = nil
    }
}
