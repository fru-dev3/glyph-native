import Foundation
import GlyphAI
import Observation
import os

/// Generative UI in the Glyph apps: Google's A2UI 1.0 message format (https://a2ui.org/specification/v1.0-a2ui/),
/// drawn by our own code (the owner's call, 2026-11-22: the format, not Google's renderer, no new package). The
/// field names follow the spec exactly, so an official renderer could take over later. The parts are in `A2UI.md`.
///
/// The hub sends a turn's screen as an array of messages (`ChatPlan.a2ui`); `A2UIStream` applies them, one surface per
/// `surfaceId`, and `A2UISurfaceView` draws one. What the person does on it comes back as an `A2UIAction`.
public enum A2UI {
    public static let version = "1.0"
    /// The one catalog these renderers support, advertised to the hub as `supportedCatalogIds`.
    public static let catalogId = "dev.fru.glyph/catalog/v1"
    /// Every part of the Glyph catalog and the properties it reads (A2UI.md). The hub's validator holds the same list.
    public static let catalog: [String: Set<String>] = [
        "Text": ["text", "variant"],
        "Image": ["url", "description", "fit", "variant"],
        "Icon": ["name"],
        "Row": ["children", "justify", "align"],
        "Column": ["children", "justify", "align"],
        "List": ["children", "direction", "align"],
        "Card": ["child"],
        "Divider": ["axis"],
        "Button": ["child", "action", "variant"],
        "CheckBox": ["label", "value"],
        "TextField": ["label", "value", "placeholder", "variant"],
        "DateTimeInput": ["value", "enableDate", "enableTime", "min", "max", "label"],
        "ChoicePicker": ["options", "value", "label", "variant", "displayStyle"],
        "Slider": ["value", "max", "min", "label", "steps"],
        "Place": ["name", "address", "latitude", "longitude", "hours", "action"],
        "DayStrip": ["start", "days", "marks", "value", "action"],
        "Chart": ["kind", "label", "points", "unit", "currency"],
        "TodoItem": ["title", "time", "tags", "done", "action"],
        "TagChip": ["name", "action"],
    ]
    static let log = Logger(subsystem: "dev.fru.glyph", category: "a2ui")

    /// JSONL (one message a line) as messages; a line that is not a JSON object is logged and skipped.
    public static func messages(jsonl: String) -> [JSONValue] {
        jsonl.split(whereSeparator: \.isNewline).compactMap { line in
            guard let v = try? JSONDecoder().decode(JSONValue.self, from: Data(line.utf8)), v.object != nil else {
                log.error("a2ui: not a message: \(line.prefix(80), privacy: .public)")
                return nil
            }
            return v
        }
    }
}

/// One component as it arrived: `{"id": ..., "component": "Text", ...its properties}`.
public struct A2UIComponent: Equatable, Sendable {
    public var id: String
    public var type: String
    public var props: [String: JSONValue]
    public subscript(_ key: String) -> JSONValue? { props[key] }
}

/// What the person did, as the spec's renderer-to-agent `action`: `message` is the envelope to send back
/// (`Hub.answer(action:surface:history:)`). Bindings in the button's context are resolved when it fires.
public struct A2UIAction: Equatable, Sendable {
    public var name: String
    public var surfaceId: String
    public var sourceComponentId: String
    public var timestamp: Date
    public var context: [String: JSONValue]
    /// Words for the chat line that shows what was chosen ("3:30 PM"); the spec's optional `userMessage`.
    public var userMessage: String?

    public var message: JSONValue {
        let f = ISO8601DateFormatter()
        var a: [String: JSONValue] = ["name": .string(name), "surfaceId": .string(surfaceId), "sourceComponentId": .string(sourceComponentId),
                                      "timestamp": .string(f.string(from: timestamp)), "context": .object(context)]
        if let userMessage { a["userMessage"] = .string(userMessage) }
        return .object(["version": .string(A2UI.version), "action": .object(a)])
    }
}

/// One surface: its components by id and its data model. Messages apply in any order a stream can bring them; a
/// child named before it arrives draws as a placeholder until it does.
@MainActor @Observable public final class A2UISurface: Identifiable {
    public let id: String
    public internal(set) var catalogId: String?
    public internal(set) var components: [String: A2UIComponent] = [:]
    public internal(set) var data: JSONValue = .object([:])
    /// Component types that are not in the catalog: logged once and drawn as nothing.
    public internal(set) var unknown: Set<String> = []
    public internal(set) var sendDataModel = false

