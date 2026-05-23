import AppKit

class SelectionOverlayView: NSView {
    var start: CGPoint?
    var current: CGPoint?

    override func draw(_ dirtyRect: NSRect) {
        guard let s = start, let c = current else { return }

        // CGEvent coords: y=0 at screen top. NSView (non-flipped): y=0 at bottom.
        // The overlay window covers the full screen, so bounds.height == screen height.
        let h = bounds.height
        let vs = NSPoint(x: s.x, y: h - s.y)
        let vc = NSPoint(x: c.x, y: h - c.y)

        let rect = NSRect(
            x: min(vs.x, vc.x),
            y: min(vs.y, vc.y),
            width: abs(vc.x - vs.x),
            height: abs(vc.y - vs.y)
        )

        guard rect.width > 1, rect.height > 1 else { return }

        // Translucent fill
        NSColor.systemBlue.withAlphaComponent(0.08).setFill()
        rect.fill()

        // Dashed border
        let path = NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5))
        path.lineWidth = 1.5
        path.setLineDash([6, 3], count: 2, phase: 0)
        NSColor.systemBlue.withAlphaComponent(0.85).setStroke()
        path.stroke()

        // Corner size indicator
        let sizeStr = "\(Int(rect.width)) × \(Int(rect.height))" as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let size = sizeStr.size(withAttributes: attrs)
        let labelRect = NSRect(
            x: rect.midX - size.width / 2 - 4,
            y: rect.midY - size.height / 2 - 2,
            width: size.width + 8,
            height: size.height + 4
        )
        NSColor.black.withAlphaComponent(0.4).setFill()
        NSBezierPath(roundedRect: labelRect, xRadius: 3, yRadius: 3).fill()
        sizeStr.draw(
            at: NSPoint(x: labelRect.minX + 4, y: labelRect.minY + 2),
            withAttributes: attrs
        )
    }
}
