import Foundation
#if os(macOS)
import Security
#endif

/// An app the public Glyph Native installs: downloaded as a signed disk image from a public GitHub
/// release, never built (a stranger has no source checkout).
public struct ReleasedApp: Identifiable, Hashable, Sendable {
    public let id: String          // also the icon's asset name ("icon-<id>")
    public let name: String
    public let job: String
    public let repo: String?       // GitHub "owner/name"; nil when there is no public download
    public let asset: String?      // the disk image's file name on the release
    public let macBundle: String?
    public let group: String       // "Layers", "Tools" or "Your life": the window's sections
    public let site: String?       // a web entry (no app to install): its address
    /// The app's page on the website; apps without a page of their own point at the home page.
    public var page: String {
        let own: Set = ["studio", "jot", "ibis", "rig", "arena", "cast", "time"]
        return "https://glyph.fru.dev" + (own.contains(id) ? "/" + id : "")
    }
    public var hasDownload: Bool { repo != nil && asset != nil }
    public var downloadURL: URL? { hasDownload ? URL(string: "https://github.com/\(repo!)/releases/latest/download/\(asset!)") : nil }
    public var latestURL: URL? { repo.flatMap { URL(string: "https://github.com/\($0)/releases/latest") } }
    public init(id: String, name: String, job: String, repo: String? = nil, asset: String? = nil, macBundle: String? = nil, group: String, site: String? = nil) {
        self.id = id; self.name = name; self.job = job; self.repo = repo; self.asset = asset; self.macBundle = macBundle; self.group = group; self.site = site
    }
    /// The same app as a FamilyApp, so the one AppCard draws both modes.
    public var family: FamilyApp {
        FamilyApp(id: id, name: name, job: job, scheme: "", iosBundle: nil, macBundle: macBundle, folder: nil, ownInstall: false)
    }
}

public enum Release {
    public static let apps: [ReleasedApp] = [
        ReleasedApp(id: "studio", name: "Glyph Bot", job: "One harness for all your agents",
                    repo: "fru-dev3/glyph-studio", asset: "Glyph-Studio-mac-arm64.dmg", macBundle: "sh.prevail.desktop", group: "Layers"),
        ReleasedApp(id: "jot", name: "Glyph Jot", job: "Personal context",
                    repo: "fru-dev3/glyph-jot", asset: "Glyph-Jot.dmg", macBundle: "dev.fru.jot.mac", group: "Layers"),
        ReleasedApp(id: "ibis", name: "Glyph Ibis", job: "What the world knows", group: "Layers", site: "https://glyph.fru.dev/ibis"),
        ReleasedApp(id: "rig", name: "Glyph Rig", job: "Where your agents run", group: "Layers", site: "https://glyph.fru.dev/rig"),
        ReleasedApp(id: "arena", name: "Glyph Arena", job: "The best recipe for each task",
                    repo: "fru-dev3/glyph-arena", asset: "Glyph-Arena-mac-arm64.dmg", macBundle: "dev.fru.glyph.arena", group: "Tools"),
        ReleasedApp(id: "cast", name: "Glyph Cast", job: "Screen videos, cleaned up",
                    repo: "fru-dev3/glyph-cast", asset: "Glyph-Cast.dmg", macBundle: "dev.fru.capture", group: "Tools"),
        ReleasedApp(id: "time", name: "Glyph Time", job: "Where your hours go",
                    repo: "fru-dev3/glyph-time", asset: "Glyph-Time.dmg", macBundle: "dev.fru.time", group: "Tools"),
        ReleasedApp(id: "connect", name: "Glyph Connect", job: "Where tools plug in", macBundle: "dev.fru.connect", group: "Tools"),
        ReleasedApp(id: "well", name: "Glyph Well", job: "Fitness, nutrition and mood", macBundle: "dev.fru.well", group: "Your life"),
        ReleasedApp(id: "crm", name: "Glyph CRM", job: "People, places, products, things", macBundle: "dev.fru.crm", group: "Your life"),
        ReleasedApp(id: "omega", name: "Glyph Omega", job: "Mission, vision, values and goals", macBundle: "dev.fru.omega", group: "Your life"),
        ReleasedApp(id: "wealth", name: "Glyph Wealth", job: "Accounts, spending and what it means", macBundle: "dev.fru.wealth", group: "Your life"),
        ReleasedApp(id: "life", name: "Glyph Life", job: "Personal administration", macBundle: "dev.fru.life", group: "Your life"),
        ReleasedApp(id: "travel", name: "Glyph X", job: "Trips, bookings and documents", macBundle: "dev.fru.travel", group: "Your life"),
    ]

