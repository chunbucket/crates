import Foundation
import AppKit

/// Runs the pipeline (tools resolved by `Tools`):
/// yt-dlp -f bestaudio -x --audio-format flac --embed-thumbnail --embed-metadata
///        --ffmpeg-location <bundle> --js-runtimes deno:<bundle>/deno
///        --print "after_move:@@done|%(duration)s|%(filepath)s"
///        -P home:<destination> -P temp:<App Support/Cuts/tmp> -o %(title)s.%(ext)s <url>
/// Intermediates (thumbnail, .webm, .part) live in the temp dir, so a failed
/// cut never leaves junk in the music folder.
enum EnqueueResult {
    case started
    case queued
    case duplicate(Cut)   // already filed, file still on disk
    case rejected         // no YouTube video id in the text
}

/// A link waiting its turn. `reuse` is the failed row a retry replaces.
struct QueuedCut: Identifiable {
    let id = UUID()
    let url: String
    let reuse: Cut?
}

final class DownloadManager: ObservableObject {
    @Published var current: ActiveCut?
    /// Waiting their turn (one yt-dlp at a time).
    @Published private(set) var queued: [QueuedCut] = []

    private let library: Library
    private let tools = Tools.shared
    private var proc: Process?
    var onStarted: ((ActiveCut) -> Void)?
    var onFinished: ((Cut) -> Void)?
    var onFailed: ((Cut) -> Void)?

    private static let tempDir = Library.supportDir.appendingPathComponent("tmp", isDirectory: true)

    /// How long a finished / failed card stays up before the shelf moves on
    /// (next queued cut, or slide-out). Failures get long enough to read.
    static func dwell(after phase: CutPhase) -> TimeInterval { phase.isFailed ? 6.0 : 1.4 }

    init(library: Library) {
        self.library = library
        Self.wipeTemp() // leftovers from a crash / force-quit
    }

    /// A cut is in flight or waiting. A finished or failed card may still sit
    /// on `current` for display — that doesn't count as busy.
    var isBusy: Bool {
        !queued.isEmpty || (current.map { !$0.phase.isTerminal } ?? false)
    }

    @discardableResult
    func enqueue(_ rawURL: String) -> EnqueueResult {
        guard let id = YouTubeURL.videoID(in: rawURL) else { return .rejected }
        let url = YouTubeURL.canonical(id)
        // Compare by id, not string: rows filed before canonicalization keep
        // their original long URLs.
        let existing = library.cuts.first { YouTubeURL.videoID(in: $0.url) == id }
        if let existing, !existing.isFailed, existing.fileExists {
            Log.d("duplicate: \(url) already filed as \(existing.cutLabel)")
            return .duplicate(existing)
        }
        // Dropping a link that failed before retries it in place.
        return schedule(url: url, reuse: existing?.isFailed == true ? existing : nil)
    }

    /// Retry a failed row: same CUT Nº, same slot.
    @discardableResult
    func retry(_ cut: Cut) -> EnqueueResult {
        schedule(url: cut.url, reuse: cut)
    }

    private func schedule(url: String, reuse: Cut?) -> EnqueueResult {
        if isBusy {
            if current?.url != url && !queued.contains(where: { $0.url == url }) {
                queued.append(QueuedCut(url: url, reuse: reuse))
            }
            return .queued
        }
        start(url, reuse: reuse)
        return .started
    }

    /// Drop a finished/failed card so the shelf shows its drop target again.
    func dismissResult() {
        if current?.phase.isTerminal == true { current = nil }
    }

    /// App is quitting: stop yt-dlp and clear anything half-written.
    func cancelAll() {
        queued.removeAll()
        proc?.terminate()
        proc = nil
        Self.wipeTemp()
    }

    private func start(_ url: String, reuse: Cut?) {
        let cut = ActiveCut(url: url,
                            cutNumber: reuse?.cutNumber ?? library.nextCutNumber,
                            id: reuse?.id ?? UUID())
        current = cut
        fetchOEmbed(for: cut)
        runYtdlp(for: cut)
        onStarted?(cut)
    }

