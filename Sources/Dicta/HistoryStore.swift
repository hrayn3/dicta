import Foundation

struct HistoryEntry: Codable, Identifiable, Equatable {
    let id: UUID
    let date: Date
    let text: String
}

/// Append-only JSONL history at
/// `~/Library/Application Support/Dicta/history.jsonl`, capped to the most
/// recent `maxEntries` on load.
final class HistoryStore {
    static let maxEntries = 50

    private let fileURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Dicta", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("history.jsonl")
    }()

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    func load() -> [HistoryEntry] {
        guard let data = try? String(contentsOf: fileURL, encoding: .utf8) else { return [] }
        let entries = data.split(separator: "\n").compactMap { line -> HistoryEntry? in
            guard let lineData = line.data(using: .utf8) else { return nil }
            return try? decoder.decode(HistoryEntry.self, from: lineData)
        }
        return Array(entries.suffix(Self.maxEntries).reversed())
    }

    @discardableResult
    func append(_ text: String) -> HistoryEntry {
        let entry = HistoryEntry(id: UUID(), date: Date(), text: text)
        if let data = try? encoder.encode(entry), let line = String(data: data, encoding: .utf8) {
            if let handle = try? FileHandle(forWritingTo: fileURL) {
                handle.seekToEndOfFile()
                handle.write((line + "\n").data(using: .utf8)!)
                try? handle.close()
            } else {
                try? (line + "\n").write(to: fileURL, atomically: true, encoding: .utf8)
            }
        }
        return entry
    }

    func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
