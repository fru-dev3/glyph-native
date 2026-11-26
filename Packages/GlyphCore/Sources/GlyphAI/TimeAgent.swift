import Foundation
import FoundationModels
import GlyphVault

/// Glyph Time's agent. Time owns alarms (AlarmKit, its list, Undo, cancel), and iOS lets no other app arm
/// one, so the tools leave a request in Time's queue (GlyphVault `TimeRequest`); the driver then opens
/// `glyph-time://arm`, Time arms it, answers on the request's id and comes back. Time also sweeps the queue
/// on every launch. Nothing shows as set until Time answers.
extension GlyphAgent {
    public static let time = GlyphAgent(
        id: "time", name: "Time", color: "007A5E",
        instructions: "You are Glyph Time's agent. For a wake-up or alarm call request_alarm, for a reminder request_reminder, for a timer start_timer; to stop, pause or resume the running timer stop_timer, pause_timer, resume_timer. Time already spent, told after the fact (\"I spent two hours on tax prep\", \"worked 45 minutes on the deck this morning\"), is log_hours: it is hours worked, not a workout or a health activity. Use the person's own words for when. Never invent a length: 0 when they did not say how long.",
        tools: { hub, ledger in [RequestAlarm(hub: hub, ledger: ledger), RequestReminder(hub: hub, ledger: ledger), StartTimer(hub: hub, ledger: ledger),
                                    LogHours(hub: hub, ledger: ledger),
                                    TimerCommand(name: "stop_timer", words: "stop the timer", hub: hub, ledger: ledger),
                                    TimerCommand(name: "pause_timer", words: "pause the timer", hub: hub, ledger: ledger),
                                    TimerCommand(name: "resume_timer", words: "resume the timer", hub: hub, ledger: ledger)] },
        fallback: { job, hub in hub.requestTime(kind: "alarm", command: job.instruction) })

    /// Opens Time to arm what was asked, and come back.
    public static let armLink = armLink(back: URL(string: "glyph-native://time"))
    /// Opens Time to arm what was asked, then back to `back` (the app that asked).
    public static func armLink(back: URL?) -> URL {
        var c = URLComponents(string: "glyph-time://arm")!
        if let back { c.queryItems = [URLQueryItem(name: "return", value: back.absoluteString)] }
        return c.url!
    }
}

public struct RequestAlarm: Tool {
    public let name = "request_alarm"
    public let description = "Ask Glyph Time for an alarm or wake-up."
    @Generable public struct Arguments {
        @Guide(description: "When, as said: in 2 hours, at 6:30 am, tomorrow at 7.") public var when: String
        @Guide(description: "A label, or empty.") public var label: String
    }
    let hub: Hub, ledger: Ledger
    public func call(arguments a: Arguments) async throws -> String {
        let d = hub.requestTime(kind: "alarm", command: "wake me up \(a.when)" + (a.label.isEmpty || a.label.lowercased().contains("wake") ? "" : " for \(a.label)")); await ledger.add(d); return d.line
    }
}

public struct RequestReminder: Tool {
    public let name = "request_reminder"
    public let description = "Ask Glyph Time for a reminder."
    @Generable public struct Arguments {
        @Guide(description: "When, as said: at 3 pm, every Wednesday at 9.") public var when: String
        @Guide(description: "What to be reminded of.") public var what: String
    }
    let hub: Hub, ledger: Ledger
    public func call(arguments a: Arguments) async throws -> String {
        let d = hub.requestTime(kind: "reminder", command: "remind me \(a.when) to \(a.what)"); await ledger.add(d); return d.line
    }
}

public struct StartTimer: Tool {
    public let name = "start_timer"
    public let description = "Ask Glyph Time to start a timer."
    @Generable public struct Arguments {
        @Guide(description: "How long, as said: 25 minutes. Empty for a running clock.") public var duration: String
        @Guide(description: "What it is for, or empty.") public var label: String
    }
    let hub: Hub, ledger: Ledger
    public func call(arguments a: Arguments) async throws -> String {
        let words = (a.label.isEmpty ? "timer" : a.label) + (a.duration.isEmpty ? "" : " for \(a.duration)")
        let d = hub.requestTime(kind: "timer", command: words); await ledger.add(d); return d.line
    }
}

