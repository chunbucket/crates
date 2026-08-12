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

        let host = NSHostingView(rootView: ShelfView(downloads: downloads, dropState: dropState))
        host.frame = catcher.bounds
        host.autoresizingMask = [.width, .height]
        catcher.addSubview(host)
        contentView = catcher
        hosting = host
    }

    override var canBecomeKey: Bool { false }

    /// Slide in at the right edge of the screen the mouse is on.
    func slideIn() {
        guard !isVisible else { return }
        layoutIfNeeded()
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let screen else { return }

        let size = hosting?.fittingSize ?? NSSize(width: 280, height: 320)
        setContentSize(size)

        let vf = screen.visibleFrame
        let margin: CGFloat = 18
        let y = min(max(mouse.y - size.height / 2, vf.minY + margin), vf.maxY - size.height - margin)
        let finalX = vf.maxX - size.width - margin
        Log.d("shelf slideIn size=\(size) final=(\(Int(finalX)),\(Int(y))) screen=\(vf)")
        setFrameOrigin(NSPoint(x: vf.maxX + 8, y: y)) // start just off-screen
        alphaValue = 0
        orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.28
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().setFrameOrigin(NSPoint(x: finalX, y: y))
            animator().alphaValue = 1
        }
    }

    func slideOut() {
        guard isVisible else { return }
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

    /// Grow/shrink smoothly when content changes (drop target → player card).
    func refit() {
        guard isVisible, let size = hosting?.fittingSize else { return }
        var f = frame
        let dY = (f.height - size.height) / 2
        f = NSRect(x: f.maxX - size.width, y: f.origin.y + dY, width: size.width, height: size.height)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            animator().setFrame(f, display: true)
        }
    }
}
