import AVFoundation
import FluidAudio
import Foundation

/// Wraps FluidAudio's Parakeet TDT v3 pipeline.
///
/// Models are downloaded once (first run) and kept warm for the app's
/// lifetime. Each recording is a fresh `SlidingWindowAsrManager` session that
/// transcribes continuously while audio streams in, so the final text arrives
/// almost immediately after the stop tap.
final class Transcriber {
    private var models: AsrModels?
    private var session: SlidingWindowAsrManager?

    // Buffers are funnelled through a single consumer task so they reach the
    // ASR engine in capture order (a Task per buffer would not guarantee it).
    private var feedContinuation: AsyncStream<AVAudioPCMBuffer>.Continuation?
    private var feedTask: Task<Void, Never>?

    func prepare(progress: @escaping (Double) -> Void) async throws {
        // Prefer the model shipped inside the .app (fully offline install);
        // fall back to downloading into the shared cache on first run.
        if let bundled = Self.bundledModelDirectory {
            models = try await AsrModels.load(from: bundled)
        } else {
            models = try await AsrModels.downloadAndLoad(version: .v3) { p in
                progress(p.fractionCompleted)
            }
        }
    }

    static var bundledModelDirectory: URL? {
        guard
            let dir = Bundle.main.resourceURL?
                .appendingPathComponent("Models/parakeet-tdt-0.6b-v3", isDirectory: true),
            FileManager.default.fileExists(atPath: dir.appendingPathComponent("parakeet_vocab.json").path)
        else { return nil }
        return dir
    }

    func beginSession() async throws {
        guard let models else { throw TranscriberError.modelsNotLoaded }
        let manager = SlidingWindowAsrManager()
        try await manager.loadModels(models)
        try await manager.startStreaming(source: .microphone)
        session = manager

        let (stream, continuation) = AsyncStream<AVAudioPCMBuffer>.makeStream()
        feedContinuation = continuation
        feedTask = Task {
            for await buffer in stream {
                await manager.streamAudio(buffer)
            }
        }
    }

    func feed(_ buffer: AVAudioPCMBuffer) {
        feedContinuation?.yield(buffer)
    }

    func endSession() async throws -> String {
        guard let session else { throw TranscriberError.noActiveSession }
        defer { self.session = nil }
        await drainFeed()
        return try await session.finish()
    }

    func discardSession() async {
        guard let session else { return }
        await drainFeed()
        await session.cancel()
        self.session = nil
    }

    private func drainFeed() async {
        feedContinuation?.finish()
        feedContinuation = nil
        await feedTask?.value
        feedTask = nil
    }
}

enum TranscriberError: LocalizedError {
    case modelsNotLoaded
    case noActiveSession

    var errorDescription: String? {
        switch self {
        case .modelsNotLoaded: return "Speech model is not loaded yet"
        case .noActiveSession: return "No active dictation session"
        }
    }
}
