import AppKit
import Foundation

enum DogVariant: String, CaseIterable {
    case shiba, corgi
}

/// The one Dog of an Alert: variant + gait animation state.
struct DogModel {
    static let frameCount = 8
    let id = UUID()
    let variant: DogVariant   // random per Alert (R14a)
    let frameHold: TimeInterval
    var frameIndex: Int
    var frameClock: TimeInterval

    static func random() -> DogModel {
        DogModel(
            variant: DogVariant.allCases.randomElement()!,
            frameHold: .random(in: 0.065...0.075),
            frameIndex: Int.random(in: 0..<frameCount),
            frameClock: 0
        )
    }
}

/// One per active Alert: state machine and ack routing (§2.3). One Dog per
/// Alert, bouncing DVD-style around the lower ⅔ of every screen (R14, R15).
/// All timing is driven by the overlay's display tick — no timers of its own (R25).
final class AlertController {
    enum State {
        case running   // pre T−0
        case overdue   // R11: persists silently, "started Xm ago"
        case finished  // acknowledged or expired
    }

    let meeting: Meeting
    let isTest: Bool
    private(set) var state: State = .running
    private(set) var dog: DogModel

    /// Position/velocity in the unit square, mapped to each screen's band at
    /// render time — every screen shows identically-composed content (§2.4).
    private(set) var position: CGPoint
    private(set) var velocity: CGVector  // unit/s; components reflect on edge bounce
    private(set) var facing: CGFloat     // +1 rightward, −1 leftward (sprites face right)

    private let sound: SoundPlayer
    private var nextBarkAt: Date
    private var didBurst = false
    /// While the Meeting details are open the Dog freezes in place.
    private var movementHeld = false

    var onFinished: ((AlertController) -> Void)?

    init(meeting: Meeting, isTest: Bool, sound: SoundPlayer) {
        self.meeting = meeting
        self.isTest = isTest
        self.sound = sound
        self.dog = DogModel.random()
        self.position = CGPoint(x: .random(in: 0.1...0.9), y: .random(in: 0.2...0.8))
        // Mostly-horizontal diagonal: slow, clickable pace (R14).
        let horizontalCrossing = TimeInterval.random(in: 16...22)
        let verticalCrossing = horizontalCrossing * TimeInterval.random(in: 1.1...1.9)
        self.velocity = CGVector(
            dx: (Bool.random() ? 1 : -1) / horizontalCrossing,
            dy: (Bool.random() ? 1 : -1) / verticalCrossing
        )
        self.facing = velocity.dx >= 0 ? 1 : -1
        self.nextBarkAt = Date().addingTimeInterval(.random(in: 4...8))
    }

    func advance(by dt: TimeInterval, now: Date) {
        guard state != .finished else { return }

        // Self-expiry: the Meeting's end time passed (R7).
        if now >= meeting.end {
            finish()
            return
        }

        // T−0: overdue, final bark burst, then silence (R11, R16).
        if state == .running && now >= meeting.start {
            state = .overdue
            if !didBurst {
                didBurst = true
                sound.burst()
            }
        }

        guard !movementHeld else { return }

        // Occasional bark while running; silent after T−0 (R16).
        if state == .running, now >= nextBarkAt {
            sound.bark()
            nextBarkAt = now.addingTimeInterval(.random(in: 8...12))
        }

        // Move; reflect off the edges of the unit square (monitor sides, R14).
        position.x += velocity.dx * CGFloat(dt)
        position.y += velocity.dy * CGFloat(dt)
        if position.x < 0 { position.x = -position.x; velocity.dx = abs(velocity.dx) }
        if position.x > 1 { position.x = 2 - position.x; velocity.dx = -abs(velocity.dx) }
        if position.y < 0 { position.y = -position.y; velocity.dy = abs(velocity.dy) }
        if position.y > 1 { position.y = 2 - position.y; velocity.dy = -abs(velocity.dy) }
        facing = velocity.dx >= 0 ? 1 : -1

        // Gait.
        dog.frameClock += dt
        while dog.frameClock >= dog.frameHold {
            dog.frameClock -= dog.frameHold
            dog.frameIndex = (dog.frameIndex + 1) % DogModel.frameCount
        }
    }

    /// Freezes the Dog while its Meeting details are open.
    func setMovementHeld(_ held: Bool) {
        movementHeld = held
        if !held {
            nextBarkAt = max(nextBarkAt, Date().addingTimeInterval(2))
        }
    }

    /// R7: Dismiss from the Meeting details, or Join (details or Banner button -
    /// opens the URL, then behaves exactly like Acknowledge).
    func acknowledge(join: Bool) {
        guard state != .finished else { return }
        if join, let url = meeting.joinURL {
            NSWorkspace.shared.open(url)
        }
        finish()
    }

    /// Torn down externally (meeting deleted/declined/moved — edge table).
    func expire() {
        guard state != .finished else { return }
        finish()
    }

    private func finish() {
        state = .finished
        onFinished?(self)
    }

    /// Banner countdown: `M:SS` before start, `started Xm ago` after (R14, R11).
    func countdownText(now: Date) -> String {
        if now < meeting.start {
            let remaining = max(0, Int(meeting.start.timeIntervalSince(now).rounded(.up)))
            return String(format: "%d:%02d", remaining / 60, remaining % 60)
        }
        let minutes = Int(now.timeIntervalSince(meeting.start) / 60)
        return minutes < 1 ? "started just now" : "started \(minutes)m ago"
    }
}
