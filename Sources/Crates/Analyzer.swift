import AVFoundation
import Accelerate

struct Analysis {
    let bpm: Double
    let key: String      // "A minor"
    let camelot: String  // "8A"
}

struct AnalysisError: Error { let what: String }

/// BPM and key from the audio itself, in-process with Accelerate. Tuned for
/// what this app records — 4/4 electronic music — not a general MIR tool.
///
/// Tempo: onset envelope (log-spectral flux) → autocorrelation over 60–200 BPM
/// with a log-normal prior around 125 → parabolic refinement.
/// Key: chroma from interpolated spectral peaks (not raw bins, whose uneven
/// low-frequency coverage biases everything toward a few pitch classes) →
/// Krumhansl–Kessler profiles → best of 24, with the bass root breaking the
/// relative major/minor tie.
enum Analyzer {
    /// Bump when the algorithm changes so every record gets re-analysed.
    static let version = 2

    private static let sampleRate: Double = 22_050
    private static let window = 2048
    private static let hop = 256
    private static let seconds: Double = 90   // the middle of the track

    static func analyze(_ url: URL) throws -> Analysis {
        let samples = try load(url)
        let f = features(samples)
        let bpm = tempo(f.flux, fps: f.fps)
        let (key, camelot) = key(chroma: f.chroma, bass: f.bass)
        return Analysis(bpm: bpm, key: key, camelot: camelot)
    }

    // MARK: - Decode: middle 90 s, mono, 22.05 kHz

    private static func load(_ url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let src = file.processingFormat
        let total = file.length
        let want = AVAudioFramePosition(seconds * src.sampleRate)
        let start = max(0, (total - want) / 2)
        let count = AVAudioFrameCount(min(want, total - start))
        guard count > AVAudioFrameCount(src.sampleRate * 5) else { throw AnalysisError(what: "too short") }
        file.framePosition = start
        guard let inBuf = AVAudioPCMBuffer(pcmFormat: src, frameCapacity: count) else { throw AnalysisError(what: "buffer") }
        try file.read(into: inBuf, frameCount: count)

        // Downmix to mono at the source rate, then resample.
        guard let monoSrc = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: src.sampleRate, channels: 1, interleaved: false),
              let monoBuf = AVAudioPCMBuffer(pcmFormat: monoSrc, frameCapacity: count),
              let inData = inBuf.floatChannelData, let monoData = monoBuf.floatChannelData else { throw AnalysisError(what: "buffer") }
        let n = Int(inBuf.frameLength)
        let channels = Int(src.channelCount)
        vDSP_vclr(monoData[0], 1, vDSP_Length(n))
        for ch in 0..<channels { vDSP_vadd(monoData[0], 1, inData[ch], 1, monoData[0], 1, vDSP_Length(n)) }
        var scale = 1 / Float(channels)
        vDSP_vsmul(monoData[0], 1, &scale, monoData[0], 1, vDSP_Length(n))
        monoBuf.frameLength = AVAudioFrameCount(n)

