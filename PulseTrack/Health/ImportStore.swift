import Foundation

enum ImportError: LocalizedError {
    case empty

    var errorDescription: String? {
        "No health samples found. Each line should look like: S|2026-11-15T23:10:00+01:00|2026-11-15T23:40:00+01:00|Core"
    }
}

/// Stores health samples sent from the PulseTrack Sync shortcut (kept for 45 days).
final class ImportStore {
    static let shared = ImportStore()
    static let didChange = Notification.Name("PulseTrackImportDidChange")

    struct Line: Hashable {
        let kind: String   // S, HR, RHR, HRV, RR, O2, W
        let start: Date
        let end: Date
        let value: String
    }

    private let lock = NSLock()
    private var cache: [Line]?

    private var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("health-import.txt")
    }

    var lastImport: Date? { UserDefaults.standard.object(forKey: "lastImport") as? Date }

    func lines() -> [Line] {
        lock.lock(); defer { lock.unlock() }
        if let cache { return cache }
        let text = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
        let parsed = Self.parse(text)
        cache = parsed
        return parsed
    }

    /// Merges new samples into the store. Returns a short summary for the shortcut.
    @discardableResult
    func ingest(_ text: String) throws -> String {
        let incoming = Self.parse(text)
        guard !incoming.isEmpty else { throw ImportError.empty }

        var all = Set(lines())
        let before = all.count
        all.formUnion(incoming)
        let added = all.count - before

        let cutoff = Date().addingTimeInterval(-45 * 86400)
        let kept = all.filter { $0.end >= cutoff }.sorted { $0.start < $1.start }
        let output = kept
            .map { "\($0.kind)|\(Self.iso.string(from: $0.start))|\(Self.iso.string(from: $0.end))|\($0.value)" }
            .joined(separator: "\n")
        try output.write(to: fileURL, atomically: true, encoding: .utf8)

        lock.lock(); cache = kept; lock.unlock()
        UserDefaults.standard.set(Date(), forKey: "lastImport")
        DispatchQueue.main.async { NotificationCenter.default.post(name: Self.didChange, object: nil) }

        let counts = Dictionary(grouping: incoming, by: \.kind).mapValues(\.count)
        let detail = counts.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", ")
        return "PulseTrack synced \(incoming.count) samples (\(added) new): \(detail)"
    }

    func clear() {
        try? FileManager.default.removeItem(at: fileURL)
        lock.lock(); cache = []; lock.unlock()
        UserDefaults.standard.removeObject(forKey: "lastImport")
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }

    // MARK: - Parsing

    static func parse(_ text: String) -> [Line] {
        text.split(whereSeparator: \.isNewline).compactMap { raw in
            let parts = raw.split(separator: "|", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count >= 4, let kind = normalizeKind(parts[0]), let start = date(parts[1]) else { return nil }
            let end = date(parts[2]) ?? start
            let value = parts[3...].joined(separator: " ")
            return Line(kind: kind, start: start, end: max(end, start), value: value)
        }
    }

    static func normalizeKind(_ s: String) -> String? {
        switch s.uppercased() {
        case "S", "SLEEP": "S"
        case "HR": "HR"
        case "RHR": "RHR"
        case "HRV": "HRV"
        case "RR", "RESP": "RR"
        case "O2", "SPO2": "O2"
        case "W", "WORKOUT": "W"
        default: nil
        }
    }

    static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let fallbackFormatters: [DateFormatter] = [
        "yyyy-MM-dd'T'HH:mm:ssZ", "yyyy-MM-dd HH:mm:ss Z", "yyyy-MM-dd'T'HH:mmZ",
        "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm"
    ].map { format in
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = format
        return f
    }

    private static let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)

    static func date(_ s: String) -> Date? {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }
        if let d = iso.date(from: t) ?? isoFractional.date(from: t) { return d }
        for f in fallbackFormatters { if let d = f.date(from: t) { return d } }
        return detector?.firstMatch(in: t, range: NSRange(t.startIndex..., in: t))?.date
    }

    /// First number in a string, accepting comma decimals ("62,5 bpm" → 62.5).
    static func number(_ s: String) -> Double? {
        let scanner = Scanner(string: s.replacingOccurrences(of: ",", with: "."))
        scanner.charactersToBeSkipped = CharacterSet(charactersIn: "0123456789.-").inverted
        return scanner.scanDouble()
    }
}
