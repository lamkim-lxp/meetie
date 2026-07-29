import EventKit
import Foundation

/// EventKit access, Meeting mapping, change observation (§2.1, ADR 0001).
final class CalendarStore {
    enum AuthorizationState: Equatable {
        case notDetermined, requesting, authorized, denied, restricted
    }

    private let store = EKEventStore()
    private let settings: SettingsStore
    private var debounceTimer: Timer?
    private var observing = false

    private(set) var authorization: AuthorizationState = .notDetermined
    private(set) var authorizationErrorDescription: String?

    /// Debounced (~2 s) calendar-change signal; AlertScheduler recomputes on it (R5).
    var onChange: (() -> Void)?
    var onAuthorizationChange: (() -> Void)?

    init(settings: SettingsStore) {
        self.settings = settings
    }

    func start() {
        authorization = Self.authorizationState(
            for: EKEventStore.authorizationStatus(for: .event)
        )
        if authorization == .authorized {
            observeChanges()
            onChange?()
        }
        onAuthorizationChange?()
    }

    /// Called from an explicit onboarding action. Permission prompts must never
    /// appear just because the menu bar app launched.
    func requestAccess(completion: (() -> Void)? = nil) {
        guard authorization == .notDetermined else {
            completion?()
            return
        }

        authorizationErrorDescription = nil
        authorization = .requesting
        onAuthorizationChange?()
        store.requestFullAccessToEvents { [weak self] granted, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.authorizationErrorDescription = error?.localizedDescription
                self.authorization = granted ? .authorized : .denied
                if granted { self.observeChanges() }
                self.onAuthorizationChange?()
                self.onChange?()
                completion?()
            }
        }
    }

    private func observeChanges() {
        guard !observing else { return }
        observing = true
        NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: .main
        ) { [weak self] _ in
            self?.scheduleChangeSignal()
        }
    }

    private func scheduleChangeSignal() {
        debounceTimer?.invalidate()
        let timer = Timer(timeInterval: 2.0, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.refreshAuthorization()
            self.onChange?()
        }
        RunLoop.main.add(timer, forMode: .common)
        debounceTimer = timer
    }

    /// Permission can be revoked mid-run (R22, edge table).
    func refreshAuthorization() {
        guard authorization != .requesting else { return }
        let status = EKEventStore.authorizationStatus(for: .event)
        let newState = Self.authorizationState(for: status)
        if newState != authorization {
            authorization = newState
            authorizationErrorDescription = nil
            if newState == .authorized {
                observeChanges()
                onChange?()
            }
            onAuthorizationChange?()
        }
    }

    static func authorizationState(for status: EKAuthorizationStatus) -> AuthorizationState {
        if status == .fullAccess {
            return .authorized
        }
        switch status {
        case .notDetermined:
            return .notDetermined
        case .restricted:
            return .restricted
        case .denied, .writeOnly:
            return .denied
        default:
            return .denied
        }
    }

    var allCalendars: [EKCalendar] {
        guard authorization == .authorized else { return [] }
        return store.calendars(for: .event).sorted {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    var calendarCount: Int {
        allCalendars.count
    }

    var exchangeCalendarNames: [String] {
        let names = allCalendars
            .filter { $0.source?.sourceType == .exchange }
            .map(\.title)
        return Array(Set(names)).sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

    /// Meetings on Watched Calendars overlapping [now, now + interval], filtered per R2–R4.
    func upcomingMeetings(within interval: TimeInterval = 12 * 3600) -> [Meeting] {
        guard authorization == .authorized else { return [] }
        let calendars = store.calendars(for: .event).filter {
            settings.isWatched(calendarID: $0.calendarIdentifier)
        }
        guard !calendars.isEmpty else { return [] }
        let now = Date()
        let predicate = store.predicateForEvents(
            withStart: now, end: now.addingTimeInterval(interval), calendars: calendars
        )
        return store.events(matching: predicate)
            .compactMap(meeting(from:))
            .sorted { $0.start < $1.start }
    }

    private func meeting(from event: EKEvent) -> Meeting? {
        guard !event.isAllDay else { return nil }                       // R2
        guard event.status != .canceled else { return nil }             // R3
        if let attendees = event.attendees,
           let me = attendees.first(where: { $0.isCurrentUser }),
           me.participantStatus == .declined {
            return nil                                                  // R3
        }
        guard let start = event.startDate, let end = event.endDate else { return nil }
        let baseID = event.eventIdentifier ?? event.calendarItemIdentifier
        return Meeting(
            occurrenceID: "\(baseID)#\(start.timeIntervalSinceReferenceDate)",
            title: event.title ?? "Untitled",
            start: start,
            end: end,
            joinURL: JoinURLDetector.joinURL(
                urlField: event.url, location: event.location, notes: event.notes
            ),
            venue: event.location,
            details: event.notes,
            calendarID: event.calendar?.calendarIdentifier ?? ""
        )
    }
}
