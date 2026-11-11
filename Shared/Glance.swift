import Foundation
import GlyphVault

/// One app's live fact on the home screen, read from data the device already has (the hub's routes
/// on the iPhone, the vault's files on the Mac). Nothing here writes. `fact` is a number and a one or
/// two word unit ("3 today", "225 to review"), right-aligned on the row; `detail` is what it counts,
/// shown only on hover or to VoiceOver, never in the list (Fru: "too wordy").
public struct Glance: Equatable, Sendable {
    public var fact: String
    public var detail: String?
    public init(_ fact: String, detail: String? = nil) { self.fact = fact; self.detail = detail }
}

/// What is being timed right now, for the Now card.
public struct Running: Equatable, Sendable {
    public var project: String
    public var start: Date        // when the clock would read 0:00 (paused time already left out)
    public var today: TimeInterval // today's total before this session
}

public enum Glances {
    // MARK: Time (GET /time, or data/apps/time/sessions/*.jsonl)

    public static func time(_ data: Data, now: Date = .now, calendar: Calendar = .current) -> (glance: Glance?, running: Running?) {
        let sessions = TimeLog.sessions(TimeLog.events(in: data))
        let day = calendar.startOfDay(for: now)
        let today = TimeLog.totals(sessions, from: day, to: now, now: now).reduce(0) { $0 + $1.seconds }
        // ponytail: a session open for more than 18 hours was left running somewhere; it is not "now".
        if let s = sessions.last(where: { $0.end == nil && $0.pausedSince == nil && now.timeIntervalSince($0.start) < 18 * 3600 }) {
            let active = s.active(at: now)
            let name = s.project ?? "Untitled"
            return (Glance("\(hm(today)) today", detail: "\(name) running"),
                    Running(project: name, start: now.addingTimeInterval(-active), today: max(0, today - active)))
        }
        guard today >= 60 else { return (nil, nil) }
        let top = TimeLog.totals(sessions, from: day, to: now, now: now).max { $0.seconds < $1.seconds }
        return (Glance("\(hm(today)) today", detail: top.map { "Most on \($0.project)" }), nil)
    }

    // MARK: Omega (GET /omega: {"files": {path: text}}, or the same files read from the vault)

    /// How many goals; the detail is the next open action tied to one (the soonest dated first).
    public static func omega(_ files: [String: String], today: Date = .now) -> Glance? {
        var goals: [String: String] = [:]
        var actions: [(text: String, goal: String?, due: String)] = []
        for (path, text) in files {
            for raw in text.split(separator: "\n") {
                let line = raw.trimmingCharacters(in: .whitespaces)
                guard line.hasPrefix("- [ ] ") else { continue }
                let body = String(line.dropFirst(6))
                let tokens = body.split(separator: " ")
                func token(_ key: String) -> String? { tokens.first { $0.hasPrefix("~\(key):") }.map { String($0.dropFirst(key.count + 2)) } }
                let title = tokens.filter { !$0.hasPrefix("~") && !(($0.hasPrefix("@") || $0.hasPrefix("+")) && $0.count == 11) }.joined(separator: " ")
                if path.hasSuffix("source/goals.md") {
                    if let id = token("id"), token("status") != "archived" { goals[id] = title }
                } else if path.hasSuffix("tasks.md"), let g = token("goal") {
                    let due = tokens.first { $0.hasPrefix("@") && $0.count == 11 }.map { String($0.dropFirst()) } ?? "9999"
                    actions.append((title, g, due))
                }
            }
        }
        guard !goals.isEmpty else { return nil }
        let next = actions.sorted(by: { ($0.due, $0.text) < ($1.due, $1.text) }).first { !$0.text.isEmpty }
        return Glance(goals.count == 1 ? "1 goal" : "\(goals.count) goals",
                      detail: next.map { [$0.text, $0.goal.flatMap { goals[$0] }].compactMap { $0 }.joined(separator: ", for ") } ?? "No next action yet")
    }

    // MARK: Well (GET /well/context "entries", or data/apps/well/entries/*.jsonl)

