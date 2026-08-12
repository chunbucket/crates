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

    func split(_ cut: Cut) {
        guard isConfigured else {
            showSetupInstructions()
            return
        }
        guard !inFlight.contains(cut.filePath) else { return }
        inFlight.insert(cut.filePath)
        failed.remove(cut.filePath)
        status[cut.filePath] = "starting…"
        Log.d("stem-split started: \(cut.filePath)")

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        // Headed for now: headless Chromium gets stonewalled by Cloudflare
        // without a warm clearance cookie. Revisit after a proven headed run.
        proc.arguments = ["-u", Self.scriptPath, cut.filePath]
        proc.environment = ProcessInfo.processInfo.environment

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
                } else {
                    self.failed.insert(cut.filePath)
                    let msg = self.status[cut.filePath].flatMap { $0.hasPrefix("failed") ? $0 : nil }
                        ?? "failed — see stemsplit.log"
                    self.status[cut.filePath] = msg
                    self.lastError = msg
                    Log.d("stem-split failed (exit \(p.terminationStatus))")
                    NSSound.beep()
                }
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

    private func showSetupInstructions() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Stem splitting needs a one-time setup"
        alert.informativeText = """
        The splitter rides your vocalremover.org Pro login through a real \
        browser (their API is Cloudflare-gated, so there's no direct route).

        One-time setup, in Terminal:

        1.  python3 -m pip install --user playwright
        2.  python3 ~/.claude/skills/stem-split/setup_auth.py
            (a browser opens — sign in to vocalremover.org, then press Enter)

        After that, Split to Stems works from this menu.
        """
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
