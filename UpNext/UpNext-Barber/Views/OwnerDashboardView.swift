//
//  OwnerDashboardView.swift
//  UpNext
//
//  The shop owner's command center.
//  Shows all barbers in a 2-column photo tile grid, each with their photo
//  filling the tile, name/status overlaid, and a Live toggle + queue preview
//  in the bottom section. Quick actions (Start, Done) right from the tile.
//
//  Design: Deep green brand background with accent green highlights.
//

import SwiftUI

struct OwnerDashboardView: View {

    @StateObject var viewModel: OwnerDashboardViewModel

    // Add to queue — tracks which barber we're adding for
    @State private var addingForBarber: Barber? = nil
    // Move entry — tracks which customer is being reassigned
    @State private var movingEntry: QueueEntry? = nil
    // In Chair sheet — tap the stat to see & manage all in-chair clients directly
    @State private var showInChairSheet = false
    // Add Walk-in to Next Available pool — owner taps "+" in the header
    @State private var showAddToNextAvailable = false

    var body: some View {
        ZStack {
            Color.brandNearBlack.ignoresSafeArea()

            if viewModel.isLoading {
                loadingView
            } else {
                mainContent
            }
        }
        .onAppear { viewModel.onAppear() }
        .onDisappear { viewModel.onDisappear() }
        .alert("Something went wrong", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") { viewModel.clearError() }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        // Add to Queue sheet — triggered when owner taps "+ Add" on a barber card
        .sheet(item: $addingForBarber) { barber in
            OwnerAddEntrySheet(viewModel: viewModel, barber: barber)
        }
        // Move Entry sheet — triggered when owner taps ⇄ on a waiting customer
        .sheet(item: $movingEntry) { entry in
            MoveEntrySheet(viewModel: viewModel, entry: entry)
        }
        // In Chair sheet — shows ALL in-chair clients regardless of barber assignment
        .sheet(isPresented: $showInChairSheet) {
            InChairSheet(viewModel: viewModel)
        }
        // Add walk-in to Next Available pool
        .sheet(isPresented: $showAddToNextAvailable) {
            AddToNextAvailableSheet(viewModel: viewModel)
        }
    }

    // MARK: - Main Content

    private var mainContent: some View {
        ScrollView {
            VStack(spacing: 20) {
                headerSection
                statsBar
                barbersList
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        // Pull-to-refresh — restarts all Firestore listeners and reloads data
        .refreshable {
            await viewModel.refresh()
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.shop?.name ?? "Dashboard")
                    .font(.brandTitle2)
                    .foregroundColor(.white)

                Text("Owner Dashboard")
                    .font(.brandSubheadline)
                    .foregroundColor(.accent)
            }

            Spacer()

            // Quick-add a walk-in to the Next Available pool without going to the kiosk
            Button(action: { showAddToNextAvailable = true }) {
                HStack(spacing: 5) {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                    Text("Walk-in")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(.black)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Color.accent)
                .cornerRadius(8)
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.top, 16)
        }
        .padding(.top, 16)
    }

    // MARK: - Stats Bar

    /// Quick glance numbers at the top — total waiting, in chair, barbers live.
    private var statsBar: some View {
        HStack(spacing: 0) {
            statItem(
                value: "\(viewModel.totalWaiting)",
                label: "Waiting",
                icon: "person.2"
            )
            Divider()
                .frame(height: 40)
                .background(Color.gray.opacity(0.3))

            // Tappable — opens the In Chair sheet to see & manage all in-chair clients
            Button(action: { showInChairSheet = true }) {
                statItem(
                    value: "\(viewModel.totalInChair)",
                    label: "In Chair",
                    icon: "person.fill",
                    tappable: true
                )
            }
            .buttonStyle(PlainButtonStyle())

            Divider()
                .frame(height: 40)
                .background(Color.gray.opacity(0.3))
            statItem(
                value: "\(viewModel.barbers.filter { $0.goLive }.count)",
                label: "Live",
                icon: "bolt.fill"
            )
        }
        .padding(.vertical, 14)
        .background(Color.brandInput)
        .cornerRadius(14)
    }

    private func statItem(value: String, label: String, icon: String, tappable: Bool = false) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundColor(.accent)
                Text(value)
                    .font(.title3)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
            }
            HStack(spacing: 3) {
                Text(label)
                    .font(.caption2)
                    .foregroundColor(.gray)
                // Small chevron hints that this stat is tappable
                if tappable {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundColor(.gray.opacity(0.6))
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Barbers List

    private var barbersList: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Ghost entries — show a warning card so the owner can clear them out
            if !viewModel.orphanedEntries.isEmpty {
                orphanedEntriesCard(viewModel.orphanedEntries)
            }

            // "Next Available" pool — unassigned customers visible to all barbers
            let nextPool = viewModel.allQueueEntries.filter {
                $0.barberId == "__next__" &&
                ($0.status == .waiting || $0.status == .notified)
            }
            if !nextPool.isEmpty {
                nextAvailablePool(nextPool)
            }

            sectionHeader("Barbers")

            ForEach(viewModel.barbers) { barber in
                barberCard(barber)
            }
        }
    }

