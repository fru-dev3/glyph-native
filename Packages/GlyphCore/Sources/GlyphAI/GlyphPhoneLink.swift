import Foundation
import CryptoKit
import GlyphVault
#if canImport(Security)
import Security
#endif
#if os(macOS)
import Network
#endif

// A Mac answering its owner's phones with no other program running: Glyph Native's Mac app starts
// `GlyphPhoneLink` when "Share with my iPhone" is on. It serves MacHub's routes on the vault's own files,
// on the home network and the tailnet, advertises itself on Bonjour, and answers only a phone that paired.
//
// Pairing: the Mac's QR carries an 8-character code (10 minutes, one use). The phone trades it once at
// `POST /pair {code, device}` for a long random token. The Mac keeps only the token's SHA-256, in the
// keychain list of paired phones; the phone keeps the token in the shared address (GlyphHub). Every other
// request needs `Authorization: Bearer <token>` (or Basic with the token as the password, which is what
// Foundation sends from a `glyph:<token>@` address); without it the answer is 401.

/// The codes and the paired phones. No UI, no sockets: the listener and the tests both drive it.
public final class GlyphPairBook: @unchecked Sendable {
    public struct Phone: Codable, Equatable, Sendable {
        public let id: String, name: String, hash: String, paired: Date
    }
    public enum Exchange: Equatable, Sendable { case token(String, Phone), wrong, expired, tooMany }

    public static let codeLife: TimeInterval = 600
    /// Failed code tries allowed in any minute; the rest of that minute answers 429.
    public static let triesPerMinute = 5
    static let alphabet = Array("ABCDEFGHJKMNPQRSTUVWXYZ23456789")   // no I, L, O, 0, 1: read off a screen

    private let lock = NSLock()
    private var codes: [String: Date] = [:]
    private var used: [String: Date] = [:]     // spent or expired codes, so a late try says "expired", not "wrong"
    private var failures: [Date] = []
    public private(set) var phones: [Phone]
    private let now: @Sendable () -> Date
    private let save: @Sendable ([Phone]) -> Void

    public init(phones: [Phone] = [], now: @escaping @Sendable () -> Date = { .now }, save: @escaping @Sendable ([Phone]) -> Void = { _ in }) {
        self.phones = phones; self.now = now; self.save = save
    }

    /// The book kept in this Mac's keychain (service dev.fru.glyph.phones).
    public static func keychain() -> GlyphPairBook {
        GlyphPairBook(phones: Keychain.load(), save: { Keychain.store($0) })
    }

    private func prune(_ t: Date) {
        for (c, e) in codes where e <= t { codes[c] = nil; used[c] = e }
        used = used.filter { t.timeIntervalSince($0.value) < 3600 }
        failures = failures.filter { t.timeIntervalSince($0) < 60 }
    }

    /// A new one-time code, good for `codeLife`.
    public func newCode() -> (code: String, expires: Date) {
        lock.lock(); defer { lock.unlock() }
        let t = now(); prune(t)
        var g = SystemRandomNumberGenerator()
        let code = String((0..<8).map { _ in Self.alphabet.randomElement(using: &g)! })
        let e = t.addingTimeInterval(Self.codeLife)
        codes[code] = e
        return (code, e)
    }

    /// The code for a token, once. A wrong code counts against the minute's tries.
    public func exchange(code raw: String, device: String) -> Exchange {
        lock.lock(); defer { lock.unlock() }
        let t = now(); prune(t)
        guard failures.count < Self.triesPerMinute else { return .tooMany }
        let code = raw.uppercased().filter { !$0.isWhitespace && $0 != "-" }
        guard codes[code] != nil else {
            if used[code] != nil { return .expired }
            failures.append(t); return .wrong
        }
        codes[code] = nil; used[code] = t
        var bytes = [UInt8](repeating: 0, count: 32)
        var g = SystemRandomNumberGenerator()
        for i in bytes.indices { bytes[i] = g.next() }
        let token = Data(bytes).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        let name = device.trimmingCharacters(in: .whitespacesAndNewlines)
        let phone = Phone(id: UUID().uuidString, name: name.isEmpty ? "iPhone" : String(name.prefix(80)), hash: Self.hash(token), paired: t)
        phones.append(phone)
        save(phones)
        return .token(token, phone)
    }

