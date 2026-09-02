import Foundation
import SwiftData
import WrenCore

/// A bin and the night it goes out. `colorHex` is the actual lid colour — bins
/// are the deliberate exception to the "sage is the only accent" rule, because
/// they map to physical objects in the yard.
@Model
final class BinCollection {
    /// Stable across edits, so notification identifiers stay idempotent.
    var binID: UUID = UUID()
    var name: String = ""
    var colorHex: String = "#4A7C6F"
    var scheduleData: Data = Data()
    /// Lead time for the reminder. 14 hours before a morning collection lands
    /// the evening before, which is when the bin actually has to go out.
    var reminderHoursBefore: Int = 14
    var isActive: Bool = true
    var sortOrder: Int = 0

    init(
        binID: UUID = UUID(),
        name: String = "",
        colorHex: String = "#4A7C6F",
        schedule: Schedule? = nil,
        reminderHoursBefore: Int = 14,
        isActive: Bool = true,
        sortOrder: Int = 0
    ) {
        self.binID = binID
        self.name = name
        self.colorHex = colorHex
        self.scheduleData = (try? schedule?.encoded()) ?? Data()
        self.reminderHoursBefore = reminderHoursBefore
        self.isActive = isActive
        self.sortOrder = sortOrder
    }
}

extension BinCollection {
    /// A corrupt blob degrades to "unscheduled" rather than taking a screen down.
    var schedule: Schedule? {
        guard !scheduleData.isEmpty else { return nil }
        return Schedule.lenientlyDecoded(from: scheduleData)
    }

    func apply(_ schedule: Schedule) {
        scheduleData = (try? schedule.encoded()) ?? Data()
    }

    /// Bridge into WrenCore, which knows nothing about SwiftData.
    var binSchedule: BinSchedule? {
        schedule.map { BinSchedule(id: binID, schedule: $0) }
    }

    func nextCollection(after date: Date = Date(), calendar: Calendar = .current) -> Date? {
        guard let schedule else { return nil }
        return ScheduleEngine.next(schedule, after: date, calendar: calendar)
    }
}
