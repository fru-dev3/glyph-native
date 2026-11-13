import Foundation

/// "Answers come from": which engine answers a chat, set once for the whole family in Glyph Native and kept in the
/// vault (`data/apps/native/settings.json`, served by the hub's GET and PUT /native/settings). One engine id is that
/// engine, `auto` is the hub's own order, two or more is the council. An app with no entry follows the default; the
/// hub fills in Well and Wealth as `ollama` (private) until the person says otherwise.
public struct AnswerSettings: Codable, Equatable, Sendable {
    public struct Engine: Codable, Equatable, Sendable {
        public var available: Bool
        public var detail: String
        public init(available: Bool, detail: String = "") { self.available = available; self.detail = detail }
    }

    /// The engines a choice can name, in the order they are listed.
    public static let engineIds = ["claude", "codex", "gemini", "ollama"]
    public static let names = ["auto": "Auto", "claude": "Claude", "codex": "Codex", "gemini": "Gemini", "ollama": "Open model"]

    public var choice: [String]            // the family default
    public var apps: [String: [String]]    // per app (surface), as the hub resolves them
    public var surfaces: [String]
    public var privateApps: [String]
    public var engines: [String: Engine]
    public var councilAvailable: Bool

    public init(choice: [String] = ["auto"], apps: [String: [String]] = [:], surfaces: [String] = [], privateApps: [String] = [],
                engines: [String: Engine] = [:], councilAvailable: Bool = false) {
        self.choice = choice; self.apps = apps; self.surfaces = surfaces; self.privateApps = privateApps
        self.engines = engines; self.councilAvailable = councilAvailable
    }

    /// The hub's GET /native/settings reply (also what PUT returns); nil when it is not one.
    public static func decode(_ data: Data) -> AnswerSettings? {
        struct Wire: Decodable {
            struct Answers: Decodable { var `default`: [String]?; var apps: [String: [String]]? }
            struct Council: Decodable { var available: Bool? }
            var answers: Answers?; var engines: [String: Engine]?; var council: Council?; var surfaces: [String]?; var `private`: [String]?
        }
        guard let w = try? JSONDecoder().decode(Wire.self, from: data), let a = w.answers, let d = a.default, !d.isEmpty else { return nil }
        return AnswerSettings(choice: d, apps: a.apps ?? [:], surfaces: w.surfaces ?? [], privateApps: w.private ?? [],
                              engines: w.engines ?? [:], councilAvailable: w.council?.available ?? false)
    }

    /// What answers this app: its own entry, else the default.
    public func choice(for surface: String) -> [String] { apps[surface].flatMap { $0.isEmpty ? nil : $0 } ?? choice }

    /// How long a chat turn waits for the hub: the council is slow, a single engine is not.
    public static func timeout(for choice: [String]) -> TimeInterval { choice.count > 1 ? 120 : 20 }

    /// "Auto", "Claude", "Open model", "Council: Claude, Codex".
    public static func words(_ choice: [String]) -> String {
        let n = choice.map { names[$0] ?? $0.capitalized }
        return n.count > 1 ? "Council: " + n.joined(separator: ", ") : n.first ?? "Auto"
    }

    /// The reply's `answered_by` in words: "Claude", "Council: Claude, Codex", "Claude (Codex was not available)".
    public static func words(by: String) -> String {
        if by.hasPrefix("council("), by.hasSuffix(")") {
            return words(by.dropFirst(8).dropLast().split(separator: ",").map(String.init))
        }
        guard let open = by.firstIndex(of: " "), by.hasSuffix(")") else { return words([by]) }
        let note = by[by.index(open, offsetBy: 2)..<by.index(before: by.endIndex)]
        let why = note.hasSuffix(" unavailable") ? "\(words([String(note.dropLast(12))])) was not available" : "no council on the vault computer"
        return "\(words([String(by[..<open])])) (\(why))"
    }

    // MARK: Kept on this phone (the App Group), so the chat knows how long to wait without asking first.

    static let key = "answerSettings"
    static let at = "answerSettingsAt"
    static var suite: UserDefaults { UserDefaults(suiteName: "group.dev.fru.glyph") ?? .standard }

    /// The last settings the hub gave this device.
    public static var cached: AnswerSettings? {
        get { suite.data(forKey: key).flatMap { try? JSONDecoder().decode(AnswerSettings.self, from: $0) } }
        set { suite.set(newValue.flatMap { try? JSONEncoder().encode($0) }, forKey: key); suite.set(Date.now, forKey: at) }
    }
    /// True when the cache is missing or older than ten minutes.
    public static var stale: Bool { cached == nil || Date.now.timeIntervalSince(suite.object(forKey: at) as? Date ?? .distantPast) > 600 }
}

extension Hub {
    /// The settings as the hub has them now, kept for the chat's timeout. Nil when the hub can't be reached
    /// or is an older one without the route.
    public func fetchAnswers() async -> AnswerSettings? {
        guard let (code, data) = await send("GET", "native/settings"), code == 200, let got = AnswerSettings.decode(data) else { return nil }
        AnswerSettings.cached = got
        return got
    }

    /// Saves the family default and the apps' own choices, and returns what the hub read back (nil: not saved).
    public func saveAnswers(choice: [String], apps: [String: [String]]) async -> AnswerSettings? {
        let body: [String: Any] = ["answers": ["default": choice, "apps": apps]]
        guard let data = try? JSONSerialization.data(withJSONObject: body),
              let (code, reply) = await send("PUT", "native/settings", body: data), code == 200, let got = AnswerSettings.decode(reply) else { return nil }
        AnswerSettings.cached = got
        return got
    }
}
