//
//  KioskViewModel.swift
//  UpNext
//
//  Manages the kiosk check-in flow — now a clean 3-step sign-in sheet experience.
//  Every walk-in goes into the shared shop pool (no barber selection).
//  Barbers claim clients from that pool when they're ready.
//
//  Flow: Welcome → Name & Phone & Party Size → Confirmation
//

import Foundation
import Combine
import FirebaseFirestore

@MainActor
class KioskViewModel: ObservableObject {

    // MARK: - Check-In Flow State

    enum KioskStep {
        case welcome        // Attract screen with shop branding + "Check In" button
        case namePhone      // Customer enters name, phone, and party size
        case confirmation   // "You're on the list!" — shows queue position + available barbers
    }

    @Published var currentStep: KioskStep = .welcome

    // MARK: - Customer Input

    @Published var customerName:  String = ""
    @Published var customerPhone: String = ""
    @Published var partySize:     Int    = 1    // How many people in the group need cuts

    // MARK: - Live Data from Firestore

    /// Barbers currently GoLive and available — shown on confirmation screen
    @Published var availableBarbers: [Barber] = []

    /// Full active queue — needed to calculate the customer's wait time estimate
    @Published var queueEntries: [QueueEntry] = []

    // MARK: - UI State

    @Published var isLoading:     Bool    = false
    @Published var errorMessage:  String? = nil

    /// The confirmed entry — populated on submission, drives the confirmation screen
    @Published var confirmedEntry: QueueEntry?

    // MARK: - Private

    private let firebase     = FirebaseService.shared
    private var cancellables = Set<AnyCancellable>()
    private let shopId:       String
    private var resetTimer:   Timer?

    // MARK: - Init

    init(shopId: String) {
        self.shopId = shopId
    }

    // MARK: - Lifecycle

    func onAppear() {
        startListeningToBarbers()
        startListeningToQueue()
    }

    func onDisappear() {
        firebase.removeAllListeners()
        cancellables.removeAll()
        resetTimer?.invalidate()
    }

