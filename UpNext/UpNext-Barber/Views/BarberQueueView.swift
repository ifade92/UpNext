//
//  BarberQueueView.swift
//  UpNext
//
//  The barber's main screen — clean dark sign-in sheet matching the owner dashboard.
//  Numbered list of today's walk-ins, completed entries crossed out with barber attribution.
//
//  Layout:
//    • Top bar (dark): barber name, GoLive toggle, current client card, Claim Next button
//    • Scrollable list: today's full sign-in sheet, sorted by check-in time
//

import SwiftUI

struct BarberQueueView: View {

    @StateObject var viewModel: BarberQueueViewModel
    @EnvironmentObject var authViewModel: AuthViewModel

    @State private var showSignOutAlert   = false
    @State private var showBarberSettings = false
    @State private var showManualAdd      = false

    // Controls whether the barber is looking at today's walk-ins or their appointments.
    // Mirrors the toggle on the owner dashboard so appointment check-ins have a
    // dedicated home instead of blending into the walk-in sheet.
    @State private var sheetMode: SheetMode = .walkIns

    enum SheetMode { case walkIns, appointments }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.brandNearBlack.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Dark control bar: GoLive toggle + current client + Claim Next
                    controlBar
                        .background(Color.brandNearBlack)

                    Divider()
                        .background(Color.white.opacity(0.08))

                    // Appointment arrival banner — appears when a booked client has checked in
                    if !viewModel.myWaitingAppointments.isEmpty {
                        appointmentArrivalBanner
                            .padding(.horizontal, 16)
                            .padding(.top, 12)
                    }

