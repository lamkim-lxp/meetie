import AppKit
import EventKit
import ServiceManagement

/// NSStatusItem with countdown text; the dropdown is the entire settings surface (§1.4).
final class MenuBarController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let calendar: CalendarStore
    private let settings: SettingsStore
    private let scheduler: AlertScheduler
    private let alerts: AlertCoordinator
    private let menu = NSMenu()
    private var refreshTimer: Timer?
    var onShowOnboarding: (() -> Void)?
    /// Refreshed on scheduler recomputes (event-driven); the 15 s timer only
    /// reformats from this cache — no periodic EventKit queries (R25).
    private var cachedUpcoming: [Meeting] = []

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        f.dateStyle = .none
        return f
    }()

    private static let dayTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEE j:mm")
        return f
    }()

    init(calendar: CalendarStore, settings: SettingsStore,
         scheduler: AlertScheduler, alerts: AlertCoordinator) {
        self.calendar = calendar
        self.settings = settings
        self.scheduler = scheduler
        self.alerts = alerts
        super.init()
    }

    func install() {
        statusItem.button?.image = Assets.menuBarIcon()
        statusItem.button?.imagePosition = .imageLeading
        statusItem.button?.font = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        menu.delegate = self
        menu.autoenablesItems = false
        statusItem.menu = menu

        // R20: updates at least once per minute.
        let timer = Timer(timeInterval: 15, repeats: true) { [weak self] _ in
            self?.refreshTitle()
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
        refreshSchedule()
    }

    // MARK: - Countdown title (R20, R22)

    func refreshSchedule() {
        cachedUpcoming = calendar.authorization == .authorized
            ? calendar.upcomingMeetings()
            : []
        refreshTitle()
    }

    private func refreshTitle() {
        guard let button = statusItem.button else { return }
        switch calendar.authorization {
        case .notDetermined, .denied, .restricted:
            button.title = " ⚠️"  // R22 — silent failure is the one forbidden failure mode
            return
        case .requesting:
            button.title = ""
            return
        case .authorized:
            break
        }
        let now = Date()
        guard let next = cachedUpcoming.first(where: { $0.start > now }) else {
            button.title = ""  // glyph only when nothing in the next 12 h
            return
        }
        let interval = next.start.timeIntervalSince(now)
        if interval < 3600 {
            button.title = " \(max(1, Int(interval / 60)))m"
        } else {
            button.title = " \(Int(interval / 3600))h"
        }
    }

    // MARK: - Dropdown (R21)

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if calendar.authorization == .notDetermined {
            let setup = NSMenuItem(
                title: "Calendar access needed - Set Up Meetie…",
                action: #selector(showOnboarding),
                keyEquivalent: ""
            )
            setup.target = self
            menu.addItem(setup)
            let hint = NSMenuItem(
                title: "Meetie cannot alert you until setup is complete",
                action: nil,
                keyEquivalent: ""
            )
            hint.isEnabled = false
            menu.addItem(hint)
        } else if calendar.authorization == .denied {
            // R22: first item explains and deep-links to System Settings.
            let warning = NSMenuItem(
                title: "No calendar access — open Privacy Settings…",
                action: #selector(openPrivacySettings), keyEquivalent: ""
            )
            warning.target = self
            menu.addItem(warning)
            let hint = NSMenuItem(
                title: "Enable Meetie under Privacy & Security → Calendars",
                action: nil, keyEquivalent: ""
            )
            hint.isEnabled = false
            menu.addItem(hint)
        } else if calendar.authorization == .restricted {
            let warning = NSMenuItem(
                title: "Calendar access is restricted by policy",
                action: nil,
                keyEquivalent: ""
            )
            warning.isEnabled = false
            menu.addItem(warning)
            let hint = NSMenuItem(
                title: "Contact your device or organization administrator",
                action: nil,
                keyEquivalent: ""
            )
            hint.isEnabled = false
            menu.addItem(hint)
        } else {
            addUpcomingMeetings(to: menu)
        }

        menu.addItem(.separator())
        addCalendarsSubmenu(to: menu)
        addNotifyAtSubmenu(to: menu)

        let sound = NSMenuItem(title: "Sound", action: #selector(toggleSound), keyEquivalent: "")
        sound.target = self
        sound.state = settings.soundEnabled ? .on : .off
        menu.addItem(sound)

        menu.addItem(.separator())

        #if DEBUG
        // R21: Test Dog ships in debug builds only.
        let test = NSMenuItem(title: "Test Dog", action: #selector(runTestDog), keyEquivalent: "")
        test.target = self
        menu.addItem(test)
        #endif

        let login = NSMenuItem(
            title: "Launch at Login",
            action: #selector(toggleLaunchAtLogin), keyEquivalent: ""
        )
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)

        if calendar.authorization != .notDetermined {
            let setup = NSMenuItem(
                title: "Set Up Meetie…",
                action: #selector(showOnboarding),
                keyEquivalent: ""
            )
            setup.target = self
            menu.addItem(setup)
        }

        menu.addItem(.separator())
        let quit = NSMenuItem(
            title: "Quit",
            action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"
        )
        quit.target = NSApp
        menu.addItem(quit)
    }

    private func addUpcomingMeetings(to menu: NSMenu) {
        let now = Date()
        let upcoming = Array(
            calendar.upcomingMeetings().filter { $0.start > now }.prefix(5)
        )
        guard !upcoming.isEmpty else {
            let empty = NSMenuItem(
                title: "No meetings in the next 12 hours", action: nil, keyEquivalent: ""
            )
            empty.isEnabled = false
            menu.addItem(empty)
            return
        }
        for (index, meeting) in upcoming.enumerated() {
            let time = Calendar.current.isDateInToday(meeting.start)
                ? Self.timeFormatter.string(from: meeting.start)
                : Self.dayTimeFormatter.string(from: meeting.start)
            let title = "\(time)   \(meeting.title.truncatedForBanner())"
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.isEnabled = false
            if index == 0 && meeting.start.timeIntervalSince(now) < 600 {
                // The imminent one, highlighted (R21).
                item.attributedTitle = NSAttributedString(
                    string: title,
                    attributes: [.font: NSFont.boldSystemFont(ofSize: NSFont.systemFontSize)]
                )
            }
            menu.addItem(item)
        }
    }

    private func addCalendarsSubmenu(to menu: NSMenu) {
        let parent = NSMenuItem(title: "Calendars", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        let calendars = calendar.allCalendars
        if calendars.isEmpty {
            let empty = NSMenuItem(title: "No calendars available", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            submenu.addItem(empty)
        }
        // Grouped by account: several accounts ship same-named calendars
        // ("Calendar", "Birthdays"), so titles alone read as duplicates.
        let groups = Dictionary(grouping: calendars) { $0.source?.title ?? "Other" }
        for (index, sourceTitle) in groups.keys.sorted().enumerated() {
            if index > 0 { submenu.addItem(.separator()) }
            let header = NSMenuItem(title: sourceTitle, action: nil, keyEquivalent: "")
            header.isEnabled = false
            submenu.addItem(header)
            for cal in groups[sourceTitle] ?? [] {
                let item = NSMenuItem(
                    title: cal.title, action: #selector(toggleCalendar(_:)), keyEquivalent: ""
                )
                item.target = self
                item.indentationLevel = 1
                item.state = settings.isWatched(calendarID: cal.calendarIdentifier) ? .on : .off
                item.representedObject = cal.calendarIdentifier
                submenu.addItem(item)
            }
        }
        parent.submenu = submenu
        menu.addItem(parent)
    }

    /// R6/R21: notify-at lead — minutes before start, or when the meeting starts.
    private func addNotifyAtSubmenu(to menu: NSMenu) {
        let parent = NSMenuItem(title: "Notify At", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        submenu.autoenablesItems = false
        let options: [(String, TimeInterval)] = [
            ("1 minute before", 60),
            ("5 minutes before", 300),
            ("10 minutes before", 600),
            ("When meeting starts", 0),
        ]
        for (label, lead) in options {
            let item = NSMenuItem(
                title: label, action: #selector(selectLeadTime(_:)), keyEquivalent: ""
            )
            item.target = self
            item.representedObject = lead
            item.state = settings.alertLeadTime == lead ? .on : .off
            submenu.addItem(item)
        }
        parent.submenu = submenu
        menu.addItem(parent)
    }

    // MARK: - Actions

    @objc private func toggleCalendar(_ sender: NSMenuItem) {
        guard let calendarID = sender.representedObject as? String else { return }
        settings.setWatched(sender.state == .off, calendarID: calendarID)  // R4
        scheduler.recompute()
    }

    @objc private func toggleSound() {
        settings.soundEnabled.toggle()
    }

    @objc private func selectLeadTime(_ sender: NSMenuItem) {
        guard let lead = sender.representedObject as? TimeInterval else { return }
        settings.alertLeadTime = lead
        scheduler.recompute()  // re-arm the timer against the new fire moments
    }

    #if DEBUG
    @objc private func runTestDog() {
        alerts.startTestAlert()
    }
    #endif

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            NSLog("Meetie: launch-at-login toggle failed: \(error)")
        }
    }

    @objc private func showOnboarding() {
        onShowOnboarding?()
    }

    @objc private func openPrivacySettings() {
        // R22: deep-link to System Settings → Privacy & Security → Calendars.
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }
}
