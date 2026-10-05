import AVFoundation
import Foundation
import os

/// Captures microphone audio via AVAudioEngine and forwards raw buffers.
/// Tracks the last time the input level looked like speech so the app can
/// auto-stop a forgotten recording.
///
/// Each recording gets a fresh engine so a device change between takes never
/// leaves a stale input format behind. A device change *during* a take (e.g.
/// AirPods connecting) stops the engine; the recorder reinstalls its tap on
/// the new input and carries on, or reports `onInterrupted` if it can't.
@MainActor
final class AudioRecorder {
    private var engine: AVAudioEngine?
    private var configObserver: NSObjectProtocol?
    private var onBuffer: ((AVAudioPCMBuffer) -> Void)?
    private var onInterrupted: (() -> Void)?
    private let lastVoice = OSAllocatedUnfairLock(initialState: Date())
    private let stats = OSAllocatedUnfairLock(initialState: CaptureStats())

    /// RMS above this counts as voice activity (~-40 dBFS).
    private nonisolated static let voiceThreshold: Float = 0.01

    var lastVoiceActivity: Date { lastVoice.withLock { $0 } }

    /// What the tap actually delivered for the current (or last) take.
    var captureStats: CaptureStats { stats.withLock { $0 } }

    func start(
        onBuffer: @escaping (AVAudioPCMBuffer) -> Void,
        onInterrupted: @escaping () -> Void
    ) throws {
        stop()
        let engine = AVAudioEngine()
        self.engine = engine
        self.onBuffer = onBuffer
        self.onInterrupted = onInterrupted
        lastVoice.withLock { $0 = Date() }
        stats.withLock { $0 = CaptureStats() }

        do {
            try run(engine)
        } catch {
            stop()
            throw error
        }

        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.restartAfterConfigurationChange() }
        }
    }

    /// Keeps recording briefly after the stop tap. People often tap while
    /// still saying their last words, so wait for a short pause in speech
    /// (or give up after `maximum`) before the caller stops the engine.
    /// `minimum` lets the buffer in flight at the tap arrive.
    func waitForPause(
        minimum: TimeInterval = 0.15,
        quiet: TimeInterval = 0.35,
        maximum: TimeInterval = 1.5
    ) async {
        let started = Date()
        while engine != nil {
            let elapsed = Date().timeIntervalSince(started)
            if elapsed >= maximum { return }
            if elapsed >= minimum, Date().timeIntervalSince(lastVoiceActivity) >= quiet { return }
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    func stop() {
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
        configObserver = nil
        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        engine = nil
        onBuffer = nil
        onInterrupted = nil
    }

    private func run(_ engine: AVAudioEngine) throws {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw RecorderError.noInputDevice
        }
        guard let onBuffer else { return }
        let lastVoice = self.lastVoice
        let stats = self.stats
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            if Self.rms(of: buffer) > Self.voiceThreshold {
                lastVoice.withLock { $0 = Date() }
            }
            stats.withLock { $0.record(buffer) }
            onBuffer(buffer)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw error
        }
    }

    private func restartAfterConfigurationChange() {
        guard let engine else { return }
        takeLog.notice("audio configuration changed mid-take; restarting input")
        stats.withLock { $0.restarts += 1 }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        do {
            try run(engine)
        } catch {
            takeLog.error("input restart failed: \(error.localizedDescription, privacy: .public)")
            let onInterrupted = self.onInterrupted
            stop()
            onInterrupted?()
        }
    }

    private nonisolated static func rms(of buffer: AVAudioPCMBuffer) -> Float {
        guard let data = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        let n = Int(buffer.frameLength)
        var sum: Float = 0
        for i in 0..<n { sum += data[i] * data[i] }
        return (sum / Float(n)).squareRoot()
    }
}

struct CaptureStats {
    var buffers = 0
    var seconds: Double = 0
    var sampleRate: Double = 0
    var firstBufferAt: Date?
    var lastBufferAt: Date?
    var restarts = 0

    mutating func record(_ buffer: AVAudioPCMBuffer) {
        let now = Date()
        if firstBufferAt == nil { firstBufferAt = now }
        lastBufferAt = now
        buffers += 1
        sampleRate = buffer.format.sampleRate
        if sampleRate > 0 { seconds += Double(buffer.frameLength) / sampleRate }
    }
}

enum RecorderError: LocalizedError {
    case noInputDevice

    var errorDescription: String? {
        switch self {
        case .noInputDevice: return "No microphone is available"
        }
    }
}
