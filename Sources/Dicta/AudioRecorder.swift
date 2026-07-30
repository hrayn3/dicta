import AVFoundation
import Foundation

/// Captures microphone audio via AVAudioEngine and forwards raw buffers.
/// Tracks the last time the input level looked like speech so the app can
/// auto-stop a forgotten recording.
final class AudioRecorder {
    private let engine = AVAudioEngine()
    private(set) var lastVoiceActivity = Date()

    /// RMS above this counts as voice activity (~-40 dBFS).
    private let voiceThreshold: Float = 0.01

    func start(onBuffer: @escaping (AVAudioPCMBuffer) -> Void) throws {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        lastVoiceActivity = Date()

        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            if let self, Self.rms(of: buffer) > self.voiceThreshold {
                self.lastVoiceActivity = Date()
            }
            onBuffer(buffer)
        }

        engine.prepare()
        try engine.start()
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }

    private static func rms(of buffer: AVAudioPCMBuffer) -> Float {
        guard let data = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        let n = Int(buffer.frameLength)
        var sum: Float = 0
        for i in 0..<n { sum += data[i] * data[i] }
        return (sum / Float(n)).squareRoot()
    }
}