    // MARK: - Orphaned Entries Card

    /// Shows "ghost" queue entries that don't belong to any known barber.
    /// These inflate the stats counters but never appear in a barber card.
    private func orphanedEntriesCard(_ entries: [QueueEntry]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Warning header
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.orange)
                Text("Ghost Entries")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.orange)
                Spacer()
                Text("Tap × to clear")
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.orange.opacity(0.08))

            Text("These entries show up in the stats but aren't linked to any barber — likely leftover from old data.")
                .font(.system(size: 11))
                .foregroundColor(.gray)
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .padding(.bottom, 4)

            // Each ghost entry with a remove button
            ForEach(entries) { entry in
                Divider().background(Color.gray.opacity(0.1)).padding(.leading, 14)
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.customerName)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                        Text("Status: \(entry.status.displayName) · ID: \(String(entry.barberId.prefix(8)))...")
                            .font(.system(size: 10))
                            .foregroundColor(.gray)
                    }
                    Spacer()
                    Button(action: { viewModel.removeFromQueue(entry: entry) }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.red.opacity(0.7))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
            }
        }
        .background(Color.brandInput)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.orange.opacity(0.3), lineWidth: 1))
    }

    // MARK: - Next Available Pool

    /// A card at the top of the dashboard showing all "no preference" customers.
    /// Any barber can tap Start to claim one and move them into their own queue.
    private func nextAvailablePool(_ entries: [QueueEntry]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.accent)
                Text("Next Available Pool")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.accent)
                Spacer()
                Text("\(entries.count) waiting")
                    .font(.system(size: 11))
                    .foregroundColor(.gray)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.accent.opacity(0.08))

            // Entries
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                if index > 0 {
                    Divider().background(Color.gray.opacity(0.1)).padding(.leading, 14)
                }
                HStack(spacing: 10) {
                    Text("\(index + 1)")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.accent)
                        .frame(width: 16)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.customerName)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                        Text(viewModel.serviceName(for: entry.serviceId))
                            .font(.system(size: 10))
                            .foregroundColor(.gray)
                    }

                    Spacer()

                    Text("\(entry.minutesWaiting)m ago")
                        .font(.system(size: 10))
                        .foregroundColor(.gray)

                    // Assign to a specific barber — opens the same MoveEntrySheet
                    Button(action: { movingEntry = entry }) {
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.brandSecondary)
                            .frame(width: 26, height: 26)
                            .background(Color.brandDotBg)
                            .cornerRadius(5)
                    }
                    .buttonStyle(PlainButtonStyle())

                    // Start — marks them in chair immediately without assigning first
                    Button(action: { viewModel.startService(entry: entry) }) {
                        Text("Start")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.black)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.accent)
                            .cornerRadius(5)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
            }
        }
        .background(Color.brandInput)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.accent.opacity(0.25), lineWidth: 1))
    }

    // MARK: - Barber Card

    private func barberCard(_ barber: Barber) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            barberCardHeader(barber)

            if let currentClient = viewModel.currentClientFor(barberId: barber.id ?? "") {
                Divider().background(Color.gray.opacity(0.2))
                currentClientRow(currentClient)
            }

            let waiting = viewModel.queueFor(barberId: barber.id ?? "")
                .filter { $0.status == .waiting || $0.status == .notified }
            if !waiting.isEmpty {
                Divider().background(Color.gray.opacity(0.2))
                waitingPreview(waiting)
            }

            // "+ Add to Queue" footer — owner can add for any barber
            Divider().background(Color.gray.opacity(0.15))
            Button(action: { addingForBarber = barber }) {
                HStack {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Add to Queue")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundColor(.accent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .background(Color.brandInput)
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(barber.goLive ? Color.accent.opacity(0.3) : Color.clear, lineWidth: 1)
        )
    }

    private func barberCardHeader(_ barber: Barber) -> some View {
        HStack(spacing: 12) {
            // Avatar — photo if available, otherwise colored initial circle
            ZStack {
                if let urlString = barber.photoUrl, let url = URL(string: urlString) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: 44, height: 44, alignment: .top)
                                .clipShape(Circle())
                        default:
                            Circle()
                                .fill(barber.goLive ? Color.accent : Color.brandDotBg)
                                .frame(width: 44, height: 44)
                        }
                    }
                    .frame(width: 44, height: 44)
                    .overlay(Circle().stroke(barber.goLive ? Color.accent : Color.clear, lineWidth: 2))
                } else {
                    Circle()
                        .fill(barber.goLive ? Color.accent : Color.brandDotBg)
                        .frame(width: 44, height: 44)
                    Text(String(barber.name.prefix(1)))
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(barber.goLive ? .black : .gray)
                }
            }

            // Name + status
            VStack(alignment: .leading, spacing: 3) {
                Text(barber.name)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)

                HStack(spacing: 6) {
                    statusBadge(barber.status)
                    if barber.goLive {
                        Text("LIVE")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.accent)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.accent.opacity(0.15))
                            .cornerRadius(4)
                    }
                }
            }

            Spacer()

            // Right side: Live toggle + waiting count
            VStack(alignment: .trailing, spacing: 6) {
                Button(action: { viewModel.toggleGoLive(barber: barber) }) {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(barber.goLive ? Color.accent : Color.gray.opacity(0.5))
                            .frame(width: 7, height: 7)
                        Text(barber.goLive ? "Live" : "Offline")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(barber.goLive ? .accent : .gray)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(barber.goLive ? Color.accent.opacity(0.12) : Color.gray.opacity(0.1))
                    .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())

                let waitCount = viewModel.waitingCountFor(barberId: barber.id ?? "")
                if waitCount > 0 {
                    VStack(spacing: 1) {
                        Text("\(waitCount)")
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundColor(.accent)
                        Text("waiting")
                            .font(.system(size: 9))
                            .foregroundColor(.gray)
                    }
                }
            }
        }
        .padding(14)
    }

    // MARK: - Current Client Row

    private func currentClientRow(_ entry: QueueEntry) -> some View {
        HStack(spacing: 10) {
            UpNextMark(size: 14)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(entry.customerName)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                    if entry.isAppointment == true {
                        appointmentBadge
                    }
                }
                Text(viewModel.serviceName(for: entry.serviceId))
                    .font(.system(size: 10))
                    .foregroundColor(.gray)
            }

            Spacer()

            if let startTime = entry.startTime {
                let minutes = Int(Date().timeIntervalSince(startTime) / 60)
                Text("\(minutes)m in chair")
                    .font(.system(size: 10))
                    .foregroundColor(.gray)
            }

            Button(action: { viewModel.completeService(entry: entry) }) {
                Text("Done")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.accent)
                    .cornerRadius(6)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.accent.opacity(0.05))
    }

    // MARK: - Waiting Preview

    private func waitingPreview(_ entries: [QueueEntry]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(entries.prefix(3).enumerated()), id: \.element.id) { index, entry in
                HStack(spacing: 10) {
                    Text("\(index + 1)")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.accent)
                        .frame(width: 16)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 5) {
                            Text(entry.customerName)
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.8))
                            if entry.isAppointment == true {
                                appointmentBadge
                            }
                        }
                        Text(viewModel.serviceName(for: entry.serviceId))
                            .font(.system(size: 10))
                            .foregroundColor(.gray)
                    }

                    Spacer()

                    // Move button — reassign to another barber
                    Button(action: { movingEntry = entry }) {
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.brandSecondary)
                            .frame(width: 26, height: 26)
                            .background(Color.brandDotBg)
                            .cornerRadius(5)
                    }
                    .buttonStyle(PlainButtonStyle())

                    // Start button — only for the first person when no one is in chair
                    if index == 0 && viewModel.currentClientFor(barberId: entry.assignedBarberId ?? entry.barberId) == nil {
                        Button(action: { viewModel.startService(entry: entry) }) {
                            Text("Start")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(.black)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.accent)
                                .cornerRadius(5)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                // Long-press any waiting client to remove them from the queue
                .contextMenu {
                    Button(role: .destructive) {
                        viewModel.removeFromQueue(entry: entry)
                    } label: {
                        Label("Remove from Queue", systemImage: "trash")
                    }
                }

                if index < min(entries.count, 3) - 1 {
                    Divider().background(Color.gray.opacity(0.1)).padding(.leading, 40)
                }
            }

            if entries.count > 3 {
                Text("+ \(entries.count - 3) more waiting")
                    .font(.system(size: 10))
                    .foregroundColor(.gray)
                    .padding(.vertical, 6)
            }
        }
    }

    private func statusBadge(_ status: BarberStatus) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor(status))
                .frame(width: 6, height: 6)
            Text(status.displayName)
                .font(.system(size: 10))
                .foregroundColor(.gray)
        }
    }

    private func statusColor(_ status: BarberStatus) -> Color {
        switch status {
        case .available: return .green
        case .onBreak:   return .orange
        case .off:       return .gray
        }
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(.accent)
            Text("Loading dashboard...")
                .font(.subheadline)
                .foregroundColor(.gray)
        }
    }

    // MARK: - Helpers

    /// Small blue "APT" pill shown next to appointment clients in the queue.
    private var appointmentBadge: some View {
        Text("APT")
            .font(.system(size: 9, weight: .bold))
            .foregroundColor(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Color.blue.opacity(0.7))
            .cornerRadius(4)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundColor(.gray)
            .tracking(1.2)
    }
}

