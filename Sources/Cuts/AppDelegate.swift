import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var collection: CollectionPanel!
    private var shelf: ShelfPanel!
    private let library = Library()
    private lazy var downloads = DownloadManager(library: library)
    private let dragMonitor = DragMonitor()
    private var lastError: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        shelf = ShelfPanel(downloads: downloads) { [weak self] url in
            self?.startCut(url)
        }

        setupStatusItem()
        setupDownloadCallbacks()
        setupDragMonitor()

        NSAppleEventManager.shared().setEventHandler(
            self, andSelector: #selector(handleURLEvent(_:reply:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL))
    }

    // MARK: - Status item + popover

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "record.circle",
                                   accessibilityDescription: "Cuts")
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
    }

    private func showMenu() {
        let menu = NSMenu()
        let clip = NSMenuItem(title: "Cut from Clipboard Link",
                              action: #selector(cutFromClipboard), keyEquivalent: "")
        clip.target = self
        menu.addItem(clip)
        if let err = lastError {
            menu.addItem(.separator())
            let e = NSMenuItem(title: "Last error: \(String(err.prefix(70)))", action: nil, keyEquivalent: "")
            e.isEnabled = false
            menu.addItem(e)
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
        guard let s = NSPasteboard.general.string(forType: .string),
              let url = YouTubeURL.extract(from: s) else {
            NSSound.beep()
            return
        }
        shelf.slideIn()
        startCut(url)
    }

    // MARK: - Downloads

    private func startCut(_ url: String) {
        downloads.enqueue(url)
        shelf.slideIn()
        shelf.refit()
        // The card grows once oEmbed fills in the real title/art.
        for delay in [0.6, 1.6] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.shelf.refit()
            }
        }
    }

    private func setupDownloadCallbacks() {
        downloads.onFinished = { [weak self] _ in
            guard let self else { return }
            // Let "filed ✓" read for a moment, then put the record away.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
                if !self.downloads.isBusy { self.shelf.slideOut() }
            }
        }
        downloads.onFailed = { [weak self] msg in
            guard let self else { return }
            self.lastError = msg
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                if !self.downloads.isBusy { self.shelf.slideOut() }
            }
        }
    }

    // MARK: - Drag detection

    private func setupDragMonitor() {
        dragMonitor.onYouTubeDragStarted = { [weak self] in
            self?.shelf.slideIn()
        }
        dragMonitor.onDragEnded = { [weak self] in
            guard let self else { return }
            // Keep the shelf up if a cut is running (or just landed).
            if !self.downloads.isBusy { self.shelf.slideOut() }
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
