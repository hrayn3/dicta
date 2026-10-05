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

    /// RMS above this counts as voice activity (~-40 dBFS).
    private nonisolated static let voiceThreshold: Float = 0.01

    var lastVoiceActivity: Date { lastVoice.withLock { $0 } }

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
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            if Self.rms(of: buffer) > Self.voiceThreshold {
                lastVoice.withLock { $0 = Date() }
            }
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
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        do {
            try run(engine)
        } catch {
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

enum RecorderError: LocalizedError {
    case noInputDevice

    var errorDescription: String? {
        switch self {
        case .noInputDevice: return "No microphone is available"
        }
    }
}
