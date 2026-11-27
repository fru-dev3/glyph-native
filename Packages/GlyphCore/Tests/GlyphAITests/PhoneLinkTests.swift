import XCTest
@testable import GlyphAI
@testable import GlyphVault

final class PhoneLinkTests: XCTestCase {
    final class Clock: @unchecked Sendable { var t = Date(timeIntervalSince1970: 1_800_000_000) }

    func book(_ clock: Clock, saved: (@Sendable ([GlyphPairBook.Phone]) -> Void)? = nil) -> GlyphPairBook {
        GlyphPairBook(now: { clock.t }, save: saved ?? { _ in })
    }

    func testCodeExchangesOnceForAToken() throws {
        let clock = Clock()
        nonisolated(unsafe) var kept: [GlyphPairBook.Phone] = []
        let b = book(clock) { kept = $0 }
        let (code, expires) = b.newCode()
        XCTAssertEqual(code.count, 8)
        XCTAssertEqual(expires.timeIntervalSince(clock.t), 600)
        guard case .token(let t, let phone) = b.exchange(code: code.lowercased(), device: "Test iPhone") else { return XCTFail("no token") }
        XCTAssertGreaterThanOrEqual(t.count, 40)
        XCTAssertEqual(phone.name, "Test iPhone")
        XCTAssertEqual(kept.count, 1)
        XCTAssertNotEqual(kept[0].hash, t)   // only the hash is kept
        XCTAssertEqual(b.phone(token: t)?.id, phone.id)
        // single use: the same code again is spent
        XCTAssertEqual(b.exchange(code: code, device: "Other"), .expired)
    }

    func testCodeExpiresAfterTenMinutes() {
        let clock = Clock(), b = book(clock)
        let (code, _) = b.newCode()
        clock.t += 601
        XCTAssertEqual(b.exchange(code: code, device: "x"), .expired)
    }

    func testWrongCodesAreRateLimited() {
        let clock = Clock(), b = book(clock)
        let (code, _) = b.newCode()
        for _ in 0..<GlyphPairBook.triesPerMinute { XCTAssertEqual(b.exchange(code: "AAAAAAAA", device: "x"), .wrong) }
        XCTAssertEqual(b.exchange(code: code, device: "x"), .tooMany)   // even the right one, for the rest of the minute
        clock.t += 61
        if case .token = b.exchange(code: code, device: "x") {} else { XCTFail("the minute is over") }
    }

    func testAuthorizationHeaders() {
        XCTAssertEqual(GlyphPairBook.token(authorization: "Bearer abc"), "abc")
        XCTAssertEqual(GlyphPairBook.token(authorization: "Basic " + Data("glyph:abc".utf8).base64EncodedString()), "abc")
        XCTAssertNil(GlyphPairBook.token(authorization: nil))
        XCTAssertNil(GlyphPairBook.token(authorization: "Token abc"))
    }

