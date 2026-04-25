//
//  OwnerAnalyticsView.swift
//  UpNext
//
//  Shop-wide analytics for the owner.
//  Shows total walk-ins for today / this week / this month,
//  a bar chart of the busiest day of the week, and a leaderboard
//  showing which barber served the most clients per period.
//
//  Data comes from AnalyticsViewModel which queries queueHistory.
//

import SwiftUI
import Charts

struct OwnerAnalyticsView: View {

    @StateObject private var viewModel: AnalyticsViewModel
    // Which period the leaderboard is scoped to
    @State private var leaderboardPeriod: Period = .week

    enum Period: String, CaseIterable {
        case today = "Today"
        case week  = "Week"
        case month = "Month"
    }

    init(shopId: String) {
        _viewModel = StateObject(wrappedValue: AnalyticsViewModel(shopId: shopId))
    }

    var body: some View {
        ZStack {
            Color.brandNearBlack.ignoresSafeArea()

            if viewModel.isLoading {
                loadingView
            } else {
                ScrollView {
                    VStack(spacing: 20) {
                        headerSection
                        statsRow
                        busiestDayChart
                        leaderboardSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 32)
                }
                .refreshable { await viewModel.refresh() }
            }
        }
        .task { await viewModel.loadData() }
        .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") { viewModel.clearError() }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView().tint(.accent)
            Text("Loading analytics…")
                .font(.caption)
                .foregroundColor(.brandSecondary)
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Analytics")
                    .font(.brandTitle2)
                    .foregroundColor(.white)
                Text("Last 90 days")
                    .font(.brandSubheadline)
                    .foregroundColor(.accent)
            }
            Spacer()
            // Trophy icon — purely decorative to give the section identity
            ZStack {
                Circle()
                    .fill(Color.accent.opacity(0.12))
                    .frame(width: 40, height: 40)
                Image(systemName: "trophy.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.accent)
            }
        }
        .padding(.top, 16)
    }

    // MARK: - Stats Row  (Today / This Week / This Month)

    private var statsRow: some View {
        HStack(spacing: 10) {
            statCard(value: viewModel.todayCount,     label: "Today",   icon: "sun.max.fill",         color: .accent)
            statCard(value: viewModel.thisWeekCount,  label: "Week",    icon: "calendar.badge.clock", color: Color(red: 0.40, green: 0.60, blue: 1.00))
            statCard(value: viewModel.thisMonthCount, label: "Month",   icon: "calendar",             color: Color(red: 0.80, green: 0.50, blue: 1.00))
        }
    }

    private func statCard(value: Int, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(color)
            Text("\(value)")
                .font(.system(size: 28, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.brandSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Color.brandInput)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(color.opacity(0.2), lineWidth: 1))
    }

    // MARK: - Busiest Day Chart

    private var busiestDayChart: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Section title
            HStack(spacing: 8) {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.accent)
                Text("Busiest Day of the Week")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
                Text("90-day total")
                    .font(.system(size: 11))
                    .foregroundColor(.brandSecondary)
            }

            if viewModel.weekdayBars.allSatisfy({ $0.count == 0 }) {
                // No data yet
                emptyChartPlaceholder
            } else {
                Chart(viewModel.weekdayBars) { bar in
                    BarMark(
                        x: .value("Day",   bar.shortName),
                        y: .value("Count", bar.count)
                    )
                    // Highlight the current day of the week in a brighter green
                    .foregroundStyle(bar.isToday ? Color.accent : Color.accent.opacity(0.45))
                    .cornerRadius(5)
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(Color.white.opacity(0.06))
                        AxisValueLabel()
                            .foregroundStyle(Color.brandSecondary)
                            .font(.system(size: 10))
                    }
                }
                .chartXAxis {
                    AxisMarks { value in
                        AxisValueLabel()
                            .foregroundStyle(Color.brandSecondary)
                            .font(.system(size: 11, weight: .semibold))
                    }
                }
                .frame(height: 160)
                .chartPlotStyle { plot in
                    plot.background(Color.clear)
                }
            }
        }
        .padding(16)
        .background(Color.brandInput)
        .cornerRadius(14)
    }

    private var emptyChartPlaceholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.bar")
                .font(.system(size: 28))
                .foregroundColor(.brandSecondary)
            Text("No data yet — check back after your first completed walk-ins.")
                .font(.caption)
                .foregroundColor(.brandSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(height: 120)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Leaderboard

    private var leaderboardSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header + period picker
            HStack(spacing: 8) {
                Image(systemName: "list.number")
                    .font(.system(size: 12))
                    .foregroundColor(.accent)
                Text("Leaderboard")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
            }

            // Today / Week / Month toggle
            Picker("Period", selection: $leaderboardPeriod) {
                ForEach(Period.allCases, id: \.self) { period in
                    Text(period.rawValue).tag(period)
                }
            }
            .pickerStyle(.segmented)
            .tint(.accent)

            // Leaderboard rows
            let rows = leaderboardRows
            if rows.isEmpty {
                Text("No completed walk-ins for this period yet.")
                    .font(.caption)
                    .foregroundColor(.brandSecondary)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { i, entry in
                        leaderboardRow(entry: entry, isLast: i == rows.count - 1)
                    }
                }
                .background(Color.brandInput)
                .cornerRadius(12)
            }
        }
        .padding(16)
        .background(Color.brandInput)
        .cornerRadius(14)
    }

    private var leaderboardRows: [AnalyticsViewModel.LeaderboardEntry] {
        switch leaderboardPeriod {
        case .today: return viewModel.leaderboard(for: viewModel.todayEntries)
        case .week:  return viewModel.leaderboard(for: viewModel.thisWeekEntries)
        case .month: return viewModel.leaderboard(for: viewModel.thisMonthEntries)
        }
    }

    private func leaderboardRow(entry: AnalyticsViewModel.LeaderboardEntry, isLast: Bool) -> some View {
        HStack(spacing: 12) {
            // Rank badge — gold/silver/bronze for top 3, plain number otherwise
            ZStack {
                Circle()
                    .fill(rankColor(entry.rank).opacity(0.15))
                    .frame(width: 32, height: 32)
                Text(rankLabel(entry.rank))
                    .font(.system(size: entry.rank <= 3 ? 14 : 12, weight: .bold))
                    .foregroundColor(rankColor(entry.rank))
            }

            // Barber avatar initial
            ZStack {
                Circle()
                    .fill(Color.accent.opacity(0.15))
                    .frame(width: 36, height: 36)
                Text(String(entry.barber.name.prefix(1)).uppercased())
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.accent)
            }

            // Barber name
            Text(entry.barber.name)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.white)

            Spacer()

            // Count + label
            VStack(alignment: .trailing, spacing: 1) {
                Text("\(entry.count)")
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                Text("served")
                    .font(.system(size: 10))
                    .foregroundColor(.brandSecondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(Color.brandInput)

        // Divider between rows except the last
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle()
                    .fill(Color.white.opacity(0.06))
                    .frame(height: 1)
                    .padding(.leading, 60)
            }
        }
    }

    // MARK: - Rank Helpers

    private func rankLabel(_ rank: Int) -> String {
        switch rank {
        case 1: return "🥇"
        case 2: return "🥈"
        case 3: return "🥉"
        default: return "\(rank)"
        }
    }

    private func rankColor(_ rank: Int) -> Color {
        switch rank {
        case 1: return Color(red: 1.0, green: 0.84, blue: 0.0)  // gold
        case 2: return Color(red: 0.75, green: 0.75, blue: 0.75) // silver
        case 3: return Color(red: 0.80, green: 0.50, blue: 0.20) // bronze
        default: return .brandSecondary
        }
    }
}