    private func startNextIfAny() {
        guard !queued.isEmpty else { return }
        let next = queued.removeFirst()
        start(next.url, reuse: next.reuse)
    }

    // MARK: - oEmbed (instant title + art, before yt-dlp even spins up)

    private func fetchOEmbed(for cut: ActiveCut) {
        var comps = URLComponents(string: "https://www.youtube.com/oembed")!
        comps.queryItems = [.init(name: "url", value: cut.url), .init(name: "format", value: "json")]
        URLSession.shared.dataTask(with: comps.url!) { [weak self] data, _, _ in
            guard let data,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
            DispatchQueue.main.async {
                if let t = obj["title"] as? String { cut.title = t }
                if let a = obj["author_name"] as? String { cut.uploader = a }
            }
            if let thumb = obj["thumbnail_url"] as? String, let tURL = URL(string: thumb) {
                self?.fetchArt(tURL, for: cut)
            }
        }.resume()
    }

    private func fetchArt(_ url: URL, for cut: ActiveCut) {
        URLSession.shared.dataTask(with: url) { data, _, _ in
            guard let data else { return }
            let dest = Library.artDir.appendingPathComponent("\(cut.cutNumber).jpg")
            try? data.write(to: dest)
            DispatchQueue.main.async { cut.artPath = dest.path }
        }.resume()
    }

    // MARK: - yt-dlp

    private func runYtdlp(for cut: ActiveCut) {
        guard FileManager.default.isExecutableFile(atPath: tools.ytdlp.path) else {
            finish(cut: cut, exitCode: -1, lastLine: "yt-dlp not found at \(tools.ytdlp.path)")
            return
        }
        let fm = FileManager.default
        try? fm.createDirectory(at: Self.tempDir, withIntermediateDirectories: true)
        try? fm.createDirectory(at: Library.destinationDir, withIntermediateDirectories: true)

        let proc = Process()
        proc.executableURL = tools.ytdlp
        var args = [
            "-f", "bestaudio",
            "-x", "--audio-format", "flac",
            "--embed-thumbnail", "--embed-metadata",
            "--newline", "--no-playlist", "--no-quiet",
            "--socket-timeout", "30", "--retries", "3",
            "--ffmpeg-location", tools.ffmpegDir.path,
        ]
        if let deno = tools.deno { args += ["--js-runtimes", "deno:\(deno.path)"] }
        args += [
            // Duration first: a title may legally contain "|", the path is the remainder.
            "--print", "after_move:@@done|%(duration)s|%(filepath)s",
            "-P", "home:" + Library.destinationDir.path,
            "-P", "temp:" + Self.tempDir.path,
            "-o", "%(title)s.%(ext)s",
            cut.url,
        ]
        proc.arguments = args
        proc.environment = tools.processEnvironment

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe

        var lastLine = ""
        var buffer = Data()
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            buffer.append(chunk)
            while let nl = buffer.firstIndex(of: 0x0A) {
                let lineData = buffer.prefix(upTo: nl)
                buffer.removeSubrange(...nl)
                guard let line = String(data: lineData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespaces), !line.isEmpty else { continue }
                lastLine = line
                self?.handle(line: line, for: cut)
            }
        }

        proc.terminationHandler = { [weak self] p in
            pipe.fileHandleForReading.readabilityHandler = nil
            // Drain whatever is left after termination (the final @@done line usually lands here).
            if let rest = try? pipe.fileHandleForReading.readToEnd(),
               let tail = String(data: rest, encoding: .utf8) {
                for line in tail.split(separator: "\n").map(String.init) {
                    let l = line.trimmingCharacters(in: .whitespaces)
                    if !l.isEmpty { lastLine = l; DispatchQueue.main.sync { self?.handle(line: l, for: cut) } }
                }
            }
            DispatchQueue.main.async {
                self?.finish(cut: cut, exitCode: p.terminationStatus, lastLine: lastLine)
            }
        }