    /// How many logs today (the last one named in the detail); nothing logged, nothing shown.
    public static func well(_ entries: [[String: Any]], now: Date = .now, calendar: Calendar = .current) -> Glance? {
        var byID: [String: [String: Any]] = [:]
        var deleted: Set<String> = []
        for e in entries {
            guard let id = e["id"] as? String else { continue }
            switch e["event"] as? String {
            case "log": byID[id] = e
            case "delete": deleted.insert(id)
            default: break
            }
        }
        let today = byID.filter { !deleted.contains($0.key) }.values.compactMap { e -> (Date, String)? in
            guard let s = (e["at"] ?? e["ts"]) as? String, let d = date(s), calendar.isDate(d, inSameDayAs: now) else { return nil }
            let name = (e["name"] as? String) ?? (e["kind"] as? String)?.capitalized ?? "Entry"
            return (d, name)
        }.sorted { $0.0 < $1.0 }
        guard let last = today.last else { return nil }
        return Glance("\(today.count) today", detail: "Last: \(last.1), \(last.0.formatted(date: .omitted, time: .shortened))")
    }

    // MARK: CRM (GET /crm/snapshot "files", or data/apps/crm/proposals/*.jsonl)

    /// Suggestions still waiting for a yes (the last line for an id wins); the names only in the detail.
    public static func crm(_ proposalLines: [String]) -> Glance? {
        var last: [String: (String, String)] = [:]   // id: (status, name)
        var order: [String] = []
        for line in proposalLines {
            guard let o = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any], let id = o["id"] as? String else { continue }
            if last[id] == nil { order.append(id) }
            last[id] = ((o["status"] as? String) ?? "pending", (o["name"] as? String) ?? "")
        }
        let waiting = order.filter { last[$0]?.0 == "pending" }
        guard !waiting.isEmpty else { return nil }
        var names: [String] = []
        for id in waiting.reversed() { if let n = last[id]?.1, !n.isEmpty, !names.contains(n) { names.append(n) }; if names.count == 2 { break } }
        let more = Set(waiting.compactMap { last[$0]?.1 }).count - names.count
        let meta = names.isEmpty ? nil : names.joined(separator: ", ") + (more > 0 ? " and \(more) more" : "")
        return Glance("\(waiting.count) to review", detail: meta)
    }

    /// "2h 12m", "45m": short enough for the row's right edge.
    static func hm(_ s: TimeInterval) -> String {
        let m = Int(max(0, s) / 60)
        return m < 60 ? "\(m)m" : m % 60 == 0 ? "\(m / 60)h" : "\(m / 60)h \(m % 60)m"
    }

    static func date(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s)
    }
/// Glyph Arena (build/_meta/arena/policy.json): how many routes Studio is following, and
    /// what this month's duels have cost against the cap.
    public static func arena(_ policyJSON: Data) -> Glance? {
        guard let o = (try? JSONSerialization.jsonObject(with: policyJSON)) as? [String: Any] else { return nil }
        let routes = (o["routes"] as? [[String: Any]])?.count ?? 0
        guard routes > 0 else { return nil }
        var detail: String?
        if let b = o["budget"] as? [String: Any], let spent = b["spent_usd"] as? Double, let cap = b["cap_usd"] as? Double {
            detail = String(format: "$%.2f of $%.0f this month", spent, cap)
        }
        return Glance("\(routes) \(routes == 1 ? "route" : "routes")", detail: detail)
    }
}

/// Where spoken words go: a simple keyword router, the first match wins (Time, Omega, CRM, Well),
/// everything else to Jot. Returns the app's id and the link that hands it the words.
public enum Router {
    static let rules: [(app: String, words: [String])] = [
        ("time", ["remind", "reminder", "reminders", "alarm", "timer", "wake me"]),
        ("omega", ["goal", "goals", "vision", "mission", "values"]),
        ("crm", ["met", "meet", "person", "company", "contact"]),
        ("well", ["ate", "eat", "eating", "meal", "breakfast", "lunch", "dinner", "snack", "symptom", "symptoms", "stool", "poop",
                  "mood", "slept", "headache", "pain", "medicine", "pill"]),
    ]

    public static func app(for words: String) -> String {
        let said = " " + words.lowercased().map { $0.isLetter || $0 == "'" ? $0 : " " }.reduce(into: "") { $0.append($1) } + " "
        for r in rules where r.words.contains(where: { said.contains(" \($0) ") }) { return r.app }
        return "jot"
    }

    /// The app's link with the words: each app's own handler takes `text`.
    public static func link(app: String, words: String) -> URL? {
        guard let a = Family.apps.first(where: { $0.id == app }) else { return nil }
        let path = ["time": "talk", "well": "log", "crm": "talk", "omega": "talk", "jot": "note"][app] ?? ""
        var c = URLComponents()
        c.scheme = a.scheme
        c.host = path
        c.queryItems = [URLQueryItem(name: "text", value: words)]
        return c.url
    }
}
