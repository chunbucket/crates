import AppKit
import SwiftUI

/// Shared hover state between the AppKit drop catcher and the SwiftUI card.
final class DropState: ObservableObject {
    @Published var hovering = false
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

        let dropState = DropState()
        let catcher = DropCatcherView(frame: NSRect(x: 0, y: 0, width: 280, height: 320))
        catcher.onURLDrop = onDrop
        catcher.onHover = { hovering in dropState.hovering = hovering }

        let host = NSHostingView(rootView: ShelfView(
            downloads: downloads, dropState: dropState,
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

    /// SwiftUI reports its real laid-out size; animate the panel to match.
    private func contentDidResize(to size: CGSize) {
        let newSize = NSSize(width: size.width, height: size.height)
        guard newSize.width > 1, newSize.height > 1 else { return }
        let previous = contentSize
        contentSize = newSize
        guard isVisible, previous != newSize else { return }
        let target = homeFrame(for: newSize)
        guard target != frame else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().setFrame(target, display: true)
        }
    }

    /// Slide in at the fixed home position.
    func slideIn() {
        guard !isVisible else { return }
        layoutIfNeeded()
        let size = contentSize ?? hosting?.fittingSize ?? NSSize(width: 280, height: 320)
        setContentSize(size)
        let home = homeFrame(for: size)
        Log.d("shelf slideIn size=\(size) home=(\(Int(home.origin.x)),\(Int(home.origin.y)))")
        setFrameOrigin(NSPoint(x: home.maxX + size.width * 0.2, y: home.origin.y)) // start off-edge
        alphaValue = 0
        orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.28
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().setFrameOrigin(home.origin)
            animator().alphaValue = 1
        }
    }

    func slideOut() {
        guard isVisible else { return }
        Log.d("shelf slideOut")
        let f = frame
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.22
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            animator().setFrameOrigin(NSPoint(x: f.origin.x + f.width * 0.4, y: f.origin.y))
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            self?.orderOut(nil)
            self?.alphaValue = 1
        })
    }

}
