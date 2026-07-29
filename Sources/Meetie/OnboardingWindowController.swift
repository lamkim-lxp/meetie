import AppKit
import CoreText
import EventKit

protocol OnboardingCalendarAccess: AnyObject {
    var authorization: CalendarStore.AuthorizationState { get }
    var authorizationErrorDescription: String? { get }
    var calendarCount: Int { get }
    var exchangeCalendarNames: [String] { get }

    func requestAccess(completion: (() -> Void)?)
    func refreshAuthorization()
}

extension CalendarStore: OnboardingCalendarAccess {}

struct OnboardingExternalActions {
    let openCalendar: () -> Void
    let openInternetAccounts: () -> Void
    let openCalendarPrivacy: () -> Void

    static let live = OnboardingExternalActions(
        openCalendar: {
            let workspace = NSWorkspace.shared
            guard let url = workspace.urlForApplication(withBundleIdentifier: "com.apple.iCal")
            else { return }
            workspace.openApplication(
                at: url,
                configuration: NSWorkspace.OpenConfiguration(),
                completionHandler: nil
            )
        },
        openInternetAccounts: {
            guard let url = URL(
                string: "x-apple.systempreferences:com.apple.Internet-Accounts-Settings.extension"
            ) else { return }
            NSWorkspace.shared.open(url)
        },
        openCalendarPrivacy: {
            guard let url = URL(
                string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars"
            ) else { return }
            NSWorkspace.shared.open(url)
        }
    )
}

final class OnboardingWindowController: NSWindowController {
    private let onboardingViewController: OnboardingViewController

    init(calendar: CalendarStore, settings: SettingsStore) {
        let viewController = OnboardingViewController(
            calendar: calendar,
            settings: settings,
            externalActions: .live
        )
        onboardingViewController = viewController

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Set Up Meetie"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.contentViewController = viewController
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 700, height: 520)

        super.init(window: window)

