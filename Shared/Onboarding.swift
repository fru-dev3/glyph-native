import Foundation

/// Vault onboarding's rules with no UI: tailscale peers, health replies, the pairing link, the
/// device role, the env file, and the guard that keeps pictures and tests off the owner's real files.
public enum Onboarding {
    public struct Peer: Equatable, Sendable { public let name: String, address: String
        public init(name: String, address: String) { self.name = name; self.address = address } }

    /// Online peers of `tailscale status --json`, by display name (the machine's name, not the
    /// long DNS name), first IPv4 address. Offline peers, self, and peers with no address are left out.
    public static func peers(statusJSON: Data) -> [Peer] {
        guard let root = try? JSONSerialization.jsonObject(with: statusJSON) as? [String: Any],
              let peers = root["Peer"] as? [String: [String: Any]] else { return [] }
        return peers.values.compactMap { p -> Peer? in
            guard p["Online"] as? Bool == true else { return nil }
            let ips = (p["TailscaleIPs"] as? [String]) ?? []
            guard let ip = ips.first(where: { !$0.contains(":") }) ?? ips.first else { return nil }
            let host = (p["HostName"] as? String) ?? ""
            let dns = ((p["DNSName"] as? String) ?? "").split(separator: ".").first.map(String.init) ?? ""
            let name = host.isEmpty ? dns : host
            return name.isEmpty ? nil : Peer(name: name, address: ip)
        }.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    /// Tailscale and Bonjour finds as one list: the same computer found both ways shows once (matched by
    /// slugged name or by address), keeping the first one's address, Tailscale's, since it works away from home.
    public static func merged(_ lists: [[Peer]]) -> [Peer] {
        var out: [Peer] = []
        for p in lists.joined() where !out.contains(where: { VaultKit.slug($0.name) == VaultKit.slug(p.name) || $0.address == p.address }) { out.append(p) }
        return out.sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    /// Where `tailscale` may live; the first that exists is run.
    public static let tailscalePaths = ["/usr/local/bin/tailscale", "/opt/homebrew/bin/tailscale",
                                        "/Applications/Tailscale.app/Contents/MacOS/Tailscale"]

    /// "on", "off" or nil (unknown) from the status JSON's BackendState.
    public static func tailscaleOn(statusJSON: Data) -> Bool? {
        guard let root = try? JSONSerialization.jsonObject(with: statusJSON) as? [String: Any],
              let s = root["BackendState"] as? String else { return nil }
        return s == "Running"
    }

    public struct HealthReply: Equatable, Sendable { public let vault: String?, domains: [String] }

    /// Nil unless the body is JSON with `"ok": true` (what jot-inbox.py's /health answers).
    public static func health(_ body: Data) -> HealthReply? {
        guard let j = try? JSONSerialization.jsonObject(with: body) as? [String: Any], j["ok"] as? Bool == true else { return nil }
        return HealthReply(vault: j["vault"] as? String, domains: (j["domains"] as? [String]) ?? [])
    }

    /// The port in a stored address ("http://host:7071" or "host:7071"), else the server's default.
    public static let defaultPort = 7071
    public static func port(of stored: String?) -> Int {
        guard let s = stored, let p = s.split(separator: ":").last.flatMap({ Int($0.filter(\.isNumber)) }), p > 0, p < 65536,
              s.contains(":"), !(s.hasPrefix("http") && s.filter({ $0 == ":" }).count == 1 && !s.dropFirst(5).contains(where: \.isNumber)) else { return defaultPort }
        return p
    }

    /// `http://<address>:<port>/health` for a bare address, or the stored URL's own host and port.
    public static func healthURL(address: String, port: Int) -> URL? { url(address: address, port: port, path: "/health") }

    /// The same address rules for any service path, like `/native/pair-codes`.
    public static func url(address: String, port: Int, path: String) -> URL? {
        let a = address.trimmingCharacters(in: .whitespaces)
        guard !a.isEmpty else { return nil }
        if a.hasPrefix("http://") || a.hasPrefix("https://") { return URL(string: a.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + path) }
        return URL(string: "http://\(a)\(a.contains(":") && !a.contains("]") && a.filter({ $0 == ":" }).count == 1 ? "" : ":\(port)")\(path)")
    }

    /// `https://glyph.fru.dev/pair#url=<address>&name=<computer>`, both percent-encoded, in the fragment so
    /// they never reach the site's server. Nil with no address.
    public static func pairingLink(address: String?, name: String, code: String? = nil) -> String? {
        guard let a = address?.trimmingCharacters(in: .whitespaces), !a.isEmpty else { return nil }
        var allowed = CharacterSet.alphanumerics; allowed.insert(charactersIn: "-._~")
        func enc(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s }
        return "https://glyph.fru.dev/pair#url=\(enc(a))&name=\(enc(name))" + (code.map { "&code=\(enc($0))" } ?? "")
    }

    /// The calm line under the QR: whole minutes left (never under 1 while live), then "This code expired."
    public static func codeLine(expires: Date, now: Date) -> String {
        let left = expires.timeIntervalSince(now)
        return left <= 0 ? "This code expired." : "Code good for \(max(1, Int(left / 60))) min"
    }

    /// True when the service says the code is gone: 410 only. A 404 (an older service) or any other
    /// answer means "no code to hold against it".
    public static func codeExpired(status: Int?) -> Bool { status == 410 }

    public struct Pairing: Equatable, Sendable { public let address: String, name: String, code: String?
        public init(address: String, name: String, code: String? = nil) { self.address = address; self.name = name; self.code = code } }

    /// The scanned or opened link, only if it is `https://glyph.fru.dev/pair#url=..&name=..` (the code the Mac
    /// shows) or `glyph-native://pair?url=..&name=..` (what the page hands over), with an http(s) address
    /// (a bare host:port gets http://). Anything else is nil: the code is not ours.
    public static func parsePairing(_ text: String) -> Pairing? {
        guard let c = URLComponents(string: text.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        let items: [URLQueryItem]?
        if c.scheme == "glyph-native", c.host == "pair" { items = c.queryItems }
        else if c.scheme == "https", c.host == "glyph.fru.dev", c.path == "/pair" {
            var f = URLComponents(); f.percentEncodedQuery = c.percentEncodedFragment; items = f.queryItems
        } else { return nil }
        guard var raw = items?.first(where: { $0.name == "url" })?.value?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }
        if !raw.hasPrefix("http://") && !raw.hasPrefix("https://") { raw = "http://" + raw }
        guard let u = URL(string: raw), u.host?.isEmpty == false else { return nil }
        let name = items?.first(where: { $0.name == "name" })?.value?.trimmingCharacters(in: .whitespaces) ?? ""
        let code = items?.first(where: { $0.name == "code" })?.value?.trimmingCharacters(in: .whitespaces)
        return Pairing(address: raw.trimmingCharacters(in: CharacterSet(charactersIn: "/")), name: name.isEmpty ? "your Mac" : name,
                       code: code?.isEmpty == false ? code : nil)
    }

    /// "this Mac" for this Mac; "keeps the vault" only for the computer whose address is the stored one
    /// (matched by name against the peer that owns that address); otherwise the device's kind.
    public static func role(device: String, kind: String, thisMac: String, storedAddress: String?, peers: [Peer]) -> String {
        if VaultKit.slug(device) == VaultKit.slug(thisMac) { return "this Mac" }
        if let a = storedAddress?.trimmingCharacters(in: .whitespaces), !a.isEmpty,
           peers.contains(where: { VaultKit.slug($0.name) == VaultKit.slug(device) && a.contains($0.address) }) { return "keeps the vault" }
        return kind
    }

    /// Sets `KEY=value`, replacing that key's line or appending it; every other line (comments too) is kept.
    public static func upsertEnv(_ text: String, key: String, value: String) -> String {
        var lines = text.components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }
        let new = "\(key)=\(value)"
        if let i = lines.firstIndex(where: { $0.hasPrefix(key + "=") }) { lines[i] = new } else { lines.append(new) }
        return lines.joined(separator: "\n") + "\n"
    }