/// Stop, pause or resume the running timer: no arguments; Time does it as it does the spoken command.
public struct TimerCommand: Tool {
    public let name: String
    public var description: String { "Ask Glyph Time to \(words)." }
    @Generable public struct Arguments {
        @Guide(description: "A label, or empty.") public var label: String?
    }
    let words: String
    let hub: Hub, ledger: Ledger
    public init(name: String, words: String, hub: Hub, ledger: Ledger) { self.name = name; self.words = words; self.hub = hub; self.ledger = ledger }
    public func call(arguments a: Arguments) async throws -> String {
        let d = hub.requestTime(kind: "timer", command: words); await ledger.add(d); return d.line
    }
}

/// Time already spent, told after the fact: one `logged` line in this device's month file (GlyphVault
/// `TimeLog`), a whole session ending when they said (just now when they said nothing). Nothing is
/// written without a length: a made-up one would be a number Fru never said.
public struct LogHours: Tool {
    public let name = "log_hours"
    public let description = "Log time already spent on something, told after the fact, in Glyph Time."
    @Generable public struct Arguments {
        @Guide(description: "How long, in minutes: two hours is 120, an hour and a half is 90. 0 when they did not say.", .range(0...1440)) public var minutes: Int
        @Guide(description: "What the time went on, in their words: tax prep, the book chapter.") public var project: String
        @Guide(description: "When it ended, as said: this morning, yesterday at 5 pm. Empty for just now.") public var when: String
    }
    let hub: Hub, ledger: Ledger
    public func call(arguments a: Arguments) async throws -> String {
        let d = await hub.logHours(minutes: a.minutes, project: a.project, when: a.when); await ledger.add(d); return d.line
    }
}

extension Hub {
    public func logHours(minutes: Int, project: String, when said: String) async -> Done {
        let what = project.trimmingCharacters(in: .whitespacesAndNewlines)
        guard minutes > 0 else { return Done(agent: "time", line: "How long did you spend on \(what.isEmpty ? "it" : what)?", title: what, ok: false) }
        let n = now(), cal = Calendar.current
        var end = n
        if !said.trimmingCharacters(in: .whitespaces).isEmpty, let w = Recall.when(said, now: n) {
            if let h = w.hour { end = cal.date(byAdding: .minute, value: Int((h * 60).rounded()), to: w.day) ?? n }
            // ponytail: a past day with no hour ends at midday; ask for the hour if that ever matters.
            else if !cal.isDate(w.day, inSameDayAs: n) { end = cal.date(byAdding: .hour, value: 12, to: w.day) ?? n }
        }
        end = min(end, n)
        let start = end.addingTimeInterval(-Double(minutes) * 60)
        let e = TimeEvent("logged", at: n, host: host, device: device, project: what.isEmpty ? nil : what,
                          label: said.isEmpty ? nil : said, start: start, end: end, where: place)
        let code = await put("time/\(TimeLog.fileName(for: e))", body: TimeLog.line(e), type: "application/x-ndjson")
        let h = minutes / 60, m = minutes % 60
        let length = [h > 0 ? "\(h) h" : "", m > 0 ? "\(m) min" : ""].filter { !$0.isEmpty }.joined(separator: " ")
        let line = "Logged \(length)" + (what.isEmpty ? "" : " on \(what)")
        if code == nil { return kept("time", line) }
        guard code == 204 else { return Done(agent: "time", line: "Time didn't take it (\(code!)): \(line)", title: line, ok: false) }
        return Done(agent: "time", line: line + ".", title: line, ok: true, link: URL(string: "glyph-time://"))
    }

    public func requestTime(kind: String, command: String) -> Done {
        let id = UUID().uuidString
        TimeRequest.append(TimeRequest(id: id, event: "request", kind: kind, command: command, now: now()), to: timeQueue)
        return Done(agent: "time", line: command, ok: true, link: GlyphAgent.armLink, waiting: id)
    }
}
