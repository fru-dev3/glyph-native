import Foundation
import FoundationModels

/// Glyph Rig's agent: the person's machines, their drives, caches, speed and the rules he keeps about them.
/// The hub's planner reads these tools (`glyphcore-report agents`) and plans jobs for them; Glyph Rig on
/// the Mac runs each one itself, over the SSH it already uses, and every change waits for a yes there.
/// Called anywhere else (another app's chat, the iPhone), a tool does nothing on any machine: its card
/// opens Glyph Rig with the words, so the change is seen and approved where the machines are.
extension GlyphAgent {
    public static let rig = GlyphAgent(
        id: "rig", name: "Rig", color: "2F5D50",
        instructions: "You are Glyph Rig's agent, over the person's Macs and their drives. machine is the machine's id or name as the data shows it (laptop, studio). Looking costs nothing: machine_status for how a machine is doing, drive_contents for what fills a drive or folder (path is a mount like /Volumes/name, ~ for the home folder, or a folder). Changes are only proposed, the person approves each in Rig: clean_caches empties only caches that rebuild themselves (never their files), speed_test measures the internet, remember_rule keeps a rule or habit they state about their machines, drives or backups so they never have to say it again. Never invent a path or a machine.",
        tools: { hub, ledger in [RigTool(name: "machine_status", description: "How one machine is doing now: disk, memory, CPU, backups, security, network.", hub: hub, ledger: ledger),
                                    RigTool(name: "drive_contents", description: "What fills a drive or folder on a machine, biggest first. Read only.", hub: hub, ledger: ledger),
                                    RigTool(name: "clean_caches", description: "Propose emptying the caches that rebuild themselves on a machine (npm, uv, Homebrew, Xcode build products and the like). Waits for a yes.", hub: hub, ledger: ledger),
                                    RigTool(name: "speed_test", description: "Propose an internet speed test on a machine. Waits for a yes.", hub: hub, ledger: ledger),
                                    RigTool(name: "remember_rule", description: "Propose keeping a rule or habit about machines, drives or backups, in their words. Waits for a yes.", hub: hub, ledger: ledger)] },
        fallback: { job, _ in RigTool.handOff(job.instruction) })
}

/// One Rig tool. Its arguments cover all five (an empty one is not used); what it does is Rig's to do.
public struct RigTool: Tool {
    public let name: String
    public let description: String
    @Generable public struct Arguments {
        @Guide(description: "The machine's id or name, as the data shows it. Empty for remember_rule.") public var machine: String
        @Guide(description: "drive_contents only: a mount (/Volumes/name), ~, or a folder. Else empty.") public var path: String
        @Guide(description: "remember_rule only: the rule in their words. Else empty.") public var rule: String
    }
    let hub: Hub, ledger: Ledger
    public init(name: String, description: String, hub: Hub, ledger: Ledger) {
        self.name = name; self.description = description; self.hub = hub; self.ledger = ledger
    }
    public func call(arguments a: Arguments) async throws -> String {
        let what = [name.replacingOccurrences(of: "_", with: " "), a.machine, a.path, a.rule].filter { !$0.isEmpty }.joined(separator: " ")
        let d = Self.handOff(what); await ledger.add(d); return d.line
    }

    /// The card outside Rig: nothing done, a tap opens Rig's chat with the words.
    static func handOff(_ words: String) -> Done {
        var c = URLComponents(string: "glyph-rig://chat")!
        c.queryItems = [URLQueryItem(name: "say", value: words)]
        return Done(agent: "rig", line: "Open Glyph Rig on a Mac to do this: \(words)", title: words, ok: true, review: true, link: c.url)
    }
}
