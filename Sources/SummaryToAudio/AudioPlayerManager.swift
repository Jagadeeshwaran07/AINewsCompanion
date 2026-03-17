import Foundation
import AVFoundation

@MainActor
public final class AudioPlayerManager: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published public private(set) var isPlaying = false
    @Published public private(set) var isPaused = false
    @Published public private(set) var isLoading = false
    @Published public var error: String?

    /// Called when playback finishes naturally (not on stop/pause).
    public var onPlaybackFinished: (() -> Void)?

    private var player: AVAudioPlayer?

    public override init() {
        super.init()
    }

    public func play(data: Data) {
        print("AudioPlayerManager: Attempting to play audio data (\(data.count) bytes)")
        // Stop any current playback so the previous client's audio (e.g. Sarvam) never keeps playing when switching to another (e.g. ElevenLabs).
        stop()
        do {
            isLoading = false
            isPaused = false

            #if os(iOS)
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.duckOthers])
            try session.setActive(true)
            #endif

            player = try AVAudioPlayer(data: data)
            player?.delegate = self
            player?.prepareToPlay()
            let success = player?.play() ?? false
            print("AudioPlayerManager: player.play() returned \(success)")
            if success {
                isPlaying = true
            }
            error = nil
        } catch {
            print("AudioPlayerManager ERROR: \(error.localizedDescription)")
            self.error = error.localizedDescription
        }
    }

    public func pause() {
        player?.pause()
        isPlaying = false
        isPaused = true
    }

    public func resume() {
        guard player != nil else { return }
        player?.play()
        isPlaying = true
        isPaused = false
    }

    public func stop() {
        player?.stop()
        player = nil
        isPlaying = false
        isPaused = false
    }

    public func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        isPlaying = false
        isPaused = false
        onPlaybackFinished?()
    }

    public func setLoading(_ loading: Bool) {
        isLoading = loading
    }

    public func setError(_ error: String?) {
        self.error = error
    }
}
