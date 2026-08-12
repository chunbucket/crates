import AppKit

/// Transparent overlay on the status item button: accepts YouTube-URL drops
/// (highlighting the button while a matching drag hovers) and forwards
/// plain clicks to the app's handlers.
final class StatusDropView: NSView {
    var onURLDrop: ((String) -> Void)?
    var onLeftClick: (() -> Void)?
    var onRightClick: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes(DragMonitor.dragTypes)
    }
    required init?(coder: NSCoder) { fatalError() }

    private var button: NSStatusBarButton? { superview as? NSStatusBarButton }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        Log.d("status item draggingEntered")
        button?.isHighlighted = true
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        button?.isHighlighted = false
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        button?.isHighlighted = false
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        button?.isHighlighted = false
        guard let url = DragMonitor.youtubeURL(on: sender.draggingPasteboard) else {
            Log.d("status item drop rejected — types=\((sender.draggingPasteboard.types ?? []).map(\.rawValue))")
            return false
        }
        onURLDrop?(url)
        return true
    }

    // Act on mouse-UP, one runloop later: showing a popover/menu while the
    // status bar's click tracking is still active detaches it from the icon.
    override func mouseDown(with event: NSEvent) {}
    override func rightMouseDown(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) {
        DispatchQueue.main.async { [weak self] in self?.onLeftClick?() }
    }

    override func rightMouseUp(with event: NSEvent) {
        DispatchQueue.main.async { [weak self] in self?.onRightClick?() }
    }
}
