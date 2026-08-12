import AppKit

/// Bridges Cuts to the stem-split runner (vocalremover.org Pro 5-stem via
/// Playwright — see ~/.claude/skills/stem-split). vocalremover's API sits
/// behind Cloudflare + Google OAuth, so splits must ride a real browser
/// context; the runner owns that. Cuts shells out, streams the runner's
/// "::CUTS::" progress lines, and shows live status per track.
final class StemSplitter: ObservableObject {
    @Published var inFlight: Set<String> = []          // file paths splitting now
    @Published var status: [String: String] = [:]      // file path → live status line
    @Published var failed: Set<String> = []            // file paths whose last split failed
    @Published var stemsVersion = 0                    // bumped when stems land (invalidates row caches)
    @Published var lastError: String?

    static let shared = StemSplitter()

    static let stemOrder = ["vocals", "drums", "bass", "guitar", "music"]
    static let stemsRoot = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("ency_me/making music/song samples/stems", isDirectory: true)

    private static var home: String { FileManager.default.homeDirectoryForCurrentUser.path }
    private static var authPath: String { home + "/.config/stem-split/auth.json" }
    private static var scriptPath: String { home + "/.claude/skills/stem-split/split.py" }

    var isConfigured: Bool {
        FileManager.default.fileExists(atPath: Self.authPath)
            && FileManager.default.fileExists(atPath: Self.scriptPath)
    }

    /// Stems on disk for a track, in vocals→drums→bass→guitar→music order.
    static func existingStems(forBasename base: String) -> [URL] {
        stemOrder.compactMap {
            let u = stemsRoot.appendingPathComponent($0).appendingPathComponent(base + ".wav")
            return FileManager.default.fileExists(atPath: u.path) ? u : nil
        }
    }

    /// vocalremover Pro per-file cap (free tier is 8 min; Pro sign-in required anyway).
    static let durationLimit: Double = 25 * 60

    func split(_ cut: Cut) {
        guard isConfigured else {
            showSetupInstructions()
            return
        }
        guard !inFlight.contains(cut.filePath) else { return }

        if let dur = cut.duration, dur > Self.durationLimit + 1 {
            guard let range = promptTrimRange(title: cut.title, duration: dur) else { return }
            trimAndSplit(cut, range: range)
            return
        }
        runSplit(fileToUpload: cut.filePath, cut: cut)
    }

    // MARK: - Trim flow (tracks longer than the service cap)

    private func promptTrimRange(title: String, duration: Double) -> (start: Double, end: Double)? {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Too long for the splitter — trim a section"
        alert.informativeText =
            "vocalremover caps files at 25 min (this one is \(Self.mmss(duration))). " +
            "Pick the section to split; a trimmed copy is sent, your original is untouched."
        let stack = NSStackView(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        let startField = NSTextField(string: "0:00")
        let endField = NSTextField(string: Self.mmss(min(duration, Self.durationLimit)))
        startField.frame = NSRect(x: 0, y: 0, width: 90, height: 24)
        endField.frame = NSRect(x: 130, y: 0, width: 90, height: 24)
        let arrow = NSTextField(labelWithString: "→")
        arrow.frame = NSRect(x: 98, y: 2, width: 26, height: 20)
        arrow.alignment = .center
        stack.addSubview(startField)
        stack.addSubview(arrow)
        stack.addSubview(endField)
        alert.accessoryView = stack
        alert.addButton(withTitle: "Trim & Split")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }

        let start = Self.parseTime(startField.stringValue) ?? 0
        var end = Self.parseTime(endField.stringValue) ?? min(duration, Self.durationLimit)
        end = min(end, duration)
        guard end > start else { return nil }
        if end - start > Self.durationLimit { end = start + Self.durationLimit }
        return (start, end)
    }

    private func trimAndSplit(_ cut: Cut, range: (start: Double, end: Double)) {
        inFlight.insert(cut.filePath)
        failed.remove(cut.filePath)
        status[cut.filePath] = "trimming \(Self.mmss(range.start))–\(Self.mmss(range.end))…"

        let trimsDir = Library.supportDir.appendingPathComponent("trims", isDirectory: true)
        try? FileManager.default.createDirectory(at: trimsDir, withIntermediateDirectories: true)
        // Same basename as the original so stems file under the same name.
        let trimmed = trimsDir.appendingPathComponent((cut.filePath as NSString).lastPathComponent)

        let ff = Process()
        ff.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")
        ff.arguments = ["-y", "-v", "error",
                        "-ss", String(format: "%.2f", range.start),
                        "-i", cut.filePath,
                        "-t", String(format: "%.2f", range.end - range.start),
                        "-c:a", "flac", trimmed.path]
        ff.terminationHandler = { [weak self] p in
            DispatchQueue.main.async {
                guard let self else { return }
                self.inFlight.remove(cut.filePath)
                guard p.terminationStatus == 0 else {
                    self.failed.insert(cut.filePath)
                    self.status[cut.filePath] = "trim failed — is ffmpeg ok?"
                    return
                }
                self.runSplit(fileToUpload: trimmed.path, cut: cut)
            }
        }
        do { try ff.run() } catch {
            inFlight.remove(cut.filePath)
            status[cut.filePath] = "couldn't launch ffmpeg"
        }
    }

    // MARK: - Runner

