import AppKit
import SwiftUI

/// Shelf UI state shared between AppKit (drop catcher, panel) and SwiftUI.
final class ShelfState: ObservableObject {
    @Published var hovering = false
    /// Copy shown on the idle card in place of "drop to cut" (e.g. a duplicate notice).
    @Published var notice: String?
}

/// AppKit dragging destination wrapping the SwiftUI shelf content.
/// SwiftUI's .onDrop only sees UTType-shaped providers; Safari address-bar
/// drags carry Safari-specific plist flavors instead, so we accept the drop
/// at the AppKit layer and read the drop pasteboard directly.
final class DropCatcherView: NSView {
    var onURLDrop: ((String) -> Void)?
    var onHover: ((Bool) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes(DragMonitor.dragTypes)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        Log.d("shelf draggingEntered")
        onHover?(true)
        return .copy
    }
    override func draggingExited(_ sender: NSDraggingInfo?) {
        Log.d("shelf draggingExited")
        onHover?(false)
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        onHover?(false)
        guard let url = DragMonitor.youtubeURL(on: sender.draggingPasteboard) else {
            Log.d("drop rejected — no youtube url in \((sender.draggingPasteboard.types ?? []).map(\.rawValue))")
            return false
        }
        Log.d("drop accepted: \(url)")
        onURLDrop?(url)
        return true
    }
}

/// Non-activating floating panel that slides in from the right screen edge.
final class ShelfPanel: NSPanel {
    private var hosting: NSHostingView<ShelfView>?
    private let state = ShelfState()
    /// Called once the panel has fully slid away and is ordered out.
    var onHidden: (() -> Void)?

    init(downloads: DownloadManager, onDrop: @escaping (String) -> Void) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 280, height: 320),
                   styleMask: [.nonactivatingPanel, .borderless],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false // SwiftUI card draws its own
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        animationBehavior = .none

        let catcher = DropCatcherView(frame: NSRect(x: 0, y: 0, width: 280, height: 320))
        catcher.onURLDrop = onDrop
        catcher.onHover = { [state] hovering in state.hovering = hovering }

        let host = NSHostingView(rootView: ShelfView(
            downloads: downloads, state: state,
            onClose: { [weak self] in self?.slideOut() },
            onSize: { [weak self] size in self?.contentDidResize(to: size) }))
        host.frame = catcher.bounds
        host.autoresizingMask = [.width, .height]
        catcher.addSubview(host)
        contentView = catcher
        hosting = host
    }

    override var canBecomeKey: Bool { false }

    /// The shelf's fixed home: right edge of the screen the mouse is on,
    /// vertically centered. Same spot every time — no chasing the cursor.
    private func homeFrame(for size: NSSize) -> NSRect {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? self.screen ?? NSScreen.main
        let vf = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let margin: CGFloat = 18
        var y = vf.midY - size.height / 2
        y = min(max(y, vf.minY + margin), vf.maxY - size.height - margin)
        return NSRect(x: vf.maxX - size.width - margin, y: y,
                      width: size.width, height: size.height)
    }

    private var contentSize: NSSize?
    /// Non-nil while sliding out. A slide-in clears it, so the slide-out's
    /// completion (which checks identity) can't order the panel out from
    /// under the slide-in that interrupted it.
    private var slideOutToken: NSObject?

    /// SwiftUI reports its real laid-out size; animate the panel to match.
    private func contentDidResize(to size: CGSize) {
        let newSize = NSSize(width: size.width, height: size.height)
        guard newSize.width > 1, newSize.height > 1 else { return }
        let previous = contentSize
        contentSize = newSize
        guard isVisible, slideOutToken == nil, previous != newSize else { return }
        let target = homeFrame(for: newSize)
        guard target != frame else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().setFrame(target, display: true)
        }
    }

    /// Slide in at the fixed home position, showing `notice` on the idle
    /// card if given. Interrupts a slide-out in progress.
    func slideIn(notice: String? = nil) {
        state.notice = notice
        if isVisible && slideOutToken == nil { return }
        slideOutToken = nil
        layoutIfNeeded()
        let size = contentSize ?? hosting?.fittingSize ?? NSSize(width: 280, height: 320)
        let home = homeFrame(for: size)
        Log.d("shelf slideIn size=\(size) home=(\(Int(home.origin.x)),\(Int(home.origin.y)))")
        // Start just off the screen edge; NSWindow's animator only animates
        // `frame` (not setFrameOrigin), so both legs go through setFrame.
        setFrame(home.offsetBy(dx: size.width * 1.2, dy: 0), display: false)
        alphaValue = 0
        orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.28
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().setFrame(home, display: true)
            animator().alphaValue = 1
        }
    }

    func slideOut() {
        guard isVisible, slideOutToken == nil else { return }
        Log.d("shelf slideOut")
        let token = NSObject()
        slideOutToken = token
        let off = frame.offsetBy(dx: frame.width * 0.4, dy: 0)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            animator().setFrame(off, display: true)
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self, self.slideOutToken === token else { return } // a slideIn took over
            self.slideOutToken = nil
            self.orderOut(nil)
            self.alphaValue = 1
            self.onHidden?()
        })
    }
}
