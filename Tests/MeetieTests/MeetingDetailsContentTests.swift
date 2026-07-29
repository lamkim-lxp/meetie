import Foundation
import Testing
@testable import Meetie

struct MeetingDetailsContentTests {
    @Test func trimsTheMeetingName() {
        let content = MeetingDetailsContent(meeting: makeMeeting(title: "  Weekly sync  "))

        #expect(content.name == "Weekly sync")
    }

    @Test func usesFallbackForBlankVenue() {
        let content = MeetingDetailsContent(meeting: makeMeeting(venue: " \n "))

        #expect(content.venue == "Not specified")
    }

    @Test func usesFallbackForMissingDescription() {
        let content = MeetingDetailsContent(meeting: makeMeeting(details: nil))

        #expect(content.description == "No description")
    }

    @Test func formatsTheDateAndTimeRange() {
        let content = MeetingDetailsContent(
            meeting: makeMeeting(),
            locale: Locale(identifier: "en_US_POSIX"),
            timeZone: TimeZone(secondsFromGMT: 0)!
        )

        #expect(content.date.contains("Jul 29, 2026"))
        #expect(content.date.contains("6:00"))
        #expect(content.date.contains("7:30"))
    }

    private func makeMeeting(
        title: String = "Weekly sync",
        venue: String? = "Conference Room A",
        details: String? = "Roadmap review"
    ) -> Meeting {
        Meeting(
            occurrenceID: "test-meeting",
            title: title,
            start: ISO8601DateFormatter().date(from: "2026-07-29T06:00:00Z")!,
            end: ISO8601DateFormatter().date(from: "2026-07-29T07:30:00Z")!,
            joinURL: URL(string: "https://example.com"),
            venue: venue,
            details: details,
            calendarID: "test-calendar"
        )
    }
}
