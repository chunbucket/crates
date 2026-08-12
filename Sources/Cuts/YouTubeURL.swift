import Foundation

enum YouTubeURL {
    /// Extracts a YouTube watch URL from arbitrary dragged/pasted text, if present.
    static func extract(from raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let host = url.host?.lowercased() else { return nil }
        let ytHosts = ["youtube.com", "www.youtube.com", "m.youtube.com", "music.youtube.com", "youtu.be", "www.youtu.be"]
        guard ytHosts.contains(host) else { return nil }
        if host.hasSuffix("youtu.be") {
            return url.path.count > 1 ? trimmed : nil
        }
        let p = url.path
        guard p.hasPrefix("/watch") || p.hasPrefix("/shorts/") || p.hasPrefix("/live/") else { return nil }
        return trimmed
    }
}
