import SwiftUI
import GlyphVault

/// The tags that exist, read from the vault's register and never from a list in an app.
///
/// Fru, 2026-11-15: "make sure that we're using consistent hashtags from the CRM ... the CRM is
/// the source of truth. And there's consistency if I'm seeing tags across all the apps." Before
/// this, Glyph Jot carried 23 tags in Swift, Glyph Well listed whatever was in its own log and
/// Glyph Wealth had fifteen categories of its own, so the same `#` meant three different sets.
///
/// A tag is an entity like a person or an org (`data/tags/<slug>/entity.md`), so the
/// hub serves it beside them at `/crm/names`, with the line it covers and the one colour it is
/// drawn in. What comes back is kept on this device, so a picker still opens on a phone with no
/// signal: the tags are the ones from the last time the vault was reached, which is the honest
/// answer and never an empty screen.
@MainActor public final class GlyphTags: ObservableObject {
    public static let shared = GlyphTags()

    /// Every tag in the register, archived ones too, in the order the vault gives them (by slug).
    @Published public private(set) var everything: [GlyphTag] = []
    /// The tags in use: the register less the archived ones, ready for a picker. Every list in the
    /// family reads this (or `forApp`), so a retired tag leaves all of them at once.
    public var all: [GlyphTag] { everything.filter { !$0.archived } }
    /// When the register was last reached. nil until it has been, on this device.
    @Published public private(set) var read: Date?

    nonisolated private static let store = "glyph.tags"
    nonisolated private static let readAt = "glyph.tags.read"

    /// The same tags, readable from any thread and without SwiftUI: the Mac app folds a tag
    /// while it files, off the main actor, and a picker on the phone draws one on it. One list,
    /// two ways in. Written only here, behind the lock.
    private nonisolated(unsafe) static var known: [GlyphTag] = []
    nonisolated private static let lock = NSLock()

    /// Every tag, archived ones too: what a name is looked up in, so an entry filed under a tag
    /// that was later retired still reads in that tag's spelling and colour.
    nonisolated public static var everything: [GlyphTag] {
        lock.lock(); defer { lock.unlock() }
        if known.isEmpty, let d = UserDefaults.standard.data(forKey: store),
           let kept = try? JSONDecoder().decode([GlyphTag].self, from: d) {
            known = kept
        }
        return known
    }

    /// The tags in use, without the archived ones (Fru, 2026-11-22: "retire or archive tags so
    /// they don't show on the lists").
    nonisolated public static var all: [GlyphTag] { everything.filter { !$0.archived } }

    /// Goes up each time the register changes, for an app that caches a list built from it.
    nonisolated public static var generation: Int { lock.lock(); defer { lock.unlock() }; return changes }
    private nonisolated(unsafe) static var changes = 0

    nonisolated private static func keep(_ tags: [GlyphTag]) {
        lock.lock(); known = tags; changes += 1; lock.unlock()
    }

    /// The tag a name already is, archived or not: by its name or one of its aliases, in any case
    /// or spacing. What "New tag" asks before it makes a second one.
    nonisolated public static func match(_ name: String) -> GlyphTag? {
        let key = GlyphTag.slug(name)
        guard !key.isEmpty else { return nil }
        let tags = everything
        return tags.first { $0.id == key } ?? tags.first { $0.aliases.contains { GlyphTag.slug($0) == key } }
    }

    /// Whether a name is a retired tag. A name the register has never seen is not.
    nonisolated public static func isArchived(_ name: String) -> Bool { match(name)?.archived ?? false }

    /// This app's archived tags, for the Tags page's Archived fold.
    nonisolated public static func archived(forApp app: String) -> [GlyphTag] {
        everything.filter { $0.archived && $0.belongs(to: app) }
    }

    /// The register's spelling of a name, from any thread. See the instance method.
    nonisolated public static func canonical(_ name: String) -> String {
        let key = GlyphTag.slug(name)
        let tags = everything
        if let hit = tags.first(where: { GlyphTag.slug($0.name) == key }) { return hit.name }
        if let hit = tags.first(where: { $0.aliases.contains { GlyphTag.slug($0) == key } }) { return hit.name }
        return name
    }

    /// What to write on screen for a tag: the register's spelling of it, in proper case
    /// (`GlyphTag.proper`). The one function every tag view in the family draws a name with, so
    /// a tag reads the same on a Tags list, on its own page, on a row and in a picker.
    nonisolated public static func display(_ name: String) -> String { GlyphTag.proper(canonical(name)) }

