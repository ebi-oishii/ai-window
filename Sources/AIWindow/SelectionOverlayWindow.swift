import AppKit

class SelectionOverlayWindow: NSWindow {
    private let overlayView = SelectionOverlayView()

    init() {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        super.init(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        hasShadow = false
        backgroundColor = .clear
        // Stay above all app windows but not above system UI
        level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue - 1)
        ignoresMouseEvents = true  // CGEventTap handles all input; overlay is visual-only
        collectionBehavior = [.canJoinAllSpaces, .stationary]

        contentView = overlayView
    }

    func update(start: CGPoint, current: CGPoint) {
        overlayView.start = start
        overlayView.current = current
        overlayView.needsDisplay = true
    }

    func clear() {
        overlayView.start = nil
        overlayView.current = nil
        overlayView.needsDisplay = true
    }
}
