import Foundation

/// R23 — first match in field order: URL field, location, notes.
enum JoinURLDetector {
    /// Compiled once; extend by appending a pattern.
    private static let patterns: [NSRegularExpression] = [
        "teams\\.microsoft\\.com/l/meetup-join",
        "teams\\.live\\.com",
        "zoom\\.us/j/",
        "meet\\.google\\.com/",
        "webex\\.com/(meet|join)",
    ].map { try! NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }

    private static let linkDetector = try! NSDataDetector(
        types: NSTextCheckingResult.CheckingType.link.rawValue
    )

    static func joinURL(urlField: URL?, location: String?, notes: String?) -> URL? {
        var candidates: [URL] = []
        if let urlField { candidates.append(urlField) }
        for text in [location, notes] {
            guard let text, !text.isEmpty else { continue }
            let range = NSRange(text.startIndex..., in: text)
            for match in linkDetector.matches(in: text, options: [], range: range) {
                if let url = match.url { candidates.append(url) }
            }
        }
        return candidates.first(where: isJoinURL)
    }

    private static func isJoinURL(_ url: URL) -> Bool {
        let s = url.absoluteString
        let range = NSRange(s.startIndex..., in: s)
        return patterns.contains { $0.firstMatch(in: s, options: [], range: range) != nil }
    }
}
