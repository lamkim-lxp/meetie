import Foundation

/// Owns active AlertControllers; the seam between scheduler, overlay, and Test Dog.
final class AlertCoordinator {
    private(set) var active: [AlertController] = []
    private let overlay: OverlayManager
    private let sound: SoundPlayer

    init(overlay: OverlayManager, sound: SoundPlayer) {
        self.overlay = overlay
        self.sound = sound
    }

    func startAlert(for meeting: Meeting) {
        start(AlertController(meeting: meeting, isTest: false, sound: sound))
    }

    /// Test Dog (R21): full fake Alert through the real pipeline,
    /// self-clears after 30 s (start == end).
    func startTestAlert() {
        let expiry = Date().addingTimeInterval(30)
        let meeting = Meeting(
            occurrenceID: "test-\(UUID().uuidString)",
            title: "Test Dog - click me!",
            start: expiry,
            end: expiry,
            joinURL: URL(string: "https://example.com"),
            venue: "Meetie's Dog Park",
            details: "A sample meeting for checking the alert details and actions.",
            calendarID: ""
        )
        start(AlertController(meeting: meeting, isTest: true, sound: sound))
    }

    private func start(_ controller: AlertController) {
        controller.onFinished = { [weak self] alert in self?.remove(alert) }
        active.append(controller)
        overlay.attach(controller)
    }

    /// Tears down Alerts whose Meeting no longer exists in the store (edge table).
    func reconcile(with meetings: [Meeting]) {
        let ids = Set(meetings.map(\.occurrenceID))
        for alert in active where !alert.isTest && !ids.contains(alert.meeting.occurrenceID) {
            alert.expire()
        }
    }

    private func remove(_ alert: AlertController) {
        overlay.detach(alert)
        active.removeAll { $0 === alert }
    }
}
