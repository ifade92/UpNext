//
//  AnalyticsViewModel.swift
//  UpNext
//
//  Powers the Analytics tab for both the owner dashboard and individual barber view.
//
//  Owner:  sees shop-wide stats + leaderboard across all barbers
//  Barber: sees only their own completions filtered by barberId
//
//  Data source: shops/{shopId}/queueHistory where status == "completed"
//  Fetches the last 90 days so the busiest-day chart has enough data to be meaningful.
//

import Foundation
import Combine

@MainActor
class AnalyticsViewModel: ObservableObject {

    // MARK: - Published State

    @Published var entries: [QueueEntry] = []   // All completed entries for the period
    @Published var barbers: [Barber] = []        // Full barber list (for owner leaderboard)
    @Published var isLoading = true
    @Published var errorMessage: String? = nil

    // MARK: - Config

    let shopId: String
    /// nil = owner view (show all barbers). Set = barber view (filter to just this barber).
    let filterBarberId: String?

    private let firebase = FirebaseService.shared

    // MARK: - Init

    init(shopId: String, filterBarberId: String? = nil) {
        self.shopId = shopId
        self.filterBarberId = filterBarberId
    }

    // MARK: - Load Data

    /// Pull the last 90 days of completed entries from Firestore.
    /// 90 days gives the busiest-day chart enough history to show real patterns.
    func loadData() async {
        isLoading = true
        errorMessage = nil

        do {
            // Fetch 90 days back so the weekday chart has enough data
            let ninetyDaysAgo = Calendar.current.date(byAdding: .day, value: -90, to: Date()) ?? Date()
            var fetched = try await firebase.fetchCompletedEntries(shopId: shopId, since: ninetyDaysAgo)

            // Appointments are excluded from all analytics — they're not walk-in counts.
            // The daily/weekly/monthly totals, weekday chart, and leaderboard
            // should only reflect walk-in and manually-added clients.
            fetched = fetched.filter { $0.isAppointment != true }

            // If this is a barber view, filter down to just their entries
            if let barberId = filterBarberId {
                fetched = fetched.filter {
                    ($0.assignedBarberId ?? $0.barberId) == barberId
                }
            }

            entries = fetched

            // Owner view also needs the barber list for the leaderboard
            if filterBarberId == nil {
                barbers = try await firebase.fetchAllBarbers(shopId: shopId)
            }

        } catch {
            errorMessage = "Couldn't load analytics. Pull to refresh."
        }

        isLoading = false
    }

    func refresh() async {
        await loadData()
    }

    func clearError() { errorMessage = nil }

    // MARK: - Date Helpers

    private var calendar: Calendar { Calendar.current }

    private var startOfToday: Date {
        calendar.startOfDay(for: Date())
    }

    private var startOfThisWeek: Date {
        // Uses the locale's first weekday (Sunday in US)
        calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())) ?? startOfToday
    }

    private var startOfThisMonth: Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: Date())) ?? startOfToday
    }

    // MARK: - Period Filters

    /// Entries completed today
    var todayEntries: [QueueEntry] {
        entries.filter { $0.checkInTime >= startOfToday }
    }

    /// Entries completed this calendar week (Sun–Sat)
    var thisWeekEntries: [QueueEntry] {
        entries.filter { $0.checkInTime >= startOfThisWeek }
    }

    /// Entries completed this calendar month
    var thisMonthEntries: [QueueEntry] {
        entries.filter { $0.checkInTime >= startOfThisMonth }
    }

    // MARK: - Count Shortcuts

    var todayCount: Int    { todayEntries.count }
    var thisWeekCount: Int { thisWeekEntries.count }
    var thisMonthCount: Int { thisMonthEntries.count }

    // MARK: - Busiest Day Chart
    // Uses ALL 90 days of data so the chart reflects long-term patterns,
    // not just this week's noise.

    struct WeekdayBar: Identifiable {
        let id = UUID()
        let shortName: String   // "Mon", "Tue", etc.
        let count: Int          // total completions on this weekday across 90 days
        let isToday: Bool       // highlight today's column
    }

    /// Returns 7 bars (Sun → Sat) with total walk-in counts per weekday over the last 90 days.
    var weekdayBars: [WeekdayBar] {
        let names = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        var counts = [Int](repeating: 0, count: 7)
        let todayWeekday = calendar.component(.weekday, from: Date()) - 1 // 0-indexed

        for entry in entries {
            // .weekday returns 1 = Sunday … 7 = Saturday, so subtract 1 for 0-indexed
            let wd = calendar.component(.weekday, from: entry.checkInTime) - 1
            counts[wd] += 1
        }

        return names.enumerated().map { i, name in
            WeekdayBar(shortName: name, count: counts[i], isToday: i == todayWeekday)
        }
    }

    // MARK: - Leaderboard (Owner only)

    struct LeaderboardEntry: Identifiable {
        let id = UUID()
        let barber: Barber
        let count: Int
        let rank: Int
    }

    /// Sorted leaderboard for a given set of entries (today / week / month).
    /// Filters out barbers with 0 completions so the list stays clean.
    func leaderboard(for periodEntries: [QueueEntry]) -> [LeaderboardEntry] {
        // Group by the barber who actually did the work (assignedBarberId takes priority)
        let grouped = Dictionary(grouping: periodEntries) {
            $0.assignedBarberId ?? $0.barberId
        }

        let sorted = barbers.compactMap { barber -> (Barber, Int)? in
            guard let id = barber.id else { return nil }
            let count = grouped[id]?.count ?? 0
            guard count > 0 else { return nil }
            return (barber, count)
        }
        .sorted { $0.1 > $1.1 }  // highest count first

        return sorted.enumerated().map { i, pair in
            LeaderboardEntry(barber: pair.0, count: pair.1, rank: i + 1)
        }
    }

    // MARK: - Barber Personal Rank (Barber view)

    /// Returns "You're #N this week" style text for a barber's personal view.
    /// Requires the full barber list to compute rank among peers.
    func personalRank(barberId: String, in periodEntries: [QueueEntry], allEntries: [QueueEntry]) -> Int? {
        // Count completions for every barber in the period
        let grouped = Dictionary(grouping: periodEntries) {
            $0.assignedBarberId ?? $0.barberId
        }
        let myCount = grouped[barberId]?.count ?? 0
        guard myCount > 0 else { return nil }

        // Count how many barbers beat this barber's count
        let beatenBy = grouped.filter { $0.key != barberId && ($0.value.count > myCount) }.count
        return beatenBy + 1
    }
}
