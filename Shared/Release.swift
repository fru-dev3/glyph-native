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
    public let repo: String        // GitHub "owner/name"
    public let asset: String       // the disk image's file name on the release
    public let macBundle: String
    public var downloadURL: URL { URL(string: "https://github.com/\(repo)/releases/latest/download/\(asset)")! }
    public var latestURL: URL { URL(string: "https://github.com/\(repo)/releases/latest")! }
    /// The same app as a FamilyApp, so the one AppCard draws both modes.
    public var family: FamilyApp {
        FamilyApp(id: id, name: name, job: job, scheme: "", iosBundle: nil, macBundle: macBundle, folder: nil, ownInstall: false)
    }
}

public enum Release {
    public static let apps: [ReleasedApp] = [
        ReleasedApp(id: "studio", name: "Glyph Studio", job: "One harness for all your agents",
                    repo: "fru-dev3/glyph-studio", asset: "Glyph-Studio-mac-arm64.dmg", macBundle: "sh.prevail.desktop"),
        ReleasedApp(id: "jot", name: "Glyph Jot", job: "Personal context",
                    repo: "fru-dev3/glyph-jot", asset: "Glyph-Jot.dmg", macBundle: "dev.fru.jot.mac"),
        ReleasedApp(id: "arena", name: "Glyph Arena", job: "The best recipe for each task",
                    repo: "fru-dev3/glyph-arena", asset: "Glyph-Arena-mac-arm64.dmg", macBundle: "dev.fru.glyph.arena"),
        ReleasedApp(id: "cast", name: "Glyph Cast", job: "Screen videos, cleaned up",
                    repo: "fru-dev3/glyph-cast", asset: "Glyph-Cast.dmg", macBundle: "dev.fru.capture"),
        ReleasedApp(id: "time", name: "Glyph Time", job: "Where your hours go",
                    repo: "fru-dev3/glyph-time", asset: "Glyph-Time.dmg", macBundle: "dev.fru.time"),
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
