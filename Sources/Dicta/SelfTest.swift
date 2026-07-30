import AVFoundation
import Foundation

/// Headless end-to-end check of the transcription pipeline:
/// `Dicta --selftest <audio-file>` loads the models, streams the file through
/// the same session code the microphone path uses, applies replacements, and
/// prints the transcript to stdout.
enum SelfTest {
    static var requestedFile: String? {
        guard let i = CommandLine.arguments.firstIndex(of: "--selftest"),
            CommandLine.arguments.indices.contains(i + 1)
        else { return nil }
        return CommandLine.arguments[i + 1]
    }

    static func run(file: String) async {
        do {
            let transcriber = Transcriber()
            print("selftest: loading models…")
            try await transcriber.prepare { _ in }

            try await transcriber.beginSession()
            print("selftest: session started")

            let audioFile = try AVAudioFile(forReading: URL(fileURLWithPath: file))
            print("selftest: file open, format=\(audioFile.processingFormat), frames=\(audioFile.length)")
            let format = audioFile.processingFormat
            let chunk = AVAudioFrameCount(4096)
            while audioFile.framePosition < audioFile.length {
                guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunk) else { break }
                try audioFile.read(into: buffer, frameCount: chunk)
                if buffer.frameLength == 0 { break }
                transcriber.feed(buffer)
            }
            print("selftest: audio fed, finishing")

            let raw = try await transcriber.endSession()
            let corrected = Replacements.apply(to: raw)
            print("selftest raw:       \(raw)")
            print("selftest corrected: \(corrected)")
            exit(0)
        } catch {
            print("selftest FAILED: \(error)")
            exit(1)
        }
    }
}