    /// The paired phone a token belongs to, or nil.
    public func phone(token: String?) -> Phone? {
        guard let token, !token.isEmpty else { return nil }
        let h = Self.hash(token)
        lock.lock(); defer { lock.unlock() }
        return phones.first { $0.hash == h }
    }

    /// Unpairs one phone: its token stops working at once.
    public func forget(_ id: String) {
        lock.lock(); defer { lock.unlock() }
        phones.removeAll { $0.id == id }; save(phones)
    }

    static func hash(_ token: String) -> String { SHA256.hash(data: Data(token.utf8)).map { String(format: "%02x", $0) }.joined() }

    /// The token in an Authorization header: `Bearer <t>`, or `Basic base64(<anything>:<t>)`.
    public static func token(authorization: String?) -> String? {
        guard let a = authorization?.trimmingCharacters(in: .whitespaces) else { return nil }
        let low = a.lowercased()
        if low.hasPrefix("bearer ") { return String(a.dropFirst(7)).trimmingCharacters(in: .whitespaces) }
        if low.hasPrefix("basic "), let d = Data(base64Encoded: String(a.dropFirst(6)).trimmingCharacters(in: .whitespaces)),
           let s = String(data: d, encoding: .utf8), let i = s.firstIndex(of: ":") { return String(s[s.index(after: i)...]) }
        return nil
    }

    enum Keychain {
        static let service = "dev.fru.glyph.phones", account = "paired"
        static func load() -> [Phone] {
            #if canImport(Security)
            let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: account, kSecReturnData as String: true]
            var out: CFTypeRef?
            guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return [] }
            return (try? JSONDecoder().decode([Phone].self, from: d)) ?? []
            #else
            return []
            #endif
        }
        static func store(_ phones: [Phone]) {
            #if canImport(Security)
            guard let d = try? JSONEncoder().encode(phones) else { return }
            let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
            if SecItemUpdate(q as CFDictionary, [kSecValueData as String: d] as CFDictionary) == errSecItemNotFound {
                var add = q; add[kSecValueData as String] = d
                add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
                SecItemAdd(add as CFDictionary, nil)
            }
            #endif
        }
    }
}

/// The phone link's answers, with no socket: method, path, headers and body in; status, headers and body out.
public struct GlyphPhoneRoutes: Sendable {
    public let book: GlyphPairBook
    public let vault: URL
    public let name: String
    /// What a loopback caller (another Glyph app on this Mac) gets back with a new code: the address a phone
    /// should use and whether away-from-home works.
    public var where_: @Sendable () -> (address: String?, tailnet: Bool) = { (nil, false) }

    public init(book: GlyphPairBook, vault: URL, name: String) { self.book = book; self.vault = vault; self.name = name }

    public struct Reply: Sendable { public var status: Int; public var headers: [String: String] = [:]; public var body = Data() }

    static func json(_ status: Int, _ obj: Any) -> Reply {
        Reply(status: status, headers: ["Content-Type": "application/json"], body: (try? JSONSerialization.data(withJSONObject: obj, options: [.withoutEscapingSlashes])) ?? Data())
    }

