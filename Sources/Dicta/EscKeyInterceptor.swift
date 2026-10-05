import AppKit
import Carbon.HIToolbox

/// Swallows Esc while a recording is in progress and reports it, so cancelling
/// a dictation doesn't also close a dialog or leave insert mode in the
/// frontmost app.
///
/// Uses a session event tap, which needs the same Accessibility permission as
/// the paste keystroke. Without it, falls back to a global monitor that sees
/// Esc but cannot stop it reaching the frontmost app.
@MainActor
final class EscKeyInterceptor {
    private let onEsc: () -> Void
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var fallbackMonitor: Any?

    init(onEsc: @escaping () -> Void) {
        self.onEsc = onEsc
    }

    func start() {
        guard tap == nil, fallbackMonitor == nil else { return }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue) | CGEventMask(1 << CGEventType.keyUp.rawValue)
        if let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let interceptor = Unmanaged<EscKeyInterceptor>.fromOpaque(userInfo).takeUnretainedValue()
                return MainActor.assumeIsolated { interceptor.handle(type: type, event: event) }
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) {
            let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            self.tap = tap
            runLoopSource = source
        } else {
            fallbackMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard event.keyCode == kVK_Escape else { return }
                Task { @MainActor in self?.onEsc() }
            }
        }
    }

    func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
            CFMachPortInvalidate(tap)
        }
        tap = nil
        runLoopSource = nil
        if let fallbackMonitor { NSEvent.removeMonitor(fallbackMonitor) }
        fallbackMonitor = nil
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        case .keyDown, .keyUp:
            guard event.getIntegerValueField(.keyboardEventKeycode) == Int64(kVK_Escape) else {
                return Unmanaged.passUnretained(event)
            }
            if type == .keyDown {
                // Defer so the tap callback returns immediately.
                DispatchQueue.main.async { [onEsc] in onEsc() }
            }
            return nil
        default:
            return Unmanaged.passUnretained(event)
        }
    }
}