// MARK: - Owner Add Entry Sheet

/// Owner adds a client directly to a specific barber's queue.
struct OwnerAddEntrySheet: View {

    @ObservedObject var viewModel: OwnerDashboardViewModel
    let barber: Barber
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var phone = ""
    @State private var selectedServiceId = ""

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !selectedServiceId.isEmpty
    }

    var body: some View {
        NavigationView {
            ZStack {
                Color.brandNearBlack.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 24) {
                        fieldSection(label: "CLIENT NAME") {
                            TextField("e.g. Marcus Johnson", text: $name)
                                .styledField()
                        }
                        fieldSection(label: "PHONE (OPTIONAL)") {
                            TextField("e.g. 254-555-0100", text: $phone)
                                .keyboardType(.phonePad)
                                .styledField()
                        }
                        fieldSection(label: "SERVICE") {
                            VStack(spacing: 0) {
                                ForEach(viewModel.services) { service in
                                    let isSelected = selectedServiceId == (service.id ?? "")
                                    Button(action: { selectedServiceId = service.id ?? "" }) {
                                        HStack {
                                            Text(service.name)
                                                .font(.subheadline)
                                                .fontWeight(isSelected ? .semibold : .regular)
                                                .foregroundColor(isSelected ? .accent : .white)
                                            Spacer()
                                            if isSelected {
                                                Image(systemName: "checkmark")
                                                    .font(.system(size: 13, weight: .semibold))
                                                    .foregroundColor(.accent)
                                            }
                                        }
                                        .padding(.horizontal, 14).padding(.vertical, 14)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                    if service.id != viewModel.services.last?.id {
                                        Divider().background(Color.gray.opacity(0.2)).padding(.leading, 14)
                                    }
                                }
                            }
                            .background(Color.brandInput).cornerRadius(12)
                        }
                        Button(action: {
                            viewModel.addManualEntry(
                                name: name.trimmingCharacters(in: .whitespaces),
                                phone: phone,
                                serviceId: selectedServiceId,
                                barberId: barber.id ?? ""
                            )
                            dismiss()
                        }) {
                            Text("Add to \(barber.name)'s Queue")
                                .font(.headline).fontWeight(.bold)
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity).padding(.vertical, 16)
                                .background(isValid ? Color.accent : Color.gray.opacity(0.3))
                                .cornerRadius(14)
                        }
                        .disabled(!isValid)
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Add to \(barber.name)'s Queue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundColor(.accent)
                }
            }
        }
    }

    private func fieldSection<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.system(size: 11, weight: .semibold)).foregroundColor(.brandSecondary).tracking(1.2)
            content()
        }
    }
}