    public func handle(method: String, path: String, query: [String: String] = [:], headers: [String: String] = [:], body: Data = Data(), loopback: Bool = false) -> Reply {
        let h = Dictionary(headers.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { a, _ in a })
        switch (method, path) {
        case ("POST", "/pair"):
            let o = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
            switch book.exchange(code: o?["code"] as? String ?? "", device: o?["device"] as? String ?? "") {
            case .token(let t, _): return Self.json(200, ["token": t, "name": name])
            case .wrong: return Self.json(401, ["error": "That code is not right."])
            case .expired: return Self.json(410, ["error": "That code expired."])
            case .tooMany: return Self.json(429, ["error": "Too many tries. Wait a minute."])
            }
        case ("POST", "/pair-codes"):
            // Only another Glyph app on this Mac may ask for a code; a phone gets one by looking at the screen.
            guard loopback else { return Self.json(403, ["error": "Only this Mac can make a code."]) }
            let (c, e) = book.newCode(), w = where_()
            return Self.json(200, ["code": c, "expires": e.timeIntervalSince1970, "url": w.address ?? NSNull(), "name": name, "tailnet": w.tailnet])
        default: break
        }
        guard book.phone(token: GlyphPairBook.token(authorization: h["authorization"])) != nil else {
            var r = Self.json(401, ["error": "Pair this phone first."]); r.headers["WWW-Authenticate"] = "Basic realm=\"Glyph\""; return r
        }
        if method == "GET", path == "/health" {
            let mh = MacHub(vault: vault)
            let domains = ((try? FileManager.default.contentsOfDirectory(atPath: mh.domains.path)) ?? []).filter { !$0.hasPrefix(".") }.sorted()
            return Self.json(200, ["ok": true, "vault": vault.lastPathComponent, "name": name, "domains": domains])
        }
        guard let (s, d) = MacHub(vault: vault).handle(method, String(path.dropFirst()), query: query, body: body,
                                                       headers: Dictionary(headers.map { ($0.key, $0.value) }, uniquingKeysWith: { a, _ in a })) else {
            return Reply(status: 501)
        }
        return Reply(status: s, headers: d.isEmpty ? [:] : ["Content-Type": d.first == UInt8(ascii: "{") || d.first == UInt8(ascii: "[") ? "application/json" : "text/plain"], body: d)
    }
}

#if os(macOS)
/// The listener: every interface on `GlyphHub.pairPort`, answering only the home network, the tailnet and
/// this Mac; Bonjour `_glyph._tcp` under the Mac's name.
@MainActor
public final class GlyphPhoneLink {
    public static let shared = GlyphPhoneLink()
    public let book: GlyphPairBook
    public private(set) var problem: String?
    public private(set) var port = UInt16(GlyphHub.pairPort)
    public private(set) var name = ""
    public var running: Bool { listener != nil }
    private var listener: NWListener?
    private var routes: GlyphPhoneRoutes?

    public init(book: GlyphPairBook = .keychain()) { self.book = book }

