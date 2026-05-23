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

        // Translucent cyan fill
        Theme.accentGlow.setFill()
        rect.fill()

        // Sharp cyan border (no dashes — Detroit aesthetic prefers solid lines)
        let path = NSBezierPath(rect: rect.insetBy(dx: 0.5, dy: 0.5))
        path.lineWidth = 1
        Theme.accent.setStroke()
        path.stroke()

        // Corner brackets — Detroit HUD targeting look
        let bracketLen: CGFloat = 12
        let brackets = NSBezierPath()
        // Top-left
        brackets.move(to: NSPoint(x: rect.minX, y: rect.maxY - bracketLen))
        brackets.line(to: NSPoint(x: rect.minX, y: rect.maxY))
        brackets.line(to: NSPoint(x: rect.minX + bracketLen, y: rect.maxY))
        // Top-right
        brackets.move(to: NSPoint(x: rect.maxX - bracketLen, y: rect.maxY))
        brackets.line(to: NSPoint(x: rect.maxX, y: rect.maxY))
        brackets.line(to: NSPoint(x: rect.maxX, y: rect.maxY - bracketLen))
        // Bottom-left
        brackets.move(to: NSPoint(x: rect.minX, y: rect.minY + bracketLen))
        brackets.line(to: NSPoint(x: rect.minX, y: rect.minY))
        brackets.line(to: NSPoint(x: rect.minX + bracketLen, y: rect.minY))
        // Bottom-right
        brackets.move(to: NSPoint(x: rect.maxX - bracketLen, y: rect.minY))
        brackets.line(to: NSPoint(x: rect.maxX, y: rect.minY))
        brackets.line(to: NSPoint(x: rect.maxX, y: rect.minY + bracketLen))
        brackets.lineWidth = 2
        Theme.accent.setStroke()
        brackets.stroke()

        // Monospaced size readout — center of the rect
        let sizeStr = "\(Int(rect.width)) × \(Int(rect.height))" as NSString
        let attrs: [NSAttributedString.Key: Any] = [
            .font: Theme.hud(11, weight: .medium),
            .foregroundColor: Theme.accent,
            .kern: 1.0,
        ]
        let size = sizeStr.size(withAttributes: attrs)
        let labelRect = NSRect(
            x: rect.midX - size.width / 2 - 6,
            y: rect.midY - size.height / 2 - 3,
            width: size.width + 12,
            height: size.height + 6
        )
        NSColor.black.withAlphaComponent(0.55).setFill()
        labelRect.fill()
        let labelBorder = NSBezierPath(rect: labelRect.insetBy(dx: 0.5, dy: 0.5))
        labelBorder.lineWidth = 1
        Theme.accentDim.setStroke()
        labelBorder.stroke()
        sizeStr.draw(
            at: NSPoint(x: labelRect.minX + 6, y: labelRect.minY + 3),
            withAttributes: attrs
        )
    }
}