// MARK: - Move Entry Sheet

/// Owner reassigns a waiting customer to a different barber.
struct MoveEntrySheet: View {

    @ObservedObject var viewModel: OwnerDashboardViewModel
    let entry: QueueEntry
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ZStack {
                Color.brandNearBlack.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 12) {
                        // Show who's being moved
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.customerName)
                                    .font(.headline).foregroundColor(.white)
                                Text(viewModel.serviceName(for: entry.serviceId))
                                    .font(.subheadline).foregroundColor(.accent)
                            }
                            Spacer()
                            Text("Move to...")
                                .font(.caption).foregroundColor(.brandSecondary)
                        }
                        .padding(14)
                        .background(Color.brandInput).cornerRadius(12)

                        // Barber list — tap to reassign
                        VStack(spacing: 0) {
                            ForEach(viewModel.barbers) { barber in
                                let isCurrent = barber.id == entry.barberId
                                Button(action: {
                                    if !isCurrent {
                                        viewModel.moveEntry(entry, toBarberId: barber.id ?? "")
                                    }
                                    dismiss()
                                }) {
                                    HStack(spacing: 12) {
                                        ZStack {
                                            Circle()
                                                .fill(barber.goLive ? Color.accent : Color.brandDotBg)
                                                .frame(width: 36, height: 36)
                                            Text(String(barber.name.prefix(1)).uppercased())
                                                .font(.system(size: 14, weight: .bold))
                                                .foregroundColor(barber.goLive ? .black : .gray)
                                        }
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(barber.name)
                                                .font(.subheadline).fontWeight(.semibold)
                                                .foregroundColor(isCurrent ? .brandSecondary : .white)
                                            Text("\(viewModel.waitingCountFor(barberId: barber.id ?? "")) waiting")
                                                .font(.caption).foregroundColor(.brandSecondary)
                                        }
                                        Spacer()
                                        if isCurrent {
                                            Text("current")
                                                .font(.caption).foregroundColor(.brandSecondary)
                                        } else {
                                            Image(systemName: "chevron.right")
                                                .font(.caption).foregroundColor(.brandSecondary)
                                        }
                                    }
                                    .padding(.horizontal, 14).padding(.vertical, 12)
                                }
                                .buttonStyle(PlainButtonStyle())
                                .disabled(isCurrent)

                                if barber.id != viewModel.barbers.last?.id {
                                    Divider().background(Color.gray.opacity(0.15)).padding(.leading, 62)
                                }
                            }
                        }
                        .background(Color.brandInput).cornerRadius(12)
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Move Customer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundColor(.accent)
                }
            }
        }
    }
}