    /// Starts (or keeps) the listener on `vault`. `GLYPH_PHONE_PORT` moves the port for a check.
    public func start(vault: URL, name: String, port: UInt16? = nil) {
        guard listener == nil else { return }
        self.name = name
        self.port = port ?? ProcessInfo.processInfo.environment["GLYPH_PHONE_PORT"].flatMap(UInt16.init) ?? UInt16(GlyphHub.pairPort)
        var r = GlyphPhoneRoutes(book: book, vault: vault, name: name)
        let p = self.port
        r.where_ = { let a = GlyphPhoneLink.addresses(); return (GlyphPhoneLink.best(a).map { "http://\($0):\(p)" }, a.tailnet != nil) }
        routes = r
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            let l = try NWListener(using: params, on: NWEndpoint.Port(rawValue: self.port)!)
            l.service = NWListener.Service(name: name, type: GlyphHub.bonjourType)
            l.newConnectionHandler = { [weak self] c in Task { @MainActor in self?.accept(c) } }
            l.stateUpdateHandler = { [weak self] s in
                Task { @MainActor in
                    guard let self else { return }
                    if case .failed(let e) = s { self.problem = "The phone link stopped: \(e.localizedDescription)"; self.stop() }
                    if case .ready = s { self.problem = nil; print("phone link ready \(self.port)"); fflush(stdout) }
                }
            }
            l.start(queue: .main)
            listener = l
        } catch { problem = "The phone link did not start: \(error.localizedDescription)" }
    }

    public func stop() { listener?.cancel(); listener = nil }

    /// A code for the QR, made here (Glyph Native) without a round trip.
    public func newCode() -> (code: String, expires: Date) { book.newCode() }

    // MARK: addresses

    /// This Mac's IPv4 addresses: on the tailnet (100.64.0.0/10) and on the home network (a private range).
    public nonisolated static func addresses() -> (tailnet: String?, lan: String?) {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return (nil, nil) }
        defer { freeifaddrs(list) }
        var ts: String?, lan: String?
        for p in sequence(first: first, next: { $0.pointee.ifa_next }) {
            guard let a = p.pointee.ifa_addr, a.pointee.sa_family == UInt8(AF_INET), (p.pointee.ifa_flags & UInt32(IFF_UP)) != 0 else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(a, socklen_t(a.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let ip = String(decoding: host.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            let ifname = String(cString: p.pointee.ifa_name)
            if isTailnet(ip) { ts = ts ?? ip }
            else if isPrivate(ip), !ip.hasPrefix("169.254."), ifname.hasPrefix("en") { lan = lan ?? ip }
        }
        return (ts, lan)
    }

    /// The address a phone should keep: the tailnet's when Tailscale is up (it works at home and away), else the home network's.
    public nonisolated static func best(_ a: (tailnet: String?, lan: String?)) -> String? { a.tailnet ?? a.lan }

    nonisolated static func isTailnet(_ ip: String) -> Bool {
        let p = ip.split(separator: ".").compactMap { Int($0) }
        return p.count == 4 && p[0] == 100 && (64...127).contains(p[1])
    }
    nonisolated static func isPrivate(_ ip: String) -> Bool {
        let p = ip.split(separator: ".").compactMap { Int($0) }
        guard p.count == 4 else { return false }
        return p[0] == 10 || (p[0] == 172 && (16...31).contains(p[1])) || (p[0] == 192 && p[1] == 168) || (p[0] == 169 && p[1] == 254)
    }

    /// Who may connect at all: this Mac, the home network, the tailnet. Everyone else is closed unanswered.
    public nonisolated static func allowed(_ host: String) -> Bool {
        let h = (host.split(separator: "%").first.map(String.init) ?? host).lowercased()
        if h == "127.0.0.1" || h == "::1" { return true }
        let v4 = h.hasPrefix("::ffff:") ? String(h.dropFirst(7)) : h
        if v4.split(separator: ".").count == 4 { return isTailnet(v4) || isPrivate(v4) }
        return h.hasPrefix("fe80:") || h.hasPrefix("fd") || h.hasPrefix("fc")   // link-local and unique-local (Tailscale's fd7a: too)
    }

    // MARK: HTTP, as little as works (the shape of Glyph Bot's PhoneLink)

    private func accept(_ c: NWConnection) {
        guard case .hostPort(let host, _) = c.endpoint, Self.allowed("\(host)"), let routes else { c.cancel(); return }
        let h = "\(host)".split(separator: "%").first.map(String.init) ?? ""
        let loopback = h == "127.0.0.1" || h == "::1" || h == "::ffff:127.0.0.1"
        c.start(queue: .main)
        GlyphHTTPRequest.read(c) { req in
            guard let req else { c.cancel(); return }
            let r = routes.handle(method: req.method, path: req.path, query: req.query, headers: req.headers, body: req.body, loopback: loopback)
            var head = "HTTP/1.1 \(r.status) \(r.status < 300 ? "OK" : "Error")\r\nCache-Control: no-store\r\nConnection: close\r\nContent-Length: \(r.body.count)\r\n"
            for (k, v) in r.headers { head += "\(k): \(v)\r\n" }
            var out = Data((head + "\r\n").utf8); out.append(r.body)
            c.send(content: out, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in c.cancel() })
        }
    }
}

