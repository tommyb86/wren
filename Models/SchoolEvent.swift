import Foundation
import SwiftData
import WrenCore

/// One event from the personal calendar feed, stored so the week ahead reads
/// instantly and survives being offline.
///
/// Keyed on the iCal `uid`, so a moved or renamed event updates in place rather
/// than turning up twice. Past events are pruned on refresh — this is a "what's
/// coming" view, not an archive.
@Model
final class SchoolEvent {
    var uid: String = ""
    var title: String = ""
    var location: String = ""
    var start: Date = Date.distantPast
    var end: Date?
    var allDay: Bool = false
    /// When the feed last carried this event, for pruning.
    var lastSeen: Date = Date()

    init(
        uid: String = "",
        title: String = "",
        location: String = "",
        start: Date = .distantPast,
        end: Date? = nil,
        allDay: Bool = false,
        lastSeen: Date = Date()
    ) {
        self.uid = uid
        self.title = title
        self.location = location
        self.start = start
        self.end = end
        self.allDay = allDay
        self.lastSeen = lastSeen
    }
}

extension SchoolEvent {
    convenience init(from event: SchoolCalendarEvent) {
        self.init(
            uid: event.uid,
            title: event.title,
            location: event.location,
            start: event.start,
            end: event.end,
            allDay: event.allDay
        )
    }

    /// The pure-value form, for the correlation engine in WrenCore.
    var calendarEvent: SchoolCalendarEvent {
        SchoolCalendarEvent(uid: uid, title: title, location: location, start: start, end: end, allDay: allDay)
    }

    func merge(_ event: SchoolCalendarEvent) {
        title = event.title
        location = event.location
        start = event.start
        end = event.end
        allDay = event.allDay
        lastSeen = Date()
    }

    /// When the event is over — an event with no end is treated as its start.
    var finish: Date { end ?? start }
}