    func testRoutesRefuseWithoutTheToken() throws {
        let vault = FileManager.default.temporaryDirectory.appending(path: "phonelink-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: vault.appending(path: "data/tags/health"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }
        let clock = Clock(), b = book(clock)
        var routes = GlyphPhoneRoutes(book: b, vault: vault, name: "Test Mac")
        routes.where_ = { ("http://192.168.1.5:7075", false) }

        // no token, a wrong token: 401 with a Basic challenge, so Foundation answers from a glyph:<token>@ address
        let none = routes.handle(method: "GET", path: "/health")
        XCTAssertEqual(none.status, 401)
        XCTAssertEqual(none.headers["WWW-Authenticate"], "Basic realm=\"Glyph\"")
        XCTAssertEqual(routes.handle(method: "GET", path: "/health", headers: ["Authorization": "Bearer nope"]).status, 401)
        XCTAssertEqual(routes.handle(method: "PUT", path: "/memo/2026-01-01 10-00-00", body: Data("hi".utf8)).status, 401)

        // a code only from this Mac
        XCTAssertEqual(routes.handle(method: "POST", path: "/pair-codes").status, 403)
        let made = routes.handle(method: "POST", path: "/pair-codes", loopback: true)
        XCTAssertEqual(made.status, 200)
        let j = try XCTUnwrap(JSONSerialization.jsonObject(with: made.body) as? [String: Any])
        XCTAssertEqual(j["url"] as? String, "http://192.168.1.5:7075")
        let code = try XCTUnwrap(j["code"] as? String)

        let wrong = routes.handle(method: "POST", path: "/pair", body: Data(#"{"code":"ZZZZZZZZ","device":"p"}"#.utf8))
        XCTAssertEqual(wrong.status, 401)
        let paired = routes.handle(method: "POST", path: "/pair", body: Data(#"{"code":"\#(code)","device":"p"}"#.utf8))
        XCTAssertEqual(paired.status, 200)
        let token = try XCTUnwrap((JSONSerialization.jsonObject(with: paired.body) as? [String: Any])?["token"] as? String)
        XCTAssertEqual(routes.handle(method: "POST", path: "/pair", body: Data(#"{"code":"\#(code)","device":"p"}"#.utf8)).status, 410)

        let health = routes.handle(method: "GET", path: "/health", headers: ["authorization": "Bearer \(token)"])
        XCTAssertEqual(health.status, 200)
        let h = try XCTUnwrap(JSONSerialization.jsonObject(with: health.body) as? [String: Any])
        XCTAssertEqual(h["ok"] as? Bool, true)
        XCTAssertEqual(h["name"] as? String, "Test Mac")
        XCTAssertEqual(h["domains"] as? [String], ["health"])
        let basic = "Basic " + Data("glyph:\(token)".utf8).base64EncodedString()
        XCTAssertEqual(routes.handle(method: "GET", path: "/health", headers: ["Authorization": basic]).status, 200)
        // a MacHub route goes through with the token; an unknown one is 501
        XCTAssertEqual(routes.handle(method: "GET", path: "/time", headers: ["Authorization": "Bearer \(token)"]).status, 200)
        XCTAssertEqual(routes.handle(method: "GET", path: "/nothing", headers: ["Authorization": "Bearer \(token)"]).status, 501)

        // forgetting the phone stops its token
        b.forget(b.phones[0].id)
        XCTAssertEqual(routes.handle(method: "GET", path: "/health", headers: ["Authorization": "Bearer \(token)"]).status, 401)
    }

    func testHTTPParse() throws {
        let raw = Data("POST /pair?x=1 HTTP/1.1\r\nHost: a\r\nContent-Length: 4\r\nAuthorization: Bearer t\r\n\r\nbody".utf8)
        let r = try XCTUnwrap(GlyphHTTPRequest.parse(raw))
        XCTAssertEqual(r.method, "POST"); XCTAssertEqual(r.path, "/pair"); XCTAssertEqual(r.query["x"], "1")
        XCTAssertEqual(r.headers["Authorization"], "Bearer t"); XCTAssertEqual(r.body, Data("body".utf8))
        XCTAssertNil(GlyphHTTPRequest.parse(Data("POST / HTTP/1.1\r\nContent-Length: 9\r\n\r\nbody".utf8)))
    }

    func testWhoMayConnect() {
        for ok in ["127.0.0.1", "192.168.1.20", "10.0.0.4", "172.20.1.1", "100.100.1.2", "::ffff:192.168.1.2", "fe80::1%en0", "fd7a:115c:a1e0::1"] {
            XCTAssertTrue(GlyphPhoneLink.allowed(ok), ok)
        }
        for no in ["8.8.8.8", "100.200.1.1", "2001:db8::1"] { XCTAssertFalse(GlyphPhoneLink.allowed(no), no) }
        XCTAssertEqual(GlyphPhoneLink.best((tailnet: "100.64.0.9", lan: "192.168.1.2")), "100.64.0.9")
        XCTAssertEqual(GlyphPhoneLink.best((tailnet: nil, lan: "192.168.1.2")), "192.168.1.2")
    }

    func testSharedAddressCarriesTheToken() {
        let a = GlyphHub.address("http://192.168.1.5:7075", token: "tok")
        XCTAssertEqual(a, "http://glyph:tok@192.168.1.5:7075")
        XCTAssertEqual(GlyphHub.token(in: a), "tok")
        XCTAssertEqual(GlyphHub.display(a), "http://192.168.1.5:7075")
        XCTAssertNil(GlyphHub.token(in: "http://hub:7071"))
        XCTAssertEqual(GlyphHub.address("http://hub:7071", token: nil), "http://hub:7071")
        XCTAssertTrue(GlyphHub.isTailnet("http://glyph:t@100.70.1.2:7075"))
        XCTAssertTrue(GlyphHub.isTailnet("http://mac.tail1234.ts.net:7075"))
        XCTAssertFalse(GlyphHub.isTailnet("http://192.168.1.5:7075"))
        XCTAssertEqual(GlyphHub.pairLink(app: "jot", address: "http://192.168.1.5:7075", name: "Test Mac", code: "K7M2PQ9X", bonjour: "Test Mac"),
                       "https://glyph.fru.dev/pair#app=jot&url=http%3A%2F%2F192.168.1.5%3A7075&name=Test%20Mac&code=K7M2PQ9X&bonjour=Test%20Mac")
        XCTAssertEqual(GlyphHub.pairLink(app: "jot", address: nil, name: "", code: nil), "https://glyph.fru.dev/pair#app=jot")
        XCTAssertEqual(GlyphPhoneApps.find("Glyph Jot")?.id, "jot")
        XCTAssertEqual(GlyphPhoneApps.find("Glyph Travel")?.id, "travel")
    }
}
