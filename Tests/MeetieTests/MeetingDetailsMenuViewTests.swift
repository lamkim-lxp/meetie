import AppKit
import Testing
@testable import Meetie

@MainActor
struct MeetingDetailsMenuViewTests {
    @Test func hidesJoinButtonWithoutMeetingLink() {
        let view = makeView(joinURL: nil)

        #expect(joinButton(in: view) == nil)
    }

    @Test func showsBlueJoinButtonWithMeetingLink() {
        let view = makeView(joinURL: URL(string: "https://meet.google.com/abc-defg-hij"))
        let button = joinButton(in: view)

        #expect(button != nil)
        #expect(button?.bezelColor == NSColor.systemBlue)
    }

    private func makeView(joinURL: URL?) -> MeetingDetailsMenuView {
        MeetingDetailsMenuView(
            meeting: Meeting(
                occurrenceID: "menu-view-test",
                title: "Weekly sync",
                start: Date(),
                end: Date().addingTimeInterval(1800),
                joinURL: joinURL,
                venue: nil,
                details: nil,
                calendarID: "test-calendar"
            ),
            onDismiss: {},
            onJoin: {}
        )
    }

    private func joinButton(in view: NSView) -> NSButton? {
        for subview in view.subviews {
            if let button = subview as? NSButton,
               button.identifier == MeetingDetailsMenuView.joinButtonIdentifier {
                return button
            }
            if let button = joinButton(in: subview) {
                return button
            }
        }
        return nil
    }
}
