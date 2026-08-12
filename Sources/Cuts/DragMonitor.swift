import AppKit

/// Watches global mouse-drag events and sniffs the drag pasteboard.
/// When someone drags a YouTube URL (Safari address bar, a link, etc.),
/// `onYouTubeDragStarted` fires. No accessibility permission needed —
/// mouse-event global monitors and drag-pasteboard reads are unrestricted.
final class DragMonitor {
    var onYouTubeDragStarted: (() -> Void)?
    var onDragEnded: (() -> Void)?

    private var monitors: [Any] = []
    private var lastChangeCount = NSPasteboard(name: .drag).changeCount
    private var dragSessionActive = false

    func start() {
        let dragged: (NSEvent) -> Void = { [weak self] _ in self?.handleDragged() }
        let up: (NSEvent) -> Void = { [weak self] _ in self?.handleUp() }

        if let m = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged, handler: dragged) {
            monitors.append(m)
        }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp, handler: up) {
            monitors.append(m)
        }
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: .leftMouseDragged) { e in dragged(e); return e } as Any)
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { e in up(e); return e } as Any)
    }

    private func handleDragged() {
        let pb = NSPasteboard(name: .drag)
        guard pb.changeCount != lastChangeCount else { return }
        lastChangeCount = pb.changeCount
        guard !dragSessionActive else { return }

        if Self.youtubeURL(on: pb) != nil {
            dragSessionActive = true
            onYouTubeDragStarted?()
        }
    }

    private func handleUp() {
        guard dragSessionActive else { return }
        dragSessionActive = false
        // Give the drop a beat to land on our panel before hiding it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) { [weak self] in
            self?.onDragEnded?()
        }
    }

    static func youtubeURL(on pb: NSPasteboard) -> String? {
        var candidates: [String] = []
        for type in [NSPasteboard.PasteboardType("public.url"),
                     NSPasteboard.PasteboardType("public.utf8-plain-text"),
                     .string] {
            if let s = pb.string(forType: type) { candidates.append(s) }
        }
        if let urls = pb.readObjects(forClasses: [NSURL.self]) as? [URL] {
            candidates.append(contentsOf: urls.map(\.absoluteString))
        }
        for c in candidates {
            if let hit = YouTubeURL.extract(from: c) { return hit }
        }
        return nil
    }
}
