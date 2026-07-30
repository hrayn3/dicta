import AppKit
import Carbon.HIToolbox

/// Delivers transcribed text into the frontmost app.
///
/// Puts the text on the pasteboard and synthesises ⌘V. If the process lacks
/// Accessibility permission the paste keystroke can't be posted, so the text
/// simply stays on the clipboard (and in history).
enum TextInserter {
    static func insert(_ text: String) {
        let pasteboard = NSPasteboard.general
        let previous = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        guard AXIsProcessTrusted() else { return }  // clipboard-only delivery

        let source = CGEventSource(stateID: .combinedSessionState)
        let vDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true)
        let vUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
        vDown?.flags = .maskCommand
        vUp?.flags = .maskCommand
        vDown?.post(tap: .cghidEventTap)
        vUp?.post(tap: .cghidEventTap)

        // Restore the previous clipboard once the paste has landed.
        if let previous {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                pasteboard.clearContents()
                pasteboard.setString(previous, forType: .string)
            }
        }
    }
}