// MARK: - In Chair Sheet

/// Shows every in-chair client across the shop, pulled directly from allQueueEntries.
/// Bypasses the barber-card lookup so ghost/orphaned entries are visible and removable.
struct InChairSheet: View {

    @ObservedObject var viewModel: OwnerDashboardViewModel
    @Environment(\.dismiss) private var dismiss

    // All entries with in_chair status — raw, no barber-ID filtering
    private var inChairEntries: [QueueEntry] {
        viewModel.allQueueEntries
            .filter { $0.status == .inChair }
            .sorted { $0.checkInTime < $1.checkInTime }
    }

    var body: some View {
        NavigationView {
            ZStack {
                Color.brandNearBlack.ignoresSafeArea()

                if inChairEntries.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 44))
                            .foregroundColor(.accent)
                        Text("Nobody in chair right now")
                            .font(.headline)
                            .foregroundColor(.white)
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 10) {
                            ForEach(inChairEntries) { entry in
                                inChairRow(entry)
                            }
                        }
                        .padding(20)
                    }
                }
            }
            .navigationTitle("In Chair (\(inChairEntries.count))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }.foregroundColor(.accent)
                }
            }
        }
    }

    private func inChairRow(_ entry: QueueEntry) -> some View {
        HStack(spacing: 14) {
            // Avatar initial circle
            ZStack {
                Circle()
                    .fill(Color.accent.opacity(0.15))
                    .frame(width: 44, height: 44)
                Text(String(entry.customerName.prefix(1)).uppercased())
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.accent)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(entry.customerName)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                    if entry.isAppointment == true {
                        Text("APT")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.7))
                            .cornerRadius(4)
                    }
                }
                // Show which barber + how long they've been in chair
                HStack(spacing: 6) {
                    Text(viewModel.barberName(for: entry.assignedBarberId ?? entry.barberId))
                        .font(.caption)
                        .foregroundColor(.accent)
                    if let startTime = entry.startTime {
                        Text("· \(Int(Date().timeIntervalSince(startTime) / 60))m in chair")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
                Text(viewModel.serviceName(for: entry.serviceId))
                    .font(.caption)
                    .foregroundColor(.gray)
            }

            Spacer()

            VStack(spacing: 6) {
                // Mark Done — archives and removes from queue
                Button(action: {
                    viewModel.completeService(entry: entry)
                }) {
                    Text("Done")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.accent)
                        .cornerRadius(6)
                }
                .buttonStyle(PlainButtonStyle())

                // Remove — for stuck/ghost entries
                Button(action: {
                    viewModel.removeFromQueue(entry: entry)
                }) {
                    Text("Remove")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.red.opacity(0.8))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(6)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(14)
        .background(Color.brandInput)
        .cornerRadius(14)
    }
}



