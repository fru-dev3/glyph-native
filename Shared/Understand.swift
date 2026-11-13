import Foundation
@_exported import GlyphAI
@_exported import GlyphVault

extension Router {
    /// The UI tests' stand-in for Claude (-rulesOnly), never used on a phone: split on sentences and "and also",
    /// ", then", route each part by keywords, and join neighbours that go to the same app.
    public static func jobs(_ words: String) -> [Job] {
        if declined(words) { return [] }
        var parts: [String] = []
        for s in words.split(whereSeparator: { ".!?;\n".contains($0) }) {
            var rest = [String(s)]
            for sep in [" and also ", ", and also ", ", also ", " and then ", ", then ", " then I ", " then i "] {
                rest = rest.flatMap { $0.components(separatedBy: sep) }
            }
            parts += rest.map { $0.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ","))) }.filter { !$0.isEmpty }
        }
        var out: [Job] = []
        for p in parts where !talk(p) {
            let app = app(for: p)
            if let last = out.last, last.agent == app, !["well", "crm", "omega"].contains(app) { out[out.count - 1].instruction += ". " + p; continue }
            out.append(piece(app, p))
        }
        for i in out.indices where out[i].agent == "jot" {
            out[i].instruction = stripLeadIn(out[i].instruction)
            if out[i].instruction.lowercased().contains("dream") { out[i].tag = "dream" }
        }
        return out
    }

    /// Told not to do anything ("don't do anything", "just testing", "never mind", "ignore that"): no jobs, whatever
    /// else was said. (Glyph Time's `VoiceForm.declined` reads the same.)
    // ponytail: the same patterns as Time's VoiceParse.swift; one copy in GlyphCore if a third app needs them.
    public static func declined(_ words: String) -> Bool {
        let s = " " + words.lowercased().replacingOccurrences(of: "\u{2019}", with: "'").replacingOccurrences(of: "just ", with: "")
            .map { $0.isLetter || $0.isNumber || $0 == "'" ? $0 : " " }.reduce(into: "") { $0.append($1) } + " "
        return s.range(of: #"\b(do ?n'?t|do not|did ?n'?t|did not|no need to)( want you to| need you to)? (do|set|start|make|create|add|change) (anything|nothing|a thing)\b"#
            + #"|\b(did ?n'?t|did not|never) ask(ed)?( you)? (for|to)\b|\b(this is|it's|its|that was) (only )?a test\b|^ *testing\b"#
            + #"|\btesting (you|your|this|the app|the mic|the microphone|it)\b|\bnever ?mind\b|\bignore (that|this|me|it)\b|\bforget (it|that|about it)\b"#,
            options: .regularExpression) != nil
    }

    /// A question or a greeting with no app's word in it ("what time is it in London", "hello, how are you"): no job.
    static func talk(_ part: String) -> Bool {
        let s = part.lowercased().trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        let opens = s.range(of: #"^(what|what's|when|where|who|why|how|which|is|are|can you hear|hi|hello|hey|thanks|thank you|ok|okay|cool)\b"#,
                            options: .regularExpression) != nil
        return opens && app(for: s) == "jot" && s.range(of: #"\b(note|jot|idea|dream|dreamed|dreamt|remember)\b"#, options: .regularExpression) == nil
    }

    static func piece(_ app: String, _ text: String) -> Job {
        var p = Job(agent: app, instruction: text)
        let low = " " + text.lowercased() + " "
        switch app {
        case "time":
            // From the first time word: "I'm going to bed and I need to wake up in 2 hours" -> "wake up in 2 hours".
            let low = text.lowercased()
            if let r = ["wake", "remind", "alarm", "timer", "set a", "set an"].compactMap({ low.range(of: $0) }).min(by: { $0.lowerBound < $1.lowerBound }) {
                p.instruction = String(text[r.lowerBound...])
            }
        case "well":
            let kinds: [(String, [String])] = [("symptom", ["symptom", "headache", "pain", "ache", "nausea", "stool", "poop"]),
                                                ("sleep", ["slept", "sleep"]), ("mood", ["mood", "feel", "feeling", "felt"])]
            p.kind = kinds.first { $0.1.contains { low.contains(" \($0) ") } }?.0 ?? "food"
            p.name = p.kind == "food" ? after(["ate ", "had ", "eating ", "eat ", "drank "], in: text) ?? text : p.kind == "symptom"
                ? (kinds[0].1.first { low.contains(" \($0) ") } ?? "symptom") : p.kind
            p.name = cap(p.name)
        case "crm":
            let who = after(["met with ", "met up with ", "meeting with ", "talked to ", "talked with ", "met ", "meet "], in: text) ?? text
            // The person: the capitalized words that open what follows ("Ken Lee at the cafe" -> "Ken Lee").
            let names = who.split(separator: " ").prefix { $0.first?.isUppercase == true }.joined(separator: " ")
            p.name = names.isEmpty ? cap(who) : names
        default: break
        }
        return p
    }

    /// The words after the first marker found ("Today I ate rice and beans" -> "rice and beans").
    static func after(_ markers: [String], in text: String) -> String? {
        for m in markers { if let r = text.range(of: m, options: .caseInsensitive) { let s = text[r.upperBound...].trimmingCharacters(in: .whitespaces); if !s.isEmpty { return s } } }
        return nil
    }

    static func cap(_ s: String) -> String { s.prefix(1).uppercased() + s.dropFirst() }

    /// "Jot down that I dreamed about flying" -> "I dreamed about flying".
    static func stripLeadIn(_ s: String) -> String {
        for lead in ["jot down that ", "jot down ", "jot that ", "make a note that ", "note that ", "write down that ", "remember that "]
        where s.lowercased().hasPrefix(lead) { return cap(String(s.dropFirst(lead.count))) }
        return s
    }
}

