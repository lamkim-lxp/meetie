import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = SettingsStore()
    private lazy var sound = SoundPlayer(settings: settings)
    private lazy var calendarStore = CalendarStore(settings: settings)
    private lazy var overlay = OverlayManager()
    private lazy var alerts = AlertCoordinator(overlay: overlay, sound: sound)
    private lazy var scheduler = AlertScheduler(
        calendar: calendarStore, alerts: alerts, settings: settings
    )
    private lazy var menuBar = MenuBarController(
        calendar: calendarStore, settings: settings, scheduler: scheduler, alerts: alerts
    )
    private lazy var onboarding = OnboardingWindowController(
        calendar: calendarStore, settings: settings
    )
    private var calendarStarted = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)  // R19

        calendarStore.onChange = { [weak self] in
            self?.scheduler.recompute()
            self?.onboarding.refresh()
        }
        calendarStore.onAuthorizationChange = { [weak self] in
            self?.menuBar.refreshSchedule()
            self?.onboarding.refresh()
        }
        scheduler.onScheduleChanged = { [weak self] in self?.menuBar.refreshSchedule() }
        menuBar.onShowOnboarding = { [weak self] in self?.onboarding.present() }

        menuBar.install()

        // Debug flags (debug builds only, like Test Dog): `--test-dog` fires a
        // Test Dog on launch; `--no-calendar` skips EventKit entirely (overlay
        // testing without the permission prompt).
        #if DEBUG
        if CommandLine.arguments.contains("--test-dog") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.alerts.startTestAlert()
            }
        }
        if CommandLine.arguments.contains("--no-calendar") {
            return
        }
        #endif
        calendarStarted = true
        calendarStore.start()

        if settings.shouldPresentOnboarding {
            settings.markOnboardingPresented()
            DispatchQueue.main.async { [weak self] in
                self?.onboarding.present()
            }
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        guard calendarStarted else { return }
        calendarStore.refreshAuthorization()
        onboarding.refresh()
    }
}
