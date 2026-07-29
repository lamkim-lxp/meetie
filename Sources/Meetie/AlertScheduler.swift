import AppKit
import Foundation

/// Computes the next fire moment (start − notify-at lead, §2.2) and owns a
/// single armed timer for it.
final class AlertScheduler {
    private let calendar: CalendarStore
    private let alerts: AlertCoordinator
    private let settings: SettingsStore
    private var timer: Timer?
    private var armedFireDate: Date?
    /// occurrenceID → meeting end. Guarantees once-only firing across recomputes
    /// (R6, R8); in-memory only — the skip rule makes persistence unnecessary (§2.2).
    private var handled: [String: Date] = [:]

    var onScheduleChanged: (() -> Void)?

    init(calendar: CalendarStore, alerts: AlertCoordinator, settings: SettingsStore) {
        self.calendar = calendar
        self.alerts = alerts
        self.settings = settings
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.recompute() }
        NotificationCenter.default.addObserver(
            forName: .NSSystemClockDidChange, object: nil, queue: .main
        ) { [weak self] _ in self?.recompute() }
    }

    func recompute() {
        timer?.invalidate()
        timer = nil
        armedFireDate = nil

        let now = Date()
        handled = handled.filter { $0.value > now }

        guard calendar.authorization == .authorized else {
            // Scheduler idles; menu bar shows the warning state (R22).
            alerts.reconcile(with: [])
            onScheduleChanged?()
            return
        }

        let meetings = calendar.upcomingMeetings()
        // Deleted/declined/moved Meetings tear their on-screen Alerts down (edge table).
        alerts.reconcile(with: meetings)

        // Skip rule (R9): only future fire moments are eligible.
        let lead = settings.alertLeadTime
        let eligible = meetings.filter {
            handled[$0.occurrenceID] == nil && $0.alertFireDate(leadTime: lead) > now
        }
        if let next = eligible.min(by: {
            $0.alertFireDate(leadTime: lead) < $1.alertFireDate(leadTime: lead)
        }) {
            arm(at: next.alertFireDate(leadTime: lead))
        }
        onScheduleChanged?()
    }

    private func arm(at date: Date) {
        armedFireDate = date
        let timer = Timer(fire: date, interval: 0, repeats: false) { [weak self] _ in
            self?.timerFired()
        }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func timerFired() {
        guard let armed = armedFireDate else { return }
        let now = Date()
        // Slept through the moment: discarded, never replayed (R9).
        if now.timeIntervalSince(armed) > 3.0 {
            recompute()
            return
        }
        // Multiple Meetings sharing one fire moment each get their own Alert (R10).
        let lead = settings.alertLeadTime
        for meeting in calendar.upcomingMeetings()
        where handled[meeting.occurrenceID] == nil
            && abs(meeting.alertFireDate(leadTime: lead).timeIntervalSince(armed)) < 0.5 {
            handled[meeting.occurrenceID] = meeting.end
            alerts.startAlert(for: meeting)
        }
        recompute()
    }
}
