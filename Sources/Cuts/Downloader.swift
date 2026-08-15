import Foundation
import AppKit

/// Runs the validated pipeline:
/// yt-dlp -f bestaudio -x --audio-format flac --embed-thumbnail --embed-metadata
///        --newline --no-playlist --print after_move:filepath --no-quiet -o <dest>/%(title)s.%(ext)s <url>
final class DownloadManager: ObservableObject {
    @Published var current: ActiveCut?
    private var queue: [String] = []
    private let library: Library
    var onFinished: ((Cut) -> Void)?
    var onFailed: ((String) -> Void)?

    private static let ytdlp = "/opt/homebrew/bin/yt-dlp"

    init(library: Library) {
        self.library = library
    }

    var isBusy: Bool { current != nil }

    func enqueue(_ url: String) {
        if isBusy {
            if !queue.contains(url) { queue.append(url) }
            return
        }
        start(url)
    }

    private func start(_ url: String) {
        let cut = ActiveCut(url: url, cutNumber: library.nextCutNumber)
        current = cut
        fetchOEmbed(for: cut)
        runYtdlp(for: cut)
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
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: Self.ytdlp)
        proc.arguments = [
            "-f", "bestaudio",
            "-x", "--audio-format", "flac",
            "--embed-thumbnail", "--embed-metadata",
            "--newline", "--no-playlist",
            "--print", "after_move:filepath", "--no-quiet",
            "-o", Library.destinationDir.path + "/%(title)s.%(ext)s",
            cut.url,
        ]
        // Apps launched from Finder/`open` get a bare PATH without
        // /opt/homebrew/bin — yt-dlp then can't find ffmpeg for the
        // FLAC extraction step. Make it explicit.
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "/opt/homebrew/bin:" + (env["PATH"] ?? "/usr/bin:/bin")
        proc.environment = env

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
            // Drain whatever is left after termination (the final filepath usually lands here).
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
        } catch {
            finish(cut: cut, exitCode: -1, lastLine: "could not launch yt-dlp: \(error.localizedDescription)")
        }
    }

    private var finalPath: String?

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
        } else if line.hasPrefix("/"), line.lowercased().hasSuffix(".flac") {
            finalPath = line
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
        // Clear busy state BEFORE callbacks so isBusy is accurate inside them
        // (the shelf's auto-dismiss checks it).
        current = nil
        finalPath = nil
        defer { if !queue.isEmpty { start(queue.removeFirst()) } }

        guard exitCode == 0, let path else {
            let msg: String
            if case .failed(let e) = cut.phase { msg = e } else { msg = lastLine }
            Log.d("cut failed (exit \(exitCode)) url=\(cut.url): \(msg)")
            cut.phase = .failed(msg)
            onFailed?(msg)
            return
        }
        cut.phase = .done
        let record = Cut(
            id: UUID(),
            cutNumber: cut.cutNumber,
            url: cut.url,
            title: cut.title == "Fetching…" ? (path as NSString).lastPathComponent : cut.title,
            uploader: cut.uploader,
            filePath: path,
            artPath: cut.artPath,
            duration: Self.probeDuration(path),
            date: cut.date
        )
        library.add(record)
        onFinished?(record)
    }

    private static func probeDuration(_ path: String) -> Double? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/ffprobe")
        p.arguments = ["-v", "quiet", "-show_entries", "format=duration", "-of", "csv=p=0", path]
        let pipe = Pipe()
        p.standardOutput = pipe
        guard (try? p.run()) != nil else { return nil }
        p.waitUntilExit()
        guard let data = try? pipe.fileHandleForReading.readToEnd(),
              let s = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        else { return nil }
        return Double(s)
    }
}