    /// True when this run must not touch the owner's real files: a picture, or a test pointing
    /// the vault or env file elsewhere.
    public static func isolated(arguments: [String] = CommandLine.arguments, environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        arguments.contains("--picture") || environment["GLYPH_NATIVE_VAULT"] != nil || environment["GLYPH_NATIVE_ENV"] != nil
    }

    public struct Blocked: Error, LocalizedError { public var errorDescription: String? { "Not written: this run is isolated and the file is outside a temporary folder." } }

    /// Writes the key into the env file (creating it and its folder). When isolated, only a file
    /// inside a temporary folder is written.
    public static func writeEnv(file: URL, key: String, value: String, isolated: Bool = Onboarding.isolated()) throws {
        if isolated, !inTemp(file) { throw Blocked() }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let old = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        try upsertEnv(old, key: key, value: value).write(to: file, atomically: true, encoding: .utf8)
    }

    static func inTemp(_ url: URL) -> Bool {
        let p = url.standardizedFileURL.resolvingSymlinksInPath().path
        return ["/private/tmp/", "/private/var/folders/", "/tmp/", "/var/folders/"].contains { p.hasPrefix($0) }
            || p.hasPrefix(URL(filePath: NSTemporaryDirectory()).resolvingSymlinksInPath().path + "/")
    }
}
