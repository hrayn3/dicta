import AVFoundation
import FluidAudio
import Foundation
import os

/// Wraps FluidAudio's Parakeet TDT v3 pipeline.
///
/// Models are loaded once and kept warm for the app's lifetime. While
/// recording, audio is only collected; the whole take is transcribed in one
/// pass when it ends. FluidAudio's streaming manager drops or repeats words
/// where its 11 s windows meet, and Dicta never shows live text, so streaming
/// bought nothing. One pass over a 30 s take still finishes in ~200 ms.
final class Transcriber {
    private var asr: AsrManager?
    private let audio = OSAllocatedUnfairLock(initialState: SessionAudio())
    private let converter = AudioConverter()

    var isReady: Bool { asr != nil }

    func prepare(progress: @escaping (Double) -> Void) async throws {
        // Prefer the model shipped inside the .app (fully offline install);
        // fall back to downloading into the shared cache on first run.
        let models: AsrModels
        if let bundled = Self.bundledModelDirectory {
            models = try await AsrModels.load(from: bundled)
        } else {
            models = try await AsrModels.downloadAndLoad(version: .v3) { p in
                progress(p.fractionCompleted)
            }
        }
        let manager = AsrManager(models: models)
        try await manager.loadModels(models)
        asr = manager
    }

    static var bundledModelDirectory: URL? {
        guard
            let dir = Bundle.main.resourceURL?
                .appendingPathComponent("Models/parakeet-tdt-0.6b-v3", isDirectory: true),
            FileManager.default.fileExists(atPath: dir.appendingPathComponent("parakeet_vocab.json").path)
        else { return nil }
        return dir
    }

    func beginSession() throws {
        guard isReady else { throw TranscriberError.modelsNotLoaded }
        audio.withLock { $0 = SessionAudio() }
    }

    /// Called on the audio thread with each captured buffer.
    func feed(_ buffer: AVAudioPCMBuffer) {
        guard let mono = Self.monoSamples(of: buffer) else { return }
        let rate = buffer.format.sampleRate
        audio.withLock { session in
            // A device change mid-take can change the sample rate; resample
            // what we have so far at its own rate before switching.
            if rate != session.pendingRate, !session.pending.isEmpty {
                session.resampled += (try? converter.resample(session.pending, from: session.pendingRate)) ?? []
                session.pending = []
            }
            session.pendingRate = rate
            session.pending += mono
        }
    }

    /// Where "Keep last recording" writes the most recent take.
    static var lastTakeURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Dicta/last-take.wav")
    }

    func endSession(saveTo saveURL: URL? = nil) async throws -> String {
        guard let asr else { throw TranscriberError.modelsNotLoaded }
        let session = audio.withLock { session in
            defer { session = SessionAudio() }
            return session
        }
        var samples = session.resampled
        if !session.pending.isEmpty {
            samples += try converter.resample(session.pending, from: session.pendingRate)
        }
        if let saveURL { Self.writeWAV(samples, to: saveURL) }
        // Shorter than the model's minimum: a mis-tap, not speech.
        guard samples.count >= ASRConstants.minimumRequiredSamples(forSampleRate: 16_000) else {
            return ""
        }
        var state = TdtDecoderState.make(decoderLayers: await asr.decoderLayerCount)
        return try await asr.transcribe(samples, decoderState: &state).text
    }

    /// 16 kHz mono 16-bit WAV — exactly what the model was given.
    private static func writeWAV(_ samples: [Float], to url: URL) {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 16_000, AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false,
        ]
        guard
            let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1),
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(max(samples.count, 1)))
        else { return }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { src in
            buffer.floatChannelData![0].update(from: src.baseAddress!, count: samples.count)
        }
        try? FileManager.default.removeItem(at: url)
        do {
            let file = try AVAudioFile(forWriting: url, settings: settings)
            try file.write(from: buffer)
        } catch {
            takeLog.error("could not save last take: \(error.localizedDescription, privacy: .public)")
        }
    }

    func discardSession() {
        audio.withLock { $0 = SessionAudio() }
    }

    /// Channel 0 as Float32, averaging channels when the input is multichannel.
    private static func monoSamples(of buffer: AVAudioPCMBuffer) -> [Float]? {
        guard let channels = buffer.floatChannelData, buffer.frameLength > 0 else { return nil }
        let frames = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        if channelCount == 1 {
            return Array(UnsafeBufferPointer(start: channels[0], count: frames))
        }
        var mono = [Float](repeating: 0, count: frames)
        for c in 0..<channelCount {
            let data = channels[c]
            for i in 0..<frames { mono[i] += data[i] }
        }
        let scale = 1 / Float(channelCount)
        for i in 0..<frames { mono[i] *= scale }
        return mono
    }
}

/// Audio collected for the current take: finished 16 kHz samples plus the
/// run still at the device's native rate.
private struct SessionAudio {
    var resampled: [Float] = []
    var pending: [Float] = []
    var pendingRate: Double = 0
}

enum TranscriberError: LocalizedError {
    case modelsNotLoaded

    var errorDescription: String? {
        switch self {
        case .modelsNotLoaded: return "Speech model is not loaded yet"
        }
    }
}
