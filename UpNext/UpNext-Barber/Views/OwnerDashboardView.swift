//
//  OwnerDashboardView.swift
//  UpNext
//
//  The shop owner's command center — redesigned as a sign-in sheet dashboard.
//  Shows today's full walk-in sheet: waiting and in-chair clients at the top,
//  completed clients crossed out below (with the barber's name attributed),
//  plus live stats and the analytics tab link.
//

import SwiftUI

struct OwnerDashboardView: View {

    @StateObject var viewModel: OwnerDashboardViewModel
    @EnvironmentObject var authViewModel: AuthViewModel

    @State private var showSettings   = false
    // Holds the pool entry the owner just tapped — drives the "assign to barber" dialog
    @State private var entryToAssign: QueueEntry? = nil
    // Controls which sheet is shown: walk-ins or appointments
    @State private var sheetMode: SheetMode = .walkIns
    // Controls which bottom tab is selected
    @State private var ownerTab: OwnerTab = .queue

    // Add Walk-In sheet state
    @State private var showAddWalkIn     = false
    @State private var addWalkInName     = ""
    @State private var addWalkInPartySize = 1
    @State private var addWalkInBarberId: String? = nil   // nil = Next Available

    enum SheetMode { case walkIns, appointments }
    enum OwnerTab   { case queue, team }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.brandNearBlack.ignoresSafeArea()

