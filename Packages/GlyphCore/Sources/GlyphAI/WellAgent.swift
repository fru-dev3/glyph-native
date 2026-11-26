import Foundation
import FoundationModels
import GlyphVault

/// Glyph Well's agent: food and drink, symptoms, mood, sleep, as Well's own `log` lines in this phone's month
/// file (Glyph Well on this phone pulls them in and lists them).
extension GlyphAgent {
    public static let well = GlyphAgent(
        // Office green, the app's own accent. It was a crimson rose, which on a green app read
        // as alien and sat a shade away from the one red this family keeps for a running mic.
        // An agent's face is its app's face; Well's is a leaf on green.
        id: "well", name: "Well", color: "008000",
        instructions: """
        You are Glyph Well's agent. Log each thing in the job with log_entry, one call each, named in 1 \
        to 4 of the person's words. Everything Glyph Well keeps is yours, not only what they ate: a \
        symptom, a mood, energy, sleep, food or drink, a medicine or supplement, stress, something they \
        did (a walk, a workout), something that happened, a lab or test result, a stool, a visit to a \
        doctor, or a plain note about how they are. Pick the kind that fits what they said; use note when \
        none of the others does, and never drop it for want of a kind. When they say to log, save or keep \
        something, call log_entry -- never answer that it sounds good and keep nothing. Something they do \
        regularly from now on ("I take vitamin D every morning now", "gym Monday Wednesday Friday at 6") is \
        start_routine, one call per thing, besides a log_entry for today when they also did it today; \
        "I stopped the vitamin D" is stop_routine.
        """,
        tools: { hub, ledger in [WellLogEntry(hub: hub, ledger: ledger), StartRoutine(hub: hub, ledger: ledger), StopRoutine(hub: hub, ledger: ledger)] },
        fallback: { job, hub in await hub.logWell(kind: job.kind, name: job.name.isEmpty ? job.instruction : job.name, said: job.instruction, at: hub.now()) })
}

public struct WellLogEntry: Tool {
    public let name = "log_entry"
    public let description = """
    Log something in Glyph Well: a symptom, a mood, energy, sleep, food or drink, a medicine, stress, \
    something they did, something that happened, a lab result, a stool, a doctor's visit, or a note.
    """
    @Generable public struct Arguments {
        @Guide(description: "1 to 4 words naming it, like Rice and beans, Headache.") public var text: String
        // Every kind WellEvent.Kind has. It offered four, so nine of the app's own kinds could not be
        // logged by voice at all: a supplement, a walk, a lab result, a visit. `note` is the catch-all,
        // and the writer coerces anything unknown to it rather than losing the line.
        @Guide(description: "What kind", .anyOf(["symptom", "mood", "energy", "sleep", "food", "med", "stress",
                                                 "activity", "event", "note", "lab", "stool", "visit"])) public var kind: String
        @Guide(description: "When, if said: minutes before now (0 for now).", .range(0...1440)) public var minutesAgo: Int
    }
    let hub: Hub, ledger: Ledger
    public func call(arguments a: Arguments) async throws -> String {
        let d = await hub.logWell(kind: a.kind, name: a.text, said: a.text, at: hub.now().addingTimeInterval(-60 * Double(a.minutesAgo)))
        await ledger.add(d); return d.line
    }
}

extension Hub {
    public func logWell(kind: String, name: String, said: String, at: Date) async -> Done {
        let id = UUID().uuidString
        let name = name.prefix(1).uppercased() + name.dropFirst()
        let line = WellLine.log(id: id, kind: kind, name: name, said: said, at: at, host: host, device: device, where: place, now: now())
        let code = await put("well/\(WellLine.file(now(), host: host))", body: Data(line.utf8), type: "application/x-ndjson")
        if code == nil { return kept("well", name) }
        guard code == 204 else { return Done(agent: "well", line: "Well didn't take it (\(code!)): \(name)", title: name, ok: false) }
        return Done(agent: "well", line: "Logged in Well: \(name)", title: name, ok: true, undo: .wellDelete(id: id), link: URL(string: "glyph-well://today"))
    }
}

/// An ongoing medicine, workout or habit (GlyphVault `Routine`): a `routine` line in Glyph Time's files, so
/// Time reminds of it and Well shows what was taken and missed. Started again by name keeps the same id
/// (an edit, never a second routine). Nothing is invented: no dose, end or time that was not said.
public struct StartRoutine: Tool {
    public let name = "start_routine"
    public let description = "Keep an ongoing medicine, supplement, workout or habit they do regularly from now on, with its days and time, so it is tracked and reminded."
    @Generable public struct Arguments {
        @Guide(description: "What it is, 1 to 4 of their words: Vitamin D, MiraLAX, Gym.") public var name: String
        @Guide(description: "What kind", .anyOf(["med", "workout", "habit"])) public var kind: String
        @Guide(description: "Days of the week it is for, like [\"mon\",\"wed\",\"fri\"]; [] for every day.") public var days: [String]
        @Guide(description: "Time of day as said: 8 am, morning, evening, after dinner. Empty when not said.") public var time: String
        @Guide(description: "The dose, only as said: 2000 IU, 17 g. Empty when not said.") public var dose: String
        @Guide(description: "When it started, as said: today, last Monday, Nov 22. Empty for today.") public var since: String
        @Guide(description: "When it ends, only as said: for 2 weeks, until Dec 20. Empty when open.") public var until: String
    }
    let hub: Hub, ledger: Ledger
    public func call(arguments a: Arguments) async throws -> String {
        let d = await hub.startRoutine(name: a.name, kind: a.kind, days: a.days, time: a.time, dose: a.dose, since: a.since, until: a.until)
        await ledger.add(d); return d.line
    }
}