    private func runSplit(fileToUpload: String, cut: Cut, headless: Bool = true) {
        inFlight.insert(cut.filePath)
        failed.remove(cut.filePath)
        status[cut.filePath] = headless ? "starting…" : "retrying with visible browser…"
        Log.d("stem-split started: \(fileToUpload) headless=\(headless) (row: \(cut.filePath))")

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        proc.arguments = ["-u", Self.scriptPath, fileToUpload]
        var env = ProcessInfo.processInfo.environment
        if headless { env["HEADLESS"] = "1" }
        proc.environment = env

        let logURL = Library.supportDir.appendingPathComponent("stemsplit.log")
        if !FileManager.default.fileExists(atPath: logURL.path) {
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
        }
        let logHandle = try? FileHandle(forWritingTo: logURL)
        logHandle?.seekToEndOfFile()

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe

        var buffer = Data()
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            logHandle?.write(chunk)
            buffer.append(chunk)
            while let nl = buffer.firstIndex(of: 0x0A) {
                let lineData = buffer.prefix(upTo: nl)
                buffer.removeSubrange(...nl)
                guard let line = String(data: lineData, encoding: .utf8) else { continue }
                self?.parse(line: line, for: cut.filePath)
            }
        }

        proc.terminationHandler = { [weak self] p in
            pipe.fileHandleForReading.readabilityHandler = nil
            try? logHandle?.close()
            DispatchQueue.main.async {
                guard let self else { return }
                self.inFlight.remove(cut.filePath)
                self.stemsVersion += 1
                if p.terminationStatus == 0 {
                    self.status[cut.filePath] = "stems filed ✓"
                    Log.d("stem-split done: \(cut.title)")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                        self.status.removeValue(forKey: cut.filePath)
                    }
                    return
                }
                let msg = self.status[cut.filePath] ?? "failed — see stemsplit.log"
                // Hidden-browser run walled off before the upload field appeared
                // (Cloudflare fingerprint check) → retry once with a visible window.
                // Auth problems won't be fixed by a window, so those don't retry.
                let looksLikeWall = msg.contains("set_input_files") || msg.contains("Timeout")
                if headless && looksLikeWall && !msg.contains("not signed in") {
                    Log.d("stem-split headless walled — retrying headed")
                    self.runSplit(fileToUpload: fileToUpload, cut: cut, headless: false)
                    return
                }
                self.failed.insert(cut.filePath)
                let display = msg.hasPrefix("failed") ? msg : "failed — see stemsplit.log"
                self.status[cut.filePath] = display
                self.lastError = display
                Log.d("stem-split failed (exit \(p.terminationStatus)): \(msg)")
                NSSound.beep()
            }
        }

        do {
            try proc.run()
        } catch {
            inFlight.remove(cut.filePath)
            status[cut.filePath] = "couldn't launch runner"
            lastError = "could not launch stem-split: \(error.localizedDescription)"
        }
    }

    private func parse(line: String, for filePath: String) {
        guard let range = line.range(of: "::CUTS:: ") else { return }
        guard let data = line[range.upperBound...].data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let stage = obj["stage"] as? String else { return }

        let text: String?
        switch stage {
        case "start":       text = "opening vocalremover…"
        case "uploading":   text = "uploading…"
        case "processing":
            let secs = obj["elapsed"] as? Int ?? 0
            text = String(format: "splitting on vocalremover… %d:%02d", secs / 60, secs % 60)
        case "processed":   text = "split done, grabbing stems…"
        case "downloading": text = "downloading stems…"
        case "stem_saved":
            let n = obj["count"] as? Int ?? 0
            let stem = obj["stem"] as? String ?? ""
            text = "saved \(stem) — \(n)/5"
        case "partial":
            let n = obj["count"] as? Int ?? 0
            text = "failed — only \(n)/5 stems came down"
        case "done":        text = "stems filed ✓"
        case "error":
            let msg = obj["msg"] as? String ?? "unknown"
            text = "failed — \(String(msg.prefix(60)))"
        default:            text = nil
        }
        if let text {
            DispatchQueue.main.async { [weak self] in
                self?.status[filePath] = text
                if stage == "stem_saved" { self?.stemsVersion += 1 }
            }
        }
    }

    // MARK: - Helpers

    static func mmss(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    /// Accepts "m:ss", "mm:ss", "h:mm:ss", or plain seconds.
    static func parseTime(_ raw: String) -> Double? {
        let parts = raw.trimmingCharacters(in: .whitespaces).split(separator: ":").map(String.init)
        guard !parts.isEmpty, parts.allSatisfy({ Double($0) != nil }) else { return nil }
        return parts.reversed().enumerated().reduce(0.0) { acc, pair in
            acc + (Double(pair.element) ?? 0) * pow(60, Double(pair.offset))
        }
    }

    private func showSetupInstructions() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Stem splitting needs a one-time setup"
        alert.informativeText = """
        The splitter rides your vocalremover.org Pro login through a real \
        browser (their API is Cloudflare-gated, so there's no direct route).

        One-time setup, in Terminal:

        python3 ~/.claude/skills/stem-split/setup_auth.py

        A browser opens — SIGN IN with your Pro account on the splitter
        page (top-right icon), and only then press Enter in Terminal.
        Without the sign-in, files over 8 min are rejected and you only
        get the free 4-stem model.
        """
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
