import Foundation

/// The vault page's rules with no UI: testable, and shared by nothing else.
public enum VaultKit {
    public struct Device: Equatable, Sendable {
        public let name: String, kind: String, version: String, seen: Date
    }
    public struct Refusal: Error, Equatable, LocalizedError, Sendable {
        public let message: String
        public var errorDescription: String? { message }
    }

    /// "Studio Mac (2)" becomes "studio-mac-2": lowercase, runs of anything else turned into one dash.
    public static func slug(_ name: String) -> String {
        var out = "", dash = false
        for ch in name.lowercased() {
            if ch.isASCII && (ch.isLetter || ch.isNumber) { if dash && !out.isEmpty { out += "-" }; out.append(ch); dash = false } else { dash = true }
        }
        return out.isEmpty ? "mac" : out
    }

    static func stamp(_ d: Date) -> String { ISO8601DateFormatter().string(from: d) }

    /// time, name, kind, version, tab separated.
    public static func line(now: Date, name: String, kind: String = "Mac", version: String) -> String {
        [stamp(now), name, kind, "Glyph Native \(version)"].joined(separator: "\t")
    }

    /// The phone tells the vault computer it exists: at most once in `every` seconds.
    public static func announceDue(last: Date?, now: Date, every: TimeInterval = 300) -> Bool {
        guard let last else { return true }
        return now.timeIntervalSince(last) >= every || now < last
    }

    /// PUT <base>/native/devices/<slug>.txt with this device's one line. The slug fits the hub's rule
    /// (^[a-z0-9][a-z0-9-]{0,63}$) and the name holds no tab or newline, so the line stays one line.
    public static func announceRequest(base: URL, name: String, kind: String, version: String, now: Date) -> URLRequest {
        var slug = String(slug(name).prefix(64))
        while slug.hasSuffix("-") { slug.removeLast() }
        let clean = String(name.map { $0.isNewline || $0 == "\t" ? " " : $0 }.prefix(200))
        var req = URLRequest(url: base.appending(path: "native/devices/\(slug).txt"), timeoutInterval: 8)
        req.httpMethod = "PUT"
        req.httpBody = Data(line(now: now, name: clean, kind: kind, version: version).utf8)
        return req
    }

    /// Nil for anything that is not exactly four fields with a real time and a name.
    public static func parse(_ text: String) -> Device? {
        let first = text.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) ?? ""
        let f = first.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        guard f.count == 4, !f[1].isEmpty, !f[2].isEmpty, let t = ISO8601DateFormatter().date(from: f[0]) else { return nil }
        return Device(name: f[1], kind: f[2], version: f[3], seen: t)
    }

    /// "just now", "2 minutes ago", "3 hours ago", "4 days ago".
    public static func ago(_ d: Date, now: Date) -> String {
        let s = max(0, Int(now.timeIntervalSince(d)))
        func n(_ v: Int, _ u: String) -> String { "\(v) \(u)\(v == 1 ? "" : "s") ago" }
        if s < 60 { return "just now" }
        if s < 3600 { return n(s / 60, "minute") }
        if s < 86400 { return n(s / 3600, "hour") }
        return n(s / 86400, "day")
    }

    public static func devicesFolder(_ vault: String) -> URL { URL(filePath: vault).appending(path: "data/apps/native/devices") }

    /// One row per file: a parsed device, or the file's name when its line does not parse.
    public enum Entry: Equatable, Sendable { case device(Device, file: String), unreadable(file: String) }

    public static func entries(vault: String) -> [Entry] {
        let dir = devicesFolder(vault)
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).filter { !$0.hasPrefix(".") }.sorted()
        let all: [Entry] = names.map { n in
            let text = (try? String(contentsOf: dir.appending(path: n), encoding: .utf8)) ?? ""
            return VaultKit.parse(text).map { .device($0, file: n) } ?? .unreadable(file: n)
        }
        func seen(_ e: Entry) -> Date { if case .device(let d, _) = e { d.seen } else { .distantPast } }
        return all.sorted { seen($0) > seen($1) }
    }

    /// Writes this Mac's line (creating the folders); the vault must already have passed `check`.
    public static func record(vault: String, name: String, version: String, now: Date = .now) throws {
        let dir = devicesFolder(vault)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try (line(now: now, name: name, version: version) + "\n")
            .write(to: dir.appending(path: slug(name) + ".txt"), atomically: true, encoding: .utf8)
    }

    /// Proves the folder before it becomes the vault: not in the Trash, a folder, writable, and a
    /// test file reads back the same. Returns the sentence to show on success.
    public static func check(_ path: String, now: Date = .now) throws -> String {
        let url = URL(filePath: (path as NSString).expandingTildeInPath).standardizedFileURL
        if url.pathComponents.contains(".Trash") { throw Refusal(message: "That folder is in the Trash, so it would be emptied. Choose another.") }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            throw Refusal(message: "That is not a folder.")
        }
        guard FileManager.default.isWritableFile(atPath: url.path) else { throw Refusal(message: "This folder cannot be written to.") }
        let probe = url.appending(path: ".glyph-vault-test-\(UUID().uuidString)")
        let body = "glyph vault test \(UUID().uuidString)"
        do { try body.write(to: probe, atomically: true, encoding: .utf8) } catch { throw Refusal(message: "This folder cannot be written to.") }
        defer { try? FileManager.default.removeItem(at: probe) }
        guard (try? String(contentsOf: probe, encoding: .utf8)) == body else {
            throw Refusal(message: "A test file read back different from what was written, so this folder is not safe to use.")
        }
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        return "Wrote and read a test file here at \(f.string(from: now))."
    }
}
