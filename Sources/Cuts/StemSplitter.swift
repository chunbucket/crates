import AppKit

/// Bridges Cuts to the stem-split runner (vocalremover.org Pro 5-stem via
/// Playwright — see ~/.claude/skills/stem-split). vocalremover's API sits
/// behind Cloudflare + Google OAuth, so splits must ride a real browser
/// context; the runner owns that. Cuts just shells out and tracks state.
final class StemSplitter: ObservableObject {
    @Published var inFlight: Set<String> = []   // file paths currently splitting
    @Published var lastError: String?

    static let shared = StemSplitter()

    private static var home: String { FileManager.default.homeDirectoryForCurrentUser.path }
    private static var authPath: String { home + "/.config/stem-split/auth.json" }
    private static var scriptPath: String { home + "/.claude/skills/stem-split/split.py" }

    var isConfigured: Bool {
        FileManager.default.fileExists(atPath: Self.authPath)
            && FileManager.default.fileExists(atPath: Self.scriptPath)
    }

    func split(_ cut: Cut) {
        guard isConfigured else {
            showSetupInstructions()
            return
        }
        guard !inFlight.contains(cut.filePath) else { return }
        inFlight.insert(cut.filePath)
        Log.d("stem-split started: \(cut.filePath)")

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        proc.arguments = [Self.scriptPath, cut.filePath]
        proc.environment = ProcessInfo.processInfo.environment.merging(["HEADLESS": "1"]) { _, new in new }

        let logURL = Library.supportDir.appendingPathComponent("stemsplit.log")
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        if let h = try? FileHandle(forWritingTo: logURL) {
            h.seekToEndOfFile()
            proc.standardOutput = h
            proc.standardError = h
        }

        proc.terminationHandler = { [weak self] p in
            DispatchQueue.main.async {
                self?.inFlight.remove(cut.filePath)
                if p.terminationStatus == 0 {
                    Log.d("stem-split done: \(cut.title)")
                } else {
                    let msg = "stem-split failed (exit \(p.terminationStatus)) — see stemsplit.log"
                    self?.lastError = msg
                    Log.d(msg)
                    NSSound.beep()
                }
            }
        }

        do {
            try proc.run()
        } catch {
            inFlight.remove(cut.filePath)
            lastError = "could not launch stem-split: \(error.localizedDescription)"
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