    /// The faint motif drawn behind each card, by app id: what the app is about.
    public static let motifs: [String: String] = [
        "studio": "sparkles", "jot": "waveform", "ibis": "globe", "rig": "terminal", "arena": "trophy",
        "cast": "play.rectangle", "time": "clock", "connect": "point.3.connected.trianglepath.dotted",
        "well": "waveform.path.ecg", "crm": "person.2", "omega": "target", "wealth": "chart.line.uptrend.xyaxis",
        "life": "checklist", "travel": "map",
    ]

    /// "0.1.7" from the URL GitHub redirects /releases/latest to (".../releases/tag/v0.1.7").
    public static func tag(from url: URL) -> String? {
        let parts = url.pathComponents
        guard let i = parts.lastIndex(of: "tag"), i + 1 < parts.count else { return nil }
        let t = parts[i + 1]
        let v = t.hasPrefix("v") ? String(t.dropFirst()) : t
        return numbers(v) == nil ? nil : v
    }

    /// Dot-separated whole numbers ("v0.10.0" is [0, 10, 0]); anything else is nil.
    static func numbers(_ v: String) -> [Int]? {
        let s = v.hasPrefix("v") ? String(v.dropFirst()) : v
        let p = s.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        return p.isEmpty || p.contains(where: { $0 == nil }) ? nil : p.map { $0! }
    }

    /// True only when `a` is strictly newer than `b`: 0.10.0 is newer than 0.9.9, equal is not newer,
    /// and a version that does not parse is never newer.
    public static func isNewer(_ a: String, than b: String) -> Bool {
        guard var x = numbers(a), var y = numbers(b) else { return false }
        while x.count < y.count { x.append(0) }
        while y.count < x.count { y.append(0) }
        return x.lexicographicallyPrecedes(y) == false && x != y
    }

    /// The version an installed bundle reports: the short version, else the build number, else "" (unknown,
    /// shown as plain "Installed"; never a question mark).
    public static func installedVersion(_ plist: [String: Any]?) -> String {
        for k in ["CFBundleShortVersionString", "CFBundleVersion"] {
            if let v = (plist?[k] as? String)?.trimmingCharacters(in: .whitespaces), !v.isEmpty { return v }
        }
        return ""
    }

    /// "Installed · 0.1.1", or just "Installed" when the version is not known.
    public static func installedLabel(_ version: String) -> String { version.isEmpty ? "Installed" : "Installed · \(version)" }

    /// The line at a card's bottom left. A fresh `note` (Moved to the Trash, Quit X first) wins for a few seconds.
    public static func cardLine(installed: String?, latest: String?, needsUpdate: Bool, looked: Bool, note: String?) -> String {
        if let note { return note }
        switch (installed, latest) {
        case let (i?, h?) where needsUpdate: return "\(i) to \(h)"
        case let (i?, _): return installedLabel(i)
        case (nil, _?): return "Not installed"
        case (nil, nil): return looked ? "Can't reach GitHub" : "Checking GitHub"
        }
    }

#if os(macOS)
    /// This app's own developer team, read from its code signature: installs only accept apps signed
    /// by the same developer. Nil when ad hoc signed (a dev build), and then no --team is passed.
    public static func ownTeam() -> String? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
        var st: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &st) == errSecSuccess, let st else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(st, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let d = info as? [String: Any] else { return nil }
        return d[kSecCodeInfoTeamIdentifier as String] as? String
    }
#endif
}

/// One app as the window filters it: plain values, so the rules are testable without the UI.
public struct ShelfItem: Identifiable, Equatable, Sendable {
    public let id: String, name: String, job: String, group: String
    public let installed: Bool, update: Bool
    public let download: Bool      // has a public download
    public let web: Bool           // a website entry: never installed, never missing
    public init(id: String, name: String, job: String, group: String, installed: Bool, update: Bool, download: Bool = true, web: Bool = false) {
        self.id = id; self.name = name; self.job = job; self.group = group; self.installed = installed; self.update = update
        self.download = download; self.web = web
    }
}

public enum ShelfFilter: Equatable, Sendable { case all, installed, updates, missing, coming, group(String) }
public enum ShelfSort: String, CaseIterable, Sendable { case group = "Group", name = "Name", status = "Status" }

/// A heading and its apps; the heading is nil when the list is one section (sorted by name or status).
public struct ShelfSection: Equatable, Sendable { public let title: String?; public let items: [ShelfItem] }

public enum ShelfLogic {
    public static let groups = ["Layers", "Tools", "Your life"]

