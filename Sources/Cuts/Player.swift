import AVFoundation

/// Row playback for the collection: one track at a time, seekable.
/// AVAudioPlayer decodes FLAC natively on macOS.
final class Player: NSObject, ObservableObject, AVAudioPlayerDelegate {
    static let shared = Player()

    @Published private(set) var cutID: UUID?
    @Published private(set) var isPlaying = false
    @Published private(set) var time: Double = 0
    private(set) var duration: Double = 0

    private var player: AVAudioPlayer?
    private var timer: Timer?

    func isCurrent(_ cut: Cut) -> Bool { cutID == cut.id }

    /// Play from the start, or resume if this cut is already loaded.
    func play(_ cut: Cut) {
        if isCurrent(cut), let player {
            player.play()
            isPlaying = true
            startTimer()
            return
        }
        stop()
        guard let url = cut.fileURL else { return }
        do {
            let p = try AVAudioPlayer(contentsOf: url)
            p.delegate = self
            p.prepareToPlay()
            player = p
            cutID = cut.id
            duration = p.duration
            time = 0
            p.play()
            isPlaying = true
            startTimer()
        } catch {
            Log.d("player: can't open \(url.lastPathComponent): \(error.localizedDescription)")
        }
    }

    func pause() {
        player?.pause()
        isPlaying = false
        timer?.invalidate()
    }

    func toggle(_ cut: Cut) {
        if isCurrent(cut) && isPlaying { pause() } else { play(cut) }
    }

    func seek(to seconds: Double) {
        guard let player else { return }
        player.currentTime = max(0, min(seconds, duration))
        time = player.currentTime
    }

    func stop() {
        player?.stop()
        player = nil
        cutID = nil
        isPlaying = false
        time = 0
        duration = 0
        timer?.invalidate()
    }

    func stopIfCurrent(_ cut: Cut) {
        if isCurrent(cut) { stop() }
    }

    private func startTimer() {
        timer?.invalidate()
        let t = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self, let player = self.player else { return }
            self.time = player.currentTime
        }
        RunLoop.main.add(t, forMode: .common) // keeps ticking while a drag or menu is up
        timer = t
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        isPlaying = false
        time = duration
        timer?.invalidate()
    }
}
