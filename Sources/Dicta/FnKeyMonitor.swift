import AppKit
import Carbon.HIToolbox

/// Listens for a bare tap of the Fn (globe) key.
///
/// Carbon hotkeys can't bind a lone modifier, so this watches `flagsChanged`
/// instead. A "tap" is Fn pressed and released with no other key in between —
/// holding Fn as a modifier (Fn+arrows, Fn+F-keys) does not trigger.
///
/// Requires Accessibility permission (same one the paste keystroke needs).
/// For a clean experience the system's own globe-key action should be set to
/// "Do Nothing" in System Settings → Keyboard.
@MainActor
final class FnKeyMonitor {
    private var flagsMonitors: [Any] = []
    private var keyDownMonitor: Any?
    private var fnIsDown = false
    private var otherKeySeen = false
    private let onTap: () -> Void

    init(onTap: @escaping () -> Void) {
        self.onTap = onTap
    }

    func start() {
        guard flagsMonitors.isEmpty else { return }
        let handle: (NSEvent) -> Void = { [weak self] event in
            Task { @MainActor in self?.handleFlagsChanged(event) }
        }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: handle) {
            flagsMonitors.append(global)
        }
        flagsMonitors.append(
            NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
                handle(event)
                return event
            } as Any
        )
    }

    func stop() {
        flagsMonitors.forEach { NSEvent.removeMonitor($0) }
        flagsMonitors = []
        removeKeyDownMonitor()
        fnIsDown = false
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        guard event.keyCode == kVK_Function else { return }
        if event.modifierFlags.contains(.function) {
            fnIsDown = true
            otherKeySeen = false
            installKeyDownMonitor()
        } else if fnIsDown {
            fnIsDown = false
            removeKeyDownMonitor()
            if !otherKeySeen { onTap() }
        }
    }

    /// While Fn is held, note any other key press so Fn-as-modifier is ignored.
    private func installKeyDownMonitor() {
        guard keyDownMonitor == nil else { return }
        keyDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] _ in
            Task { @MainActor in self?.otherKeySeen = true }
        }
    }

    private func removeKeyDownMonitor() {
        if let keyDownMonitor { NSEvent.removeMonitor(keyDownMonitor) }
        keyDownMonitor = nil
    }
}
