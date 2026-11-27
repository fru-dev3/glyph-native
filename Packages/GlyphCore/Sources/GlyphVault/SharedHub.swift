import Foundation

/// The one vault address every Glyph app on a phone shares, kept in the App Group `group.dev.fru.glyph`.
/// Pair once in Glyph Native and they all reach it; disconnect there and they all stop.
/// An app reads it with `GlyphHub.address(fallbackKey:)`, passing the key its own Settings used before
/// ("vaultURL", "inboxURL", "inbox"), so nothing breaks before that app is rebuilt to ask for it.
public enum GlyphHub {
    public static let group = "group.dev.fru.glyph"
    static let key = "sharedHubURL"

    static func suite(_ name: String) -> UserDefaults { UserDefaults(suiteName: name) ?? .standard }

    static let offKey = "sharedHubOff"

    /// The one answer every app uses. A shared address wins; after a Disconnect in Glyph Native there is
    /// none (nil, never the app's old or built-in address); if Glyph Native never paired on this phone,
    /// `fallback` is what the app used before, so nothing breaks until then.
    public static func resolve(suiteName: String = group, fallback: () -> String?) -> String? {
        let s = suite(suiteName)
        let shared = s.string(forKey: key)?.trimmingCharacters(in: .whitespaces) ?? ""
        if !shared.isEmpty { return shared }
        if s.bool(forKey: offKey) { return nil }
        let t = fallback()?.trimmingCharacters(in: .whitespaces) ?? ""
        return t.isEmpty ? nil : t
    }

    /// True when a shared address is in force (an app shows its own address field read-only then).
    public static func isShared(suiteName: String = group) -> Bool {
        !(suite(suiteName).string(forKey: key)?.trimmingCharacters(in: .whitespaces) ?? "").isEmpty
    }

    /// The shared address, else the app's own old setting (until a Disconnect), else nil.
    public static func address(fallbackKey: String, suiteName: String = group, fallback: UserDefaults = .standard) -> String? {
        resolve(suiteName: suiteName) { fallback.string(forKey: fallbackKey) }
    }

    /// Pairing succeeded: every app on this phone now reaches `address`.
    public static func setAddress(_ address: String, suiteName: String = group) {
        suite(suiteName).removeObject(forKey: offKey)
        suite(suiteName).set(address.trimmingCharacters(in: .whitespaces), forKey: key)
    }

    /// Disconnect: every app has no address until Glyph Native pairs again.
    public static func clearAddress(suiteName: String = group) {
        suite(suiteName).removeObject(forKey: key)
        suite(suiteName).set(true, forKey: offKey)
    }
}

// MARK: Pairing with a Mac (Glyph Native's phone link)

extension GlyphHub {
    /// The port Glyph Native's Mac app answers phones on, and its Bonjour type.
    public static let pairPort = 7075
    public static let bonjourType = "_glyph._tcp"

    /// `http://glyph:<token>@host:port`: the shared address with the pairing token inside it. Every app on the
    /// phone reads this one address, and Foundation answers the Mac's 401 challenge from it, so an app that was
    /// never rebuilt for tokens still sends one (Hub sends it up front as a Bearer header).
    public static func address(_ address: String, token: String?) -> String {
        guard let token, !token.isEmpty, var c = URLComponents(string: address.trimmingCharacters(in: .whitespaces)) else { return address }
        c.user = "glyph"; c.password = token
        return c.string ?? address
    }

    /// The address without its token, for showing on screen.
    public static func display(_ address: String) -> String {
        guard var c = URLComponents(string: address), c.password != nil || c.user != nil else { return address }
        c.user = nil; c.password = nil
        return c.string ?? address
    }

    /// The token inside a shared address, if any.
    public static func token(in address: String?) -> String? {
        address.flatMap { URLComponents(string: $0)?.password }.flatMap { $0.isEmpty ? nil : $0 }
    }

    /// `https://glyph.fru.dev/pair#app=..&url=..&name=..&code=..&bonjour=..`, every value percent-encoded and in the
    /// fragment, so nothing reaches the site's server. With no address it is the install page alone (`#app=..`).
    public static func pairLink(app: String?, address: String?, name: String, code: String?, bonjour: String? = nil) -> String {
        var allowed = CharacterSet.alphanumerics; allowed.insert(charactersIn: "-._~")
        func enc(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s }
        var parts: [String] = []
        if let app, !app.isEmpty { parts.append("app=\(enc(app))") }
        if let a = address?.trimmingCharacters(in: .whitespaces), !a.isEmpty {
            parts.append("url=\(enc(a))"); parts.append("name=\(enc(name))")
            if let code { parts.append("code=\(enc(code))") }
            if let bonjour, !bonjour.isEmpty { parts.append("bonjour=\(enc(bonjour))") }
        }
        return "https://glyph.fru.dev/pair" + (parts.isEmpty ? "" : "#" + parts.joined(separator: "&"))
    }

