import Foundation
import Testing
@testable import Meetie

struct SoundPlayerTests {
    @Test func barkDoesNotWaitForSlowAudioPlayback() {
        let settings = SettingsStore()
        let previousSoundSetting = settings.soundEnabled
        settings.soundEnabled = true
        defer { settings.soundEnabled = previousSoundSetting }

        let player = SlowSoundPlayer()
        let sound = SoundPlayer(
            settings: settings,
            barkPlayers: [player],
            burstPlayer: nil,
            warmsAudioOutput: false
        )

        let start = CFAbsoluteTimeGetCurrent()
        sound.bark()
        let elapsed = CFAbsoluteTimeGetCurrent() - start

        #expect(elapsed < 0.02)
        #expect(player.playStarted.wait(timeout: .now() + 1) == .success)
    }
}

private final class SlowSoundPlayer: SoundPlaying {
    var currentTime: TimeInterval = 0
    var isPlaying = false
    var volume: Float = 1
    let playStarted = DispatchSemaphore(value: 0)

    func pause() {}
    func stop() {}
    func prepareToPlay() -> Bool { true }

    func play() -> Bool {
        playStarted.signal()
        Thread.sleep(forTimeInterval: 0.1)
        return true
    }
}