        guard let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: monoSrc, to: target) else { throw AnalysisError(what: "converter") }
        let outCap = AVAudioFrameCount(Double(n) * sampleRate / src.sampleRate) + 4096
        guard let outBuf = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: outCap) else { throw AnalysisError(what: "buffer") }
        var handedOver = false
        var error: NSError?
        let status = converter.convert(to: outBuf, error: &error) { _, outStatus in
            if handedOver { outStatus.pointee = .endOfStream; return nil }
            handedOver = true
            outStatus.pointee = .haveData
            return monoBuf
        }
        guard status != .error, let out = outBuf.floatChannelData else { throw error ?? AnalysisError(what: "convert") }
        return Array(UnsafeBufferPointer(start: out[0], count: Int(outBuf.frameLength)))
    }

    // MARK: - One STFT pass → onset envelope + chroma

    private static func features(_ samples: [Float]) -> (flux: [Float], chroma: [Float], bass: [Float], fps: Double) {
        let n = window, half = n / 2
        let log2n = vDSP_Length(log2(Double(n)))
        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return ([], [], [], 0) }
        defer { vDSP_destroy_fftsetup(setup) }

        var hann = [Float](repeating: 0, count: n)
        vDSP_hann_window(&hann, vDSP_Length(n), Int32(vDSP_HANN_NORM))

        // Peaks are read between these bins (≈80 Hz … 5 kHz); below 260 Hz they
        // also feed the bass chroma that names the root.
        let binHz = sampleRate / Double(n)
        let kMin = max(2, Int(80 / binHz)), kMax = min(half - 2, Int(5000 / binHz))
        let bassCeiling = 260.0

        var frame = [Float](repeating: 0, count: n)
        var real = [Float](repeating: 0, count: half)
        var imag = [Float](repeating: 0, count: half)
        var mags = [Float](repeating: 0, count: half)
        var prevLog = [Float](repeating: 0, count: half)
        var logMag = [Float](repeating: 0, count: half)
        var chroma = [Float](repeating: 0, count: 12)
        var bass = [Float](repeating: 0, count: 12)
        var flux: [Float] = []
        let frames = max(0, (samples.count - n) / hop + 1)
        flux.reserveCapacity(frames)

        samples.withUnsafeBufferPointer { src in
            for t in 0..<frames {
                vDSP_vmul(src.baseAddress! + t * hop, 1, hann, 1, &frame, 1, vDSP_Length(n))
                real.withUnsafeMutableBufferPointer { rp in
                    imag.withUnsafeMutableBufferPointer { ip in
                        var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                        frame.withUnsafeBufferPointer { fp in
                            fp.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: half) { cp in
                                vDSP_ctoz(cp, 2, &split, 1, vDSP_Length(half))
                            }
                        }
                        vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                        vDSP_zvabs(&split, 1, &mags, 1, vDSP_Length(half))
                    }
                }
                mags[0] = 0 // DC / Nyquist packing
                // log(1 + |X|)
                var one: Float = 1
                vDSP_vsadd(mags, 1, &one, &logMag, 1, vDSP_Length(half))
                var count = Int32(half)
                vvlogf(&logMag, logMag, &count)
                // onset strength: rectified spectral flux
                var f: Float = 0
                if t > 0 {
                    for k in 0..<half { let d = logMag[k] - prevLog[k]; if d > 0 { f += d } }
                }
                flux.append(f)
                swap(&prevLog, &logMag)
                // Chroma from spectral peaks, each placed by parabolic
                // interpolation so a low bin doesn't smear across semitones.
                var frameMax: Float = 0
                vDSP_maxv(mags, 1, &frameMax, vDSP_Length(half))
                let threshold = frameMax * 0.02
                guard frameMax > 0 else { continue }
                for k in kMin...kMax where mags[k] > threshold && mags[k] > mags[k - 1] && mags[k] >= mags[k + 1] {
                    let y0 = mags[k - 1], y1 = mags[k], y2 = mags[k + 1]
                    let denom = y0 - 2 * y1 + y2
                    let offset = abs(denom) > 1e-9 ? 0.5 * (y0 - y2) / denom : 0
                    let freq = (Double(k) + Double(offset)) * binHz
                    let midi = 69 + 12 * log2(freq / 440)
                    let pc = ((Int(midi.rounded()) % 12) + 12) % 12
                    let weight = log1p(y1)
                    chroma[pc] += weight
                    if freq < bassCeiling { bass[pc] += weight }
                }
            }
        }
        let fps = sampleRate / Double(hop)
        return (flux, chroma, bass, fps)
    }

    // MARK: - Tempo

    private static func tempo(_ flux: [Float], fps: Double) -> Double {
        let n = flux.count
        guard n > Int(fps * 10) else { return 0 }
        // Detrend with a half-second moving average, then rectify: leaves the pulse.
        let w = max(1, Int(fps * 0.5))
        var env = [Float](repeating: 0, count: n)
        var running: Float = 0
        for i in 0..<n {
            running += flux[i]
            if i >= w { running -= flux[i - w] }
            let mean = running / Float(min(i + 1, w))
            env[i] = max(0, flux[i] - mean)
        }
        let minLag = Int(fps * 60 / 200), maxLag = Int(fps * 60 / 60)
        // Autocorrelation out to twice the slowest lag, for harmonic summation.
        var acf = [Double](repeating: 0, count: 2 * maxLag + 3)
        for lag in (minLag - 1)...(2 * maxLag + 2) where lag > 0 && lag < n {
            var dot: Float = 0
            vDSP_dotpr(env, 1, Array(env[lag...]), 1, &dot, vDSP_Length(n - lag))
            acf[lag] = Double(dot) / Double(n - lag)
        }
        // Log-normal prior around 125 BPM settles half/double; scoring a lag
        // together with its double (harmonic summation) settles the 3:2
        // "dotted" error a syncopated bassline invites.
        func prior(_ bpm: Double) -> Double { exp(-0.5 * pow(log2(bpm / 125) / 0.7, 2)) }
        var bestLag = minLag, bestScore = -1.0
        for lag in minLag...maxLag {
            let score = (acf[lag] + 0.5 * acf[2 * lag]) * prior(60 * fps / Double(lag))
            if score > bestScore { bestScore = score; bestLag = lag }
        }
        // Parabolic interpolation on the raw autocorrelation for sub-frame precision.
        var lag = Double(bestLag)
        if bestLag > minLag - 1, bestLag < maxLag + 1 {
            let y0 = acf[bestLag - 1], y1 = acf[bestLag], y2 = acf[bestLag + 1]
            let denom = y0 - 2 * y1 + y2
            if abs(denom) > 1e-12 { lag += 0.5 * (y0 - y2) / denom }
        }
        return (60 * fps / lag * 10).rounded() / 10
    }

    // MARK: - Key

    private static let major: [Float] = [6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88]
    private static let minor: [Float] = [6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17]
    private static let names = ["C", "Db", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B"]
    private static let camelotMinor = [5, 12, 7, 2, 9, 4, 11, 6, 1, 8, 3, 10]
    private static let camelotMajor = [8, 3, 10, 5, 12, 7, 2, 9, 4, 11, 6, 1]

    private static func key(chroma: [Float], bass: [Float]) -> (String, String) {
        guard chroma.count == 12, chroma.reduce(0, +) > 0 else { return ("", "") }
        // The bass line's most-played note, as a tonic bonus: profiles alone
        // can't tell a key from its relative, the bass usually can.
        let bassMax = max(bass.max() ?? 0, 1e-6)
        var best = (score: -Double.infinity, tonic: 0, isMinor: false)
        for tonic in 0..<12 {
            for (profile, isMinor) in [(major, false), (minor, true)] {
                let rotated = (0..<12).map { profile[($0 - tonic + 12) % 12] }
                let r = pearson(chroma, rotated) + 0.2 * Double(bass[tonic] / bassMax)
                if r > best.score { best = (r, tonic, isMinor) }
            }
        }
        let name = "\(names[best.tonic]) \(best.isMinor ? "minor" : "major")"
        let camelot = "\(best.isMinor ? camelotMinor[best.tonic] : camelotMajor[best.tonic])\(best.isMinor ? "A" : "B")"
        return (name, camelot)
    }

    private static func pearson(_ a: [Float], _ b: [Float]) -> Double {
        let n = Double(a.count)
        let ma = a.reduce(0, +) / Float(n), mb = b.reduce(0, +) / Float(n)
        var num = 0.0, da = 0.0, db = 0.0
        for i in 0..<a.count {
            let x = Double(a[i] - ma), y = Double(b[i] - mb)
            num += x * y; da += x * x; db += y * y
        }
        return da > 0 && db > 0 ? num / (da * db).squareRoot() : 0
    }
}

