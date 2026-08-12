import AppKit
import SwiftUI

/// The collection, as a manually-positioned panel hanging just below the
/// menu bar icon. Replaces NSPopover, whose status-item anchoring proved
/// unreliable on this setup (notch-adjacent icon, macOS 26) — here every
/// coordinate is computed explicitly, same as the shelf.
final class CollectionPanel: NSPanel {
    private var hosting: NSHostingView<AnyView>?
    private var monitors: [Any] = []
    weak var statusWindow: NSWindow?

    init(library: Library, downloads: DownloadManager) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 340, height: 440),
                   styleMask: [.nonactivatingPanel, .borderless],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        animationBehavior = .none

        let root = AnyView(
            CollectionView(library: library, downloads: downloads)
                .background(.ultraThickMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                )
        )
        let host = NSHostingView(rootView: root)
        host.frame = contentRect(forFrameRect: frame)
        contentView = host
        hosting = host
    }

    override var canBecomeKey: Bool { false }

    func toggle() {
        isVisible ? closePanel() : open()
    }

    func open() {
        let size = NSSize(width: 340, height: 440)
        let anchor = statusWindow?.frame
        let screen = statusWindow?.screen ?? NSScreen.main
        let vf = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 860)

        var x = (anchor?.midX ?? vf.maxX - 40) - size.width / 2
        x = min(max(x, vf.minX + 8), vf.maxX - size.width - 8)
        let y = vf.maxY - size.height - 6
        Log.d("collection open anchor=\(anchor ?? .zero) frame=(\(Int(x)),\(Int(y)))")

        setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
        alphaValue = 0
        orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            animator().alphaValue = 1
        }
        installMonitors()
    }

    func closePanel() {
        removeMonitors()
        guard isVisible else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.12
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.orderOut(nil)
            self?.alphaValue = 1
        })
    }

    /// Transient behavior by hand: any click outside the panel (and not on
    /// the status icon, whose own handler toggles) closes it.
    private func installMonitors() {
        removeMonitors()
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown],
                                                     handler: { [weak self] _ in self?.closePanel() }) {
            monitors.append(m)
        }
        if let m = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown],
                                                    handler: { [weak self] e in
            guard let self else { return e }
            if e.window !== self && e.window !== self.statusWindow { self.closePanel() }
            return e
        }) {
            monitors.append(m)
        }
    }

    private func removeMonitors() {
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
    }
}