                if viewModel.isLoading {
                    loadingView
                } else {
                    // Outer container: tab content on top, custom tab bar pinned to bottom
                    VStack(spacing: 0) {

                        // Tab content area
                        Group {
                            if ownerTab == .queue {
                                mainContent
                            } else {
                                teamTab
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                        ownerTabBar
                    }
                }
            }
            .navigationTitle(viewModel.shop?.name ?? "Dashboard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.brandNearBlack, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 14) {
                        // Add walk-in — only show on the queue tab
                        if ownerTab == .queue && sheetMode == .walkIns {
                            Button {
                                addWalkInName      = ""
                                addWalkInPartySize = 1
                                addWalkInBarberId  = nil
                                showAddWalkIn      = true
                            } label: {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 20))
                                    .foregroundStyle(Color.accent)
                            }
                        }
                        Button { showSettings = true } label: {
                            Image(systemName: "gearshape")
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }
                }
            }
        }
        .onAppear   { viewModel.onAppear()    }
        .onDisappear { viewModel.onDisappear() }
        .alert("Something went wrong", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") { viewModel.clearError() }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .sheet(isPresented: $showSettings) {
            ShopSettingsView(
                viewModel: ShopSettingsViewModel(shopId: viewModel.shopId),
                showDismissButton: true,
                onSignOut: { authViewModel.signOut() },
                barberId: authViewModel.appUser?.barberId,
                appUser: authViewModel.appUser
            )
        }
        // Add Walk-In sheet — owner manually adds a client from the dashboard
        .sheet(isPresented: $showAddWalkIn) {
            addWalkInSheet
        }
        // "Assign to barber" action sheet — appears when owner taps a waiting pool entry
        .confirmationDialog(
            entryToAssign.map { "Assign \($0.customerName) to…" } ?? "Assign to…",
            isPresented: Binding(
                get: { entryToAssign != nil },
                set: { if !$0 { entryToAssign = nil } }
            ),
            titleVisibility: .visible
        ) {
            // Show ALL barbers — owner can assign to any barber regardless of live status.
            // If the entry has multiple people (partySize > 1), split this one person off
            // into their own in-chair entry instead of moving the whole group.
            ForEach(viewModel.barbers) { barber in
                Button(barber.name) {
                    if let entry = entryToAssign, let barberId = barber.id {
                        if (entry.partySize ?? 1) > 1 {
                            viewModel.splitAndAssign(entry: entry, toBarberId: barberId)
                        } else {
                            viewModel.assignAndStartPoolEntry(entry: entry, toBarberId: barberId)
                        }
                    }
                    entryToAssign = nil
                }
            }
            if viewModel.barbers.isEmpty {
                Button("No barbers found") { }.disabled(true)
            }
            Button("Cancel", role: .cancel) { entryToAssign = nil }
        }
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView().tint(.white)
            Text("Loading…")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.5))
        }
    }

    // MARK: - Main Content

    private var mainContent: some View {
        ScrollView {
            VStack(spacing: 16) {
                statCards
                lastBarberBanner
                liveBarberRow
                sheetSection
            }
            .padding(16)
        }
        .refreshable {
            await viewModel.refresh()
        }
    }

    // MARK: - Stat Cards

    private var statCards: some View {
        LazyVGrid(
            columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
            spacing: 10
        ) {
            statCard(
                title:  "Waiting",
                value:  "\(viewModel.totalWaiting)",
                color:  .orange
            )
            statCard(
                title:  "In Chair",
                value:  "\(viewModel.totalInChair)",
                color:  Color.accent
            )
            statCard(
                title:  "Done Today",
                value:  "\(viewModel.completedWalkInsToday.count)",  // walk-ins only, appointments excluded
                color:  .blue
            )
        }
    }

    private func statCard(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))
            Text(value)
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(color)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(color.opacity(0.2), lineWidth: 1))
    }

    // MARK: - Last Barber Banner

    @ViewBuilder
    private var lastBarberBanner: some View {
        if let last = viewModel.lastClaimingBarber {
            HStack(spacing: 10) {
                Image(systemName: "scissors")
                    .foregroundStyle(Color.accent)
                Text("Last taken by:")
                    .foregroundStyle(.white.opacity(0.5))
                Text(last)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                Spacer()
            }
            .font(.subheadline)
            .padding(12)
            .background(Color.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.accent.opacity(0.2), lineWidth: 1))
        }
    }

    // MARK: - Live Barber Row

    @ViewBuilder
    private var liveBarberRow: some View {
        let live = viewModel.barbers.filter { $0.isVisibleOnKiosk }
        if !live.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Circle().fill(Color.accent).frame(width: 7, height: 7)
                    Text("\(live.count) barber\(live.count == 1 ? "" : "s") taking walk-ins")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.accent)
                }
                HStack(spacing: 8) {
                    ForEach(live) { barber in
                        Text(barber.name)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Color.white.opacity(0.08), in: Capsule())
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.accent.opacity(0.2), lineWidth: 1))
        }
    }

    // MARK: - Sign-In Sheet Section

    private var sheetSection: some View {
        VStack(alignment: .leading, spacing: 10) {

            // Header row: title + date
            HStack {
                Label(
                    sheetMode == .walkIns ? "Today's Walk-In Sheet" : "Today's Appointments",
                    systemImage: sheetMode == .walkIns ? "list.bullet.clipboard" : "calendar.badge.checkmark"
                )
                .font(.headline)
                .foregroundStyle(.white)
                Spacer()
                Text(Date(), format: .dateTime.month(.abbreviated).day())
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.4))
            }

            // Mode toggle — Walk-Ins vs Appointments
            HStack(spacing: 0) {
                modeToggleButton(label: "Walk-Ins", badge: viewModel.todayWalkInsOnly.count, mode: .walkIns)
                modeToggleButton(
                    label: "Appointments",
                    badge: viewModel.todayAppointments.count,
                    mode: .appointments,
                    alertCount: viewModel.waitingAppointments.count  // Unread badge for waiting ones
                )
            }
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))

            // Sheet list — expand party-size entries so each person gets their own numbered row
            let entries = sheetMode == .walkIns ? viewModel.todayWalkInsOnly : viewModel.todayAppointments
            if entries.isEmpty {
                emptySheetState
            } else {
                // Build a flat list: one item per person (party of 3 → 3 rows)
                let expanded: [(rowNum: Int, entry: QueueEntry, isFirst: Bool)] = {
                    var result: [(rowNum: Int, entry: QueueEntry, isFirst: Bool)] = []
                    var counter = 0
                    for entry in entries {
                        let size = max(1, entry.partySize ?? 1)
                        for p in 0..<size {
                            result.append((rowNum: counter, entry: entry, isFirst: p == 0))
                            counter += 1
                        }
                    }
                    return result
                }()
                VStack(spacing: 0) {
                    ForEach(Array(expanded.enumerated()), id: \.offset) { idx, item in
                        sheetRow(entry: item.entry, rowIndex: item.rowNum, isFirst: item.isFirst)
                        if idx < expanded.count - 1 {
                            Divider()
                                .background(Color.white.opacity(0.07))
                                .padding(.leading, 60)
                        }
                    }
                }
                .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.1), lineWidth: 1))
            }
        }
    }

    private func modeToggleButton(label: String, badge: Int, mode: SheetMode, alertCount: Int = 0) -> some View {
        let isActive = sheetMode == mode
        return Button { withAnimation(.easeInOut(duration: 0.15)) { sheetMode = mode } } label: {
            HStack(spacing: 5) {
                Text(label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isActive ? .black : .white.opacity(0.45))
                // Red dot on Appointments if there are waiting ones the owner hasn't acted on
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

    @ViewBuilder
    private func sheetRow(entry: QueueEntry, rowIndex: Int, isFirst: Bool = true) -> some View {
        let isDone   = entry.status == .completed
        let isOut    = entry.status == .walkedOut || entry.status == .removed
        let isActive = entry.status == .inChair
        let fade     = isDone || isOut

        HStack(spacing: 12) {

            // Position badge — use rowIndex (sort order) not entry.position (unreliable stored value)
            Text("#\(rowIndex + 1)")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(fade ? .white.opacity(0.25) : .white.opacity(0.6))
                .frame(width: 40, alignment: .leading)

            // Name + detail
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(entry.customerName)
                        .font(.subheadline.weight(fade ? .regular : .semibold))
                        .strikethrough(fade)
                        .foregroundStyle(fade ? .white.opacity(0.3) : .white)
                    // Remote badge — shows arrival status for customers who checked in from the website
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

                // Status detail line
                Group {
                    if isDone {
                        let bName = viewModel.barberName(for: entry.assignedBarberId ?? entry.barberId)
                        Label("Served by \(bName)", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(Color.accent.opacity(0.7))
                    } else if isActive {
                        let bName = viewModel.barberName(for: entry.assignedBarberId ?? entry.barberId)
                        Label("With \(bName)", systemImage: "scissors")
                            .foregroundStyle(Color.accent)
                    } else if isOut {
                        Label("Walked out", systemImage: "person.fill.xmark")
                            .foregroundStyle(.red.opacity(0.6))
                    } else if entry.isAppointment == true {
                        // Change 1: appointments show who they're waiting on
                        let bName = viewModel.barberName(for: entry.assignedBarberId ?? entry.barberId)
                        Label("Waiting on \(bName)", systemImage: "calendar")
                            .foregroundStyle(.blue.opacity(0.85))
                    } else {
                        Text(entry.checkInTime, format: .dateTime.hour().minute())
                            .foregroundStyle(.white.opacity(0.35))
                    }
                }
                .font(.caption)
            }

            Spacer()

            // Appointments are self-managing — only show ✕ to remove if needed.
            // Walk-ins are owner-managed: assign arrow + remove (waiting), Done (in_chair).
            if entry.isAppointment == true {
                // Active appointment: only the lead row gets a remove button
                let isActiveAppt = entry.status == .waiting || entry.status == .inChair || entry.status == .notified
                if isFirst && isActiveAppt {
                    Button {
                        viewModel.removeFromQueue(entry: entry)
                    } label: {
                        Image(systemName: "xmark.circle")
                            .font(.system(size: 18))
                            .foregroundStyle(.red.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                }
            } else {
                // Walk-in waiting: assign arrow (every row) + remove (lead row only)
                if entry.status == .waiting {
                    HStack(spacing: 8) {
                        Button {
                            entryToAssign = entry
                        } label: {
                            Image(systemName: "arrow.right.circle.fill")
                                .font(.system(size: 20))
                                .foregroundStyle(Color.accent)
                        }
                        .buttonStyle(.plain)

                        if isFirst {
                            Button {
                                viewModel.removeFromQueue(entry: entry)
                            } label: {
                                Image(systemName: "person.fill.xmark")
                                    .font(.caption)
                                    .foregroundStyle(.red.opacity(0.6))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // Walk-in in_chair: Done button (lead row only)
                if isFirst && entry.status == .inChair {
                    Button {
                        viewModel.completeService(entry: entry)
                    } label: {
                        Text("Done ✓")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.accent, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            // Status chip (shown for all other statuses)
            if entry.status != .waiting && entry.status != .inChair {
                statusChip(for: entry.status)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .opacity(isOut ? 0.5 : 1.0)
    }

    @ViewBuilder
    private func statusChip(for status: QueueStatus) -> some View {
        switch status {
        case .waiting:
            chip("Waiting", color: .orange)
        case .notified:
            chip("Notified", color: .blue)
        case .inChair:
            chip("In Chair", color: Color.accent)
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

    // MARK: - Custom Bottom Tab Bar

    private var ownerTabBar: some View {
        HStack(spacing: 0) {
            ownerTabItem(icon: "list.bullet.clipboard", label: "Queue",  tab: .queue)
            ownerTabItem(icon: "person.2.fill",         label: "Barbers", tab: .team)
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 24)  // Extra bottom padding for home indicator safe area
        .background(
            Color.brandNearBlack
                .overlay(Divider().frame(maxWidth: .infinity, maxHeight: 1), alignment: .top)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    private func ownerTabItem(icon: String, label: String, tab: OwnerTab) -> some View {
        let isActive = ownerTab == tab
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) { ownerTab = tab }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(isActive ? Color.accent : .white.opacity(0.35))
                Text(label)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(isActive ? Color.accent : .white.opacity(0.35))
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Team Tab (Barber Live Toggles)

    private var teamTab: some View {
        ScrollView {
            VStack(spacing: 12) {

                // Section header
                HStack {
                    Label("Barber Availability", systemImage: "person.2.fill")
                        .font(.headline)
                        .foregroundStyle(.white)
                    Spacer()
                    // Quick summary — how many are currently live
                    let liveCount = viewModel.barbers.filter { $0.isVisibleOnKiosk }.count
                    Text(liveCount == 0 ? "All offline" : "\(liveCount) live")
                        .font(.caption)
                        .foregroundStyle(liveCount > 0 ? Color.accent : .white.opacity(0.35))
                }

                // One row per barber — shows live/offline toggle the owner can flip instantly
                if viewModel.barbers.isEmpty {
                    Text("No barbers yet. Add them in Settings.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.3))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(viewModel.barbers.enumerated()), id: \.element.id) { idx, barber in
                            barberToggleRow(barber: barber)
                            if idx < viewModel.barbers.count - 1 {
                                Divider()
                                    .background(Color.white.opacity(0.07))
                                    .padding(.leading, 60)
                            }
                        }
                    }
                    .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.1), lineWidth: 1))
                }
            }
            .padding(16)
        }
        .refreshable { await viewModel.refresh() }
    }

    private func barberToggleRow(barber: Barber) -> some View {
        let isLive = barber.isVisibleOnKiosk

        return HStack(spacing: 14) {

            // Avatar / initial bubble
            ZStack {
                Circle()
                    .fill(isLive ? Color.accent.opacity(0.15) : Color.white.opacity(0.06))
                    .frame(width: 44, height: 44)
                Text(String(barber.name.prefix(1)).uppercased())
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(isLive ? Color.accent : .white.opacity(0.4))
            }

            // Name + status text
            VStack(alignment: .leading, spacing: 2) {
                Text(barber.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text(isLive ? "Taking walk-ins" : "Offline")
                    .font(.caption)
                    .foregroundStyle(isLive ? Color.accent.opacity(0.8) : .white.opacity(0.3))
            }

            Spacer()

            // Big tap target toggle pill
            Button {
                viewModel.toggleGoLive(barber: barber)
            } label: {
                HStack(spacing: 5) {
                    if isLive {
                        Circle()
                            .fill(Color.black.opacity(0.5))
                            .frame(width: 7, height: 7)
                    }
                    Text(isLive ? "Live" : "Offline")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(isLive ? .black : .white.opacity(0.5))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(isLive ? Color.accent : Color.white.opacity(0.1), in: Capsule())
                .overlay(Capsule().stroke(isLive ? Color.clear : Color.white.opacity(0.15), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    // MARK: - Empty Sheet State

    private var emptySheetState: some View {
        HStack(spacing: 12) {
            Image(systemName: "clipboard")
                .foregroundStyle(.white.opacity(0.3))
            Text("No walk-ins yet today. They'll appear here as clients sign in at the kiosk.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.3))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Add Walk-In Sheet

    private var addWalkInSheet: some View {
        NavigationStack {
            // VStack splits the sheet into scrollable content + pinned button at bottom
            VStack(spacing: 0) {
                Color.brandNearBlack.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {

                        // ── Name ──────────────────────────────────────────
                        VStack(alignment: .leading, spacing: 6) {
                            Text("CLIENT NAME")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.4))
                                .kerning(1)
                            TextField("e.g. Marcus Johnson", text: $addWalkInName)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.words)
                                .padding(13)
                                .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                                .foregroundStyle(.white)
                        }

                        // ── Party Size ────────────────────────────────────
                        VStack(alignment: .leading, spacing: 6) {
                            Text("PARTY SIZE")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.4))
                                .kerning(1)
                            HStack(spacing: 0) {
                                // Minus
                                Button {
                                    if addWalkInPartySize > 1 { addWalkInPartySize -= 1 }
                                } label: {
                                    Image(systemName: "minus")
                                        .font(.system(size: 17, weight: .bold))
                                        .frame(width: 48, height: 48)
                                        .foregroundStyle(addWalkInPartySize > 1 ? Color.accent : .white.opacity(0.2))
                                }
                                .buttonStyle(.plain)

                                Text("\(addWalkInPartySize)")
                                    .font(.system(size: 22, weight: .bold, design: .monospaced))
                                    .foregroundStyle(.white)
                                    .frame(minWidth: 44)

                                // Plus
                                Button {
                                    if addWalkInPartySize < 8 { addWalkInPartySize += 1 }
                                } label: {
                                    Image(systemName: "plus")
                                        .font(.system(size: 17, weight: .bold))
                                        .frame(width: 48, height: 48)
                                        .foregroundStyle(addWalkInPartySize < 8 ? Color.accent : .white.opacity(0.2))
                                }
                                .buttonStyle(.plain)

                                Spacer()
                                if addWalkInPartySize > 1 {
                                    Text("\(addWalkInPartySize) people")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(Color.accent.opacity(0.8))
                                }
                            }
                            .padding(.horizontal, 8)
                            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                        }

                        // ── Barber ────────────────────────────────────────
                        VStack(alignment: .leading, spacing: 8) {
                            Text("ASSIGN TO")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.4))
                                .kerning(1)

                            // "Next Available" option
                            barberPickerRow(id: nil, name: "Next Available", icon: "⚡")

                            // All barbers — scroll freely without the button getting buried
                            ForEach(viewModel.barbers) { barber in
                                barberPickerRow(
                                    id: barber.id,
                                    name: barber.name,
                                    icon: barber.goLive ? "🟢" : "⚫️"
                                )
                            }
                        }
                    }
                    .padding(20)
                }

                // ── Add Button — always visible, pinned to bottom ─────────
                Divider().overlay(Color.white.opacity(0.08))

                Button {
                    let name = addWalkInName.trimmingCharacters(in: .whitespaces)
                    let finalName = name.isEmpty ? "Walk-in" : name
                    if let barberId = addWalkInBarberId {
                        viewModel.addManualEntry(
                            name: finalName, phone: "", serviceId: "",
                            barberId: barberId, partySize: addWalkInPartySize
                        )
                    } else {
                        viewModel.addWalkInToNextAvailable(
                            name: finalName, phone: "", serviceId: "",
                            partySize: addWalkInPartySize
                        )
                    }
                    showAddWalkIn = false
                } label: {
                    Text("Add to Queue")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.accent, in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(Color.brandNearBlack)
            }
            .background(Color.brandNearBlack.ignoresSafeArea())
            .navigationTitle("Add Walk-In")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { showAddWalkIn = false }
                        .foregroundStyle(Color.accent)
                }
            }
        }
    }

    private func barberPickerRow(id: String?, name: String, icon: String) -> some View {
        let isSelected = addWalkInBarberId == id
        return Button {
            addWalkInBarberId = id
        } label: {
            HStack(spacing: 12) {
                Text(icon)
                    .font(.system(size: 14))
                Text(name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accent)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                isSelected
                    ? Color.accent.opacity(0.12)
                    : Color.white.opacity(0.05),
                in: RoundedRectangle(cornerRadius: 12)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.accent.opacity(0.4) : Color.white.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
