import Foundation

/// Post-transcription corrections from `~/.dicta-replacements.txt`.
///
/// One rule per line: `wrong -> right`. Lines starting with `#` are comments.
/// Matching is case-insensitive on word boundaries; the replacement is used
/// verbatim, so it also serves to force capitalisation (e.g. `mareva
/// injunction -> Mareva injunction`).
enum Replacements {
    static var fileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".dicta-replacements.txt")
    }

    static func apply(to text: String) -> String {
        guard let contents = try? String(contentsOf: fileURL, encoding: .utf8) else { return text }
        var result = text
        for line in contents.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            let parts = trimmed.components(separatedBy: "->")
            guard parts.count == 2 else { continue }
            let wrong = parts[0].trimmingCharacters(in: .whitespaces)
            let right = parts[1].trimmingCharacters(in: .whitespaces)
            guard !wrong.isEmpty else { continue }

            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: wrong))\\b"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            else { continue }
            result = regex.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: NSRegularExpression.escapedTemplate(for: right)
            )
        }
        return result
    }

    /// Create a starter file on first run so the user can discover the feature.
    static func ensureStarterFile() {
        guard !FileManager.default.fileExists(atPath: fileURL.path) else { return }
        let starter = """
        # Dicta replacements — one per line, applied after transcription.
        # Format:  what the model hears -> what you meant
        # Matching is case-insensitive on whole words.
        #
        # estopple -> estoppel
        # mareva injunction -> Mareva injunction
        """
        try? starter.write(to: fileURL, atomically: true, encoding: .utf8)
    }
}
