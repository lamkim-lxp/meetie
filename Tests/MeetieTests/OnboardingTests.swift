import AppKit
import EventKit
import Foundation
import Testing
@testable import Meetie

struct OnboardingSettingsTests {
    @Test func presentingOnboardingDoesNotMarkItCompleted() {
        let (settings, defaults, suite) = makeSettings()
        defer { defaults.removePersistentDomain(forName: suite) }

        settings.markOnboardingPresented()

        #expect(settings.shouldPresentOnboarding == false)
        #expect(settings.hasCompletedOnboarding == false)
    }

    @Test func completingOnboardingPersistsTheCurrentVersion() {
        let (settings, defaults, suite) = makeSettings()
        defer { defaults.removePersistentDomain(forName: suite) }

        settings.markOnboardingCompleted()

        #expect(settings.hasCompletedOnboarding)
    }

    @Test func mapsEventKitAuthorizationStatesUsedByOnboarding() {
        #expect(CalendarStore.authorizationState(for: .notDetermined) == .notDetermined)
        #expect(CalendarStore.authorizationState(for: .fullAccess) == .authorized)
        #expect(CalendarStore.authorizationState(for: .writeOnly) == .denied)
        #expect(CalendarStore.authorizationState(for: .restricted) == .restricted)
    }

    private func makeSettings() -> (SettingsStore, UserDefaults, String) {
        let suite = "MeetieTests.Onboarding.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (SettingsStore(defaults: defaults), defaults, suite)
    }
}

@MainActor
struct OnboardingViewControllerTests {
    @Test func introductionShowsOnlyOneLargeCenteredAction() throws {
        let fakeCalendar = FakeOnboardingCalendar(authorization: .authorized)
        let (settings, defaults, suite) = makeSettings()
        defer { defaults.removePersistentDomain(forName: suite) }
        let controller = makeController(calendar: fakeCalendar, settings: settings)
        controller.loadView()
        controller.view.layoutSubtreeIfNeeded()

        let primary = try #require(
            button(
                identifiedBy: OnboardingViewController.primaryButtonIdentifier,
                in: controller.view
            )
        )
        let secondary = try #require(
            button(
                identifiedBy: OnboardingViewController.secondaryButtonIdentifier,
                in: controller.view
            )
        )
        let primaryFrame = primary.convert(primary.bounds, to: controller.view)

        #expect(primary.title == "Get Started")
        #expect(primary.controlSize == .large)
        #expect(secondary.isHidden)
        #expect(abs(primaryFrame.midX - controller.view.bounds.midX) < 0.5)
    }

    @Test func authorizedUserCanCompleteAllFourSteps() {
        let fakeCalendar = FakeOnboardingCalendar(authorization: .authorized)
        let (settings, defaults, suite) = makeSettings()
        defer { defaults.removePersistentDomain(forName: suite) }
        var didClose = false
        let controller = makeController(calendar: fakeCalendar, settings: settings)
        controller.onClose = { didClose = true }
        controller.loadView()

        clickPrimary(in: controller)
        #expect(controller.step == .permission)

        clickPrimary(in: controller)
        #expect(controller.step == .outlook)

        clickPrimary(in: controller)
        #expect(controller.step == .ready)

        clickPrimary(in: controller)
        #expect(settings.hasCompletedOnboarding)
        #expect(didClose)
    }

    @Test func permissionPromptRequiresTheExplicitAllowAction() {
        let fakeCalendar = FakeOnboardingCalendar(authorization: .notDetermined)
        let (settings, defaults, suite) = makeSettings()
        defer { defaults.removePersistentDomain(forName: suite) }
        let controller = makeController(calendar: fakeCalendar, settings: settings)
        controller.loadView()

        #expect(fakeCalendar.requestCount == 0)

        clickPrimary(in: controller)
        #expect(fakeCalendar.requestCount == 0)

        clickPrimary(in: controller)
        #expect(fakeCalendar.requestCount == 1)
    }

    @Test func deniedPermissionOffersSettingsAndStillAllowsSetupToContinue() {
        let fakeCalendar = FakeOnboardingCalendar(authorization: .denied)
        let (settings, defaults, suite) = makeSettings()
        defer { defaults.removePersistentDomain(forName: suite) }
        var privacyOpenCount = 0
        let controller = OnboardingViewController(
            calendar: fakeCalendar,
            settings: settings,
            externalActions: OnboardingExternalActions(
                openCalendar: {},
                openInternetAccounts: {},
                openCalendarPrivacy: { privacyOpenCount += 1 }
            )
        )
        controller.loadView()
        clickPrimary(in: controller)

        clickPrimary(in: controller)
        #expect(privacyOpenCount == 1)

        clickSecondary(in: controller)
        #expect(controller.step == .outlook)
    }

    private func makeController(
        calendar: FakeOnboardingCalendar,
        settings: SettingsStore
    ) -> OnboardingViewController {
        OnboardingViewController(
            calendar: calendar,
            settings: settings,
            externalActions: OnboardingExternalActions(
                openCalendar: {},
                openInternetAccounts: {},
                openCalendarPrivacy: {}
            )
        )
    }

    private func makeSettings() -> (SettingsStore, UserDefaults, String) {
        let suite = "MeetieTests.OnboardingView.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (SettingsStore(defaults: defaults), defaults, suite)
    }

    private func clickPrimary(in controller: OnboardingViewController) {
        button(
            identifiedBy: OnboardingViewController.primaryButtonIdentifier,
            in: controller.view
        )?.performClick(nil)
    }

    private func clickSecondary(in controller: OnboardingViewController) {
        button(
            identifiedBy: OnboardingViewController.secondaryButtonIdentifier,
            in: controller.view
        )?.performClick(nil)
    }

    private func button(
        identifiedBy identifier: NSUserInterfaceItemIdentifier,
        in view: NSView
    ) -> NSButton? {
        if let button = view as? NSButton, button.identifier == identifier {
            return button
        }
        for subview in view.subviews {
            if let match = button(identifiedBy: identifier, in: subview) {
                return match
            }
        }
        return nil
    }
}

private final class FakeOnboardingCalendar: OnboardingCalendarAccess {
    var authorization: CalendarStore.AuthorizationState
    var authorizationErrorDescription: String?
    var calendarCount = 2
    var exchangeCalendarNames = ["Work"]
    var requestCount = 0
    var refreshCount = 0

    init(authorization: CalendarStore.AuthorizationState) {
        self.authorization = authorization
    }

    func requestAccess(completion: (() -> Void)?) {
        requestCount += 1
        authorization = .requesting
    }

    func refreshAuthorization() {
        refreshCount += 1
    }
}
