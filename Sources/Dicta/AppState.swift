import AVFoundation
import AppKit
import KeyboardShortcuts
import ServiceManagement
import SwiftUI
import os

/// Per-take diagnostics: `log stream --predicate 'subsystem == "com.hughrayner.dicta"'`.
let takeLog = Logger(subsystem: "com.hughrayner.dicta", category: "take")

extension KeyboardShortcuts.Name {
    /// Default: ⌃⌥Space — tappable with one hand.
    static let toggleDictation = Self(
        "toggleDictation",
        default: .init(.space, modifiers: [.control, .option])
    )
}

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    enum Phase: Equatable {
        case loadingModel(String)
        case idle
        case starting
        case recording
        case transcribing
        case failed(String)
    }

    @Published var phase: Phase = .loadingModel("Starting…")
    @Published var enabled = true {
        didSet {
            if !enabled, phase == .recording { cancelRecording() }
        }
    }
    @Published var history: [HistoryEntry] = []
    @Published var axTrusted = AXIsProcessTrusted()
    @Published var keepHistory = UserDefaults.standard.object(forKey: "keepHistory") as? Bool ?? true {
        didSet { UserDefaults.standard.set(keepHistory, forKey: "keepHistory") }
    }
    @Published var useFnKey = UserDefaults.standard.bool(forKey: "useFnKey") {
        didSet {
            UserDefaults.standard.set(useFnKey, forKey: "useFnKey")
            updateFnMonitor()
        }
    }
    /// Debug aid: keep the most recent take as a WAV so a bad transcript can
    /// be checked against what the mic actually heard. Off by default.
    @Published var keepLastRecording = UserDefaults.standard.bool(forKey: "keepLastRecording") {
        didSet {
            UserDefaults.standard.set(keepLastRecording, forKey: "keepLastRecording")
            if !keepLastRecording { try? FileManager.default.removeItem(at: Transcriber.lastTakeURL) }
        }
    }
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled {
        didSet { updateLaunchAtLogin() }
    }

    private let recorder = AudioRecorder()
    private let transcriber = Transcriber()
    private let historyStore = HistoryStore()

    /// Auto-stop after this much sustained silence while recording.
    private let silenceLimit: TimeInterval = 300
    private var silenceTimer: Timer?
    private var recordingStartedAt = Date()
    private lazy var escInterceptor = EscKeyInterceptor { [weak self] in
        self?.cancelRecording()
    }
    private lazy var fnMonitor = FnKeyMonitor { [weak self] in
        self?.toggleDictation()
    }

    var menuBarImage: NSImage {
        if !enabled { return MenuBarIcon.paused }
        switch phase {
        case .loadingModel: return MenuBarIcon.loading
        case .idle: return MenuBarIcon.idle
        case .starting, .recording: return MenuBarIcon.recording
        case .transcribing: return MenuBarIcon.transcribing
        case .failed: return MenuBarIcon.failed
        }
    }

    var statusLine: String {
        if !enabled { return "Paused" }
        switch phase {
        case .loadingModel(let detail): return detail
        case .idle: return "Ready — tap shortcut to dictate"
        case .starting: return "Starting microphone…"
        case .recording: return "Recording… tap shortcut to finish, Esc to cancel"
        case .transcribing: return "Transcribing…"
        case .failed(let message): return message
        }
    }

    func bootstrap() {
        history = historyStore.load()
        requestAccessibilityIfNeeded()

        KeyboardShortcuts.onKeyUp(for: .toggleDictation) { [weak self] in
            Task { @MainActor in
                guard let self, !self.useFnKey else { return }
                self.toggleDictation()
            }
        }
        updateFnMonitor()

        Task {
            do {
                phase = .loadingModel("Downloading speech model (first run only)…")
                try await transcriber.prepare { progress in
                    Task { @MainActor [weak self] in
                        if progress < 1.0 {
                            self?.phase = .loadingModel(
                                "Downloading speech model… \(Int(progress * 100))%")
                        }
                    }
                }
                phase = .idle
            } catch {
                phase = .failed("Model load failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Dictation flow

    func toggleDictation() {
        guard enabled else { return }
        switch phase {
        case .idle: startRecording()
        // A failed take shouldn't need a relaunch: the next tap retries.
        // (A failed model load can't be retried this way.)
        case .failed where transcriber.isReady: startRecording()
        case .recording: finishRecording(reason: "tap")
        // .starting: ignore repeat taps until the mic is live, or a
        // bounced key would start a second recording.
        default: break
        }
    }

    private func startRecording() {
        phase = .starting
        Task {
            do {
                guard await requestMicAccess() else {
                    phase = .failed("Microphone access denied — enable in System Settings → Privacy")
                    return
                }
                try transcriber.beginSession()
                try recorder.start(
                    onBuffer: { [transcriber] buffer in transcriber.feed(buffer) },
                    onInterrupted: { [weak self] in self?.finishRecording(reason: "input lost") }
                )
                // Paused while the mic was starting up.
                guard enabled, phase == .starting else {
                    recorder.stop()
                    transcriber.discardSession()
                    if phase == .starting { phase = .idle }
                    return
                }
                phase = .recording
                recordingStartedAt = Date()
                escInterceptor.start()
                startSilenceWatchdog()
            } catch {
                transcriber.discardSession()
                phase = .failed("Could not start recording: \(error.localizedDescription)")
            }
        }
    }

    private func finishRecording(reason: String) {
        guard phase == .recording else { return }
        let stopAt = Date()
        let voiceAgeAtStop = stopAt.timeIntervalSince(recorder.lastVoiceActivity)
        escInterceptor.stop()
        stopSilenceWatchdog()
        phase = .transcribing
        Task {
            await recorder.recordTail()
            recorder.stop()
            let stats = recorder.captureStats
            let lastBufferAge = stats.lastBufferAt.map { stopAt.timeIntervalSince($0) } ?? -1
            takeLog.notice(
                """
                take stopped by \(reason, privacy: .public): wall \(stopAt.timeIntervalSince(self.recordingStartedAt), format: .fixed(precision: 2))s, \
                audio \(stats.seconds, format: .fixed(precision: 2))s in \(stats.buffers) buffers @ \(Int(stats.sampleRate)) Hz, \
                last buffer \(lastBufferAge, format: .fixed(precision: 2))s before stop, \
                last voice \(voiceAgeAtStop, format: .fixed(precision: 2))s before stop, \
                waited \(Date().timeIntervalSince(stopAt), format: .fixed(precision: 2))s, restarts \(stats.restarts)
                """)
            do {
                var text = try await transcriber.endSession(
                    saveTo: keepLastRecording ? Transcriber.lastTakeURL : nil)
                takeLog.notice("transcribed \(text.split(separator: " ").count) words")
                text = Replacements.apply(to: text)
                text = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    if keepHistory {
                        let entry = historyStore.append(text)
                        history.insert(entry, at: 0)
                        history = Array(history.prefix(HistoryStore.maxEntries))
                    }
                    TextInserter.insert(text)
                }
                phase = .idle
            } catch {
                phase = .failed("Transcription failed: \(error.localizedDescription)")
            }
        }
    }

    func cancelRecording() {
        guard phase == .recording else { return }
        recorder.stop()
        escInterceptor.stop()
        stopSilenceWatchdog()
        transcriber.discardSession()
        phase = .idle
    }

    // MARK: - Silence watchdog

    private func startSilenceWatchdog() {
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.phase == .recording else { return }
                if Date().timeIntervalSince(self.recorder.lastVoiceActivity) > self.silenceLimit {
                    self.finishRecording(reason: "silence")
                }
            }
        }
    }

    private func stopSilenceWatchdog() {
        silenceTimer?.invalidate()
        silenceTimer = nil
    }

    // MARK: - History

    func clearHistory() {
        historyStore.clear()
        history = []
    }

    /// macOS never prompts for Accessibility on its own — the app must ask.
    /// Without it we can't paste at the cursor or see the Fn/Esc keys.
    private func requestAccessibilityIfNeeded() {
        if !AXIsProcessTrusted() {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
            AXIsProcessTrustedWithOptions(options as CFDictionary)
        }
        refreshAXStatus()
    }

    func refreshAXStatus() {
        axTrusted = AXIsProcessTrusted()
    }

    func openAccessibilitySettings() {
        let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    private func updateFnMonitor() {
        if useFnKey {
            fnMonitor.start()
        } else {
            fnMonitor.stop()
        }
    }

    // MARK: - Misc

    private func requestMicAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }

    private func updateLaunchAtLogin() {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Registration only works from a bundled .app; ignore in dev runs.
        }
    }
}
