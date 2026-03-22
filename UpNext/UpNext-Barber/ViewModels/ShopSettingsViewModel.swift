//
//  ShopSettingsViewModel.swift
//  UpNext
//
//  Drives the Shop Settings screen — the owner's control panel for managing
//  barbers and services. All reads/writes go through FirebaseService.
//
//  Two sections:
//    1. Barbers — add, edit name/type, reorder, delete
//    2. Services — add, edit name/duration/price/active, delete
//

import Foundation
import Combine
import FirebaseAuth

@MainActor
class ShopSettingsViewModel: ObservableObject {

    // MARK: - Published State

    @Published var barbers: [Barber] = []
    @Published var services: [Service] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    // Flips to true after a password reset email is sent — used to show confirmation in the UI
    @Published var resetPasswordSent = false

    // Controls whether the "Add Barber" sheet is showing
    @Published var showAddBarber = false
    // Controls whether the "Add Service" sheet is showing
    @Published var showAddService = false

    // The barber currently being edited (nil = no edit sheet open)
    @Published var editingBarber: Barber? = nil
    // The service currently being edited (nil = no edit sheet open)
    @Published var editingService: Service? = nil

    // Auto-close time — "HH:MM" in 24hr format, nil = disabled
    // Every night at this time all barbers are taken offline automatically.
    @Published var autoCloseTime: Date? = nil
    @Published var autoCloseEnabled: Bool = false

    // MARK: - Private

    // Internal so views can read shopId to display the shop code banner
    let shopId: String
    private let firebase = FirebaseService.shared
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Init

    init(shopId: String) {
        self.shopId = shopId
    }

    // MARK: - Lifecycle

