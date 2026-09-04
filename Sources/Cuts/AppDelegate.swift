import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var collection: CollectionPanel!
    private var shelf: ShelfPanel!
    private let library = Library()
    private lazy var downloads = DownloadManager(library: library)
    private let dragMonitor = DragMonitor()
    private var lastFailure: (url: String, message: String)?
    /// The one timer that puts the shelf away; re-arming cancels the previous
    /// one so a stale dwell can never dismiss a newer card.
    private var pendingSlideOut: DispatchWorkItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        shelf = ShelfPanel(downloads: downloads) { [weak self] url in
            self?.startCut(url)
        }
        shelf.onHidden = { [weak self] in self?.downloads.dismissResult() }

        setupStatusItem()
        setupDownloadCallbacks()
        setupDragMonitor()

        NSAppleEventManager.shared().setEventHandler(
            self, andSelector: #selector(handleURLEvent(_:reply:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL))
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Don't leave an orphaned yt-dlp writing into the music folder.
        downloads.cancelAll()
    }

    // MARK: - Status item + popover

    /// Hand-drawn vinyl glyph. Idle: template (adapts to menu bar).
    /// Active: dark vinyl on an amber glow disc — the "playing" state.
    private func vinylIcon(active: Bool) -> NSImage {
        let size = NSSize(width: 20, height: 20)
        let img = NSImage(size: size, flipped: false) { rect in
            if active {
                NSColor(calibratedRed: 1.0, green: 0.71, blue: 0.33, alpha: 1).setFill() // amber
                NSBezierPath(ovalIn: rect.insetBy(dx: 0.5, dy: 0.5)).fill()
            }
            let ink = NSColor.black
            let ring = NSBezierPath(ovalIn: rect.insetBy(dx: 3.5, dy: 3.5))
            ring.lineWidth = 1.6
            ink.setStroke()
            ring.stroke()
            let groove = NSBezierPath(ovalIn: rect.insetBy(dx: 6.2, dy: 6.2))
            groove.lineWidth = 0.7
            ink.withAlphaComponent(0.55).setStroke()
            groove.stroke()
            let dot = NSBezierPath(ovalIn: NSRect(x: rect.midX - 1.4, y: rect.midY - 1.4, width: 2.8, height: 2.8))
            ink.setFill()
            dot.fill()
            return true
        }
        img.isTemplate = !active
        return img
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = vinylIcon(active: false)
            // Transparent overlay makes the icon itself a drop target —
            // a stationary destination macOS tracks from before any drag
            // begins — and forwards clicks to our handlers.
            let overlay = StatusDropView(frame: button.bounds)
            overlay.autoresizingMask = [.width, .height]
            overlay.onURLDrop = { [weak self] url in
                Log.d("status item drop: \(url)")
                self?.startCut(url)
            }
            overlay.onLeftClick = { [weak self] in self?.collection.toggle() }
            overlay.onRightClick = { [weak self] in self?.showMenu() }
            button.addSubview(overlay)
        }
        collection = CollectionPanel(library: library, downloads: downloads)
        collection.statusWindow = statusItem.button?.window
        collection.onVisibilityChange = { [weak self] visible in
            guard let self else { return }
            self.statusItem.button?.image = self.vinylIcon(active: visible)
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        let clip = NSMenuItem(title: "Cut from Clipboard Link",
                              action: #selector(cutFromClipboard), keyEquivalent: "")
        clip.target = self
        menu.addItem(clip)
        if let failure = lastFailure {
            menu.addItem(.separator())
            let e = NSMenuItem(title: "Last error: \(String(failure.message.prefix(70)))", action: nil, keyEquivalent: "")
            e.isEnabled = false
            menu.addItem(e)
            let retry = NSMenuItem(title: "Retry Last Failed Cut",
                                   action: #selector(retryLastFailed), keyEquivalent: "")
            retry.target = self
            menu.addItem(retry)
        }
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Cuts", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
        // Native status-item menu positioning: assign, click, unassign.
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        DispatchQueue.main.async { [weak self] in self?.statusItem.menu = nil }
    }

    @objc private func cutFromClipboard() {
        // Same reader as drops: handles plain text, public.url and Safari's
        // plist flavors, and scheme-less / embedded URLs.
        guard let url = DragMonitor.youtubeURL(on: NSPasteboard.general) else {
            NSSound.beep()
            return
        }
        startCut(url)
    }

    @objc private func retryLastFailed() {
        if let failure = lastFailure { startCut(failure.url) }
    }

    // MARK: - Downloads

    private func startCut(_ url: String) {
        pendingSlideOut?.cancel()
        switch downloads.enqueue(url) {
        case .started, .queued:
            shelf.slideIn()
        case .duplicate(let existing):
            downloads.dismissResult()
            shelf.slideIn(notice: "already on the shelf · \(existing.cutLabel)")
            scheduleSlideOut(after: 2.2)
        case .rejected:
            NSSound.beep()
        }
    }

    private func scheduleSlideOut(after delay: TimeInterval) {
        pendingSlideOut?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.slideOutIfIdle() }
        pendingSlideOut = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    /// Put the shelf away unless something still needs it on screen.
    private func slideOutIfIdle() {
        if !downloads.isBusy && !dragMonitor.isDragging { shelf.slideOut() }
    }

    private func setupDownloadCallbacks() {
        downloads.onFinished = { [weak self] _ in
            self?.scheduleSlideOut(after: DownloadManager.dwell(after: .done))
        }
        downloads.onFailed = { [weak self] url, message in
            self?.lastFailure = (url, message)
            self?.scheduleSlideOut(after: DownloadManager.dwell(after: .failed(message)))
        }
    }

    // MARK: - Drag detection

    private func setupDragMonitor() {
        dragMonitor.onYouTubeDragStarted = { [weak self] in
            guard let self else { return }
            // A stale "filed ✓" card shouldn't cover the drop target.
            self.pendingSlideOut?.cancel()
            self.downloads.dismissResult()
            self.shelf.slideIn()
        }
        dragMonitor.onDragEnded = { [weak self] in
            self?.slideOutIfIdle()
        }
        dragMonitor.start()
    }

    // MARK: - cuts:// URL scheme (testing + automation)

    @objc private func handleURLEvent(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        guard let raw = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let comps = URLComponents(string: raw),
              comps.scheme == "cuts",
              let encoded = comps.queryItems?.first(where: { $0.name == "url" })?.value,
              let url = YouTubeURL.extract(from: encoded) else { return }
        startCut(url)
    }
}