        viewController.onClose = { [weak self] in
            self?.close()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present() {
        onboardingViewController.restart()
        window?.center()
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func refresh() {
        onboardingViewController.refresh()
    }
}

final class OnboardingViewController: NSViewController {
    enum Step: Int, CaseIterable {
        case introduction
        case permission
        case outlook
        case ready
    }

    static let primaryButtonIdentifier = NSUserInterfaceItemIdentifier("Onboarding.primary")
    static let secondaryButtonIdentifier = NSUserInterfaceItemIdentifier("Onboarding.secondary")
    static let statusIdentifier = NSUserInterfaceItemIdentifier("Onboarding.status")
    static let checkAgainIdentifier = NSUserInterfaceItemIdentifier("Onboarding.checkAgain")

    private let calendar: OnboardingCalendarAccess
    private let settings: SettingsStore
    private let externalActions: OnboardingExternalActions

    private let contentHost = NSVisualEffectView()
    private let progressLabel = NSTextField(labelWithString: "")
    private var progressPaws: [NSImageView] = []
    private let backButton = NSButton()
    private let secondaryButton = NSButton()
    private let primaryButton = NSButton()
    private var primaryCenterConstraint: NSLayoutConstraint?
    private var primaryTrailingConstraint: NSLayoutConstraint?
    private var primaryLargeWidthConstraint: NSLayoutConstraint?

    private(set) var step: Step = .introduction
    var onClose: (() -> Void)?

    init(
        calendar: OnboardingCalendarAccess,
        settings: SettingsStore,
        externalActions: OnboardingExternalActions
    ) {
        self.calendar = calendar
        self.settings = settings
        self.externalActions = externalActions
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 760, height: 560))

        let background = NSVisualEffectView()
        background.material = .underWindowBackground
        background.blendingMode = .behindWindow
        background.state = .active
        background.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(background)

        let header = makeHeader()
        header.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(header)

        contentHost.material = .popover
        contentHost.blendingMode = .withinWindow
        contentHost.state = .active
        contentHost.wantsLayer = true
        contentHost.layer?.cornerRadius = 20
        contentHost.layer?.masksToBounds = true
        contentHost.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(contentHost)

        let footer = makeFooter()
        footer.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(footer)

        NSLayoutConstraint.activate([
            background.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            background.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            background.topAnchor.constraint(equalTo: root.topAnchor),
            background.bottomAnchor.constraint(equalTo: root.bottomAnchor),

            header.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 34),
            header.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -34),
            header.topAnchor.constraint(equalTo: root.topAnchor, constant: 42),

            contentHost.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 28),
            contentHost.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -28),
            contentHost.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 18),
            contentHost.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -18),

            footer.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 34),
            footer.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -34),
            footer.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -24),
            footer.heightAnchor.constraint(equalToConstant: 44),
        ])

        view = root
        render()
    }

    func restart() {
        step = .introduction
        if isViewLoaded {
            render()
        }
    }

    func refresh() {
        guard isViewLoaded else { return }
        render()
    }

    private func makeHeader() -> NSView {
        let product = NSTextField(labelWithString: "MEETIE SETUP")
        product.font = .monospacedSystemFont(ofSize: 11, weight: .semibold)
        product.textColor = .secondaryLabelColor

        let pawStack = NSStackView()
        pawStack.orientation = .horizontal
        pawStack.alignment = .centerY
        pawStack.spacing = 7
        for _ in Step.allCases {
            let paw = NSImageView()
            paw.image = NSImage(
                systemSymbolName: "pawprint.fill",
                accessibilityDescription: nil
            )
            paw.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 10, weight: .medium)
            paw.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                paw.widthAnchor.constraint(equalToConstant: 14),
                paw.heightAnchor.constraint(equalToConstant: 14),
            ])
            progressPaws.append(paw)
            pawStack.addArrangedSubview(paw)
        }

        progressLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        progressLabel.textColor = .secondaryLabelColor

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let header = NSStackView(views: [product, spacer, pawStack, progressLabel])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 14
        return header
    }

    private func makeFooter() -> NSView {
        let footer = NSView()

        backButton.title = "Back"
        backButton.bezelStyle = .rounded
        backButton.target = self
        backButton.action = #selector(backClicked)
        backButton.translatesAutoresizingMaskIntoConstraints = false
        footer.addSubview(backButton)

        secondaryButton.bezelStyle = .rounded
        secondaryButton.target = self
        secondaryButton.action = #selector(secondaryClicked)
        secondaryButton.identifier = Self.secondaryButtonIdentifier
        secondaryButton.translatesAutoresizingMaskIntoConstraints = false
        footer.addSubview(secondaryButton)

        primaryButton.bezelStyle = .rounded
        primaryButton.bezelColor = .controlAccentColor
        primaryButton.target = self
        primaryButton.action = #selector(primaryClicked)
        primaryButton.keyEquivalent = "\r"
        primaryButton.identifier = Self.primaryButtonIdentifier
        primaryButton.translatesAutoresizingMaskIntoConstraints = false
        footer.addSubview(primaryButton)

        let centered = primaryButton.centerXAnchor.constraint(equalTo: footer.centerXAnchor)
        let trailing = primaryButton.trailingAnchor.constraint(equalTo: footer.trailingAnchor)
        let largeWidth = primaryButton.widthAnchor.constraint(equalToConstant: 190)
        primaryCenterConstraint = centered
        primaryTrailingConstraint = trailing
        primaryLargeWidthConstraint = largeWidth

        NSLayoutConstraint.activate([
            backButton.leadingAnchor.constraint(equalTo: footer.leadingAnchor),
            backButton.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
            backButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 82),

            secondaryButton.trailingAnchor.constraint(
                equalTo: primaryButton.leadingAnchor,
                constant: -10
            ),
            secondaryButton.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
            secondaryButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 100),

            primaryButton.centerYAnchor.constraint(equalTo: footer.centerYAnchor),
            primaryButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 126),
            trailing,
        ])
        return footer
    }

    private func render() {
        updateProgress()
        contentHost.subviews.forEach { $0.removeFromSuperview() }

        let page: NSView
        switch step {
        case .introduction:
            page = introductionPage()
        case .permission:
            page = permissionPage()
        case .outlook:
            page = outlookPage()
        case .ready:
            page = readyPage()
        }

        page.translatesAutoresizingMaskIntoConstraints = false
        contentHost.addSubview(page)
        NSLayoutConstraint.activate([
            page.leadingAnchor.constraint(equalTo: contentHost.leadingAnchor, constant: 38),
            page.trailingAnchor.constraint(equalTo: contentHost.trailingAnchor, constant: -38),
            page.topAnchor.constraint(equalTo: contentHost.topAnchor, constant: 30),
            page.bottomAnchor.constraint(equalTo: contentHost.bottomAnchor, constant: -30),
        ])
        updateButtons()
    }

    private func updateProgress() {
        progressLabel.stringValue = "\(step.rawValue + 1) OF \(Step.allCases.count)"
        for (index, paw) in progressPaws.enumerated() {
            paw.contentTintColor = index <= step.rawValue ? .systemOrange : .tertiaryLabelColor
        }
    }

    private func updateButtons() {
        backButton.isHidden = step == .introduction
        primaryButton.isEnabled = true
        secondaryButton.isHidden = true
        let isIntroduction = step == .introduction
        if isIntroduction {
            primaryTrailingConstraint?.isActive = false
            primaryCenterConstraint?.isActive = true
            primaryLargeWidthConstraint?.isActive = true
        } else {
            primaryCenterConstraint?.isActive = false
            primaryLargeWidthConstraint?.isActive = false
            primaryTrailingConstraint?.isActive = true
        }
        primaryButton.controlSize = isIntroduction ? .large : .regular
        primaryButton.font = isIntroduction
            ? Self.roundedFont(ofSize: 15, weight: .semibold)
            : .systemFont(ofSize: NSFont.systemFontSize)

        switch step {
        case .introduction:
            primaryButton.title = "Get Started"
        case .permission:
            switch calendar.authorization {
            case .notDetermined:
                primaryButton.title = "Allow Calendar Access"
                secondaryButton.title = "Set Up Later"
                secondaryButton.isHidden = false
            case .requesting:
                primaryButton.title = "Waiting for macOS…"
                primaryButton.isEnabled = false
            case .authorized:
                primaryButton.title = "Continue"
            case .denied:
                primaryButton.title = "Open Calendar Settings"
                secondaryButton.title = "Continue Setup"
                secondaryButton.isHidden = false
            case .restricted:
                primaryButton.title = "Continue Setup"
            }
        case .outlook:
            primaryButton.title = "Continue"
        case .ready:
            primaryButton.title = "Start Using Meetie"
        }
    }

    private func introductionPage() -> NSView {
        let dog = PixelDogView()
        dog.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            dog.widthAnchor.constraint(equalToConstant: 180),
            dog.heightAnchor.constraint(equalToConstant: 180),
        ])

        let eyebrow = makeEyebrow("Good boy alert.")
        let title = makeTitle("Never miss a Meeting again.")
        let body = makeBody(
            "Meetie watches Apple Calendar and sends a playful, full-screen Alert "
                + "before each Meeting."
        )

        let features = NSStackView()
        features.orientation = .vertical
        features.alignment = .leading
        features.spacing = 11
        features.addArrangedSubview(
            makeFeature(symbol: "calendar", text: "Uses the calendars already on your Mac")
        )
        features.addArrangedSubview(
            makeFeature(symbol: "clock.badge", text: "Alerts you one minute before by default")
        )
        features.addArrangedSubview(
            makeFeature(symbol: "cursorarrow.click.2", text: "Click the Dog to review or join")
        )

        let copy = NSStackView(views: [eyebrow, title, body, features])
        copy.orientation = .vertical
        copy.alignment = .leading
        copy.spacing = 12
        copy.setCustomSpacing(20, after: body)
        copy.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let page = NSStackView(views: [dog, copy])
        page.orientation = .horizontal
        page.alignment = .centerY
        page.spacing = 34
        return page
    }

    private func permissionPage() -> NSView {
        let heading = makeHeading(
            symbol: "calendar.badge.clock",
            eyebrow: "CALENDAR ACCESS",
            title: "Let Meetie see your Meetings"
        )
        let body = makeBody(
            "Meetie reads titles, times, locations, and notes so it can schedule Alerts "
                + "and find join links. It never edits your calendars."
        )
        let privacy = makeCallout(
            symbol: "lock.shield.fill",
            text: "Calendar data stays on this Mac. EventKit requires Full Access "
                + "to read Meeting details.",
            color: .systemBlue
        )

        let status: NSView
        switch calendar.authorization {
        case .notDetermined:
            status = makeCallout(
                symbol: "hand.tap.fill",
                text: "Choose Allow Calendar Access, then approve the macOS prompt.",
                color: .systemOrange
            )
        case .requesting:
            status = makeCallout(
                symbol: "ellipsis.circle.fill",
                text: "Waiting for a response from macOS.",
                color: .systemOrange
            )
        case .authorized:
            status = makeCallout(
                symbol: "checkmark.circle.fill",
                text: "Calendar access is on.",
                color: .systemGreen
            )
        case .denied:
            let detail = calendar.authorizationErrorDescription.map { " \($0)" } ?? ""
            status = makeCallout(
                symbol: "exclamationmark.triangle.fill",
                text: "Calendar access is off. Enable Meetie under Privacy & Security "
                    + "→ Calendars.\(detail)",
                color: .systemRed
            )
        case .restricted:
            status = makeCallout(
                symbol: "lock.trianglebadge.exclamationmark.fill",
                text: "A device or organization policy is preventing Calendar access.",
                color: .systemRed
            )
        }
        status.identifier = Self.statusIdentifier

        let page = NSStackView(views: [heading, body, privacy, status])
        page.orientation = .vertical
        page.alignment = .leading
        page.spacing = 16
        page.setCustomSpacing(20, after: body)
        return page
    }

    private func outlookPage() -> NSView {
        let heading = makeHeading(
            symbol: "arrow.triangle.2.circlepath",
            eyebrow: "OUTLOOK CALENDAR",
            title: "Sync Outlook with Apple Calendar"
        )
        let body = makeBody(
            "Outlook stays in sync through your Microsoft Exchange account. "
                + "There is no one-time import."
        )

        let steps = NSStackView()
        steps.orientation = .vertical
        steps.alignment = .leading
        steps.spacing = 8
        steps.addArrangedSubview(makeInstruction(number: 1, text: "Open the Calendar app."))
        steps.addArrangedSubview(
            makeInstruction(number: 2, text: "Choose Calendar → Add Account.")
        )
        steps.addArrangedSubview(
            makeInstruction(number: 3, text: "Select Microsoft Exchange and sign in.")
        )
        steps.addArrangedSubview(
            makeInstruction(number: 4, text: "Make sure Calendars is turned on.")
        )

        let openCalendar = NSButton(
            title: "Open Calendar",
            target: self,
            action: #selector(openCalendarClicked)
        )
        openCalendar.bezelStyle = .rounded
        let openAccounts = NSButton(
            title: "Open Internet Accounts",
            target: self,
            action: #selector(openInternetAccountsClicked)
        )
        openAccounts.bezelStyle = .rounded
        let checkAgain = NSButton(
            title: "Check Again",
            target: self,
            action: #selector(checkAgainClicked)
        )
        checkAgain.bezelStyle = .rounded
        checkAgain.identifier = Self.checkAgainIdentifier

        let actions = NSStackView(views: [openCalendar, openAccounts, checkAgain])
        actions.orientation = .horizontal
        actions.alignment = .centerY
        actions.spacing = 8

        let status: NSView
        if calendar.authorization != .authorized {
            status = makeCallout(
                symbol: "questionmark.circle.fill",
                text: "Calendar access is needed before Meetie can confirm your accounts.",
                color: .systemOrange
            )
        } else if calendar.exchangeCalendarNames.isEmpty {
            status = makeCallout(
                symbol: "arrow.clockwise.circle.fill",
                text: "No Exchange calendars detected yet. Finish signing in, then check again.",
                color: .systemOrange
            )
        } else {
            let names = calendar.exchangeCalendarNames.prefix(3).joined(separator: ", ")
            let count = calendar.exchangeCalendarNames.count
            status = makeCallout(
                symbol: "checkmark.circle.fill",
                text: "Outlook connected. Found \(count) Exchange "
                    + "\(count == 1 ? "calendar" : "calendars"): \(names).",
                color: .systemGreen
            )
        }
        status.identifier = Self.statusIdentifier

        let page = NSStackView(views: [heading, body, steps, actions, status])
        page.orientation = .vertical
        page.alignment = .leading
        page.spacing = 12
        page.setCustomSpacing(16, after: body)
        return page
    }

    private func readyPage() -> NSView {
        let dog = PixelDogView()
        dog.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            dog.widthAnchor.constraint(equalToConstant: 126),
            dog.heightAnchor.constraint(equalToConstant: 126),
        ])

        let check = NSImageView()
        check.image = NSImage(
            systemSymbolName: "checkmark.seal.fill",
            accessibilityDescription: "Ready"
        )
        check.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 34, weight: .medium)
        check.contentTintColor = .systemGreen

        let hero = NSStackView(views: [dog, check])
        hero.orientation = .horizontal
        hero.alignment = .centerY
        hero.spacing = -22

        let eyebrow = makeEyebrow("READY TO ROAM")
        let title = makeTitle("Meetie lives in your menu bar.")
        let body = makeBody(
            "Keep Meetie running and a Dog will arrive before each Meeting. "
                + "You can change Watched Calendars, timing, and sound from the menu."
        )

        let summary = NSStackView()
        summary.orientation = .vertical
        summary.alignment = .leading
        summary.spacing = 10

        let calendarText: String
        if calendar.authorization == .authorized {
            calendarText = calendar.calendarCount == 1
                ? "1 calendar is watched"
                : "\(calendar.calendarCount) calendars are watched"
        } else {
            calendarText = "Calendar access still needs attention"
        }
        summary.addArrangedSubview(makeFeature(symbol: "calendar", text: calendarText))
        summary.addArrangedSubview(
            makeFeature(
                symbol: "clock",
                text: "Alerts arrive \(leadTimeDescription(settings.alertLeadTime))"
            )
        )
        summary.addArrangedSubview(
            makeFeature(
                symbol: settings.soundEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill",
                text: settings.soundEnabled ? "Bark sounds are on" : "Bark sounds are off"
            )
        )

        let copy = NSStackView(views: [eyebrow, title, body, summary])
        copy.orientation = .vertical
        copy.alignment = .leading
        copy.spacing = 12
        copy.setCustomSpacing(18, after: body)
        copy.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let page = NSStackView(views: [hero, copy])
        page.orientation = .horizontal
        page.alignment = .centerY
        page.spacing = 30
        return page
    }

    private func makeHeading(symbol: String, eyebrow: String, title: String) -> NSView {
        let image = NSImageView()
        image.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        image.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 36, weight: .medium)
        image.contentTintColor = .systemOrange
        image.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            image.widthAnchor.constraint(equalToConstant: 54),
            image.heightAnchor.constraint(equalToConstant: 54),
        ])

        let labels = NSStackView(views: [makeEyebrow(eyebrow), makeTitle(title)])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 5

        let row = NSStackView(views: [image, labels])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 16
        return row
    }

    private func makeEyebrow(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .monospacedSystemFont(ofSize: 11, weight: .semibold)
        label.textColor = .systemOrange
        return label
    }

    private func makeTitle(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = Self.roundedFont(ofSize: 29, weight: .bold)
        label.maximumNumberOfLines = 2
        label.lineBreakMode = .byWordWrapping
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }

    private func makeBody(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 15)
        label.textColor = .secondaryLabelColor
        label.maximumNumberOfLines = 4
        label.lineBreakMode = .byWordWrapping
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }

    private func makeFeature(symbol: String, text: String) -> NSView {
        let image = NSImageView()
        image.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        image.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        image.contentTintColor = .systemOrange
        image.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            image.widthAnchor.constraint(equalToConstant: 20),
            image.heightAnchor.constraint(equalToConstant: 20),
        ])

        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 13, weight: .medium)

        let row = NSStackView(views: [image, label])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 9
        return row
    }

    private func makeInstruction(number: Int, text: String) -> NSView {
        let badge = StepNumberBadgeView(number: number)
        badge.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            badge.widthAnchor.constraint(equalToConstant: 22),
            badge.heightAnchor.constraint(equalToConstant: 22),
        ])

        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 13, weight: .medium)

        let row = NSStackView(views: [badge, label])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        return row
    }

    private func makeCallout(symbol: String, text: String, color: NSColor) -> NSView {
        let image = NSImageView()
        image.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        image.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)
        image.contentTintColor = color
        image.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            image.widthAnchor.constraint(equalToConstant: 22),
            image.heightAnchor.constraint(equalToConstant: 22),
        ])

        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 13)
        label.maximumNumberOfLines = 3
        label.lineBreakMode = .byWordWrapping
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let row = NSStackView(views: [image, label])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 10
        row.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
        row.wantsLayer = true
        row.layer?.backgroundColor = color.withAlphaComponent(0.10).cgColor
        row.layer?.cornerRadius = 10
        row.widthAnchor.constraint(greaterThanOrEqualToConstant: 520).isActive = true
        return row
    }

    private func leadTimeDescription(_ lead: TimeInterval) -> String {
        switch lead {
        case 0:
            return "when a Meeting starts"
        case 60:
            return "1 minute before"
        default:
            return "\(Int(lead / 60)) minutes before"
        }
    }

    private static func roundedFont(ofSize size: CGFloat, weight: NSFont.Weight) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = base.fontDescriptor.withDesign(.rounded) else { return base }
        return NSFont(descriptor: descriptor, size: size) ?? base
    }

    @objc private func primaryClicked() {
        switch step {
        case .introduction:
            step = .permission
            render()
        case .permission:
            switch calendar.authorization {
            case .notDetermined:
                calendar.requestAccess { [weak self] in
                    self?.render()
                }
                render()
            case .requesting:
                break
            case .authorized, .restricted:
                step = .outlook
                render()
            case .denied:
                externalActions.openCalendarPrivacy()
            }
        case .outlook:
            step = .ready
            render()
        case .ready:
            settings.markOnboardingCompleted()
            onClose?()
        }
    }

    @objc private func secondaryClicked() {
        switch step {
        case .introduction:
            break
        case .permission:
            if calendar.authorization == .denied {
                step = .outlook
                render()
            } else {
                onClose?()
            }
        case .outlook, .ready:
            break
        }
    }

    @objc private func backClicked() {
        guard let previous = Step(rawValue: step.rawValue - 1) else { return }
        step = previous
        render()
    }

    @objc private func openCalendarClicked() {
        externalActions.openCalendar()
    }

    @objc private func openInternetAccountsClicked() {
        externalActions.openInternetAccounts()
    }

    @objc private func checkAgainClicked() {
        calendar.refreshAuthorization()
        render()
    }
}