/// The driver's planner: a short router session turns one paragraph into jobs [{agent, instruction}] (guided generation); every answer is
/// checked against the words said, and without the model (or with nothing it can back) the rules
/// above do it. Nothing leaves the device.
/// The driver's reading of one chat turn: Glyph Core Intelligence (the hub's POST /understand, Claude), with the
/// turns before it. Nothing is reasoned on the device (d-mvvc6oj6: one Claude brain; the on-device model only
/// transcribes). Claude answers, asks back, or hands out jobs.
public enum Understand {
    public static let nothing = "Got it. Nothing to do."

    /// What the driver does with a turn.
    public enum Turn: Equatable {
        /// Said back in full, wearing the face of the agent that answers ("glyph", the driver, when none is named).
        case answer(String, agent: String)
        /// A question back; the next turn carries it in the history.
        case ask(String)
        /// Jobs for the app agents (each a tool and its arguments), as cards.
        case act([ChatPlan.Job])
        /// Nothing to do, and a short line back.
        case none(String)
    }

    /// Claude's plan read as a turn.
    public static func turn(_ p: ChatPlan) -> Turn {
        switch p.kind {
        case "answer" where !p.reply.isEmpty: return .answer(p.reply, agent: p.jobs.first?.agent ?? "glyph")
        case "ask" where !(p.question + p.reply).isEmpty: return .ask(p.question.isEmpty ? p.reply : p.question)
        case "act" where !p.jobs.isEmpty: return .act(p.jobs)
        default: return .none(p.reply.isEmpty ? nothing : p.reply)
        }
    }

    /// One turn. Told not to do anything: nothing, always. Otherwise Claude through the hub, with Omega's
    /// preferences for the driver; nil when the hub or Claude can't be reached (the words are kept to send again).
    public static func plan(_ said: String, history: [ChatTurn] = [], hub: Hub) async -> Turn? {
        await planned(said, history: history, hub: hub)?.turn
    }

    /// `plan`, with who wrote the answer ("claude", "council(claude,codex)"; empty when the hub does not say).
    public static func planned(_ said: String, history: [ChatTurn] = [], hub: Hub) async -> (turn: Turn, by: String)? {
        if Router.declined(said) { return (.none(nothing), "") }
        guard let base = hub.base else { return nil }
        let prefs = await HubPreferences.shared.text("native", hub: base)
        return await hub.understand(surface: "native", text: said, history: history, preferences: prefs).map { (turn($0), $0.answeredBy) }
    }

    /// UI tests (-rulesOnly) only: the keyword rules stand in for Claude, so runs are the same everywhere.
    public static func rules(_ said: String) -> [Job]? {
        let jobs = Router.jobs(said)
        return Router.declined(said) || jobs.isEmpty ? nil : jobs
    }
}

/// Omega's preferences for an app's scope (`Hub.preferenceText`), kept 10 minutes so a message doesn't fetch them.
/// A hub that is away or slow (over 3 s) gives none, tried again in a minute; the sentence is read without them.
// ponytail: the same actor as Time's TimeKeeper.swift; into GlyphCore if a third app needs it.
actor HubPreferences {
    static let shared = HubPreferences()
    var kept: [String: (at: Date, text: String)] = [:]
    func text(_ scope: String, hub: URL) async -> String {
        let key = scope + " " + hub.absoluteString   // per hub: a new address in Settings is asked at once
        if let k = kept[key], Date().timeIntervalSince(k.at) < 600 { return k.text }
        let got = await withTaskGroup(of: String?.self) { g in
            g.addTask { await Hub(base: hub, model: "").preferenceText(for: scope) }
            g.addTask { try? await Task.sleep(for: .seconds(3)); return nil }
            let first = await g.next() ?? nil
            g.cancelAll()
            return first
        }
        kept[key] = (got == nil ? Date().addingTimeInterval(-540) : .now, got ?? "")
        return got ?? ""
    }
}