    public init(id: String) { self.id = id }

    public var root: A2UIComponent? { components["root"] }

    func take(_ list: [JSONValue]) {
        for c in list {
            guard let o = c.object, let cid = o["id"]?.string, let type = o["component"]?.string else {
                A2UI.log.error("a2ui: a component without id or component in \(self.id, privacy: .public)"); continue
            }
            if A2UI.catalog[type] == nil, !unknown.contains(type) {
                unknown.insert(type)
                A2UI.log.notice("a2ui: unknown component \(type, privacy: .public) in \(self.id, privacy: .public), drawn as nothing")
            }
            components[cid] = A2UIComponent(id: cid, type: type, props: o.filter { $0.key != "id" && $0.key != "component" })
        }
    }

    // MARK: The data model (JSON Pointer, RFC 6901)

    /// A pointer made whole: a path without a leading "/" is relative to `scope` (a template's item).
    static func absolute(_ path: String, scope: String) -> String {
        if path.hasPrefix("/") { return path }
        if path.isEmpty || path == "." { return scope.isEmpty ? "/" : scope }
        return (scope.hasSuffix("/") ? scope : scope + "/") + path
    }

    static func tokens(_ pointer: String) -> [String] {
        pointer.split(separator: "/", omittingEmptySubsequences: true)
            .map { $0.replacingOccurrences(of: "~1", with: "/").replacingOccurrences(of: "~0", with: "~") }
    }

    public func value(at pointer: String) -> JSONValue? {
        var at: JSONValue? = data
        for t in Self.tokens(pointer) {
            switch at {
            case .object(let o): at = o[t]
            case .array(let a): at = Int(t).flatMap { a.indices.contains($0) ? a[$0] : nil }
            default: return nil
            }
        }
        return at
    }

    /// Sets (or with nil removes) the value at a pointer, making the objects on the way.
    public func set(_ value: JSONValue?, at pointer: String) {
        data = Self.setting(data, Self.tokens(pointer)[...], to: value) ?? .object([:])
    }

    static func setting(_ node: JSONValue?, _ path: ArraySlice<String>, to value: JSONValue?) -> JSONValue? {
        guard let head = path.first else { return value }
        let rest = path.dropFirst()
        if case .array(var a) = node, let i = Int(head) {
            let next = setting(a.indices.contains(i) ? a[i] : nil, rest, to: value)
            if a.indices.contains(i) { if let next { a[i] = next } else { a.remove(at: i) } }
            else if let next, i == a.count { a.append(next) }
            return .array(a)
        }
        var o = node?.object ?? [:]
        o[head] = setting(o[head], rest, to: value)
        return .object(o)
    }

    /// A property's value: the literal, or what a `{"@path": ...}` binding points at. `@call` is not drawn in
    /// phase A (logged, nil).
    public func resolve(_ v: JSONValue?, scope: String = "") -> JSONValue? {
        guard case .object(let o) = v else { return v }
        if let p = o["@path"]?.string { return value(at: Self.absolute(p, scope: scope)) }
        if o["@call"] != nil { A2UI.log.notice("a2ui: @call is not supported yet"); return nil }
        return v
    }

    /// The pointer a property is bound to, when it is bound.
    public func binding(_ v: JSONValue?, scope: String = "") -> String? {
        v?.object?["@path"]?.string.map { Self.absolute($0, scope: scope) }
    }

    // MARK: One send at a time

    /// A sent action, so one tap writes once: "Add to the trip" (Glyph X) and "Save" (Glyph Wealth) could be
    /// tapped twice and saved twice (2026-11-22). `key` is the part that sent it (`A2UISurface.key`).
    public enum Sent: Equatable, Sendable {
        case sending(String)
        case answered(String, line: String?)
        case failed(String, line: String)
    }
    /// The surface's send: while one is out no other action leaves it, and its buttons say so.
    public internal(set) var sent: Sent?

    /// A part's key for `sent`: its id, and its template item when it has one (each TodoItem of a List is its own).
    public static func key(_ id: String, scope: String = "") -> String { scope.isEmpty ? id : "\(id)@\(scope)" }