/// Runs the analyser in the background, one record at a time, and writes the
/// result back into the library.
final class AnalysisQueue {
    static let shared = AnalysisQueue()
    private let queue = DispatchQueue(label: "crates.analysis", qos: .utility)
    private var pending = Set<UUID>()

    func enqueue(_ record: Record, library: Library) {
        guard !record.isFailed, let url = record.fileURL,
              record.analysis < Analyzer.version, !pending.contains(record.id) else { return }
        pending.insert(record.id)
        queue.async {
            let started = Date()
            let result = try? Analyzer.analyze(url)
            DispatchQueue.main.async {
                self.pending.remove(record.id)
                guard var current = library.records.first(where: { $0.id == record.id }) else { return }
                if let r = result {
                    current.bpm = r.bpm
                    current.key = r.key
                    current.camelot = r.camelot
                }
                current.analysis = Analyzer.version   // tried; don't loop on a file that won't decode
                library.upsert(current)
                Log.d(String(format: "analysed %@: %@ (%.1fs)", record.title,
                             result.map { "\($0.bpm) BPM · \($0.camelot) \($0.key)" } ?? "failed", Date().timeIntervalSince(started)))
            }
        }
    }

    /// Everything filed that the current analyser hasn't seen.
    func backfill(_ library: Library) {
        for record in library.records { enqueue(record, library: library) }
    }
}