    public static func matches(_ i: ShelfItem, _ f: ShelfFilter) -> Bool {
        switch f {
        case .all: true
        case .installed: i.installed
        case .updates: i.update
        case .missing: !i.installed && i.download && !i.web
        case .coming: !i.installed && !i.download && !i.web
        case .group(let g): i.group == g
        }
    }

    public static func apply(_ items: [ShelfItem], filter: ShelfFilter, search: String, sort: ShelfSort) -> [ShelfSection] {
        let q = search.trimmingCharacters(in: .whitespaces)
        let hits = items.filter { i in
            matches(i, filter) && (q.isEmpty || i.name.localizedCaseInsensitiveContains(q) || i.job.localizedCaseInsensitiveContains(q))
        }
        if hits.isEmpty { return [] }
        switch sort {
        case .group:
            return groups.compactMap { g in
                let m = hits.filter { $0.group == g }
                return m.isEmpty ? nil : ShelfSection(title: g, items: m)
            }
        case .name:
            return [ShelfSection(title: nil, items: hits.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })]
        case .status:
            // Updates first, then not installed, then installed; the family's order within each.
            func rank(_ i: ShelfItem) -> Int { i.update ? 0 : (i.installed ? 2 : (i.download && !i.web ? 1 : 3)) }
            return [ShelfSection(title: nil, items: hits.enumerated().sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }.map(\.element))]
        }
    }

    /// How many cards fit across at the minimum comfortable width (250pt, 14pt gaps), at most 4.
    public static func fit(width: Double) -> Int { max(1, min(4, Int((width + 14) / 264))) }

    /// Columns for a group of `count` cards when `fit` fit across: the largest number up to `fit` that fills
    /// every row (4 apps: 4, else 2, else 1); when none above 1 does (5 or 7 apps), just `fit`.
    public static func columns(count: Int, fit: Int) -> Int {
        let f = max(1, min(4, fit))
        return stride(from: f, to: 1, by: -1).first { count % $0 == 0 } ?? f
    }

    /// The sentence shown when nothing is listed.
    public static func empty(filter: ShelfFilter, search: String) -> String {
        let q = search.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty { return "No apps match \"\(q)\"." }
        switch filter {
        case .updates: return "Nothing to update."
        case .missing: return "Everything is installed."
        case .installed: return "Nothing is installed yet."
        case .coming: return "Nothing is coming."
        default: return "No apps here."
        }
    }
}

/// Whether an app may be moved to the Trash: plain values, so the rule is testable without AppKit.
public enum Uninstall: Equatable, Sendable {
    case allowed, running, notInstalled, launcher
    public static func check(installed: Bool, running: Bool, bundle: String?, launcherBundle: String?) -> Uninstall {
        if let b = bundle, b == launcherBundle { return .launcher }
        if !installed { return .notInstalled }
        return running ? .running : .allowed
    }
}

public enum HeroState: Equatable, Sendable {
    case checking, offline
    case install(missing: Int, total: Int), updates(Int), current(Int)

    /// From row state only: `looked` is true once GitHub was asked, `anyLatest` once any app got an answer.
    public static func from(looked: Bool, anyLatest: Bool, total: Int, missing: Int, stale: Int) -> HeroState {
        if !looked { return .checking }
        if !anyLatest { return .offline }
        if missing > 0 { return .install(missing: missing, total: total) }
        if stale > 0 { return .updates(stale) }
        return .current(total)
    }

    /// Nothing to install or update: the hero then says what the family is.
    public var isCurrent: Bool { if case .current = self { return true }; return false }

    public var status: String {
        switch self {
        case .checking: "Checking GitHub"
        case .offline: "Can't reach GitHub"
        case .install(let m, _): "\(m) to install"
        case .updates(let n): "\(n) to update"
        case .current: "Up to date"
        }
    }
    public var headline: String {
        switch self {
        case .checking: "Looking for the latest versions."
        case .offline: "Showing what is on this Mac."
        case .install(let m, let t): m == t ? "One install. Every app." : "\(m) more to install."
        case .updates(let n): n == 1 ? "1 update ready." : "\(n) updates ready."
        // The calm state says what the family is, not that nothing happened: the fact moved to the small line above.
        case .current: "One life. One vault."
        }
    }
    /// The button's words; nil while still asking.
    public var action: String? {
        switch self {
        case .checking: nil
        case .offline: "Try again"
        case .install: "Install All"
        case .updates: "Update All"
        case .current: nil   // nothing to do; Settings has "Check now"
        }
    }
}
