import AVFoundation
import Foundation

protocol SoundPlaying: AnyObject {
    var currentTime: TimeInterval { get set }
    var isPlaying: Bool { get }
    var volume: Float { get set }

    func pause()
    func stop()
    func prepareToPlay() -> Bool
    func play() -> Bool
}

extension AVAudioPlayer: SoundPlaying {}

/// Bark playback through the default output at system volume via AVAudioPlayer -
/// deliberately not Notification Center, so Focus/DND cannot suppress it (R16).
final class SoundPlayer {
    /// Prepared players keep decoding and output startup off the animation tick.
    private let barkPlayers: [SoundPlaying]
    /// `dog_barking_mono_full` is preferred for the T−0 burst (R16a).
    private let burstPlayer: SoundPlaying?
    private let settings: SettingsStore
    private let playbackQueue = DispatchQueue(label: "com.meetie.audio-playback")

    convenience init(settings: SettingsStore) {
        let barkPlayers: [SoundPlaying] = Assets.barkSampleURLs().compactMap {
            try? AVAudioPlayer(contentsOf: $0)
        }
        let burstPlayer = Assets.burstSampleURL().flatMap {
            try? AVAudioPlayer(contentsOf: $0)
        }
        self.init(
            settings: settings,
            barkPlayers: barkPlayers,
            burstPlayer: burstPlayer,
            warmsAudioOutput: true
        )
    }

    init(
        settings: SettingsStore,
        barkPlayers: [SoundPlaying],
        burstPlayer: SoundPlaying?,
        warmsAudioOutput: Bool
    ) {
        self.settings = settings
        self.barkPlayers = barkPlayers
        self.burstPlayer = burstPlayer
        preparePlayers(warmsAudioOutput: warmsAudioOutput)
    }

    func bark() {
        guard settings.soundEnabled else { return }  // R21 Sound toggle
        playbackQueue.async { [self] in
            guard let player = barkPlayers.filter({ !$0.isPlaying }).randomElement() else {
                return
            }
            play(player)
        }
    }

    func burst() {
        guard settings.soundEnabled else { return }  // R21 Sound toggle
        playbackQueue.async { [self] in
            guard let player = burstPlayer ?? barkPlayers.randomElement() else {
                return
            }
            play(player)
        }
    }

    private func preparePlayers(warmsAudioOutput: Bool) {
        let players = barkPlayers + [burstPlayer].compactMap { $0 }
        for player in players {
            player.volume = 1
            if !player.prepareToPlay() {
                NSLog("Meetie: failed to prepare a bark sound")
            }
        }

        // Starting the output device can take tens of milliseconds. Do it once,
        // silently, during app launch before any Dog animation is running.
        guard warmsAudioOutput, let warmup = players.first else { return }
        warmup.volume = 0
        if warmup.play() {
            warmup.pause()
            warmup.currentTime = 0
        } else {
            NSLog("Meetie: failed to warm the audio output")
        }
        warmup.volume = 1
    }

    private func play(_ player: SoundPlaying) {
        if player.isPlaying {
            player.stop()
        }
        player.currentTime = 0
        if !player.play() {
            NSLog("Meetie: failed to play a bark sound")
        }
    }
}