    // MARK: - Real-Time Listeners

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
                    // Only show barbers who are GoLive and available — these are who's taking walk-ins
                    self?.availableBarbers = barbers.filter { $0.isVisibleOnKiosk }
                }
            )
            .store(in: &cancellables)
    }

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
                    self?.queueEntries = entries
                }
            )
            .store(in: &cancellables)
    }

    // MARK: - Navigation

    func goToNext() {
        switch currentStep {
        case .welcome:      currentStep = .namePhone
        case .namePhone:    submitCheckIn()
        case .confirmation: resetKiosk()
        }
    }

    func goBack() {
        switch currentStep {
        case .welcome:      break   // Can't go back from welcome
        case .namePhone:    currentStep = .welcome
        case .confirmation: resetKiosk()
        }
    }

    // MARK: - Validation

    var isNameValid: Bool {
        !customerName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - Wait Time Estimate

    /// Estimated wait for a new walk-in based on the shared pool queue + live walk-in barbers.
    ///
    /// Key rules:
    ///  1. Only walk-in entries count toward the wait — appointment check-ins are
    ///     assigned to a specific barber and don't compete for walk-in chairs.
    ///  2. Only barbers who are GoLive (availableBarbers) are factored in — appointment-only
    ///     barbers with their own clients should not affect the walk-in wait time.
    ///  3. The formula divides by the number of live barbers so having more people
    ///     available shortens the wait proportionally.
    ///     Example: 2 people waiting, 2 live barbers → ceil(2/2) × 45min = 45min ✓
    var estimatedWaitMinutes: Int {
        guard !availableBarbers.isEmpty else { return 0 }

        let liveBarbers = availableBarbers.count

        // IDs of barbers who are currently GoLive — used to check chair occupancy
        let liveBarberIds = Set(availableBarbers.compactMap { $0.id })

        // Only non-appointment entries waiting in the shared pool count toward walk-in wait
        let waitingWalkIns = queueEntries.filter {
            ($0.status == .waiting || $0.status == .notified) &&
            ($0.isAppointment != true)
        }.count

        // Count how many live barbers are currently occupied (with anyone — appointment or
        // walk-in — if they're busy they can't take the next walk-in)
        let occupiedChairs = queueEntries.filter { entry in
            entry.status == .inChair &&
            liveBarberIds.contains(entry.assignedBarberId ?? entry.barberId)
        }.count

        // Average service time across the live barbers (fallback to 30 if data is missing)
        let totalTime = availableBarbers.map { $0.avgServiceTime }.reduce(0, +)
        let avgTime   = totalTime > 0 ? totalTime / liveBarbers : 30

        // If any live barber has an open chair, the next walk-in can be seated right away
        let openChairs = max(0, liveBarbers - occupiedChairs)
        if openChairs > 0 { return 0 }

        // All chairs are full — figure out how many rounds of cuts before a new walk-in
        // gets seated. Using ceil() so we never under-estimate (round up, not down).
        let rounds = Int(ceil(Double(waitingWalkIns) / Double(liveBarbers)))
        return max(1, rounds) * avgTime
    }

    /// Sequential position this new customer will hold (end of current line)
    var nextPosition: Int {
        queueEntries.count + 1
    }

    // MARK: - Submit Check-In

    /// Creates queue entries in Firestore and moves to confirmation.
    /// All walk-ins go into the shared pool — barberId = "__next__", noPreference = true.
    ///
    /// When partySize > 1, each person gets their OWN independent Firestore document
    /// so any barber can claim each one separately. They share a groupId for visual context.
    /// When partySize == 1, a single entry is created (no group overhead).
    func submitCheckIn() {
        guard isNameValid else { return }
        isLoading = true

        let name  = customerName.trimmingCharacters(in: .whitespaces)
        let phone = customerPhone.trimmingCharacters(in: .whitespaces)
        let count = max(1, partySize)

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let firstCreated: QueueEntry

                if count > 1 {
                    // ── Group check-in: one independent entry per person ──────────────
                    // buildGroupEntries creates entries with shared groupId so barbers see
                    // they came together, but each entry can be claimed individually.
                    let entries = BarberQueueViewModel.buildGroupEntries(
                        name:            name,
                        phone:           phone,
                        count:           count,
                        shopId:          self.shopId,
                        barberId:        "__next__",
                        basePosition:    self.nextPosition,
                        avgServiceTime:  self.estimatedWaitMinutes > 0 ? self.estimatedWaitMinutes : 30
                    )
                    let created = try await self.firebase.addGroupToQueue(shopId: self.shopId, entries: entries)
                    // Show confirmation for the first person — they represent the group
                    // Safe fallback — entries is guaranteed non-empty here since count >= 2,
                    // but we avoid the force unwrap to prevent any edge-case crash.
                    guard let lead = created.first ?? entries.first else { return }
                    firstCreated = lead
                } else {
                    // ── Solo check-in: single entry ──────────────────────────────────
                    let entry = QueueEntry(
                        customerName:          name,
                        customerPhone:         phone,
                        barberId:              "__next__",
                        assignedBarberId:      nil,
                        serviceId:             nil,
                        status:                .waiting,
                        position:              self.nextPosition,
                        checkInTime:           Date(),
                        notifiedTime:          nil,
                        startTime:             nil,
                        endTime:               nil,
                        estimatedWaitMinutes:  self.estimatedWaitMinutes,
                        partySize:             nil,
                        noPreference:          true,
                        isAppointment:         false,
                        isRemoteCheckIn:       false,   // Kiosk = physically in the shop
                        notifiedAlmostUp:      false,
                        notifiedYoureUp:       false
                    )
                    firstCreated = try await self.firebase.addToQueue(shopId: self.shopId, entry: entry)
                }

                self.confirmedEntry  = firstCreated
                self.currentStep     = .confirmation
                self.isLoading       = false
                self.startResetTimer()

                // Upsert customer record (for return visit recognition later)
                if !phone.isEmpty {
                    let customer = Customer(
                        name:              name,
                        phoneNumber:       self.formatPhoneNumber(phone),
                        visitCount:        1,
                        lastVisitDate:     Date(),
                        preferredBarberId: nil
                    )
                    try? await self.firebase.upsertCustomer(customer)
                }
            } catch {
                self.isLoading    = false
                self.errorMessage = "Couldn't add you to the list. Please try again."
            }
        }
    }

    // MARK: - Reset

    func resetKiosk() {
        resetTimer?.invalidate()
        customerName  = ""
        customerPhone = ""
        partySize     = 1
        confirmedEntry = nil
        errorMessage  = nil
        currentStep   = .welcome
    }

    /// Auto-resets to the welcome screen 15 seconds after confirmation
    /// so the kiosk is fresh for the next customer.
    private func startResetTimer() {
        resetTimer?.invalidate()
        resetTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: false) { _ in
            Task { @MainActor [weak self] in self?.resetKiosk() }
        }
    }

    // MARK: - Helpers

    private func formatPhoneNumber(_ phone: String) -> String {
        let digits = phone.filter { $0.isNumber }
        if digits.count == 10          { return "+1\(digits)" }
        if digits.count == 11 && digits.hasPrefix("1") { return "+\(digits)" }
        return "+\(digits)"
    }
}
