import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var collection: CollectionPanel!
    private var shelf: ShelfPanel!
    private let library = Library()
    private lazy var downloads = DownloadManager(library: library)
    private let dragMonitor = DragMonitor()
    /// The one timer that puts the shelf away; re-arming cancels the previous
    /// one so a stale dwell can never dismiss a newer card.
    private var pendingSlideOut: DispatchWorkItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        Tools.shared.prewarm()
        Notifier.shared.start()
        Notifier.shared.onActivate = { [weak self] in self?.collection.open() }
        UpdateCheck.shared.onAvailable = { version in
            Notifier.shared.post(title: "Crates \(version) is out", body: "Get it from ency.world/crates")
        }
        UpdateCheck.shared.start()
        // BPM/key for anything the current analyser hasn't seen, in the background.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self else { return }
            AnalysisQueue.shared.backfill(self.library)
        }

        shelf = ShelfPanel(downloads: downloads) { [weak self] url in
            self?.startRecord(url)
        }
        shelf.onHidden = { [weak self] in
            self?.downloads.dismissResult()
            Player.shared.stop()
        }

        setupStatusItem()
        setupDownloadCallbacks()
        setupDragMonitor()

        NSAppleEventManager.shared().setEventHandler(
            self, andSelector: #selector(handleURLEvent(_:reply:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL))

        // First launch with nothing filed: show the (empty) collection once so
        // a new user sees where things go and how to drop a link.
        if !UserDefaults.standard.bool(forKey: "hasLaunched") {
            UserDefaults.standard.set(true, forKey: "hasLaunched")
            if library.records.isEmpty {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in self?.collection.open() }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Don't leave an orphaned yt-dlp writing into the music folder.
        downloads.cancelAll()
    }

    // MARK: - Status item + popover

    /// Hand-drawn vinyl glyph. Idle: template (adapts to menu bar).
    /// Active: dark vinyl on an amber glow disc — the collection is open.
    /// The inner groove has a lead-in gap so the disc visibly spins while a
    /// record is in progress (`angle`).
    private func vinylIcon(active: Bool, angle: Double = 0) -> NSImage {
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
            // Groove: a 270° arc, rotated by `angle`.
            let groove = NSBezierPath()
            groove.appendArc(withCenter: NSPoint(x: rect.midX, y: rect.midY), radius: rect.width / 2 - 6.2,
                             startAngle: 90 - angle, endAngle: 90 - angle - 270, clockwise: true)
            groove.lineWidth = 0.9
            groove.lineCapStyle = .round
            ink.withAlphaComponent(0.6).setStroke()
            groove.stroke()
            let dot = NSBezierPath(ovalIn: NSRect(x: rect.midX - 1.4, y: rect.midY - 1.4, width: 2.8, height: 2.8))
            ink.setFill()
            dot.fill()
            return true
        }
        img.isTemplate = !active
        return img
    }

    // MARK: - Menu bar icon spin (while a record is in progress)

    private var iconAngle: Double = 0
    private var iconTimer: Timer?
    private var iconSpinning = false
    /// Ease-out to the next rest position after the last record lands.
    private var iconEaseOut: (started: Date, from: Double, to: Double)?

    private func refreshIcon() {
        statusItem.button?.image = vinylIcon(active: collection.isVisible, angle: iconAngle)
    }

    private func setIconSpinning(_ on: Bool) {
        if on {
            iconEaseOut = nil
            guard !iconSpinning else { return }
            iconSpinning = true
            if iconTimer == nil {
                let t = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.tickIcon() }
                RunLoop.main.add(t, forMode: .common)
                iconTimer = t
            }
        } else if iconSpinning {
            iconSpinning = false
            iconEaseOut = (Date(), iconAngle, (iconAngle / 360).rounded(.up) * 360)
        }
    }

    private func tickIcon() {
        if iconSpinning {
            iconAngle += 360 / 2.0 / 30 // two seconds per revolution
        } else if let ease = iconEaseOut {
            let p = min(1, Date().timeIntervalSince(ease.started) / 0.5)
            iconAngle = ease.from + (ease.to - ease.from) * (1 - pow(1 - p, 3))
            if p >= 1 {
                iconEaseOut = nil
                iconAngle = 0
                iconTimer?.invalidate()
                iconTimer = nil
            }
        } else {
            iconTimer?.invalidate()
            iconTimer = nil
            return
        }
        refreshIcon()
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
                self?.startRecord(url)
            }
            overlay.onLeftClick = { [weak self] in self?.collection.toggle() }
            overlay.onRightClick = { [weak self] in self?.showMenu() }
            button.addSubview(overlay)
        }
        collection = CollectionPanel(
            library: library, downloads: downloads,
            onRetry: { [weak self] record in
                self?.startRecord(record.url) // a retry is just the same link again; enqueue lands it in its row
            },
            onUpdateAndRetry: { [weak self] record in
                Tools.shared.updateYtdlp { result in
                    if case .failure(let error) = result {
                        Notifier.shared.post(title: "yt-dlp update failed", body: error.localizedDescription)
                    }
                    self?.startRecord(record.url)
                }
            },
            onRemove: { [weak self] record in self?.removeRecord(record) })
        collection.statusWindow = statusItem.button?.window
        collection.onVisibilityChange = { [weak self] visible in
            guard let self else { return }
            self.refreshIcon()
            // The row transport is the only control, so closing the shelf stops playback.
            if !visible { Player.shared.stop() }
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Record from Clipboard Link", action: #selector(recordFromClipboard), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(withTitle: "Update yt-dlp…", action: #selector(updateYtdlp), keyEquivalent: "").target = self
        if let version = UpdateCheck.shared.available {
            menu.addItem(.separator())
            menu.addItem(withTitle: "Crates \(version) available…", action: #selector(openDownloadPage), keyEquivalent: "").target = self
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Crates", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        // Native status-item menu positioning: assign, click, unassign.
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        DispatchQueue.main.async { [weak self] in self?.statusItem.menu = nil }
    }

    @objc private func recordFromClipboard() {
        // Same reader as drops: handles plain text, public.url and Safari's
        // plist flavors, and scheme-less / embedded URLs.
        guard let url = DragMonitor.youtubeURL(on: NSPasteboard.general) else {
            NSSound.beep()
            return
        }
        startRecord(url)
    }

    // MARK: - Removing a record

    /// Take the row off the shelf; ask (once, unless told not to) whether the
    /// FLAC goes to the Trash with it. Failed / missing-file rows have no file
    /// to ask about.
    private func removeRecord(_ record: Record) {
        Player.shared.stopIfCurrent(record)
        guard record.fileExists, let url = record.fileURL else {
            library.remove(record)
            return
        }
        var trash = Settings.shared.removePolicy == RemovePolicy.trash
        if Settings.shared.removePolicy == RemovePolicy.ask {
            // The panel floats at status-bar level, above a modal alert (8 vs 25);
            // drop it to plain floating while the prompt is up so the alert lands
            // on top, and keep it open behind the alert.
            collection.holdOpen = true
            let level = collection.level
            collection.level = .floating
            defer {
                collection.holdOpen = false
                collection.level = level
            }
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "Remove “\(record.title)” from the crate?"
            alert.informativeText = "The FLAC can stay in your records folder, or go to the Trash with it."
            alert.addButton(withTitle: "Remove, Keep File")
            alert.addButton(withTitle: "Remove & Trash File")
            alert.addButton(withTitle: "Cancel")
            alert.showsSuppressionButton = true
            alert.suppressionButton?.title = "Don't ask again"
            let choice = alert.runModal()
            guard choice != .alertThirdButtonReturn else { return }
            trash = choice == .alertSecondButtonReturn
            if alert.suppressionButton?.state == .on {
                Settings.shared.removePolicy = trash ? RemovePolicy.trash : RemovePolicy.keep
            }
        }
        library.remove(record)
        if trash {
            do { try FileManager.default.trashItem(at: url, resultingItemURL: nil) }
            catch { Log.d("trash failed for \(url.lastPathComponent): \(error.localizedDescription)") }
        }
    }

    @objc private func openDownloadPage() {
        NSWorkspace.shared.open(UpdateCheck.downloadPage)
    }

    @objc private func openSettings() {
        SettingsWindow.shared.show()
    }

    @objc private func updateYtdlp() {
        Tools.shared.updateYtdlp { result in
            switch result {
            case .success(let version):
                Notifier.shared.post(title: "yt-dlp updated", body: version)
            case .failure(let error):
                Notifier.shared.post(title: "yt-dlp update failed", body: error.localizedDescription)
            }
        }
    }

    // MARK: - Downloads

    /// Every record enters here (drop, clipboard, URL scheme, row retry).
    private func startRecord(_ url: String) {
        switch downloads.enqueue(url) {
        case .started:
            break // onStarted raised the shelf
        case .queued:
            raiseShelf()
        case .duplicate(let existing):
            downloads.dismissResult()
            shelf.slideIn(notice: "already in the crate · \(existing.numberLabel)")
            scheduleSlideOut(after: 2.2)
        case .rejected:
            NSSound.beep()
        }
    }

    /// Bring the record player up and stop any pending put-away.
    private func raiseShelf() {
        pendingSlideOut?.cancel()
        shelf.slideIn()
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
        // Every start (drop, retry, queue advance) brings the record player up
        // and stops any preview.
        downloads.onStarted = { [weak self] _ in
            Player.shared.stop()
            self?.setIconSpinning(true)
            self?.raiseShelf()
        }
        downloads.onSettled = { [weak self] record in
            guard let self else { return }
            if !record.isFailed { AnalysisQueue.shared.enqueue(record, library: self.library) }
            // Keep turning through the dwell if more links are waiting.
            self.setIconSpinning(!self.downloads.queued.isEmpty)
            self.scheduleSlideOut(after: DownloadManager.dwell(failed: record.isFailed))
            // The card says it when the shelf is up; otherwise the system does.
            guard !self.shelf.isVisible else { return }
            Notifier.shared.post(title: record.isFailed ? "Recording failed · \(record.title)" : "Recorded · \(record.title)",
                                 body: record.isFailed ? (record.error ?? "unknown error") : record.numberLabel)
        }
    }

    // MARK: - Drag detection

    private func setupDragMonitor() {
        dragMonitor.onYouTubeDragStarted = { [weak self] in
            guard let self else { return }
            // A stale "filed ✓" card shouldn't cover the drop target.
            self.downloads.dismissResult()
            self.raiseShelf()
        }
        dragMonitor.onDragEnded = { [weak self] in
            self?.slideOutIfIdle()
        }
        dragMonitor.start()
    }

    // MARK: - records:// URL scheme (automation + tests)
    //   crates://record?url=<encoded link>   crates://crate   crates://settings   crates://update   crates://update-check   crates://play?record=N

    @objc private func handleURLEvent(_ event: NSAppleEventDescriptor, reply: NSAppleEventDescriptor) {
        guard let raw = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let comps = URLComponents(string: raw), comps.scheme == "crates" else { return }
        switch comps.host {
        case "record":
            if let encoded = comps.queryItems?.first(where: { $0.name == "url" })?.value,
               let url = YouTubeURL.extract(from: encoded) {
                startRecord(url)
            }
        case "crate": collection.open()
        case "settings": openSettings()
        case "update": updateYtdlp()
        case "update-check": UpdateCheck.shared.checkIfDue(force: true)
        case "play": // crates://play?record=<number> — tests
            if let n = comps.queryItems?.first(where: { $0.name == "record" })?.value.flatMap(Int.init),
               let record = library.records.first(where: { $0.number == n }) {
                collection.open()
                Player.shared.play(record)
            }
        default: break
        }
    }
}