private final class StepNumberBadgeView: NSView {
    private let number: Int

    init(number: Int) {
        self.number = number
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel("Step \(number)")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.systemOrange.setFill()
        NSBezierPath(ovalIn: bounds).fill()

        let text = NSAttributedString(
            string: "\(number)",
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .bold),
                .foregroundColor: NSColor.black,
            ]
        )
        let line = CTLineCreateWithAttributedString(text)
        let glyphBounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        guard let context = NSGraphicsContext.current?.cgContext else { return }

        context.saveGState()
        context.textMatrix = .identity
        context.textPosition = CGPoint(
            x: bounds.midX - glyphBounds.midX,
            y: bounds.midY - glyphBounds.midY
        )
        CTLineDraw(line, context)
        context.restoreGState()
    }
}

private final class PixelDogView: NSView {
    private let spriteFrame = Assets.spriteFrames(for: .shiba).first

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel("Pixel-art Shiba Dog")
    }

    convenience init() {
        self.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if let spriteFrame, let context = NSGraphicsContext.current {
            context.imageInterpolation = .none
            let side = min(bounds.width, bounds.height)
            let destination = NSRect(
                x: bounds.midX - side / 2,
                y: bounds.midY - side / 2,
                width: side,
                height: side
            )
            context.cgContext.draw(spriteFrame, in: destination)
            return
        }

        guard let fallback = NSImage(
            systemSymbolName: "pawprint.fill",
            accessibilityDescription: nil
        ) else { return }
        fallback.draw(
            in: bounds.insetBy(dx: bounds.width * 0.25, dy: bounds.height * 0.25),
            from: .zero,
            operation: .sourceOver,
            fraction: 1
        )
    }
}
