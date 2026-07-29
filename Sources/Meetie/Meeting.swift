import Foundation

/// A timed (non-all-day) event on a Watched Calendar the user has not declined (R2).
struct Meeting: Equatable {
    /// eventIdentifier + occurrence start date — distinguishes occurrences of recurring events (§2.1).
    let occurrenceID: String
    let title: String
    let start: Date
    let end: Date
    let joinURL: URL?
    let venue: String?
    let details: String?
    let calendarID: String

    /// The Alert's fire moment: leadTime seconds before start (R6);
    /// leadTime 0 = when the meeting starts.
    func alertFireDate(leadTime: TimeInterval) -> Date {
        start.addingTimeInterval(-leadTime)
    }
}
