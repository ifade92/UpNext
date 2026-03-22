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
        }
    }

    /// Clean up when the owner leaves the dashboard.
    func onDisappear() {
        firebase.removeAllListeners()
        cancellables.removeAll()
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
            } catch {
                errorMessage = "Couldn't remove from queue. Try again."
            }
        }
    }

    /// Owner manually adds a client directly to a specific barber's queue.
    func addManualEntry(name: String, phone: String, serviceId: String, barberId: String) {
        let waiting = queueFor(barberId: barberId)
            .filter { $0.status == .waiting || $0.status == .notified }.count
        let avg = barbers.first { $0.id == barberId }?.avgServiceTime ?? 30

        let entry = QueueEntry(
            customerName: name,
            customerPhone: phone,
            barberId: barberId,
            assignedBarberId: nil,
            serviceId: serviceId,
            status: .waiting,
            position: waiting + 1,
            checkInTime: Date(),
            notifiedTime: nil,
            startTime: nil,
            endTime: nil,
            estimatedWaitMinutes: waiting * avg,
            noPreference: false,
            notifiedAlmostUp: false,
            notifiedYoureUp: false
        )
        Task {
            do {
                _ = try await firebase.addToQueue(shopId: shopId, entry: entry)
            } catch {
                errorMessage = "Couldn't add to queue. Try again."
            }
        }
    }


    /// Owner manually adds a walk-in to the "Next Available" pool — no barber preference.
    /// Shows up in the Next Available Pool card for any barber to claim.
    func addWalkInToNextAvailable(name: String, phone: String, serviceId: String) {
        let entry = QueueEntry(
            customerName: name,
            customerPhone: phone,
            barberId: "__next__",       // Magic ID — routes to the next available pool
            assignedBarberId: nil,
            serviceId: serviceId,
            status: .waiting,
            position: totalWaiting + 1,
            checkInTime: Date(),
            notifiedTime: nil,
            startTime: nil,
            endTime: nil,
            estimatedWaitMinutes: 0,
            noPreference: true,         // Tells the queue this client has no barber preference
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

    /// Owner reassigns a waiting customer to a different barber.
    func moveEntry(_ entry: QueueEntry, toBarberId: String) {
        var updated = entry
        updated.barberId = toBarberId
        updated.assignedBarberId = toBarberId
        Task {
            do {
                try await firebase.updateQueueEntry(shopId: shopId, entry: updated)
            } catch {
                errorMessage = "Couldn't move customer. Try again."
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

    /// Pull-to-refresh — restarts all listeners and reloads one-time data.
    func refresh() async {
        firebase.removeAllListeners()
        cancellables.removeAll()
        startListeningToBarbers()
        startListeningToQueue()
        await loadShop()
        await loadServices()
    }

    /// Clear any displayed error.
    func clearError() {
        errorMessage = nil
    }
}
