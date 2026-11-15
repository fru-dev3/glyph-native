import SwiftUI

/// The tags that exist, read from the vault's register and never from a list in an app.
///
/// Fru, 2026-11-15: "make sure that we're using consistent hashtags from the CRM ... the CRM is
/// the source of truth. And there's consistency if I'm seeing tags across all the apps." Before
/// this, Glyph Jot carried 23 tags in Swift, Glyph Well listed whatever was in its own log and
/// Glyph Wealth had fifteen categories of its own, so the same `#` meant three different sets.
///
/// A tag is an entity like a person or an org (`data/entities/tags/<slug>/entity.md`), so the
/// hub serves it beside them at `/crm/names`, with the line it covers and the one colour it is
/// drawn in. What comes back is kept on this device, so a picker still opens on a phone with no
/// signal: the tags are the ones from the last time the vault was reached, which is the honest
/// answer and never an empty screen.
@MainActor public final class GlyphTags: ObservableObject {
    public static let shared = GlyphTags()

    /// Every tag in the register, in the order the vault gives them (by slug), ready for a picker.
    @Published public private(set) var all: [GlyphTag] = []
    /// When the register was last reached. nil until it has been, on this device.
    @Published public private(set) var read: Date?

    nonisolated private static let store = "glyph.tags"
    nonisolated private static let readAt = "glyph.tags.read"

    /// The same tags, readable from any thread and without SwiftUI: the Mac app folds a tag
    /// while it files, off the main actor, and a picker on the phone draws one on it. One list,
    /// two ways in. Written only here, behind the lock.
    private nonisolated(unsafe) static var known: [GlyphTag] = []
    nonisolated private static let lock = NSLock()

    nonisolated public static var all: [GlyphTag] {
        lock.lock(); defer { lock.unlock() }
        if known.isEmpty, let d = UserDefaults.standard.data(forKey: store),
           let kept = try? JSONDecoder().decode([GlyphTag].self, from: d) {
            known = kept
        }
        return known
    }

    nonisolated private static func keep(_ tags: [GlyphTag]) {
        lock.lock(); known = tags; lock.unlock()
    }

    /// The register's spelling of a name, from any thread. See the instance method.
    nonisolated public static func canonical(_ name: String) -> String {
        let key = GlyphTag.slug(name)
        let tags = all
        if let hit = tags.first(where: { GlyphTag.slug($0.name) == key }) { return hit.name }
        if let hit = tags.first(where: { $0.aliases.contains { GlyphTag.slug($0) == key } }) { return hit.name }
        return name
    }

    /// The colour a tag is drawn in, from any thread. See the instance method.
    nonisolated public static func color(_ name: String) -> Color {
        let key = GlyphTag.slug(name)
        if let hex = all.first(where: { GlyphTag.slug($0.name) == key })?.color { return hex }
        return GlyphTagHash.color(name)
    }

    /// What a tag covers, for a picker that explains itself. nil for one he has just made.
    nonisolated public static func covers(_ name: String) -> String? {
        let key = GlyphTag.slug(name)
        return all.first { GlyphTag.slug($0.name) == key }?.covers
    }

    public init() {
        if let d = UserDefaults.standard.data(forKey: Self.store),
           let kept = try? JSONDecoder().decode([GlyphTag].self, from: d) {
            all = kept
            Self.keep(kept)
        }
        read = UserDefaults.standard.object(forKey: Self.readAt) as? Date
    }

    /// Ask the hub. A failure leaves what is already here: a tag list that empties itself because
    /// Tailscale is off is worse than a slightly old one.
    @discardableResult
    public func refresh(_ base: URL?) async -> Bool {
        guard let base else { return false }
        var req = URLRequest(url: base.appending(path: "crm/names"))
        req.timeoutInterval = 12
        guard let (data, response) = try? await URLSession.shared.data(for: req),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let rows = try? JSONDecoder().decode([Row].self, from: data) else { return false }
        let tags = rows.filter { $0.kind == "tag" }.map {
            GlyphTag(name: $0.name, covers: $0.covers, hex: $0.color, aliases: $0.aliases ?? [])
        }
        guard !tags.isEmpty else { return false }
        take(tags)
        if let d = try? JSONEncoder().encode(tags) {
            UserDefaults.standard.set(d, forKey: Self.store)
            UserDefaults.standard.set(read, forKey: Self.readAt)
        }
        return true
    }

