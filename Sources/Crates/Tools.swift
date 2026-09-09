import Foundation

struct ToolError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

/// The command-line tools Crates shells out to, and where they live.
///
/// Inside a built bundle (staged by build.sh):
///   Crates.app/Contents/MacOS/ffmpeg
///   Crates.app/Contents/MacOS/deno                             (yt-dlp's JS runtime — QuickJS was
///                                                             tried: minutes per challenge vs ~2 s)
///   Crates.app/Contents/Resources/yt-dlp_macos/yt-dlp_macos    (+ _internal/, PyInstaller onedir;
///                                                             under Resources because the tree mixes code and data)
///
/// yt-dlp updates are downloaded to ~/Library/Application Support/Crates/bin
/// and win over the bundled copy while they are newer, so the signed bundle
/// is never modified. Outside a bundle (plain `swift run`) everything falls
/// back to Homebrew so the dev loop keeps working.
final class Tools: ObservableObject {
    static let shared = Tools()

    private static let bundleBin = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS", isDirectory: true)
    private static let bundledYtdlpDir = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/yt-dlp_macos", isDirectory: true)
    private static let updatesDir = Library.supportDir.appendingPathComponent("bin", isDirectory: true)
    private static let updatedYtdlpDir = updatesDir.appendingPathComponent("yt-dlp_macos", isDirectory: true)
    private static let updatedVersionFile = updatesDir.appendingPathComponent("yt-dlp.version")
    private static let homebrew = URL(fileURLWithPath: "/opt/homebrew/bin", isDirectory: true)
    private static let releaseZip = URL(string: "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos.zip")!

    /// Version of the yt-dlp that `ytdlp` points at (yt-dlp versions are
    /// zero-padded dates, so plain string comparison orders them).
    @Published private(set) var ytdlpVersion: String
    private(set) var ytdlp: URL
    /// Directory holding ffmpeg, for `--ffmpeg-location`.
    let ffmpegDir: URL
    /// Bundled deno for `--js-runtimes`; nil = let yt-dlp find deno on PATH (dev).
    let deno: URL?
    /// Running the bundled/updated toolchain rather than Homebrew.
    let isBundled: Bool

    private init() {
        let fm = FileManager.default
        isBundled = fm.isExecutableFile(atPath: Self.bundledYtdlpDir.appendingPathComponent("yt-dlp_macos").path)
        let bundledFfmpeg = Self.bundleBin.appendingPathComponent("ffmpeg")
        ffmpegDir = fm.isExecutableFile(atPath: bundledFfmpeg.path) ? Self.bundleBin : Self.homebrew
        let bundledDeno = Self.bundleBin.appendingPathComponent("deno")
        deno = fm.isExecutableFile(atPath: bundledDeno.path) ? bundledDeno : nil
        (ytdlp, ytdlpVersion) = Self.resolveYtdlp(bundled: isBundled)
        Log.d("tools: yt-dlp=\(ytdlp.path) (\(ytdlpVersion)) ffmpeg=\(ffmpegDir.path) deno=\(deno?.path ?? "PATH")")
    }