    public enum PairOutcome: Equatable, Sendable {
        case paired(token: String, name: String)
        case wrongCode, expired, tooMany
        case noPairing          // the computer answered 404: an older hub with no tokens (pair as before)
        case unreachable
    }

    /// Trades the Mac's one-time code for this phone's long token: `POST <address>/pair {code, device}`.
    public static func exchange(address: String, code: String, device: String, timeout: TimeInterval = 6,
                                session: URLSession = .shared) async -> PairOutcome {
        guard let url = URL(string: display(address))?.appending(path: "pair") else { return .unreachable }
        var r = URLRequest(url: url, timeoutInterval: timeout)
        r.httpMethod = "POST"; r.cachePolicy = .reloadIgnoringLocalCacheData
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        r.httpBody = try? JSONSerialization.data(withJSONObject: ["code": code, "device": device])
        guard let (d, resp) = try? await session.data(for: r), let h = resp as? HTTPURLResponse else { return .unreachable }
        switch h.statusCode {
        case 200:
            guard let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any], let t = j["token"] as? String, !t.isEmpty else { return .unreachable }
            return .paired(token: t, name: j["name"] as? String ?? "")
        case 404, 405, 501: return .noPairing
        case 410: return .expired
        case 429: return .tooMany
        default: return .wrongCode
        }
    }

    /// True when the address is on the tailnet (100.64.0.0/10 or a *.ts.net name), so it works away from home.
    public static func isTailnet(_ address: String) -> Bool {
        guard let host = URLComponents(string: display(address))?.host?.lowercased() else { return false }
        if host.hasSuffix(".ts.net") { return true }
        let p = host.split(separator: ".").compactMap { Int($0) }
        return p.count == 4 && p[0] == 100 && (64...127).contains(p[1])
    }
}

/// Where each Glyph iPhone app installs from: its public TestFlight link. One table for every Mac app's
/// "Get the iPhone app" sheet; glyph.fru.dev/pair keeps the same list (docs/pair/index.html in the site repo).
/// A `TODO-` link is a placeholder until the App Store Connect record has its public link.
public enum GlyphPhoneApps {
    public struct App: Sendable, Equatable { public let id: String, name: String, testFlight: String }
    public static let all: [App] = [
        App(id: "native", name: "Glyph Native", testFlight: "https://testflight.apple.com/join/TODO-native"),
        App(id: "jot", name: "Glyph Jot", testFlight: "https://testflight.apple.com/join/TODO-jot"),
        App(id: "time", name: "Glyph Time", testFlight: "https://testflight.apple.com/join/TODO-time"),
        App(id: "well", name: "Glyph Well", testFlight: "https://testflight.apple.com/join/TODO-well"),
        App(id: "crm", name: "Glyph CRM", testFlight: "https://testflight.apple.com/join/TODO-crm"),
        App(id: "omega", name: "Glyph Omega", testFlight: "https://testflight.apple.com/join/TODO-omega"),
        App(id: "bot", name: "Glyph Bot", testFlight: "https://testflight.apple.com/join/TODO-bot"),
        App(id: "connect", name: "Glyph Connect", testFlight: "https://testflight.apple.com/join/TODO-connect"),
        App(id: "wealth", name: "Glyph Wealth", testFlight: "https://testflight.apple.com/join/TODO-wealth"),
        App(id: "life", name: "Glyph Life", testFlight: "https://testflight.apple.com/join/TODO-life"),
        App(id: "travel", name: "Glyph X", testFlight: "https://testflight.apple.com/join/TODO-travel"),
    ]
    /// By id ("jot") or by the name an app calls itself ("Glyph Jot"; "Glyph Travel" is Glyph X).
    public static func find(_ key: String) -> App? {
        let k = key.lowercased()
        return all.first { $0.id == k || $0.name.lowercased() == k } ?? (k == "glyph travel" ? all.first { $0.id == "travel" } : nil)
    }
}
