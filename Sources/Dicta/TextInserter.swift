import AppKit
import Carbon.HIToolbox

/// Delivers transcribed text into the frontmost app.
///
/// Puts the text on the pasteboard and synthesises ⌘V. If the process lacks
/// Accessibility permission the paste keystroke can't be posted, so the text
/// simply stays on the clipboard (and in history).
@MainActor
enum TextInserter {
    /// How long the target app gets to read the pasteboard before the
    /// previous contents come back. There is no "paste finished" signal, so
    /// this errs long: restoring too early pastes the old clipboard instead.
    private static let restoreDelay: TimeInterval = 1.5

    /// nspasteboard.org convention: clipboard managers skip transient items.
    private static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")

    static func insert(_ text: String) {
        let pasteboard = NSPasteboard.general

        guard AXIsProcessTrusted() else {
            // Clipboard-only delivery: leave the text there for a manual paste.
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            return
        }

        let saved = snapshot(of: pasteboard)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        pasteboard.setData(Data(), forType: transientType)
        let ourChange = pasteboard.changeCount

        let source = CGEventSource(stateID: .combinedSessionState)
        let vDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true)
        let vUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
        vDown?.flags = .maskCommand
        vUp?.flags = .maskCommand
        vDown?.post(tap: .cghidEventTap)
        vUp?.post(tap: .cghidEventTap)

        DispatchQueue.main.asyncAfter(deadline: .now() + restoreDelay) {
            // Something else was copied meanwhile: that wins.
            guard pasteboard.changeCount == ourChange else { return }
            pasteboard.clearContents()
            if !saved.isEmpty { pasteboard.writeObjects(saved) }
        }
    }

    /// Copies every item and type, not just plain text, so images, files and
    /// rich text survive the round trip.
    private static func snapshot(of pasteboard: NSPasteboard) -> [NSPasteboardItem] {
        (pasteboard.pasteboardItems ?? []).compactMap { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) { copy.setData(data, forType: type) }
            }
            return copy.types.isEmpty ? nil : copy
        }
    }
}