    /// Takes the one send for `key`: false, and nothing may be sent, while a send is out or once `key` was answered.
    public func send(from key: String) -> Bool {
        switch sent {
        case .sending: return false
        case .answered(let k, _) where k == key: return false
        default: sent = .sending(key); return true
        }
    }

    /// The hub's answer to the send that is out (its first line, shown under the button), or nil when it failed:
    /// then every button comes back and one line says why.
    public func answered(_ line: String?, failed: Bool = false) {
        guard case .sending(let k) = sent else { return }
        sent = failed ? .failed(k, line: line ?? "Not sent: Glyph can't be reached. Try again.") : .answered(k, line: line)
    }

    /// Forgets a send nothing will answer (no one listens for actions).
    public func cancelSend() { if case .sending = sent { sent = nil } }

    /// The `action` a component carries, as the message to send, or nil (none, or a local `functionCall`).
    public func action(_ v: JSONValue?, source: String, scope: String = "", userMessage: String? = nil, now: Date = .now) -> A2UIAction? {
        guard let event = v?.object?["event"]?.object, let name = event["name"]?.string else { return nil }
        let context = (event["context"]?.object ?? [:]).mapValues { resolve($0, scope: scope) ?? .null }
        return A2UIAction(name: name, surfaceId: id, sourceComponentId: source, timestamp: now, context: context,
                          userMessage: event["userMessage"].flatMap { resolve($0, scope: scope)?.string } ?? userMessage)
    }
}

/// The surfaces a turn brought, in the order they were made. Apply messages as they come.
@MainActor @Observable public final class A2UIStream {
    public private(set) var surfaces: [A2UISurface] = []

    public init(_ messages: [JSONValue] = []) { messages.forEach(apply) }
    public convenience init(jsonl: String) { self.init(A2UI.messages(jsonl: jsonl)) }

    public func surface(_ id: String) -> A2UISurface? { surfaces.first { $0.id == id } }

    /// One envelope: `{"version": "1.0", "<one of the four>": {...}}`. Anything else is logged and ignored.
    public func apply(_ message: JSONValue) {
        guard let m = message.object, m["version"]?.string == A2UI.version else {
            A2UI.log.error("a2ui: not a 1.0 message"); return
        }
        if let c = m["createSurface"]?.object, let sid = c["surfaceId"]?.string {
            let s = A2UISurface(id: sid)
            s.catalogId = c["catalogId"]?.string
            s.sendDataModel = c["sendDataModel"]?.bool ?? false
            if let d = c["dataModel"], d.object != nil { s.data = d }
            s.take(c["components"]?.array ?? [])
            if let cat = s.catalogId, cat != A2UI.catalogId { A2UI.log.notice("a2ui: catalog \(cat, privacy: .public) is not ours; drawing what we know") }
            surfaces.removeAll { $0.id == sid }
            surfaces.append(s)
        } else if let u = m["updateComponents"]?.object, let sid = u["surfaceId"]?.string {
            guard let s = surface(sid) else { A2UI.log.error("a2ui: updateComponents before createSurface \(sid, privacy: .public)"); return }
            s.take(u["components"]?.array ?? [])
        } else if let u = m["updateDataModel"]?.object, let sid = u["surfaceId"]?.string {
            guard let s = surface(sid) else { A2UI.log.error("a2ui: updateDataModel before createSurface \(sid, privacy: .public)"); return }
            let value = u["value"]
            s.set(value == .null ? nil : value, at: u["path"]?.string ?? "/")
        } else if let d = m["deleteSurface"]?.object, let sid = d["surfaceId"]?.string {
            surfaces.removeAll { $0.id == sid }
        } else {
            A2UI.log.error("a2ui: a message with nothing we know in it")
        }
    }
}

public extension JSONValue {
    var string: String? { if case .string(let s) = self { return s }; return nil }
    var number: Double? {
        switch self { case .number(let n): return n; case .string(let s): return Double(s); default: return nil }
    }
    var bool: Bool? { if case .bool(let b) = self { return b }; return nil }
    var array: [JSONValue]? { if case .array(let a) = self { return a }; return nil }
    var object: [String: JSONValue]? { if case .object(let o) = self { return o }; return nil }
}
