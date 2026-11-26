import Foundation
import GlyphAI
import Testing

@testable import GlyphCapture

@Suite("A2UI 1.0 messages in the Glyph catalog")
@MainActor
struct A2UITests {
    private func msg(_ s: String) -> JSONValue { try! JSONDecoder().decode(JSONValue.self, from: Data(s.utf8)) }

    @Test("Every fixture decodes: one surface, a root, every part in the catalog, every child present")
    func fixtures() {
        #expect(A2UIFixtures.all.count == 5)
        for f in A2UIFixtures.all {
            let stream = A2UIStream(jsonl: f.jsonl)
            #expect(stream.surfaces.count == 1, "\(f.name)")
            let s = stream.surfaces[0]
            #expect(s.catalogId == A2UI.catalogId, "\(f.name)")
            #expect(s.root != nil, "\(f.name)")
            #expect(s.unknown.isEmpty, "\(f.name)")
            for c in s.components.values {
                #expect(A2UI.catalog[c.type] != nil, "\(f.name): \(c.type)")
                for k in c.props.keys where k != "weight" { #expect(A2UI.catalog[c.type]!.contains(k), "\(f.name): \(c.type).\(k)") }
                for id in (c["children"]?.array ?? []).compactMap(\.string) + [c["child"]?.string].compactMap({ $0 }) {
                    #expect(s.components[id] != nil, "\(f.name): \(c.id) names \(id)")
                }
            }
        }
        let todos = A2UIStream(jsonl: A2UIFixtures.all.first { $0.name == "todos" }!.jsonl).surfaces[0]
        #expect(todos.value(at: "/todos")?.array?.count == 3)
        #expect(todos.resolve(todos.components["todo"]?["title"], scope: "/todos/1")?.string == "Call the dentist")
    }

    @Test("Updates apply as they come: a child named before it arrives, then arrives; a later update replaces")
    func incremental() {
        let stream = A2UIStream()
        stream.apply(msg(#"{"version":"1.0","createSurface":{"surfaceId":"s","catalogId":"dev.fru.glyph/catalog/v1"}}"#))
        stream.apply(msg(#"{"version":"1.0","updateComponents":{"surfaceId":"s","components":[{"id":"root","component":"Column","children":["a","b"]},{"id":"a","component":"Text","text":"One"}]}}"#))
        let s = stream.surface("s")!
        #expect(s.components["a"] != nil && s.components["b"] == nil)   // b draws as a placeholder for now
        stream.apply(msg(#"{"version":"1.0","updateComponents":{"surfaceId":"s","components":[{"id":"b","component":"Text","text":"Two"},{"id":"a","component":"Text","text":"One again"}]}}"#))
        #expect(s.components["b"]?["text"]?.string == "Two")
        #expect(s.components["a"]?["text"]?.string == "One again")
        // Before createSurface, or not 1.0: ignored.
        stream.apply(msg(#"{"version":"1.0","updateComponents":{"surfaceId":"nope","components":[{"id":"root","component":"Text","text":"x"}]}}"#))
        stream.apply(msg(#"{"version":"0.9","createSurface":{"surfaceId":"old"}}"#))
        #expect(stream.surfaces.map(\.id) == ["s"])
        stream.apply(msg(#"{"version":"1.0","deleteSurface":{"surfaceId":"s"}}"#))
        #expect(stream.surfaces.isEmpty)
    }

    @Test("Bindings read the data model; a write lands at its pointer; null removes; relative paths use the scope")
    func binding() {
        let stream = A2UIStream(jsonl: """
        {"version":"1.0","createSurface":{"surfaceId":"d"}}
        {"version":"1.0","updateDataModel":{"surfaceId":"d","value":{"user":{"name":"Ken"},"rows":[{"t":"a"},{"t":"b"}]}}}
        {"version":"1.0","updateDataModel":{"surfaceId":"d","path":"/user/age","value":41}}
        """)
        let s = stream.surface("d")!
        #expect(s.resolve(msg(#"{"@path":"/user/name"}"#))?.string == "Ken")
        #expect(s.resolve(msg(#"{"@path":"/user/age"}"#))?.number == 41)
        #expect(s.resolve(msg(#"{"@path":"t"}"#), scope: "/rows/1")?.string == "b")
        #expect(s.resolve(.string("literal"))?.string == "literal")
        s.set(.string("Ana"), at: "/user/name")
        s.set(.bool(true), at: "/form/agree")
        s.set(.string("c"), at: "/rows/2/t")
        #expect(s.value(at: "/user/name")?.string == "Ana" && s.value(at: "/form/agree")?.bool == true)
        #expect(s.value(at: "/rows")?.array?.count == 3)
        stream.apply(msg(#"{"version":"1.0","updateDataModel":{"surfaceId":"d","path":"/user/age","value":null}}"#))
        #expect(s.value(at: "/user/age") == nil && s.value(at: "/user/name") != nil)
        #expect(A2UISurface.tokens("/a~1b/c~0d") == ["a/b", "c~d"])
    }

    @Test("A part the catalog does not have is kept aside, logged and drawn as nothing; the rest still draws")
    func unknown() {
        let stream = A2UIStream(jsonl: """
        {"version":"1.0","createSurface":{"surfaceId":"u","catalogId":"dev.fru.glyph/catalog/v1"}}
        {"version":"1.0","updateComponents":{"surfaceId":"u","components":[{"id":"root","component":"Column","children":["x","t"]},{"id":"x","component":"Hologram","beam":1},{"id":"t","component":"Text","text":"Still here"},{"component":"Text"}]}}
        not json at all
        """)
        let s = stream.surface("u")!
        #expect(s.unknown == ["Hologram"])
        #expect(s.components["t"]?["text"]?.string == "Still here")
        #expect(s.components.count == 3)   // the one without an id is dropped
        _ = A2UISurfaceView(surface: s) { _ in }.body   // builds without trapping
    }

    @Test("An action round trip: the button's context resolved from the data model, sent as the spec's envelope, and the plan back")
    func action() throws {
        let f = A2UIFixtures.all.first { $0.name == "time-picker" }!
        let s = A2UIStream(jsonl: f.jsonl).surfaces[0]
        s.set(.array([.string("16:00")]), at: "/choice")   // the person picks 4:00 PM
        let when = Date(timeIntervalSince1970: 1_795_000_000)
        let a = try #require(s.action(s.components["set"]?["action"], source: "set", userMessage: "Set reminder", now: when))
        #expect(a.name == "setReminder" && a.surfaceId == "when" && a.sourceComponentId == "set")
        #expect(a.context["choice"] == .array([.string("16:00")]) && a.context["time"]?.string == "15:30")
        let out = try JSONSerialization.jsonObject(with: JSONEncoder().encode(a.message)) as! [String: Any]
        #expect(out["version"] as? String == "1.0")
        let body = try #require(out["action"] as? [String: Any])
        #expect(Set(body.keys) == ["name", "surfaceId", "sourceComponentId", "timestamp", "context", "userMessage"])
        #expect(ISO8601DateFormatter().date(from: body["timestamp"] as! String) == when)
        // A local function call is not an action for the hub.
        #expect(s.action(msg(#"{"functionCall":{"@call":"openUrl","args":{"url":"https://example.com"}}}"#), source: "x") == nil)
        // And the hub's answer with a screen decodes into the plan an app already reads.
        let plan = try JSONDecoder().decode(ChatPlan.self, from: Data("""
        {"kind": "answer", "reply": "Set for 4:00 PM.", "a2ui": [\(f.jsonl.split(separator: "\n").joined(separator: ","))]}
        """.utf8))
        #expect(plan.a2ui.count == 3 && A2UIStream(plan.a2ui).surfaces.first?.id == "when")
        #expect(try JSONDecoder().decode(ChatPlan.self, from: Data(#"{"kind": "none"}"#.utf8)).a2ui.isEmpty)
    }

    @Test("A screen's button writes once: a second tap is dropped while the first is out and after the answer; a failed send lets it go again")
    func sendsOnce() async throws {
        let s = A2UIStream(jsonl: A2UIFixtures.all.first { $0.name == "place" }!.jsonl).surfaces[0]
        let save = A2UISurface.key("save")
        var writes = 0
        // What a tap does (A2UINode.fire): the gate, then the send; the hub answers later (ChatModel.act settles it).
        func tap(_ key: String) -> Bool { guard s.send(from: key) else { return false }; writes += 1; return true }

        #expect(tap(save))                  // the first tap
        #expect(s.sent == .sending(save))
        #expect(!tap(save))                 // the second, while the first is out: dropped
        #expect(!tap("other"))              // and no other part sends meanwhile
        _ = A2UISurfaceView(surface: s) { _ in }.body   // draws in its sending state
        s.answered("Added in Travel: Lakeside Coffee")
        #expect(s.sent == .answered(save, line: "Added in Travel: Lakeside Coffee"))
        #expect(!tap(save))                 // answered: never a second write from it
        #expect(writes == 1)
        #expect(A2UISurface.key("todo", scope: "/todos/1") == "todo@/todos/1")

        // Unreachable: every button comes back with one line, and the next tap sends.
        let t = A2UIStream(jsonl: A2UIFixtures.all.first { $0.name == "time-picker" }!.jsonl).surfaces[0]
        #expect(t.send(from: "set"))
        t.answered(nil, failed: true)
        guard case .failed("set", let why) = t.sent else { Issue.record("not failed: \(String(describing: t.sent))"); return }
        #expect(!why.isEmpty)
        #expect(t.send(from: "skip"))
        t.cancelSend()
        #expect(t.sent == nil)

        #if os(iOS)
        // In the chat: ChatModel.act answers the screen it came from.
        let u = A2UIStream(jsonl: A2UIFixtures.all.first { $0.name == "place" }!.jsonl).surfaces[0]
        let model = ChatModel(app: "test") { _, _ in [] }
        model.onAction = { _, _ in [ChatEntry(text: "Added", done: true)] }
        var line = ChatEntry.answer("Lakeside Coffee"); line.surfaces = [u]
        model.entries = [line]
        #expect(u.send(from: save))
        await model.act(try #require(u.action(u.components["save"]?["action"], source: "save")))
        #expect(u.sent == .answered(save, line: "Added"))
        #endif
    }

    @Test("Dates and times keep the value's own form")
    func dates() {
        let f = A2UINode.dateFormat(date: false, time: true)
        let d = A2UINode.parseDate("15:30", date: false, time: true)!
        #expect(f.string(from: d) == "15:30")
        #expect(A2UINode.dateFormat(date: true, time: false).string(from: A2UINode.parseDate("2026-11-24", date: true, time: false)!) == "2026-11-24")
    }
}
