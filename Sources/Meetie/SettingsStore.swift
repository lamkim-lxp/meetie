import Foundation

/// UserDefaults-backed settings: watched-calendar opt-outs (R4, opt-out model —
/// calendars added later are Watched by default, R5), sound toggle, and the
/// notify-at lead time (R6, R21), and versioned onboarding state (R34).
final class SettingsStore {
    static let currentOnboardingVersion = 1

    private let defaults: UserDefaults
    private let unwatchedKey = "unwatchedCalendarIDs"
    private let soundKey = "soundEnabled"
    private let leadKey = "alertLeadSeconds"
    private let presentedOnboardingKey = "presentedOnboardingVersion"
    private let completedOnboardingKey = "completedOnboardingVersion"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Notify-at choices: minutes before start, or 0 = when the meeting starts.
    static let leadOptions: [TimeInterval] = [60, 300, 600, 0]

    var soundEnabled: Bool {
        get { defaults.object(forKey: soundKey) as? Bool ?? true }
        set { defaults.set(newValue, forKey: soundKey) }
    }

    var alertLeadTime: TimeInterval {
        get {
            guard let value = defaults.object(forKey: leadKey) as? TimeInterval,
                  Self.leadOptions.contains(value) else { return 60 }
            return value
        }
        set { defaults.set(newValue, forKey: leadKey) }
    }

    var unwatchedCalendarIDs: Set<String> {
        get { Set(defaults.stringArray(forKey: unwatchedKey) ?? []) }
        set { defaults.set(Array(newValue).sorted(), forKey: unwatchedKey) }
    }

    /// Presentation and completion are separate so dismissing setup does not
    /// force the onboarding window open again at every launch.
    var shouldPresentOnboarding: Bool {
        defaults.integer(forKey: presentedOnboardingKey) < Self.currentOnboardingVersion
    }

    var hasCompletedOnboarding: Bool {
        defaults.integer(forKey: completedOnboardingKey) >= Self.currentOnboardingVersion
    }

    func markOnboardingPresented() {
        defaults.set(Self.currentOnboardingVersion, forKey: presentedOnboardingKey)
    }

    func markOnboardingCompleted() {
        defaults.set(Self.currentOnboardingVersion, forKey: completedOnboardingKey)
    }

    func isWatched(calendarID: String) -> Bool {
        !unwatchedCalendarIDs.contains(calendarID)
    }

    func setWatched(_ watched: Bool, calendarID: String) {
        var set = unwatchedCalendarIDs
        if watched { set.remove(calendarID) } else { set.insert(calendarID) }
        unwatchedCalendarIDs = set
    }
}