    /// The colour a tag is drawn in, from any thread. See the instance method.
    nonisolated public static func color(_ name: String) -> Color {
        let key = GlyphTag.slug(name)
        if let hex = everything.first(where: { GlyphTag.slug($0.name) == key })?.color { return hex }
        return GlyphTagHash.color(name)
    }

    /// The tags one app works in, from any thread: its own subset of the register, in the
    /// register's order. An app shows these and nothing else, so Glyph Well offers stool, food and
    /// workout rather than every tag in the vault.
    nonisolated public static func forApp(_ app: String) -> [GlyphTag] {
        all.filter { $0.belongs(to: app) }
    }

    /// What a tag covers, for a picker that explains itself. nil for one he has just made.
    nonisolated public static func covers(_ name: String) -> String? {
        let key = GlyphTag.slug(name)
        return everything.first { GlyphTag.slug($0.name) == key }?.covers
    }

    public init() {
        if let d = UserDefaults.standard.data(forKey: Self.store),
           let kept = try? JSONDecoder().decode([GlyphTag].self, from: d) {
            everything = kept
            Self.keep(kept)
        }
        read = UserDefaults.standard.object(forKey: Self.readAt) as? Date
    }

    /// Ask the hub. A failure leaves what is already here: a tag list that empties itself because
    /// the network is off is worse than a slightly old one.
    @discardableResult
    public func refresh(_ base: URL?) async -> Bool {
        guard let base else { return false }
        home = .hub(base)
        // With the archived ones, for the Archived fold and for "that name is taken". A hub from
        // before 2026-11-22 answers that with a 404, so the plain list is asked next.
        let names = base.appending(path: "crm/names")
        var rows: [Row]?
        for url in [names.appending(queryItems: [URLQueryItem(name: "archived", value: "1")]), names] where rows == nil {
            var req = URLRequest(url: url)
            req.timeoutInterval = 12
            if let (data, response) = try? await URLSession.shared.data(for: req),
               (response as? HTTPURLResponse)?.statusCode == 200 {
                rows = try? JSONDecoder().decode([Row].self, from: data)
            }
        }
        guard let rows else { return false }
        let tags = rows.filter { $0.kind == "tag" }.map {
            GlyphTag(name: $0.name, covers: $0.covers, hex: $0.color, aliases: $0.aliases ?? [], apps: $0.apps ?? [],
                     archived: $0.archived ?? false, count: $0.count)
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
    public func take(_ tags: [GlyphTag]) { everything = tags; Self.keep(tags); read = .now }

    /// The register's spelling of a name, following the aliases a page carries: "Comedy" is
    /// "Jokes", "Books" is "Learning". A name the register has never seen keeps its own spelling,
    /// because it is a tag he has just made and the hub will register it on the next save.
    public func canonical(_ name: String) -> String { Self.canonical(name) }

    /// The colour a tag is drawn in everywhere: its own, from its page, or the family's hash of
    /// its name for one he has just made.
    public func color(_ name: String) -> Color { Self.color(name) }

    /// This app's own tags. See the static twin.
    public func forApp(_ app: String) -> [GlyphTag] { all.filter { $0.belongs(to: app) } }

    /// This app's archived tags. See the static twin.
    public func archived(forApp app: String) -> [GlyphTag] { everything.filter { $0.archived && $0.belongs(to: app) } }

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

    /// The register as it is on this Mac's own disk: `data/tags/<slug>/entity.md` (`data/entities/tags`
    /// before 2026-11-22, now a link to it; a folder with no page is no tag).
    /// The Mac app has the vault mounted, so it needs no hub to know what a tag is called.
    @discardableResult
    public func readVault(_ vault: URL) -> Bool {
        home = .vault(vault)
        let root = vault.appending(path: TagFolders.root(vault, old: "data/entities/tags"))
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
            let apps = (try? JSONDecoder().decode([String].self, from: Data((front["apps"] ?? "[]").utf8))) ?? []
            tags.append(GlyphTag(name: name, covers: unquote(front["covers"]), hex: unquote(front["color"]), aliases: aliases, apps: apps,
                                 archived: unquote(front["archived"])?.lowercased() == "true"))
        }
        guard !tags.isEmpty else { return false }
        take(tags)
        if let d = try? JSONEncoder().encode(tags) {
            UserDefaults.standard.set(d, forKey: Self.store)
            UserDefaults.standard.set(read, forKey: Self.readAt)
        }
        return true
    }

    // MARK: Making, archiving and editing a tag (Fru, 2026-11-22: "Where do I add or manage tags.
    // Eg I need a new dev tag. Then I want to retire or archive tags so they don't show on the lists.")

    /// Where the register was last read from, which is where a change is written: the hub on a
    /// phone (`refresh`), the vault's own files on a Mac (`readVault`). An app does nothing more.
    enum Home: Equatable { case hub(URL), vault(URL) }
    private(set) var home: Home?

    /// What "New tag" came to.
    public enum Made: Equatable, Sendable {
        /// Made, by its slug.
        case made(String)
        /// That name is already this tag (or an alias of it), archived or not: offer it instead.
        case existing(GlyphTag)
        /// Not written, with the sentence to show.
        case failed(String)
    }

    /// The colours a new tag can take: the family's, distinct on a dark ground. Never gold.
    nonisolated public static let palette = ["#008000", "#3a7bc8", "#2a9d8f", "#983ac8", "#c83a8f", "#c83a46", "#c86a3a", "#7a7f87"]

    /// The family's apps a tag can be shown in, by id, with the name a person reads.
    nonisolated public static let familyApps: [(id: String, name: String)] = [
        ("well", "Well"), ("jot", "Jot"), ("crm", "CRM"), ("wealth", "Wealth"), ("life", "Life"), ("time", "Time"),
        ("omega", "Omega"), ("travel", "X"), ("estate", "Estate"), ("connect", "Connect"), ("bot", "Bot"), ("rig", "Rig"),
    ]

    /// The app this is, by its family id, read off the bundle (`dev.fru.well.ios` is "well"), so a
    /// tag made in an app shows in it without the app saying so. nil outside the family.
    nonisolated public static var appHere: String? {
        let parts = (Bundle.main.bundleIdentifier ?? "").split(separator: ".").map(String.init)
        guard parts.count >= 3, parts[0] == "dev", parts[1] == "fru" else { return nil }
        let id = parts[2] == "studio" ? "bot" : parts[2]
        return familyApps.contains { $0.id == id } ? id : nil
    }

    /// Makes a tag: its name as typed (shown in proper case), what it covers, its colour, and the
    /// apps that show it. A name that is already a tag or one of its aliases, archived or not,
    /// comes back as `.existing` and nothing is written, so there is never a second Dev.
    public func create(_ name: String, covers: String? = nil, color: String? = nil, apps: [String]) async -> Made {
        let name = name.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !GlyphTag.slug(name).isEmpty else { return .failed("Give it a name.") }
        if let hit = Self.match(name) { return .existing(hit) }
        var body: [String: Any] = ["name": name, "apps": apps]
        if let covers, !covers.trimmingCharacters(in: .whitespaces).isEmpty { body["covers"] = covers }
        if let color { body["color"] = color }
        switch home {
        case .hub(let base):
            let (code, answer) = await post(base, body)
            if code == 200 { await refresh(base); return .made(GlyphTag.slug(name)) }
            if code == 409, let slug = answer["existing"] as? String {
                await refresh(base)
                return Self.match(slug).map(Made.existing) ?? .failed("That name is already a tag.")
            }
            return .failed("Your vault could not be reached. Try again in a moment.")
        case .vault(let vault):
            let slug = GlyphTag.slug(name)
            let page = vault.appending(path: "\(TagFolders.root(vault, old: "data/entities/tags"))/\(slug)/entity.md")
            guard !FileManager.default.fileExists(atPath: page.path()) else {
                readVault(vault)
                return Self.match(slug).map(Made.existing) ?? .failed("That name is already a tag.")
            }
            let now = Self.now()
            var head = ["name: \(Self.json(name))", "kind: tag", "aliases: []"]
            if let c = body["covers"] as? String { head.append("covers: \(Self.json(Self.oneLine(c)))") }
            if let color { head.append("color: \(Self.json(color.lowercased()))") }
            head += ["apps: \(Self.json(apps))", "id: tags/\(slug)", "created: \(now)", "updated: \(now)"]
            let text = "---\n" + head.joined(separator: "\n") + "\n---\n\n## Your notes\n\n\n## Conversations\n"
            do {
                try FileManager.default.createDirectory(at: page.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data(text.utf8).write(to: page, options: .withoutOverwriting)
            } catch { return .failed("The tag could not be written to your vault.") }
            readVault(vault)
            return .made(slug)
        case nil:
            return .failed("Your vault has not been reached on this device yet.")
        }
    }

    /// Archives a tag (`archived: true` and `archived_at` on its own page), or restores it. The
    /// page is never deleted or moved, and what was filed under it keeps it.
    @discardableResult
    public func setArchived(_ slug: String, _ archived: Bool) async -> Bool {
        await change(slug, ["archived": archived ? "true" : nil, "archived_at": archived ? Self.now() : nil],
                     hub: ["slug": slug, "archived": archived])
    }

    /// Changes what a tag covers, its colour and the apps that show it. An empty meaning takes
    /// the line away.
    @discardableResult
    public func edit(_ slug: String, covers: String?, color: String?, apps: [String]) async -> Bool {
        let c = Self.oneLine(covers ?? "")
        return await change(slug, ["covers": c.isEmpty ? nil : Self.json(c),
                                   "color": color.map { Self.json($0.lowercased()) },
                                   "apps": Self.json(apps)],
                            hub: ["slug": slug, "covers": c, "color": color ?? "", "apps": apps])
    }

    private func change(_ slug: String, _ fields: [String: String?], hub body: [String: Any]) async -> Bool {
        switch home {
        case .hub(let base):
            guard await post(base, body).0 == 200 else { return false }
            await refresh(base)
            return true
        case .vault(let vault):
            let page = vault.appending(path: "\(TagFolders.root(vault, old: "data/entities/tags"))/\(slug)/entity.md")
            guard GlyphTag.slug(slug) == slug, let text = try? String(contentsOf: page, encoding: .utf8) else { return false }
            var all = fields; all["updated"] = Self.now()
            guard (try? Data(Self.setFront(text, all).utf8).write(to: page, options: .atomic)) != nil else { return false }
            readVault(vault)
            return true
        case nil:
            return false
        }
    }

    private func post(_ base: URL, _ body: [String: Any]) async -> (Int, [String: Any]) {
        var req = URLRequest(url: base.appending(path: "tags"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 12
        guard let (data, response) = try? await URLSession.shared.data(for: req) else { return (0, [:]) }
        return ((response as? HTTPURLResponse)?.statusCode ?? 0, (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:])
    }

    /// The page with these front matter keys set (nil removes one), the rest byte for byte: the
    /// hub's `tag_set_front`, for the Mac, which writes the vault itself.
    nonisolated static func setFront(_ text: String, _ fields: [String: String?]) -> String {
        guard text.hasPrefix("---\n"), let end = text.range(of: "\n---", range: text.index(text.startIndex, offsetBy: 3)..<text.endIndex) else { return text }
        var done = Set<String>(), out: [String] = []
        for line in text[text.index(text.startIndex, offsetBy: 4)..<end.lowerBound].split(separator: "\n", omittingEmptySubsequences: false) {
            let key = String(line.prefix { $0 != ":" }).trimmingCharacters(in: .whitespaces)
            if let value = fields[key] {
                done.insert(key)
                if let value { out.append("\(key): \(value)") }
                continue
            }
            out.append(String(line))
        }
        for (k, v) in fields.sorted(by: { $0.key < $1.key }) where !done.contains(k) { if let v { out.append("\(k): \(v)") } }
        return "---\n" + out.joined(separator: "\n") + text[end.lowerBound...]
    }

    nonisolated private static func json(_ value: Any) -> String {
        // A list as Python's json.dumps writes it (", " between), as the hub and seed-tags.py do.
        if let list = value as? [String] { return "[" + list.map { json($0) }.joined(separator: ", ") + "]" }
        return (try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed, .withoutEscapingSlashes]))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
    }
    nonisolated private static func oneLine(_ s: String) -> String { String(s.split(whereSeparator: \.isWhitespace).joined(separator: " ").prefix(200)) }
    nonisolated private static func now() -> String {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f.string(from: .now)
    }

    private struct Row: Decodable {
        let name: String
        let kind: String
        let aliases: [String]?
        let covers: String?
        let color: String?
        let apps: [String]?
        let archived: Bool?
        let count: Int?
    }
}

/// One tag as the register holds it.
public struct GlyphTag: Codable, Identifiable, Hashable, Sendable {
    // `apps` arrived after tags were already kept on devices, so a kept tag without it decodes
    // as empty rather than failing and emptying the picker.
    enum CodingKeys: String, CodingKey { case name, covers, hex, aliases, apps, archived, count }
    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        covers = try c.decodeIfPresent(String.self, forKey: .covers)
        hex = try c.decodeIfPresent(String.self, forKey: .hex)
        aliases = try c.decodeIfPresent([String].self, forKey: .aliases) ?? []
        apps = try c.decodeIfPresent([String].self, forKey: .apps) ?? []
        archived = try c.decodeIfPresent(Bool.self, forKey: .archived) ?? false
        count = try c.decodeIfPresent(Int.self, forKey: .count)
    }

    public let name: String
    /// The one line on what belongs under it, shown under the name in a picker.
    public let covers: String?
    /// "#rrggbb" from the page, so the tag is the same colour in every app.
    public let hex: String?
    /// Older spellings of the same tag. A note written with one still reads.
    public let aliases: [String]
    /// The apps this tag belongs to, by their family id ("well", "crm", "jot"). Empty means it
    /// belongs to the apps that hold everything, Glyph CRM and Glyph Jot, and to no other.
    ///
    /// Fru, 2026-11-15: "every app will have tags, like for well, which is health... and this is
    /// a subset of the tags in CRM. So you have things like tag for stool, tag for food, tag for
    /// a workout, tag for feeling." The subset is written on the tag's own page in the register,
    /// never in an app, so moving a tag between apps is editing one file in the vault.
    public let apps: [String]

    /// Retired (`archived: true` on its page): left out of every list, still found by its name, so
    /// what was filed under it keeps it. Never deleted or moved (Fru, 2026-11-22).
    public let archived: Bool

    /// How many app entries are filed under it, counted by the hub from the files (its tags, its kind, an
    /// alias). Nil when the register came from a page on disk or an older hub: not known, never a zero.
    public let count: Int?

    public init(name: String, covers: String? = nil, hex: String? = nil, aliases: [String] = [], apps: [String] = [],
                archived: Bool = false, count: Int? = nil) {
        self.name = name; self.covers = covers; self.hex = hex; self.aliases = aliases; self.apps = apps
        self.archived = archived; self.count = count
    }

    /// Glyph CRM and Glyph Jot hold every tag: one is the register itself and the other captures
    /// anything. Every other app shows the subset its own page names, and a tag that names no app
    /// belongs to those two alone.
    public func belongs(to app: String) -> Bool {
        // Glyph Native too (2026-11-23): its chat sends anything to any app, so its drawer lists every tag.
        if app == "crm" || app == "jot" || app == "native" { return true }
        return apps.contains(app)
    }

    public var id: String { Self.slug(name) }

    /// A tag's name as it is SHOWN, in proper case: the first letter a capital, the rest as it
    /// was written, a hyphenated slug read as words, and the acronyms kept whole.
    ///
    /// Fru, 2026-11-21, with "general" in lower case above "Feelings", "Food" and "Workout" on
    /// one list: "all tags are proper case. There should be consistency, because tags are one of
    /// the most important primitives that I have."
    ///
    /// Only what is drawn. The stored name, the slug and the hashtag someone types are left as
    /// they are, so nothing on disk moves and a tag is still found by the word it was filed
    /// under. Every shared tag view goes through `GlyphTags.display`, which is this over the
    /// register's own spelling.
    ///
    ///     general -> General      care-team -> Care team      crm -> CRM
    ///     Real Estate -> Real Estate (already proper: unchanged)
    public static func proper(_ name: String) -> String {
        // A slug reads as words; a name that already has spaces keeps its own punctuation.
        let spaced = name.contains(" ") ? name : name.replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " ")
        let words = spaced.split(separator: " ", omittingEmptySubsequences: true).map { word -> String in
            acronyms.contains(word.lowercased()) ? word.uppercased() : String(word)
        }
        let joined = words.joined(separator: " ")
        guard let first = joined.first else { return name }
        return first.uppercased() + joined.dropFirst()
    }

    /// Written in capitals wherever they stand in a tag's name. A short list on purpose: a word
    /// goes here when a tag with it exists, never in case one might.
    public static let acronyms: Set<String> = ["crm", "ai", "id"]

    /// "Real Estate" -> "real-estate", the vault's own spelling of the same tag.
    public static func slug(_ name: String) -> String {
        name.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).joined(separator: "-")
    }

    public var color: Color? {
        guard let hex, let v = UInt32(hex.dropFirst(), radix: 16), hex.hasPrefix("#"), hex.count == 7 else { return nil }
        return Color(red: Double(v >> 16 & 0xFF) / 255, green: Double(v >> 8 & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}
