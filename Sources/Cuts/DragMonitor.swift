import AppKit

/// Detects a YouTube URL being dragged anywhere in the system.
///
/// Implementation: a 120ms poll of the *drag* pasteboard's changeCount plus
/// `NSEvent.pressedMouseButtons`. Both are plain state queries — no global
/// event monitors, no event taps, nothing macOS can permission-gate. A new
/// drag = drag-pasteboard changeCount bumps while the left button is down;
/// we then re-evaluate its contents every tick until it matches or the
/// button comes up (Safari can populate the URL a beat after drag start).
final class DragMonitor {
    var onYouTubeDragStarted: (() -> Void)?
    var onDragEnded: (() -> Void)?

    private var timer: Timer?
    private var lastCC: Int
    private var trackingDrag = false
    private var matched = false

    init() {
        lastCC = NSPasteboard(name: .drag).changeCount
    }

    func start() {
        let t = Timer(timeInterval: 0.12, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        Log.d("DragMonitor started (polling), initial cc=\(lastCC)")
    }

    private func tick() {
        let buttonDown = NSEvent.pressedMouseButtons & 1 == 1
        let pb = NSPasteboard(name: .drag)

        if pb.changeCount != lastCC {
            lastCC = pb.changeCount
            let types = (pb.types ?? []).map(\.rawValue).prefix(6).joined(separator: ", ")
            Log.d("drag pb cc=\(lastCC) buttonDown=\(buttonDown) types=[\(types)]")
            trackingDrag = buttonDown
            matched = false
        }

        guard trackingDrag else { return }

        if !buttonDown {
            let wasMatched = matched
            trackingDrag = false
            matched = false
            Log.d("drag ended (matched=\(wasMatched))")
            if wasMatched {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) { [weak self] in
                    self?.onDragEnded?()
                }
            }
            return
        }

        guard !matched else { return }
        if let url = Self.youtubeURL(on: pb) {
            matched = true
            Log.d("matched: \(url)")
            onYouTubeDragStarted?()
        }
    }

    /// Every pasteboard type a YouTube URL can hide in. Safari address-bar
    /// drags carry NO public.url — the URL lives in Safari's plist flavors
    /// (WebURLsWithTitlesPboardType / bookmarkDictionaryList), which are
    /// written immediately rather than promised, so read those first.
    static let dragTypes: [NSPasteboard.PasteboardType] = [
        NSPasteboard.PasteboardType("WebURLsWithTitlesPboardType"),
        NSPasteboard.PasteboardType("com.apple.Safari.bookmarkDictionaryList"),
        NSPasteboard.PasteboardType("public.url"),
        NSPasteboard.PasteboardType("public.utf8-plain-text"),
        .string, .URL,
    ]

    static func youtubeURL(on pb: NSPasteboard) -> String? {
        var candidates: [String] = []

        if let plist = pb.propertyList(forType: NSPasteboard.PasteboardType("WebURLsWithTitlesPboardType")) as? [[String]],
           let urls = plist.first {
            candidates += urls
        }
        if let dicts = pb.propertyList(forType: NSPasteboard.PasteboardType("com.apple.Safari.bookmarkDictionaryList")) as? [[String: Any]] {
            candidates += dicts.compactMap { $0["URLString"] as? String }
        }
        for type in [NSPasteboard.PasteboardType("public.url"),
                     NSPasteboard.PasteboardType("public.utf8-plain-text"),
                     .string] {
            if let s = pb.string(forType: type) { candidates.append(s) }
        }
        if let urls = pb.readObjects(forClasses: [NSURL.self]) as? [URL] {
            candidates += urls.map(\.absoluteString)
        }

        for c in candidates {
            if let hit = YouTubeURL.extract(from: c) { return hit }
        }
        return nil
    }
}
