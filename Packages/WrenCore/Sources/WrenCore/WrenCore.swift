import Foundation

/// Pure-Foundation core. No UIKit, no SwiftUI, no SwiftData — so this package
/// compiles and tests on any platform with a Swift toolchain, including Windows.
///
/// Phase 0 keeps this deliberately near-empty: it exists to prove the
/// `swift test` leg of the pipeline. Schedule, ScheduleEngine, Money and
/// BillingPeriod land in Phase 1 onwards.
public enum WrenCore {
    public static let version = "0.1.0"

    /// Australian financial year containing `date`: 1 July – 30 June.
    /// Returns the starting calendar year, so 2026-08-01 -> 2026 (FY2026/27).
    public static func financialYear(of date: Date, calendar: Calendar = .current) -> Int {
        let parts = calendar.dateComponents([.year, .month], from: date)
        guard let year = parts.year, let month = parts.month else { return 0 }
        return month >= 7 ? year : year - 1
    }
}
