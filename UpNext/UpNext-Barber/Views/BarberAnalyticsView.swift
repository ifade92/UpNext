//
//  BarberAnalyticsView.swift
//  UpNext
//
//  Personal analytics for an individual barber.
//  Shows only their own completed walk-ins: today / week / month counts,
//  their busiest day chart, and a "your rank" hint compared to the shop.
//
//  Reuses AnalyticsViewModel with filterBarberId set so all computations
//  are scoped to just this barber's entries.
//

import SwiftUI
import Charts

struct BarberAnalyticsView: View {

    // Two separate ViewModels:
    // - personal: filtered to just this barber (for their own stats + chart)
    // - shop: unfiltered (needed to compute rank among all barbers)
    @StateObject private var personal: AnalyticsViewModel
    @StateObject private var shop: AnalyticsViewModel

    let barberId: String
    let barberName: String

    init(shopId: String, barberId: String, barberName: String) {
        self.barberId   = barberId
        self.barberName = barberName
        _personal = StateObject(wrappedValue: AnalyticsViewModel(shopId: shopId, filterBarberId: barberId))
        _shop     = StateObject(wrappedValue: AnalyticsViewModel(shopId: shopId))
    }

    var body: some View {
        ZStack {
            Color.brandNearBlack.ignoresSafeArea()

            if personal.isLoading {
                loadingView
            } else {
                ScrollView {
                    VStack(spacing: 20) {
                        headerSection
                        rankBanner
                        statsRow
                        busiestDayChart
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 32)
                }
                .refreshable {
                    await personal.refresh()
                    await shop.refresh()
                }
            }
        }
        .task {
            // Load both in parallel
            async let p: () = personal.loadData()
            async let s: () = shop.loadData()
            _ = await (p, s)
        }
        .alert("Error", isPresented: .constant(personal.errorMessage != nil)) {
            Button("OK") { personal.clearError() }
        } message: {
            Text(personal.errorMessage ?? "")
        }
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView().tint(.accent)
            Text("Loading your stats…")
                .font(.caption)
                .foregroundColor(.brandSecondary)
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("My Analytics")
                    .font(.brandTitle2)
                    .foregroundColor(.white)
                Text("Your performance, last 90 days")
                    .font(.brandSubheadline)
                    .foregroundColor(.accent)
            }
            Spacer()
            ZStack {
                Circle()
                    .fill(Color.accent.opacity(0.12))
                    .frame(width: 40, height: 40)
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 16))
                    .foregroundColor(.accent)
            }
        }
        .padding(.top, 16)
    }

    // MARK: - Rank Banner
    // Shows how the barber is ranked this week relative to their teammates.
    // Only appears if there's enough data to compute a meaningful rank.

    @ViewBuilder
    private var rankBanner: some View {
        let weekRank = shop.personalRank(
            barberId: barberId,
            in: shop.thisWeekEntries,
            allEntries: shop.entries
        )
        let monthRank = shop.personalRank(
            barberId: barberId,
            in: shop.thisMonthEntries,
            allEntries: shop.entries
        )

        if let rank = weekRank ?? monthRank {
            let period = weekRank != nil ? "this week" : "this month"
            let emoji  = rank == 1 ? "🔥" : rank == 2 ? "💪" : "📈"

            HStack(spacing: 12) {
                Text(emoji)
                    .font(.system(size: 22))
                VStack(alignment: .leading, spacing: 2) {
                    Text("You're #\(rank) \(period)")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    Text("Keep it up, \(barberName.components(separatedBy: " ").first ?? barberName)!")
                        .font(.caption)
                        .foregroundColor(.brandSecondary)
                }
                Spacer()
            }
            .padding(14)
            .background(Color.accent.opacity(0.08))
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.accent.opacity(0.2), lineWidth: 1))
        }
    }

    // MARK: - Stats Row

    private var statsRow: some View {
        HStack(spacing: 10) {
            statCard(value: personal.todayCount,     label: "Today",  icon: "sun.max.fill",          color: .accent)
            statCard(value: personal.thisWeekCount,  label: "Week",   icon: "calendar.badge.clock",  color: Color(red: 0.40, green: 0.60, blue: 1.00))
            statCard(value: personal.thisMonthCount, label: "Month",  icon: "calendar",              color: Color(red: 0.80, green: 0.50, blue: 1.00))
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
            HStack(spacing: 8) {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.accent)
                Text("Your Busiest Day")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
                Text("90-day total")
                    .font(.system(size: 11))
                    .foregroundColor(.brandSecondary)
            }

            if personal.weekdayBars.allSatisfy({ $0.count == 0 }) {
                VStack(spacing: 8) {
                    Image(systemName: "chart.bar")
                        .font(.system(size: 28))
                        .foregroundColor(.brandSecondary)
                    Text("Complete some walk-ins to see your busiest days.")
                        .font(.caption)
                        .foregroundColor(.brandSecondary)
                        .multilineTextAlignment(.center)
                }
                .frame(height: 120)
                .frame(maxWidth: .infinity)
            } else {
                Chart(personal.weekdayBars) { bar in
                    BarMark(
                        x: .value("Day",   bar.shortName),
                        y: .value("Count", bar.count)
                    )
                    .foregroundStyle(bar.isToday ? Color.accent : Color.accent.opacity(0.45))
                    .cornerRadius(5)
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                            .foregroundStyle(Color.white.opacity(0.06))
                        AxisValueLabel()
                            .foregroundStyle(Color.brandSecondary)
                            .font(.system(size: 10))
                    }
                }
                .chartXAxis {
                    AxisMarks { _ in
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
}