/// One HTTP/1.1 request off a connection: the request line, headers and a Content-Length body.
public struct GlyphHTTPRequest: Sendable {
    public var method: String, path: String, query: [String: String], headers: [String: String], body: Data

    public static func read(_ c: NWConnection, buffer: Data = Data(), done: @escaping @Sendable (GlyphHTTPRequest?) -> Void) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, end, error in
            var buf = buffer
            if let data { buf.append(data) }
            guard buf.count < 30_000_000 else { return done(nil) }
            if let r = parse(buf) { return done(r) }
            if end || error != nil { return done(nil) }
            read(c, buffer: buf, done: done)
        }
    }

    /// Nil until the headers and the whole body are in.
    public static func parse(_ data: Data) -> GlyphHTTPRequest? {
        guard let split = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let lines = String(decoding: data[..<split.lowerBound], as: UTF8.self).components(separatedBy: "\r\n")
        let first = lines.first?.split(separator: " ").map(String.init) ?? []
        guard first.count >= 2 else { return nil }
        var headers: [String: String] = [:]
        for l in lines.dropFirst() { if let i = l.firstIndex(of: ":") { headers[String(l[..<i])] = l[l.index(after: i)...].trimmingCharacters(in: .whitespaces) } }
        let length = headers.first { $0.key.lowercased() == "content-length" }.flatMap { Int($0.value) } ?? 0
        let body = data[split.upperBound...]
        guard body.count >= length else { return nil }
        let comps = URLComponents(string: first[1])
        let query = Dictionary((comps?.queryItems ?? []).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { a, _ in a })
        return GlyphHTTPRequest(method: first[0], path: comps?.path ?? first[1], query: query, headers: headers, body: Data(body.prefix(length)))
    }
}

/// For the other Glyph Mac apps' "Get the iPhone app" sheet: a pairing code from Glyph Native on this Mac.
public enum GlyphPhonePairing {
    public struct Code: Sendable { public let code: String, expires: Date, address: String?, name: String, tailnet: Bool }

    /// Asks the phone link on this Mac for a code (loopback only). Nil when Glyph Native is not sharing.
    public static func askNative(port: Int = GlyphHub.pairPort) async -> Code? {
        guard let url = URL(string: "http://127.0.0.1:\(port)/pair-codes") else { return nil }
        var r = URLRequest(url: url, timeoutInterval: 2); r.httpMethod = "POST"
        guard let (d, resp) = try? await URLSession.shared.data(for: r), (resp as? HTTPURLResponse)?.statusCode == 200,
              let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any], let c = j["code"] as? String, let e = j["expires"] as? Double else { return nil }
        return Code(code: c, expires: Date(timeIntervalSince1970: e), address: j["url"] as? String, name: j["name"] as? String ?? "", tailnet: j["tailnet"] as? Bool ?? false)
    }

    /// A hub named in ~/.config/glyph/env (GLYPH_VAULT_URL, the owner's own server): its `/native/pair-codes`, as before.
    public static func askHub(_ address: String) async -> Code? {
        guard let url = URL(string: address)?.appending(path: "native/pair-codes") else { return nil }
        var r = URLRequest(url: url, timeoutInterval: 3); r.httpMethod = "POST"
        guard let (d, resp) = try? await URLSession.shared.data(for: r), (resp as? HTTPURLResponse)?.statusCode == 200,
              let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any], let c = j["code"] as? String, let e = j["expires"] as? Double else { return nil }
        return Code(code: c, expires: Date(timeIntervalSince1970: e), address: address, name: Host.current().localizedName ?? "", tailnet: GlyphHub.isTailnet(address))
    }

    /// The code for this Mac's QR: the owner's hub when one is set, else Glyph Native's phone link.
    public static func code() async -> Code? {
        if let a = GlyphMacHub.address { return await askHub(a) ?? Code(code: "", expires: .distantFuture, address: a, name: Host.current().localizedName ?? "", tailnet: GlyphHub.isTailnet(a)) }
        return await askNative()
    }
}
#endif
