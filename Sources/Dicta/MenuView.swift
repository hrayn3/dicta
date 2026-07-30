import AppKit
import KeyboardShortcuts
import SwiftUI

struct MenuView: View {
    @EnvironmentObject var state: AppState
    @State private var copiedID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Status
            HStack {
                Image(nsImage: state.menuBarImage)
                Text(state.statusLine)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if !state.axTrusted {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Can't paste at the cursor — Accessibility permission needed. Transcripts go to the clipboard and history instead.")
                            .font(.caption2)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Grant in System Settings…") { state.openAccessibilitySettings() }
                            .buttonStyle(.link)
                            .font(.caption2)
                    }
                }
            }

            Divider()

            // Controls
            Toggle("Enabled", isOn: $state.enabled)
                .toggleStyle(.switch)
                .controlSize(.small)

            Toggle("Use 🌐 Fn key as shortcut", isOn: $state.useFnKey)
                .toggleStyle(.checkbox)
            if state.useFnKey {
                Text("Set System Settings → Keyboard → “Press 🌐 key to” to “Do Nothing” so it doesn’t also trigger emoji or Apple dictation.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                HStack {
                    Text("Shortcut")
                    Spacer()
                    KeyboardShortcuts.Recorder(for: .toggleDictation)
                }
            }

            Toggle("Keep history", isOn: $state.keepHistory)
                .toggleStyle(.checkbox)
            Toggle("Launch at login", isOn: $state.launchAtLogin)
                .toggleStyle(.checkbox)

            Divider()

            // History
            HStack {
                Text("History").font(.headline)
                Spacer()
                if !state.history.isEmpty {
                    Button("Clear") { state.clearHistory() }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }

            if state.history.isEmpty {
                Text("Transcripts appear here — click one to copy it.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                // Explicit height: in a MenuBarExtra window a ScrollView's
                // ideal height is zero, so maxHeight alone collapses it.
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(state.history) { entry in
                            HistoryRow(entry: entry, copied: copiedID == entry.id) {
                                copy(entry)
                            }
                        }
                    }
                }
                .frame(height: min(240, CGFloat(state.history.count) * 60))
            }

            Divider()

            HStack {
                Button("Edit replacements…") {
                    Replacements.ensureStarterFile()
                    NSWorkspace.shared.open(Replacements.fileURL)
                }
                .buttonStyle(.link)
                .font(.caption)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .font(.caption)
            }
        }
        .padding(12)
        .frame(width: 320)
        .onAppear { state.refreshAXStatus() }
    }

    private func copy(_ entry: HistoryEntry) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.text, forType: .string)
        copiedID = entry.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            if copiedID == entry.id { copiedID = nil }
        }
    }
}

private struct HistoryRow: View {
    let entry: HistoryEntry
    let copied: Bool
    let onCopy: () -> Void

    var body: some View {
        Button(action: onCopy) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.date, format: .dateTime.day().month().hour().minute())
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text(copied ? "Copied ✓" : entry.text)
                    .font(.caption)
                    .lineLimit(3)
                    .foregroundStyle(copied ? Color.accentColor : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 2)
    }
}
