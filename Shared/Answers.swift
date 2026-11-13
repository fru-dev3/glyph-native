import Foundation
import SwiftUI

/// "Answers come from" for both Glyph Native apps: reads the choice from the vault computer, changes it, and shows
/// only what the vault computer sent back. Nothing here is shown that was not read back (no guesses while away).
@MainActor
public final class AnswersModel: ObservableObject {
    /// What the vault computer last said; nil until it has been reached.
    @Published public private(set) var settings: AnswerSettings?
    /// True when the vault computer could not be reached on the last try.
    @Published public private(set) var away = false
    @Published public private(set) var busy = false
    @Published public private(set) var saveFailed = false
    private let hub: Hub

    public init(base: URL?, model: String) { hub = Hub(base: base, model: model) }

    /// The apps that chat, in the catalog's order and with its names (Glyph Native first); one the vault computer
    /// lists that is not in the catalog follows. Before the vault computer has answered, the catalog's own list.
    public var apps: [(id: String, name: String)] {
        let catalog = [("native", "Glyph Native")] + Family.apps.filter { $0.id != "arena" }.map { ($0.id, $0.name) }
        guard let s = settings else { return catalog }
        return catalog.filter { s.surfaces.contains($0.0) } + s.surfaces.filter { id in !catalog.contains { $0.0 == id } }.map { ($0, "Glyph " + $0.capitalized) }
    }

    /// An SF Symbol for each choice (no vendor logos).
    public static func symbol(_ id: String) -> String {
        ["auto": "wand.and.stars", "claude": "sparkle", "codex": "curlybraces", "gemini": "diamond", "ollama": "cpu"][id] ?? "circle"
    }

    /// "The council answers: Claude and Open model. Slower, and in words only." (empty with one ticked)
    public var councilBanner: String {
        guard let c = settings?.choice, c.count > 1 else { return "" }
        let n = c.map { AnswerSettings.names[$0] ?? $0 }
        let list = n.count == 2 ? n.joined(separator: " and ") : n.dropLast().joined(separator: ", ") + " and " + n.last!
        return "The council answers: \(list). Slower, and in words only."
    }

    public func load() async {
        busy = true; defer { busy = false }
        if let got = await hub.fetchAnswers() { settings = got; away = false } else { away = true; settings = nil }
    }

    public var enabled: Bool { settings != nil && !away && !busy }

    // MARK: The choices

    /// The choice after one tick: Auto stands alone; an engine ticked on Auto replaces it; none left means Auto.
    public static func toggled(_ current: [String], _ id: String) -> [String] {
        if id == "auto" { return ["auto"] }
        var set = current.filter { $0 != "auto" }
        if let i = set.firstIndex(of: id) { set.remove(at: i) } else { set.append(id) }
        let ordered = AnswerSettings.engineIds.filter(set.contains)
        return ordered.isEmpty ? ["auto"] : ordered
    }

    public func available(_ id: String) -> Bool { id == "auto" || settings?.engines[id]?.available == true }

    /// The line under an engine that is not there: "Not on your vault computer".
    public static let missing = "Not on your vault computer"

    public func tick(_ id: String) async {
        guard let s = settings, available(id) || s.choice.contains(id) else { return }
        await save(choice: Self.toggled(s.choice, id), apps: stored(s))
    }

    /// One app's own choice (a single engine or Auto), or nil to follow the default.
    public func setApp(_ app: String, to id: String?) async {
        guard let s = settings else { return }
        var apps = stored(s)
        if let id { apps[app] = [id] } else { apps[app] = nil }
        await save(choice: s.choice, apps: apps)
    }

    /// The apps' own entries as they go back: the private defaults the hub filled in stay the hub's.
    private func stored(_ s: AnswerSettings) -> [String: [String]] {
        s.apps.filter { !(s.privateApps.contains($0.key) && $0.value == ["ollama"]) }
    }

    private func save(choice: [String], apps: [String: [String]]) async {
        busy = true; saveFailed = false
        if let got = await hub.saveAnswers(choice: choice, apps: apps) { settings = got; away = false }
        else { saveFailed = true; if let again = await hub.fetchAnswers() { settings = again } else { away = true; settings = nil } }
        busy = false
    }

    // MARK: Words

    public var defaultWords: String { settings.map { AnswerSettings.words($0.choice) } ?? "" }
    public var severalTicked: Bool { (settings?.choice.count ?? 0) > 1 }
    public static let intro = "Chats in every Glyph app use this unless the app has its own choice."
    public static let awayLine = "Can't reach your vault computer. Nothing can be changed here."

    /// What an app's menu shows: its own choice, "Follows default", or Well and Wealth's private default.
    public func appWords(_ id: String) -> String {
        guard let s = settings else { return "" }
        guard let own = s.apps[id] else { return "Follows default" }
        let words = AnswerSettings.words(own)
        return s.privateApps.contains(id) && own == ["ollama"] ? words + " (private by default)" : words
    }
    /// Whether the app has an entry of its own that is not the private default (the menu ticks that one).
    public func appChoice(_ id: String) -> String? {
        guard let s = settings, let own = s.apps[id], own.count == 1 else { return nil }
        return s.privateApps.contains(id) && own == ["ollama"] ? nil : own[0]
    }
    public func followsDefault(_ id: String) -> Bool { appChoice(id) == nil }
    /// "Follows default", or for Well and Wealth "Open model (private by default)" in that place.
    public func followLabel(_ id: String) -> String {
        settings?.privateApps.contains(id) == true ? "Open model (private by default)" : "Follows default"
    }
    /// Well and Wealth, while they still have the private default.
    public func isPrivate(_ id: String) -> Bool {
        guard let s = settings, s.privateApps.contains(id) else { return false }
        return s.apps[id] == ["ollama"]
    }
}