// MARK: - Add To Next Available Sheet

/// Owner manually adds a walk-in to the Next Available pool from the dashboard —
/// no need to go to the kiosk. The entry gets barberId "__next__" so any barber
/// can claim it from their queue view.
struct AddToNextAvailableSheet: View {

    @ObservedObject var viewModel: OwnerDashboardViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var phone = ""
    @State private var selectedServiceId = ""

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !selectedServiceId.isEmpty
    }

    var body: some View {
        NavigationView {
            ZStack {
                Color.brandNearBlack.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 24) {

                        // Info banner explaining what "next available" means
                        HStack(spacing: 10) {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 13))
                                .foregroundColor(.accent)
                            Text("This client will go into the Next Available pool. Any barber can claim them.")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        .padding(12)
                        .background(Color.accent.opacity(0.07))
                        .cornerRadius(10)

                        fieldSection(label: "CLIENT NAME") {
                            TextField("e.g. Marcus Johnson", text: $name)
                                .styledField()
                        }
                        fieldSection(label: "PHONE (OPTIONAL)") {
                            TextField("e.g. 254-555-0100", text: $phone)
                                .keyboardType(.phonePad)
                                .styledField()
                        }
                        fieldSection(label: "SERVICE") {
                            VStack(spacing: 0) {
                                ForEach(viewModel.services) { service in
                                    let isSelected = selectedServiceId == (service.id ?? "")
                                    Button(action: { selectedServiceId = service.id ?? "" }) {
                                        HStack {
                                            Text(service.name)
                                                .font(.subheadline)
                                                .fontWeight(isSelected ? .semibold : .regular)
                                                .foregroundColor(isSelected ? .accent : .white)
                                            Spacer()
                                            if isSelected {
                                                Image(systemName: "checkmark")
                                                    .font(.system(size: 13, weight: .semibold))
                                                    .foregroundColor(.accent)
                                            }
                                        }
                                        .padding(.horizontal, 14).padding(.vertical, 14)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                    if service.id != viewModel.services.last?.id {
                                        Divider().background(Color.gray.opacity(0.2)).padding(.leading, 14)
                                    }
                                }
                            }
                            .background(Color.brandInput).cornerRadius(12)
                        }

                        Button(action: {
                            viewModel.addWalkInToNextAvailable(
                                name: name.trimmingCharacters(in: .whitespaces),
                                phone: phone,
                                serviceId: selectedServiceId
                            )
                            dismiss()
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "bolt.fill")
                                    .font(.system(size: 13))
                                Text("Add to Next Available")
                                    .font(.headline).fontWeight(.bold)
                            }
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity).padding(.vertical, 16)
                            .background(isValid ? Color.accent : Color.gray.opacity(0.3))
                            .cornerRadius(14)
                        }
                        .disabled(!isValid)
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Add Walk-in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundColor(.accent)
                }
            }
        }
    }

    private func fieldSection<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.system(size: 11, weight: .semibold)).foregroundColor(.brandSecondary).tracking(1.2)
            content()
        }
    }
}

// MARK: - TextField Style Helper

private extension View {
    func styledField() -> some View {
        self
            .padding(14)
            .background(Color.brandInput)
            .cornerRadius(12)
            .foregroundColor(.white)
            .tint(.accent)
    }
}

// MARK: - Preview

#Preview {
    OwnerDashboardView(
        viewModel: OwnerDashboardViewModel(shopId: "test-shop")
    )
}