    /// The one rule for which yt-dlp runs: a downloaded update while it is
    /// newer than the bundled copy, else the bundled copy (dropping a stale
    /// update), else Homebrew. Used at launch and again after an update so
    /// "what runs now" and "what runs next launch" can't disagree.
    private static func resolveYtdlp(bundled: Bool) -> (URL, String) {
        guard bundled else { return (homebrew.appendingPathComponent("yt-dlp"), "homebrew") }
        let fm = FileManager.default
        let bundledVersion = Bundle.main.infoDictionary?["CratesBundledYtdlp"] as? String ?? ""
        let updated = updatedYtdlpDir.appendingPathComponent("yt-dlp_macos")
        let updatedVersion = (try? String(contentsOf: updatedVersionFile, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if fm.isExecutableFile(atPath: updated.path), updatedVersion > bundledVersion {
            return (updated, updatedVersion)
        }
        if fm.fileExists(atPath: updatedYtdlpDir.path) { try? fm.removeItem(at: updatesDir) }
        return (bundledYtdlpDir.appendingPathComponent("yt-dlp_macos"), bundledVersion)
    }

    /// Environment for a yt-dlp process. Only the Homebrew fallback needs
    /// its bin dir on PATH (for deno/ffmpeg); the bundle is self-contained.
    var processEnvironment: [String: String] {
        var env = ProcessInfo.processInfo.environment
        if !isBundled { env["PATH"] = Self.homebrew.path + ":" + (env["PATH"] ?? "/usr/bin:/bin") }
        return env
    }

    /// macOS verifies every freshly installed Mach-O the first time it runs
    /// (about 7 s for yt-dlp's hundred-odd dylibs). Pay that at app launch,
    /// in the background, instead of on the first record.
    func prewarm() {
        guard isBundled else { return }
        let exe = ytdlp
        DispatchQueue.global(qos: .utility).async {
            let started = Date()
            _ = Self.run(exe, ["--version"])
            Log.d(String(format: "yt-dlp prewarm took %.1fs", Date().timeIntervalSince(started)))
        }
    }

    /// Download the latest official onedir build into Application Support,
    /// verify it runs, and switch to it. Completion on the main thread.
    func updateYtdlp(completion: @escaping (Result<String, Error>) -> Void) {
        guard isBundled else {
            completion(.failure(ToolError("dev build uses Homebrew's yt-dlp — run `brew upgrade yt-dlp`")))
            return
        }
        URLSession.shared.downloadTask(with: Self.releaseZip) { tmp, _, error in
            let result = Result<String, Error> {
                guard let tmp else { throw error ?? ToolError("download failed") }
                let fm = FileManager.default
                let staging = Self.updatesDir.appendingPathComponent("staging", isDirectory: true)
                let newDir = staging.appendingPathComponent("yt-dlp_macos", isDirectory: true)
                try? fm.removeItem(at: staging)
                try fm.createDirectory(at: newDir, withIntermediateDirectories: true)
                let zip = staging.appendingPathComponent("yt-dlp_macos.zip")
                try fm.moveItem(at: tmp, to: zip)
                guard Self.run(URL(fileURLWithPath: "/usr/bin/unzip"), ["-q", zip.path, "-d", newDir.path]).status == 0 else {
                    throw ToolError("couldn't unzip the download")
                }
                // The download carries the quarantine flag; the copy we run must not.
                _ = Self.run(URL(fileURLWithPath: "/usr/bin/xattr"), ["-dr", "com.apple.quarantine", newDir.path])
                let exe = newDir.appendingPathComponent("yt-dlp_macos")
                let probe = Self.run(exe, ["--version"]) // also pays the first-launch scan
                let version = probe.output.trimmingCharacters(in: .whitespacesAndNewlines)
                guard probe.status == 0, !version.isEmpty else { throw ToolError("the downloaded yt-dlp won't run") }
                try? fm.removeItem(at: Self.updatedYtdlpDir)
                try fm.moveItem(at: newDir, to: Self.updatedYtdlpDir)
                try version.write(to: Self.updatedVersionFile, atomically: true, encoding: .utf8)
                try? fm.removeItem(at: staging)
                return version
            }
            DispatchQueue.main.async {
                if case .success = result { (self.ytdlp, self.ytdlpVersion) = Self.resolveYtdlp(bundled: true) }
                Log.d("yt-dlp update: \(result) → running \(self.ytdlpVersion)")
                completion(result)
            }
        }.resume()
    }

    /// Run a tool to completion, capturing stdout+stderr.
    @discardableResult
    private static func run(_ exe: URL, _ args: [String]) -> (status: Int32, output: String) {
        let p = Process()
        p.executableURL = exe
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do { try p.run() } catch { return (-1, error.localizedDescription) }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }
}