                    // Clean scrollable sign-in list
                    signInList
                }
            }
            .navigationTitle(viewModel.barber?.name ?? "Walk-Ins")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.brandNearBlack, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 14) {
                        Button { showManualAdd = true } label: {
                            Image(systemName: "plus")
                                .foregroundStyle(.white.opacity(0.85))
                        }
                        Button { showBarberSettings = true } label: {
                            Image(systemName: "person.circle")
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }
                }
            }
        }
        .onAppear    { viewModel.onAppear()    }
        .onDisappear { viewModel.onDisappear() }
        .alert("Sign Out", isPresented: $showSignOutAlert) {
            Button("Sign Out", role: .destructive) {
                Task { await authViewModel.signOut() }
            }
            Button("Cancel",   role: .cancel)      { }
        } message: {
            Text("Are you sure you want to sign out?")
        }
        .alert("Something went wrong", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") { viewModel.clearError() }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .sheet(isPresented: $showBarberSettings) { barberSettingsSheet }
        .sheet(isPresented: $showManualAdd)      { ManualAddSheet(viewModel: viewModel, isPresented: $showManualAdd) }
    }

    // MARK: - Control Bar

    private var controlBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                if let barber = viewModel.barber {
                    Text(barber.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                }
                Spacer()
                goLiveToggle
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)

            if let client = viewModel.currentClient {
                currentClientCard(client)
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
            }

            claimNextButton
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
        }
    }

    private var goLiveToggle: some View {
        Button { viewModel.toggleGoLive() } label: {
            HStack(spacing: 7) {
                Circle()
                    .fill(viewModel.isGoLive ? Color.accent : Color.gray.opacity(0.5))
                    .frame(width: 8, height: 8)
                Text(viewModel.isGoLive ? "Taking Walk-Ins" : "Not Available")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(viewModel.isGoLive ? Color.accent : .white.opacity(0.4))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                viewModel.isGoLive ? Color.accent.opacity(0.12) : Color.white.opacity(0.07),
                in: Capsule()
            )
            .overlay(Capsule().stroke(
                viewModel.isGoLive ? Color.accent.opacity(0.4) : Color.white.opacity(0.15),
                lineWidth: 1
            ))
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.2), value: viewModel.isGoLive)
    }

    private func currentClientCard(_ client: QueueEntry) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("In Your Chair")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.4))
                Text(client.customerName)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
            }
            Spacer()
            Button { viewModel.completeService(entry: client) } label: {
                Label("Done", systemImage: "checkmark")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(Color.accent, in: RoundedRectangle(cornerRadius: 10))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Color.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.accent.opacity(0.3), lineWidth: 1))
    }

    private var claimNextButton: some View {
        let canClaim = !viewModel.hasCurrentClient
                    && viewModel.poolEntries.first != nil
                    && viewModel.isGoLive

        let label: String = {
            if !viewModel.isGoLive           { return "Toggle Available to Claim" }
            if viewModel.hasCurrentClient    { return "Finish Current Client First" }
            guard let next = viewModel.poolEntries.first else { return "No One Waiting" }
            return "Claim Next — \(next.customerName)"
        }()

        return Button { viewModel.claimNext() } label: {
            HStack(spacing: 8) {
                Image(systemName: "hand.raised.fill")
                Text(label)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(12)
            .background(
                canClaim ? Color.accent : Color.white.opacity(0.06),
                in: RoundedRectangle(cornerRadius: 12)
            )
            .foregroundStyle(canClaim ? .white : .white.opacity(0.3))
        }
        .buttonStyle(.plain)
        .disabled(!canClaim)
        .animation(.easeInOut(duration: 0.15), value: canClaim)
    }

    // MARK: - Appointment Arrival Banner

    /// Shown above the sign-in list whenever one or more booked clients have checked in.
    /// Purely informational — no action needed. Auto-completes after 1 hour.
    private var appointmentArrivalBanner: some View {
        VStack(spacing: 8) {
            // Section label
            HStack(spacing: 6) {
                Image(systemName: "scissors")
                    .foregroundStyle(.blue)
                Text("With You Now")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                Spacer()
                Text("\(viewModel.myWaitingAppointments.count)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.blue.opacity(0.2), in: Capsule())
            }

            // One card per arrived appointment — informational only, no action required
            ForEach(viewModel.myWaitingAppointments) { appt in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(appt.customerName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                        // Show "With [barber] · [time]" — barber's name from their own profile
                        let barberName = viewModel.barber?.name ?? "you"
                        Text("With \(barberName) · \(appt.checkInTime, format: .dateTime.hour().minute())")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.45))
                    }
                    Spacer()
                    // No button needed — disappears automatically after 1 hour
                    Text("Auto-completes in ~1 hr")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.28))
                        .multilineTextAlignment(.trailing)
                }
                .padding(12)
                .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.blue.opacity(0.3), lineWidth: 1))
            }
        }
        .padding(12)
        .background(Color.blue.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.blue.opacity(0.2), lineWidth: 1))
        .animation(.easeInOut(duration: 0.2), value: viewModel.myWaitingAppointments.count)
    }

    // MARK: - Sign-In List

    private var signInList: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Header row: date + live count + sort toggle
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Label(
                            sheetMode == .walkIns ? "Today's Walk-Ins" : "Today's Appointments",
                            systemImage: sheetMode == .walkIns ? "list.bullet.clipboard" : "calendar.badge.checkmark"
                        )
                        .font(.headline)
                        .foregroundStyle(.white)
                        Text(Date(), format: .dateTime.weekday(.wide).month(.wide).day())
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    Spacer()
                    // Sort direction toggle — oldest first (↑) or newest first (↓)
                    Button { viewModel.toggleSortOrder() } label: {
                        HStack(spacing: 5) {
                            Text(viewModel.sortAscending ? "Oldest First" : "Newest First")
                                .font(.caption.weight(.medium))
                            Image(systemName: viewModel.sortAscending ? "arrow.up" : "arrow.down")
                                .font(.caption.weight(.bold))
                        }
                        .foregroundStyle(.white.opacity(0.5))
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Color.white.opacity(0.07), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)

                // Walk-Ins vs Appointments toggle — mirrors OwnerDashboardView
                HStack(spacing: 0) {
                    barberModeToggleButton(
                        label: "Walk-Ins",
                        badge: viewModel.shopWideSignInSheet.count,
                        mode: .walkIns
                    )
                    barberModeToggleButton(
                        label: "Appointments",
                        badge: viewModel.myTodayAppointments.count,
                        mode: .appointments,
                        alertCount: viewModel.myWaitingAppointments.count
                    )
                }
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 16)

                // Branch: render the walk-in sign-in sheet OR the appointments list
                if sheetMode == .appointments {
                    appointmentsList
                } else if viewModel.shopWideSignInSheet.isEmpty {
                    emptyState
                } else {
                    // All rows in one rounded card — same pattern as OwnerDashboardView.
                    //
                    // Two kinds of entries can exist in Firestore:
                    //   - NEW (groupId-based): Each person in a group has their own
                    //     independent entry (partySize nil or 1). No expansion needed —
                    //     each entry is already one row. Each barber can claim independently.
                    //   - LEGACY (partySize > 1): A single entry represents N people.
                    //     We still expand these for backward compat. All actions apply to
                    //     the whole group (old behavior), but new check-ins won't do this.
                    //
                    // The expansion loop handles both: new entries expand to exactly 1 row,
                    // legacy entries expand to N rows as before.
                    let expandedRows: [(rowNum: Int, entry: QueueEntry, slotIndex: Int, isFirst: Bool)] = {
                        var result: [(rowNum: Int, entry: QueueEntry, slotIndex: Int, isFirst: Bool)] = []
                        var counter = 0
                        for entry in viewModel.shopWideSignInSheet {
                            // New group entries: partySize is nil/1, each entry is one person.
                            // Legacy entries: partySize > 1, expand to multiple rows.
                            let size = max(1, entry.partySize ?? 1)
                            for p in 0..<size {
                                result.append((rowNum: counter, entry: entry, slotIndex: p, isFirst: p == 0))
                                counter += 1
                            }
                        }
                        return result
                    }()

                    VStack(spacing: 0) {
                        ForEach(Array(expandedRows.enumerated()), id: \.offset) { idx, item in
                            sheetRow(entry: item.entry, rowIndex: item.rowNum, slotIndex: item.slotIndex, isFirst: item.isFirst)
                            if idx < expandedRows.count - 1 {
                                Divider()
                                    .background(Color.white.opacity(0.06))
                                    .padding(.leading, 60)
                            }
                        }
                    }
                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.08), lineWidth: 1))
                    .padding(.horizontal, 16)
                }

                Color.clear.frame(height: 32)
            }
        }
    }

    // Mode toggle pill — "Walk-Ins" vs "Appointments" — matches the owner dashboard styling.
    // alertCount drives a small red dot on the inactive tab when appointments are waiting.
    private func barberModeToggleButton(label: String, badge: Int, mode: SheetMode, alertCount: Int = 0) -> some View {
        let isActive = sheetMode == mode
        return Button { withAnimation(.easeInOut(duration: 0.15)) { sheetMode = mode } } label: {
            HStack(spacing: 5) {
                Text(label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isActive ? .black : .white.opacity(0.45))
                // Red dot: signals a waiting appointment the barber hasn't seen yet
                if alertCount > 0 && !isActive {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 7, height: 7)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(isActive ? Color.accent : Color.clear, in: RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Appointments List
    // Shows this barber's scheduled appointments for today — waiting, in chair,
    // and already-completed. Appointments auto-seat + auto-complete, so there are
    // no action buttons here beyond a remove (✕) on active entries if needed.
    @ViewBuilder
    private var appointmentsList: some View {
        let appointments = viewModel.myTodayAppointments

        if appointments.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "calendar")
                    .font(.system(size: 36))
                    .foregroundStyle(.white.opacity(0.2))
                Text("No appointments today")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.5))
                Text("Booked clients will appear here when they check in.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.3))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(appointments.enumerated()), id: \.offset) { idx, entry in
                    appointmentRow(entry: entry, rowIndex: idx)
                    if idx < appointments.count - 1 {
                        Divider()
                            .background(Color.white.opacity(0.06))
                            .padding(.leading, 60)
                    }
                }
            }
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.blue.opacity(0.2), lineWidth: 1))
            .padding(.horizontal, 16)
        }
    }

    // Single appointment row — mirrors sheetRow's layout but tailored to appointment states.
    // Appointments auto-seat + auto-complete, so actions are minimal (just a remove ✕).
    @ViewBuilder
    private func appointmentRow(entry: QueueEntry, rowIndex: Int) -> some View {
        let isDone   = entry.status == .completed
        let isOut    = entry.status == .walkedOut || entry.status == .removed
        let isActive = entry.status == .waiting || entry.status == .notified || entry.status == .inChair
        let fade     = isDone || isOut

        HStack(spacing: 12) {
            // Position badge
            Text("#\(rowIndex + 1)")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(fade ? .white.opacity(0.2) : .white.opacity(0.55))
                .frame(width: 40, alignment: .leading)

            // Name + status detail line
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(entry.customerName)
                        .font(.subheadline.weight(fade ? .regular : .semibold))
                        .strikethrough(fade, color: .white.opacity(0.35))
                        .foregroundStyle(fade ? .white.opacity(0.3) : .white)
                    // Remote check-in badge (if the appointment checked in from the website)
                    if entry.isRemoteCheckIn == true {
                        if entry.remoteStatus == "arrived" {
                            Text("✅ Arrived")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.green)
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(Color.green.opacity(0.15), in: Capsule())
                        } else {
                            Text("📍 On the Way")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.orange)
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(Color.orange.opacity(0.15), in: Capsule())
                        }
                    }
                }

                // Context line — check-in time, in-chair state, or resolved status
                Group {
                    if isDone {
                        Label("Done", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(Color.accent.opacity(0.7))
                    } else if entry.status == .inChair {
                        Label("In your chair", systemImage: "scissors")
                            .foregroundStyle(Color.accent)
                    } else if isOut {
                        Label(entry.status == .walkedOut ? "Walked out" : "Removed",
                              systemImage: "person.fill.xmark")
                            .foregroundStyle(.red.opacity(0.6))
                    } else {
                        // Waiting / notified — show check-in time
                        Label {
                            Text(entry.checkInTime, format: .dateTime.hour().minute())
                        } icon: {
                            Image(systemName: "calendar")
                        }
                        .foregroundStyle(.blue.opacity(0.85))
                    }
                }
                .font(.caption)
            }

            Spacer()

            // Active appointment: override buttons in case auto-manage needs help.
            // Done marks it complete early; ✕ removes it if they no-show or cancel.
            if isActive {
                HStack(spacing: 8) {
                    Button { viewModel.completeService(entry: entry) } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                            Text("Done")
                                .font(.caption.weight(.bold))
                        }
                        .foregroundStyle(Color.black)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.accent, in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)

                    Button { viewModel.removeFromQueue(entry: entry) } label: {
                        Image(systemName: "xmark.circle")
                            .font(.system(size: 18))
                            .foregroundStyle(.red.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                }
            } else {
                // Status chip for completed / walked out / removed
                statusChip(for: entry.status, isMyClient: false)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .opacity(isOut ? 0.5 : 1.0)
    }

    @ViewBuilder
    private func sheetRow(entry: QueueEntry, rowIndex: Int, slotIndex: Int = 0, isFirst: Bool = true) -> some View {
        let isMyClient = entry.barberId == viewModel.barberId && entry.status == .inChair
        let isDone     = entry.status == .completed
        let isOut      = entry.status == .walkedOut || entry.status == .removed
        let fade       = isDone || isOut

        // For new group entries (groupId-based), show which slot this person is.
        // For legacy entries expanded via partySize, slotIndex > 0 means a guest row.
        let isGroupEntry   = entry.groupId != nil
        let isGuestSlot    = slotIndex > 0  // 0 = primary/first person
        let displayName: String = {
            if isGroupEntry, let idx = entry.partyIndex, let total = entry.groupSize, total > 1 {
                // New-style group entry — show "Carlos (1 of 3)" for the primary,
                // "Carlos (2 of 3)" for guests. partyIndex is 1-based.
                return "\(entry.customerName) (\(idx) of \(total))"
            } else if isGuestSlot {
                // Legacy partySize expansion — label guests as "+1", "+2", etc.
                return "\(entry.customerName) +\(slotIndex)"
            }
            return entry.customerName
        }()

        HStack(spacing: 12) {

            // Position number — use rowIndex (sort order) not stored position field
            Text("#\(rowIndex + 1)")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(fade ? .white.opacity(0.2) : .white.opacity(0.5))
                .frame(width: 40, alignment: .leading)

            // Name + attribution
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(displayName)
                        .font(.subheadline.weight(fade ? .regular : .semibold))
                        .strikethrough(fade, color: .white.opacity(0.35))
                        .foregroundStyle(fade ? .white.opacity(0.3) : .white)
                    // Remote badge — shows arrival status for customers who checked in from the website
                    if entry.isRemoteCheckIn == true {
                        if entry.remoteStatus == "arrived" {
                            // Customer tapped "I'm Here" — they're at the shop now
                            Text("✅ Arrived")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.green)
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(Color.green.opacity(0.15), in: Capsule())
                        } else {
                            // Still on the way — don't seat them yet
                            Text("📍 On the Way")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.orange)
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(Color.orange.opacity(0.15), in: Capsule())
                        }
                    }
                }

                // Status detail — barber attribution on completed/in-chair rows
                Group {
                    if isDone {
                        let bName = viewModel.allBarbers.first { $0.id == (entry.assignedBarberId ?? entry.barberId) }?.name ?? "Barber"
                        Label("Served by \(bName)", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(Color.accent.opacity(0.7))
                    } else if isMyClient {
                        Label("In your chair", systemImage: "scissors")
                            .foregroundStyle(Color.accent)
                    } else if entry.status == .inChair {
                        let bName = viewModel.allBarbers.first { $0.id == (entry.assignedBarberId ?? entry.barberId) }?.name ?? "Barber"
                        Label("With \(bName)", systemImage: "scissors")
                            .foregroundStyle(.white.opacity(0.5))
                    } else if isOut {
                        Label("Walked out", systemImage: "person.fill.xmark")
                            .foregroundStyle(.red.opacity(0.5))
                    } else {
                        Text(entry.checkInTime, format: .dateTime.hour().minute())
                            .foregroundStyle(.white.opacity(0.3))
                    }
                }
                .font(.caption)
            }

            Spacer()

            // Remove button only on the lead row of a group — don't show per-person
            if isFirst && entry.status == .waiting {
                Button { viewModel.removeFromQueue(entry: entry) } label: {
                    Image(systemName: "person.fill.xmark")
                        .font(.caption)
                        .foregroundStyle(.red.opacity(0.5))
                }
                .buttonStyle(.plain)
            }

            statusChip(for: entry.status, isMyClient: isMyClient)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(isMyClient ? Color.accent.opacity(0.07) : Color.clear)
        .opacity(isOut ? 0.5 : 1.0)
    }

    @ViewBuilder
    private func statusChip(for status: QueueStatus, isMyClient: Bool) -> some View {
        switch status {
        case .waiting:
            chip("Waiting", color: .orange)
        case .notified:
            chip("Notified", color: .blue)
        case .inChair:
            chip(isMyClient ? "My Chair" : "In Chair", color: isMyClient ? Color.accent : .blue)
        case .completed:
            chip("Done", color: .gray)
        case .walkedOut:
            chip("Left", color: .red)
        case .removed:
            chip("Removed", color: .red)
        }
    }

    private func chip(_ label: String, color: Color) -> some View {
        Text(label)
            .font(.caption2.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
    }

    private var emptyState: some View {
        HStack(spacing: 12) {
            Image(systemName: "clipboard")
                .foregroundStyle(.white.opacity(0.3))
            Text("No walk-ins yet today — they'll appear here as clients check in.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.3))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
    }

    // MARK: - Barber Settings Sheet

    private var barberSettingsSheet: some View {
        BarberSettingsSheet(
            barber: viewModel.barber,
            appUser: authViewModel.appUser,
            onDone: { showBarberSettings = false },
            onSignOut: {
                showBarberSettings = false
                showSignOutAlert = true
            }
        )
    }
}

// MARK: - Manual Add Sheet

struct ManualAddSheet: View {

    @ObservedObject var viewModel: BarberQueueViewModel
    @Binding var isPresented: Bool

    @State private var name:      String = ""
    @State private var phone:     String = ""
    @State private var partySize: Int    = 1
    @State private var seatNow:   Bool   = false

    private var canSubmit: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section("Client Info") {
                    TextField("Name (required)", text: $name)
                        .textContentType(.name)
                        .autocorrectionDisabled()
                    TextField("Phone (optional)", text: $phone)
                        .textContentType(.telephoneNumber)
                        .keyboardType(.phonePad)
                }
                Section("Party Size") {
                    Stepper(partySize == 1 ? "1 person" : "\(partySize) people",
                            value: $partySize, in: 1...8)
                }
                Section {
                    Toggle(isOn: $seatNow) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Seat Now").font(.body)
                            Text(seatNow ? "Goes straight to your chair" : "Joins the bottom of the waiting list")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .tint(Color.accent)
                }
                Section {
                    Button {
                        viewModel.addManualEntry(
                            name:      name.trimmingCharacters(in: .whitespaces),
                            phone:     phone,
                            partySize: partySize > 1 ? partySize : nil,
                            status:    seatNow ? .inChair : .waiting
                        )
                        isPresented = false
                    } label: {
                        HStack {
                            Spacer()
                            Text(seatNow ? "Add & Seat Now" : "Add to Waiting List")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(canSubmit ? Color.accent : .secondary)
                            Spacer()
                        }
                    }
                    .disabled(!canSubmit)
                }
            }
            .navigationTitle("Add Walk-In")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                }
            }
        }
    }
}