    func onAppear() {
        loadData()
        // Subscribe to real-time barber updates so the list stays live
        // while the owner is on this screen
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
                }
            )
            .store(in: &cancellables)

        // Load shop settings to get the current auto-close time
        Task { await loadShopSettings() }
    }

    func onDisappear() {
        cancellables.removeAll()
    }

    // MARK: - Load

    /// Pull barbers (real-time) and services (one-time) on screen appear.
    func loadData() {
        isLoading = true
        Task {
            do {
                // Services don't change in real time so a one-shot fetch is fine
                self.services = try await firebase.fetchAllServices(shopId: shopId)
            } catch {
                self.errorMessage = error.localizedDescription
            }
            self.isLoading = false
        }
    }

    // MARK: - Barber Actions

    /// Add a brand-new barber. Called when owner submits the "Add Barber" sheet.
    func addBarber(name: String, email: String, barberType: BarberType) {
        Task {
            do {
                let newBarber = Barber(
                    name: name,
                    photoUrl: nil,
                    email: email.isEmpty ? nil : email,
                    bookingUrl: nil,
                    status: .available,
                    goLive: barberType == .walkin,   // Walk-ins go live immediately; others start off
                    barberType: barberType,
                    serviceIds: [],
                    avgServiceTime: 30,
                    currentClientId: nil,
                    order: barbers.count
                )
                _ = try await firebase.addBarber(shopId: shopId, barber: newBarber)
                // Real-time listener will pick up the new barber automatically
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
    }

    /// Save edits to an existing barber. Called from the edit sheet.
    func saveBarber(_ barber: Barber) {
        Task {
            do {
                try await firebase.updateBarber(shopId: shopId, barber: barber)
                // Real-time listener will reflect the change automatically
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
    }

    /// Delete a barber. Confirms via the UI before calling this.
    func deleteBarber(_ barber: Barber) {
        guard let id = barber.id else { return }
        Task {
            do {
                try await firebase.deleteBarber(shopId: shopId, barberId: id)
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
    }

    /// Reorder barbers via the ↑/↓ buttons in the Settings list.
    /// Updates order values in Firestore so the kiosk and barber view reflect the new sequence.
    func moveBarbers(from source: IndexSet, to destination: Int) {
        guard let sourceIndex = source.first else { return }

        // Manually move the element — avoids importing SwiftUI just for Array.move(fromOffsets:toOffset:)
        // When moving down, subtract 1 because removal shifts the index before insertion
        let target = destination > sourceIndex ? destination - 1 : destination
        let item = barbers.remove(at: sourceIndex)
        barbers.insert(item, at: target)

        // Write a clean 0, 1, 2, 3... order index to every barber in Firestore
        Task {
            do {
                for (index, barber) in barbers.enumerated() {
                    var updated = barber
                    updated.order = index
                    try await firebase.updateBarber(shopId: shopId, barber: updated)
                }
            } catch {
                self.errorMessage = "Couldn't save barber order. Try again."
            }
        }
    }

    // MARK: - Service Actions

    /// Add a new service to the shop menu.
    func addService(name: String, estimatedMinutes: Int, price: Double?) {
        Task {
            do {
                let newService = Service(
                    name: name,
                    estimatedMinutes: estimatedMinutes,
                    price: price,
                    active: true,                   // New services are active by default
                    order: services.count           // Add to end of the list
                )
                let saved = try await firebase.addService(shopId: shopId, service: newService)
                // Append locally for instant UI update
                self.services.append(saved)
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
    }

    /// Save edits to an existing service.
    func saveService(_ service: Service) {
        Task {
            do {
                try await firebase.updateService(shopId: shopId, service: service)
                // Update the local array so the UI refreshes immediately
                if let index = services.firstIndex(where: { $0.id == service.id }) {
                    services[index] = service
                }
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
    }

    /// Delete a service from the menu.
    func deleteService(_ service: Service) {
        guard let id = service.id else { return }
        Task {
            do {
                try await firebase.deleteService(shopId: shopId, serviceId: id)
                services.removeAll { $0.id == id }
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
    }

    /// Toggle a service's active state (shows/hides it on the kiosk).
    func toggleServiceActive(_ service: Service) {
        var updated = service
        updated.active.toggle()
        saveService(updated)
    }

    // MARK: - Shop Settings (Auto-Close)

    /// Load current shop settings from Firestore — specifically the auto-close time.
    func loadShopSettings() async {
        do {
            let shop = try await firebase.fetchShop(shopId: shopId)
            if let timeStr = shop.settings.autoCloseTime {
                // Parse "HH:MM" string back into a Date for the DatePicker
                autoCloseTime = parseTimeString(timeStr)
                autoCloseEnabled = true
            } else {
                autoCloseTime = nil
                autoCloseEnabled = false
            }
        } catch {
            // Non-fatal — settings may not exist yet on older shops
        }
    }

    /// Save the auto-close time to Firestore.
    /// Called when owner toggles or changes the time picker.
    func saveAutoCloseTime() {
        Task {
            do {
                // Fetch current settings so we only update the autoCloseTime field
                var shop = try await firebase.fetchShop(shopId: shopId)
                shop.settings.autoCloseTime = autoCloseEnabled
                    ? formatTimeString(autoCloseTime ?? defaultCloseDate())
                    : nil
                try await firebase.updateShopSettings(shopId: shopId, settings: shop.settings)
            } catch {
                self.errorMessage = "Couldn't save auto-close time. Try again."
            }
        }
    }

    // MARK: - Time Helpers

    /// Convert "HH:MM" string → Date (today, at that hour/minute)
    private func parseTimeString(_ str: String) -> Date? {
        let parts = str.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        comps.hour   = parts[0]
        comps.minute = parts[1]
        return Calendar.current.date(from: comps)
    }

    /// Convert a Date → "HH:MM" string
    private func formatTimeString(_ date: Date) -> String {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
        let h = comps.hour   ?? 21
        let m = comps.minute ?? 0
        return String(format: "%02d:%02d", h, m)
    }

    /// Default close time: 9:00 PM
    private func defaultCloseDate() -> Date {
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        comps.hour = 21; comps.minute = 0
        return Calendar.current.date(from: comps) ?? Date()
    }


    // MARK: - Account Actions

    /// Send a password reset email to the currently logged-in owner.
    /// Firebase sends the link to whatever email is on the Auth account.
    func resetPassword() {
        guard let email = Auth.auth().currentUser?.email else {
            errorMessage = "No email address found for your account."
            return
        }
        Task {
            do {
                try await Auth.auth().sendPasswordReset(withEmail: email)
                // Let the view know the email went out so it can show a confirmation
                resetPasswordSent = true
            } catch {
                errorMessage = "Couldn't send reset email. Try again."
            }
        }
    }

    // MARK: - Helpers

    func clearError() {
        errorMessage = nil
    }
}
