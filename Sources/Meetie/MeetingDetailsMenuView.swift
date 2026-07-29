import AppKit

struct MeetingDetailsContent: Equatable {
    let name: String
    let date: String
    let venue: String
    let description: String

    init(
        meeting: Meeting,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) {
        name = Self.displayText(meeting.title, fallback: "Untitled")
        date = Self.dateText(
            start: meeting.start,
            end: meeting.end,
            locale: locale,
            timeZone: timeZone
        )
        venue = Self.displayText(meeting.venue, fallback: "Not specified")
        description = Self.displayText(meeting.details, fallback: "No description")
    }

    private static func displayText(_ text: String?, fallback: String) -> String {
        guard let value = text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return fallback
        }
        return value
    }

    private static func dateText(
        start: Date,
        end: Date,
        locale: Locale,
        timeZone: TimeZone
    ) -> String {
        let dateTime = DateFormatter()
        dateTime.locale = locale
        dateTime.timeZone = timeZone
        dateTime.dateStyle = .medium
        dateTime.timeStyle = .short

        let time = DateFormatter()
        time.locale = locale
        time.timeZone = timeZone
        time.dateStyle = .none
        time.timeStyle = .short

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        if calendar.isDate(start, inSameDayAs: end) {
            return "\(dateTime.string(from: start)) - \(time.string(from: end))"
        }
        return "\(dateTime.string(from: start)) - \(dateTime.string(from: end))"
    }
}

final class MeetingDetailsMenuView: NSView {
    private static let width: CGFloat = 380
    static let joinButtonIdentifier = NSUserInterfaceItemIdentifier("MeetingDetails.join")

    private let onDismiss: () -> Void
    private let onJoin: (() -> Void)?

    init(
        meeting: Meeting,
        onDismiss: @escaping () -> Void,
        onJoin: (() -> Void)?
    ) {
        self.onDismiss = onDismiss
        self.onJoin = onJoin
        super.init(frame: NSRect(x: 0, y: 0, width: Self.width, height: 1))

        let content = MeetingDetailsContent(meeting: meeting)
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 9
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        let heading = NSTextField(labelWithString: "MEETING DETAILS")
        heading.font = .systemFont(ofSize: 11, weight: .semibold)
        heading.textColor = .secondaryLabelColor
        stack.addArrangedSubview(heading)

        stack.addArrangedSubview(Self.fieldRow(label: "Name", value: content.name, lines: 2))
        stack.addArrangedSubview(Self.fieldRow(label: "Date", value: content.date, lines: 2))
        stack.addArrangedSubview(Self.fieldRow(label: "Venue", value: content.venue, lines: 2))
        stack.addArrangedSubview(
            Self.fieldRow(label: "Description", value: content.description, lines: 4)
        )

        let separator = NSBox()
        separator.boxType = .separator
        stack.addArrangedSubview(separator)

        let buttonRow = NSStackView()
        buttonRow.orientation = .horizontal
        buttonRow.alignment = .centerY
        buttonRow.spacing = 8

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        buttonRow.addArrangedSubview(spacer)

        let dismissButton = NSButton(
            title: "Dismiss",
            target: self,
            action: #selector(dismissClicked)
        )
        dismissButton.bezelStyle = .rounded
        buttonRow.addArrangedSubview(dismissButton)

        if meeting.joinURL != nil, onJoin != nil {
            let joinButton = NSButton(
                title: "Join",
                target: self,
                action: #selector(joinClicked)
            )
            joinButton.bezelStyle = .rounded
            joinButton.bezelColor = .systemBlue
            joinButton.contentTintColor = .white
            joinButton.keyEquivalent = "\r"
            joinButton.identifier = Self.joinButtonIdentifier
            buttonRow.addArrangedSubview(joinButton)
            joinButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 82).isActive = true
        }
        dismissButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 82).isActive = true

        stack.addArrangedSubview(buttonRow)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: Self.width),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 13),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12),
            separator.widthAnchor.constraint(equalTo: stack.widthAnchor),
            buttonRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])

        layoutSubtreeIfNeeded()
        frame.size.height = ceil(stack.fittingSize.height + 25)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private static func fieldRow(label: String, value: String, lines: Int) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .top
        row.spacing = 12

        let name = NSTextField(labelWithString: label)
        name.font = .systemFont(ofSize: 13, weight: .medium)
        name.textColor = .secondaryLabelColor
        name.alignment = .right
        name.widthAnchor.constraint(equalToConstant: 78).isActive = true
        name.setContentHuggingPriority(.required, for: .horizontal)

        let text = NSTextField(wrappingLabelWithString: value)
        text.font = .systemFont(ofSize: 13)
        text.maximumNumberOfLines = lines
        text.lineBreakMode = .byTruncatingTail
        text.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        row.addArrangedSubview(name)
        row.addArrangedSubview(text)
        return row
    }

    @objc private func dismissClicked() {
        enclosingMenuItem?.menu?.cancelTracking()
        onDismiss()
    }

    @objc private func joinClicked() {
        enclosingMenuItem?.menu?.cancelTracking()
        onJoin?()
    }
}