public struct StopRoutine: Tool {
    public let name = "stop_routine"
    public let description = "Stop an ongoing medicine, workout or habit they no longer do. Its record stays."
    @Generable public struct Arguments {
        @Guide(description: "What they stopped, in their words: vitamin D, the gym.") public var name: String
    }
    let hub: Hub, ledger: Ledger
    public func call(arguments a: Arguments) async throws -> String {
        let d = await hub.stopRoutine(name: a.name); await ledger.add(d); return d.line
    }
}

extension Hub {
    /// Every routine in Time's files (the hub's `GET time`, or the vault on a Mac). Empty when away.
    public func routines() async -> [Routine] {
        guard let (code, data) = await send("GET", "time"), code == 200 else { return [] }
        return TimeLog.routines(TimeLog.events(in: data))
    }

    /// 1 Monday ... 7 Sunday from "mon", "Monday", "weekdays", "weekends".
    static func weekdays(_ said: [String]) -> [Int] {
        let names = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"]
        var out = Set<Int>()
        for w in said.map({ $0.lowercased().trimmingCharacters(in: .whitespaces) }) {
            if w.hasPrefix("weekday") { out.formUnion(1...5) } else if w.hasPrefix("weekend") { out.formUnion([6, 7]) }
            else if let i = names.firstIndex(where: { w.hasPrefix($0) }) { out.insert(i + 1) }
        }
        return out.count == 7 ? [] : out.sorted()
    }

    public func startRoutine(name: String, kind: String, days: [String], time: String, dose: String, since: String, until: String) async -> Done {
        let n = now(), cal = Calendar.current
        let what = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !what.isEmpty else { return Done(agent: "well", line: "What should I keep track of?", ok: false) }
        let title = what.prefix(1).uppercased() + what.dropFirst()
        let existing = await routines().first { $0.title.caseInsensitiveCompare(title) == .orderedSame && $0.active(n) }
        var r = existing ?? Routine(id: UUID().uuidString, title: title)
        r.days = Self.weekdays(days)
        r.kind = ["med", "workout"].contains(kind) ? kind : "habit"
        if !dose.trimmingCharacters(in: .whitespaces).isEmpty { r.dose = dose.trimmingCharacters(in: .whitespaces) }
        if let w = time.isEmpty ? nil : Recall.when(time, now: n), let h = w.hour {
            r.time = cal.date(byAdding: .minute, value: Int((h * 60).rounded()), to: cal.startOfDay(for: n))
        }
        let start = since.isEmpty ? nil : (Self.isoDay(since) ?? Recall.when(since, now: n)?.day)
        r.since = cal.startOfDay(for: min(start ?? existing?.since ?? n, n))
        if !until.isEmpty, let w = Self.isoDay(until) ?? Recall.when(until, now: n)?.day ?? Self.forLength(until, from: r.since ?? n) { r.until = w }
        r.on = true; r.archived = false
        let e = TimeLog.routineLine(r, host: host, device: device, at: n)
        let code = await put("time/\(TimeLog.fileName(for: e))", body: TimeLog.line(e), type: "application/x-ndjson")
        let line = "\(title): \(r.cadence(cal))" + (r.dose.map { ", \($0)" } ?? "") + (existing == nil ? ", kept from now on" : ", updated")
        if code == nil { return kept("well", line) }
        guard code == 204 else { return Done(agent: "well", line: "Time didn't take it (\(code!)): \(line)", title: title, ok: false) }
        return Done(agent: "well", line: line + ". Glyph Time will remind you.", title: title, ok: true, link: URL(string: "glyph-well://today"))
    }

    public func stopRoutine(name: String) async -> Done {
        let n = now(), what = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let list = await routines().filter { $0.active(n) }
        let exact = list.filter { $0.title.lowercased() == what }
        let hits = !exact.isEmpty ? exact : list.filter { $0.title.lowercased().contains(what) || what.contains($0.title.lowercased()) }
        guard hits.count == 1, var r = hits.first else {
            return Done(agent: "well", line: hits.isEmpty ? "I don't see \(name) among what you take or do regularly." : "Which one: \(hits.map(\.title).joined(separator: ", "))?", ok: false)
        }
        r.until = n
        let e = TimeLog.routineLine(r, host: host, device: device, at: n)
        let code = await put("time/\(TimeLog.fileName(for: e))", body: TimeLog.line(e), type: "application/x-ndjson")
        let line = "Stopped \(r.title)"
        if code == nil { return kept("well", line) }
        guard code == 204 else { return Done(agent: "well", line: "Time didn't take it (\(code!)): \(line)", title: r.title, ok: false) }
        return Done(agent: "well", line: line + ". Its record stays.", title: r.title, ok: true, link: URL(string: "glyph-well://today"))
    }

    static func isoDay(_ s: String) -> Date? {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        return f.date(from: String(s.trimmingCharacters(in: .whitespaces).prefix(10)))
    }

    /// "for 2 weeks", "10 days", "a month" from the start, or nil.
    static func forLength(_ s: String, from start: Date) -> Date? {
        let t = s.lowercased()
        let n = Int(t.split(whereSeparator: { !$0.isNumber }).first ?? "") ?? (t.contains(" a ") || t.hasPrefix("a ") || t.contains("one") ? 1 : 0)
        guard n > 0 else { return nil }
        let unit: Calendar.Component? = t.contains("week") ? .weekOfYear : t.contains("month") ? .month : t.contains("day") ? .day : nil
        return unit.flatMap { Calendar.current.date(byAdding: $0, value: n, to: start) }
    }
}