    /// What a check hands in, in place of a vault: the same rows, without the hub.
    public func take(_ tags: [GlyphTag]) { all = tags; Self.keep(tags); read = .now }

    /// The register's spelling of a name, following the aliases a page carries: "Comedy" is
    /// "Jokes", "Books" is "Learning". A name the register has never seen keeps its own spelling,
    /// because it is a tag he has just made and the hub will register it on the next save.
    public func canonical(_ name: String) -> String { Self.canonical(name) }

    /// The colour a tag is drawn in everywhere: its own, from its page, or the family's hash of
    /// its name for one he has just made.
    public func color(_ name: String) -> Color { Self.color(name) }

    /// A tag made in an app joins the register, so the next app to look sees it. Glyph Jot's
    /// memos and Glyph Well's entries register their tags by being saved; an app that files by
    /// something else (Glyph Wealth files by category) says so here instead.
    @discardableResult
    public func make(_ name: String, at base: URL?) async -> Bool {
        let tag = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let base, !tag.isEmpty else { return false }
        var req = URLRequest(url: base.appending(path: "tags"))
        req.httpMethod = "PUT"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["tags": [tag]])
        req.timeoutInterval = 12
        guard let (_, response) = try? await URLSession.shared.data(for: req),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return false }
        return await refresh(base)
    }

    /// The register as it is on this Mac's own disk: `data/entities/tags/<slug>/entity.md`.
    /// The Mac app has the vault mounted, so it needs no hub to know what a tag is called.
    @discardableResult
    public func readVault(_ vault: URL) -> Bool {
        let root = vault.appending(path: "data/entities/tags")
        guard let slugs = try? FileManager.default.contentsOfDirectory(atPath: root.path()) else { return false }
        var tags: [GlyphTag] = []
        for slug in slugs.sorted() where !slug.hasPrefix(".") {
            guard let text = try? String(contentsOf: root.appending(path: slug + "/entity.md"), encoding: .utf8) else { continue }
            var front: [String: String] = [:]
            for line in text.split(separator: "\n", omittingEmptySubsequences: false).dropFirst() {
                if line.hasPrefix("---") { break }
                guard let colon = line.firstIndex(of: ":") else { continue }
                front[String(line[line.startIndex..<colon]).trimmingCharacters(in: .whitespaces)] =
                    String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            }
            let unquote: (String?) -> String? = { $0?.trimmingCharacters(in: CharacterSet(charactersIn: "\"")) }
            guard let name = unquote(front["name"]), !name.isEmpty else { continue }
            let aliases = (try? JSONDecoder().decode([String].self, from: Data((front["aliases"] ?? "[]").utf8))) ?? []
            tags.append(GlyphTag(name: name, covers: unquote(front["covers"]), hex: unquote(front["color"]), aliases: aliases))
        }
        guard !tags.isEmpty else { return false }
        take(tags)
        if let d = try? JSONEncoder().encode(tags) {
            UserDefaults.standard.set(d, forKey: Self.store)
            UserDefaults.standard.set(read, forKey: Self.readAt)
        }
        return true
    }

    private struct Row: Decodable {
        let name: String
        let kind: String
        let aliases: [String]?
        let covers: String?
        let color: String?
    }
}

/// One tag as the register holds it.
public struct GlyphTag: Codable, Identifiable, Hashable, Sendable {
    public let name: String
    /// The one line on what belongs under it, shown under the name in a picker.
    public let covers: String?
    /// "#rrggbb" from the page, so the tag is the same colour in every app.
    public let hex: String?
    /// Older spellings of the same tag. A note written with one still reads.
    public let aliases: [String]

    public init(name: String, covers: String? = nil, hex: String? = nil, aliases: [String] = []) {
        self.name = name; self.covers = covers; self.hex = hex; self.aliases = aliases
    }

    public var id: String { Self.slug(name) }

    /// "Real Estate" -> "real-estate", the vault's own spelling of the same tag.
    public static func slug(_ name: String) -> String {
        name.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).joined(separator: "-")
    }

    public var color: Color? {
        guard let hex, let v = UInt32(hex.dropFirst(), radix: 16), hex.hasPrefix("#"), hex.count == 7 else { return nil }
        return Color(red: Double(v >> 16 & 0xFF) / 255, green: Double(v >> 8 & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}
