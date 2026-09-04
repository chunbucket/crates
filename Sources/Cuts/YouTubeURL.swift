import Foundation

enum YouTubeURL {
    /// Canonical watch URL for the first YouTube video found in `raw`.
    /// `raw` may be a full URL, a scheme-less one, or text with a URL inside.
    /// Canonical form drops playlist/radio/tracking params so yt-dlp skips the
    /// playlist extractor and the same video always dedupes to one cut.
    static func extract(from raw: String) -> String? {
        videoID(in: raw).map(canonical)
    }

    static func canonical(_ id: String) -> String { "https://www.youtube.com/watch?v=\(id)" }

    /// Short form of a canonical URL for labels: "youtube.com/watch?v=…".
    static func display(_ canonicalURL: String) -> String {
        canonicalURL.replacingOccurrences(of: "https://www.", with: "")
    }

    /// The 11-char video ID from any YouTube URL shape: watch?v=, youtu.be/,
    /// shorts/, live/, embed/, v/ — on youtube.com, youtube-nocookie.com and
    /// the www / m / music subdomains. Host must start a hostname (no
    /// "notyoutube.com") and be followed directly by the path (no
    /// "youtube.com.evil.com").
    static func videoID(in raw: String) -> String? {
        let range = NSRange(raw.startIndex..., in: raw)
        guard let m = regex.firstMatch(in: raw, range: range),
              let r = Range(m.range(at: 1), in: raw) else { return nil }
        return String(raw[r])
    }

    private static let regex = try! NSRegularExpression(
        pattern: #"(?<![A-Za-z0-9-])(?:https?://)?(?:(?:www|m|music)\.)?"#
            + #"(?:youtube(?:-nocookie)?\.com/(?:watch\?(?:[^\s&#]*&)*v=|(?:shorts|live|embed|v)/)|youtu\.be/)"#
            + #"([A-Za-z0-9_-]{11})(?![A-Za-z0-9_-])"#,
        options: [.caseInsensitive])
}
