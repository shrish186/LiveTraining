import Foundation

/// Writes rows in the session format (docs/session-format.md) to a CSV file, in batches,
/// so nothing accumulates in memory. Same row format as mobile/lib/recording/csv_row.dart.
///
/// Not thread-safe: WatchRecorder only touches it from its serial `io` queue.
final class SessionWriter {
    static let header = "t_ms,source,kind,x,y,z,value"

    let csvURL: URL
    private let handle: FileHandle
    private var buffer = ""
    private var bufferedRows = 0

    /// Row counts per "source/kind", e.g. "apple_watch/acc".
    private(set) var counts: [String: Int] = [:]

    init(csvURL: URL) throws {
        self.csvURL = csvURL
        FileManager.default.createFile(atPath: csvURL.path, contents: nil)
        handle = try FileHandle(forWritingTo: csvURL)
        buffer = SessionWriter.header + "\n"
    }

    func vector(_ tMs: Int, _ source: String, _ kind: String, _ x: Double, _ y: Double, _ z: Double) {
        append("\(tMs),\(source),\(kind),\(Self.format(x)),\(Self.format(y)),\(Self.format(z)),", key: "\(source)/\(kind)")
    }

    func scalar(_ tMs: Int, _ source: String, _ kind: String, _ value: Double) {
        append("\(tMs),\(source),\(kind),,,,\(Self.format(value))", key: "\(source)/\(kind)")
    }

    func event(_ tMs: Int, _ source: String, _ label: String) {
        append("\(tMs),\(source),event,,,,\(Self.sanitize(label))", key: "\(source)/event")
    }

    func flush() {
        guard !buffer.isEmpty, let data = buffer.data(using: .utf8) else { return }
        handle.write(data)
        buffer = ""
        bufferedRows = 0
    }

    func close() {
        flush()
        try? handle.close()
    }

    private func append(_ row: String, key: String) {
        buffer += row
        buffer += "\n"
        bufferedRows += 1
        counts[key, default: 0] += 1
        if bufferedRows >= 1000 { flush() }
    }

    /// Up to 5 decimals, trailing zeros trimmed, "." separator, no "-0".
    static func format(_ v: Double) -> String {
        guard v.isFinite else { return "" }
        var s = String(format: "%.5f", v)
        if s.contains(".") {
            while s.hasSuffix("0") { s.removeLast() }
            if s.hasSuffix(".") { s.removeLast() }
        }
        return s == "-0" ? "0" : s
    }

    /// Event labels may not contain commas, quotes or newlines.
    static func sanitize(_ label: String) -> String {
        let cleaned = label.components(separatedBy: CharacterSet(charactersIn: ",\"\r\n")).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? "mark" : cleaned
    }
}
