import Cocoa

class RightClickDragMonitor {
    var onDragStart: (() -> Void)?
    var onDragUpdate: ((CGPoint, CGPoint) -> Void)?
    var onSelectionMade: ((CGRect) -> Void)?
    var onDragCancelled: (() -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    fileprivate var dragStart: CGPoint?
    fileprivate var isDragging = false
    fileprivate let minDragDistance: CGFloat = 20

    // Accessed only on main run loop thread; nonisolated(unsafe) silences Swift 6 warning
    nonisolated(unsafe) static var current: RightClickDragMonitor?

    func start() {
        RightClickDragMonitor.current = self

        let mask = CGEventMask(
            (1 << CGEventType.rightMouseDown.rawValue) |
            (1 << CGEventType.rightMouseDragged.rawValue) |
            (1 << CGEventType.rightMouseUp.rawValue)
        )

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: tapCallback,
            userInfo: nil
        )

        guard let tap = eventTap else {
            print("[AIWindow] Failed to create CGEventTap — grant Accessibility permission and restart")
            return
        }

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
        print("[AIWindow] Right-click drag monitor active")
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            }
        }
        eventTap = nil
        runLoopSource = nil
        RightClickDragMonitor.current = nil
    }

    // Called from tapCallback on the main run loop thread
    fileprivate func process(type: CGEventType, event: CGEvent) -> CGEvent? {
        let loc = event.location

        switch type {
        case .rightMouseDown:
            dragStart = loc
            isDragging = false
            return event

        case .rightMouseDragged:
            guard let start = dragStart else { return event }
            let dist = hypot(loc.x - start.x, loc.y - start.y)
            if dist >= minDragDistance {
                if !isDragging {
                    isDragging = true
                    onDragStart?()
                }
                onDragUpdate?(start, loc)
                return nil  // suppress event to prevent other drag behaviors
            }
            return isDragging ? nil : event

        case .rightMouseUp:
            let wasDragging = isDragging
            let start = dragStart
            dragStart = nil
            isDragging = false

            guard wasDragging, let s = start else {
                return event  // normal right-click, let context menu show
            }

            let rect = CGRect(
                x: min(s.x, loc.x),
                y: min(s.y, loc.y),
                width: abs(loc.x - s.x),
                height: abs(loc.y - s.y)
            )
            onSelectionMade?(rect)
            return nil  // suppress context menu

        case .tapDisabledByTimeout:
            print("[AIWindow] tap disabled by timeout — re-enabling")
            if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            return nil

        default:
            // kCGEventTapDisabledByUserInput = 0xFFFFFFFF
            // Triggered when NSApp.activate() is called or secure input is entered.
            // Must re-enable or the tap stays dead for the rest of the session.
            if type.rawValue == 0xFFFF_FFFE || type.rawValue == 0xFFFF_FFFF {
                print("[AIWindow] tap disabled by user-input event (0x\(String(type.rawValue, radix: 16))) — re-enabling")
                if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
                return nil
            }
            return event
        }
    }

    deinit { stop() }
}

// C-callable callback — no captured context; uses static `current` via main run loop
private func tapCallback(
    _ proxy: CGEventTapProxy,
    _ type: CGEventType,
    _ event: CGEvent,
    _ userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let monitor = RightClickDragMonitor.current else {
        return Unmanaged.passRetained(event)
    }
    if let result = monitor.process(type: type, event: event) {
        return Unmanaged.passRetained(result)
    }
    return nil
}