        do {
            try proc.run()
            self.proc = proc
        } catch {
            finish(cut: cut, exitCode: -1, lastLine: "could not launch yt-dlp: \(error.localizedDescription)")
        }
    }

    private var finalPath: String?
    private var finalDuration: Double?

    private func handle(line: String, for cut: ActiveCut) {
        let apply: () -> Void
        if let range = line.range(of: #"\[download\]\s+([\d.]+)%"#, options: .regularExpression) {
            let pctStr = line[range].replacingOccurrences(of: "[download]", with: "")
                .replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)
            let pct = (Double(pctStr) ?? 0) / 100.0
            apply = { cut.phase = .cutting(pct) }
        } else if line.hasPrefix("[ExtractAudio]") || line.hasPrefix("[Metadata]")
                    || line.hasPrefix("[EmbedThumbnail]") || line.hasPrefix("[ThumbnailsConvertor]") {
            apply = { cut.phase = .pressing }
        } else if line.hasPrefix("@@done|") {
            let parts = line.dropFirst("@@done|".count).split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
            if parts.count == 2 {
                finalDuration = Double(parts[0]) // "NA" → nil
                finalPath = String(parts[1])
            }
            apply = {}
        } else if line.hasPrefix("ERROR") {
            apply = { cut.phase = .failed(line) }
        } else {
            apply = {}
        }
        if Thread.isMainThread { apply() } else { DispatchQueue.main.async(execute: apply) }
    }

    private func finish(cut: ActiveCut, exitCode: Int32, lastLine: String) {
        let path = finalPath
        let duration = finalDuration
        finalPath = nil
        finalDuration = nil
        proc = nil

        // The card stays on `current` in its terminal state so "filed ✓" /
        // the failure reason actually render.
        if exitCode == 0, let path, FileManager.default.fileExists(atPath: path) {
            cut.phase = .done
            let record = Cut(
                id: cut.id,
                cutNumber: cut.cutNumber,
                url: cut.url,
                title: cut.hasTitle ? cut.title : URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent,
                uploader: cut.uploader,
                filePath: path,
                artPath: cut.artPath,
                duration: duration,
                date: cut.date
            )
            library.upsert(record)
            onFinished?(record)
        } else {
            let raw: String
            if case .failed(let e) = cut.phase { raw = e } else { raw = lastLine }
            let msg = Self.humanize(raw, exitCode: exitCode)
            Log.d("cut failed (exit \(exitCode)) url=\(cut.url): \(raw)")
            Self.wipeTemp()
            // No oEmbed title either (private/removed video): show the link instead.
            if !cut.hasTitle { cut.title = YouTubeURL.display(cut.url) }
            cut.phase = .failed(msg)
            let record = Cut(
                id: cut.id,
                cutNumber: cut.cutNumber,
                url: cut.url,
                title: cut.title,
                uploader: cut.uploader,
                status: CutStatus.failed,
                error: msg,
                filePath: nil,
                artPath: cut.artPath,
                duration: nil,
                date: cut.date
            )
            library.upsert(record)
            onFailed?(record)
        }

        // The next queued cut replaces the result card after its dwell.
        if !queued.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.dwell(after: cut.phase)) { [weak self] in
                self?.startNextIfAny()
            }
        }
    }

    /// yt-dlp's error line → something a person can act on.
    private static func humanize(_ raw: String, exitCode: Int32) -> String {
        var s = raw
        if s.hasPrefix("ERROR:") { s = String(s.dropFirst(6)).trimmingCharacters(in: .whitespaces) }
        // "[youtube] abc123def45: This video is unavailable" → "This video is unavailable"
        if let r = s.range(of: #"^\[[^\]]+\]\s+[A-Za-z0-9_-]{11}:\s*"#, options: .regularExpression) {
            s.removeSubrange(r)
        }
        if s.contains("403") {
            s = "YouTube refused the download (403) — update yt-dlp in Settings, then retry"
        } else if s.lowercased().contains("sign in to confirm") {
            s = "YouTube wants a sign-in (bot check) — try again later or update yt-dlp"
        }
        if s.isEmpty { s = "yt-dlp exited with code \(exitCode)" }
        return s
    }

    private static func wipeTemp() {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil) else { return }
        for item in items { try? fm.removeItem(at: item) }
    }
}
