import SwiftUI
import AppKit
import NativeKit
import GlyphVault

/// The Mac's Today: the same lines as the iPhone home, read straight from the vault's files
/// (Setup.vaultPath: where Glyph Bot's config says it is, GLYPH_NATIVE_VAULT in the UI check).
@MainActor
final class Today: ObservableObject {
    @Published var glances: [String: Glance] = [:]
    @Published var running: Running?
    @Published private(set) var loaded = false
    @Published private(set) var vaultAvailable = false
    private var readID = 0

    static var vault: URL? { Setup.vaultPath.map { URL(filePath: $0) } }

    func refresh() {
        readID += 1
        let id = readID
        guard let v = Self.vault else { clear(); return }
        Task.detached(priority: .utility) {
            let r = Self.read(v)
            await MainActor.run {
                guard self.readID == id else { return }
                guard let r else { self.clear(); return }
                self.glances = r.0
                self.running = r.1
                self.vaultAvailable = true
                self.loaded = true
            }
        }
    }

    private func clear() {
        glances = [:]
        running = nil
        vaultAvailable = false
        loaded = true
    }

    nonisolated static func read(_ v: URL) -> ([String: Glance], Running?)? {
        let fm = FileManager.default
        guard (try? fm.contentsOfDirectory(atPath: v.path)) != nil else { return nil }
        func files(_ rel: String, _ ext: String) -> [URL] {
            ((try? fm.contentsOfDirectory(at: v.appending(path: rel), includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.pathExtension == ext }.sorted { $0.path < $1.path }
        }
        func text(_ u: URL) -> String? { try? String(contentsOf: u, encoding: .utf8) }
        var g: [String: Glance] = [:]
        // Time: this month's and last month's sessions.
        let months = TimeLog.recentMonths()
        let timeData = files("data/apps/time/sessions", "jsonl").filter { months.contains(String($0.lastPathComponent.prefix(7))) }
            .compactMap { try? Data(contentsOf: $0) }.reduce(into: Data()) { $0.append($1); $0.append(10) }
        let t = Glances.time(timeData)
        g["time"] = t.glance
        // Omega: every domain's goals and tasks.
        var omega: [String: String] = [:]
        for d in (try? fm.contentsOfDirectory(atPath: v.appending(path: "data/domains").path)) ?? [] where !d.hasPrefix("_") && !d.hasPrefix(".") {
            for rel in ["source/goals.md", "memory/tasks.md"] {
                let p = "data/domains/\(d)/\(rel)"
                if let s = text(v.appending(path: p)) { omega[p] = s }
            }
        }
        g["omega"] = Glances.omega(omega)
        // Well: this month's entries.
        let month = TimeLog.month(.now)
        let entries = files("data/apps/well/entries", "jsonl").filter { $0.lastPathComponent.hasPrefix(month) }
            .compactMap(text).flatMap { $0.split(separator: "\n") }
            .compactMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any] }
        g["well"] = Glances.well(entries)
        // CRM: suggestions waiting.
        g["crm"] = Glances.crm(files("data/apps/crm/proposals", "jsonl").compactMap(text).flatMap { $0.split(separator: "\n").map(String.init) })
        // Arena: the routing policy Studio follows.
        if let p = try? Data(contentsOf: v.appending(path: "build/_meta/arena/policy.json")) { g["arena"] = Glances.arena(p) }
        guard (try? fm.contentsOfDirectory(atPath: v.path)) != nil else { return nil }
        return (g, t.running)
    }
}

/// The top of the window, one slot that always holds something: the clock while a timer runs, a
/// quiet line when none does, and the vault's own message when there is no vault to read.
struct Hero: View {
    @EnvironmentObject var shelf: Shelf
    @EnvironmentObject var today: Today

    var body: some View {
        if !today.loaded {
            HStack { Spacer(); ProgressView().controlSize(.small); Spacer() }
                .frame(height: 132).glyphCard()
        } else if !today.vaultAvailable {
            TodayNoVault { shelf.showSettings = true }
        } else if let r = today.running {
            MacNowCard(running: r)
                .onTapGesture { if let row = time { shelf.open(row) } }
                .testFrame("now")
        } else {
            idle
        }
    }

    private var time: Shelf.Row? { shelf.rows.first { $0.app.id == "time" && $0.path != nil } }

    /// Nothing running: the same card, quiet, so the window never jumps when a timer starts or stops.
    private var idle: some View {
        HStack(spacing: 14) {
            markTime.frame(width: 38, height: 38).clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text("Nothing is timing").font(.system(size: 15, weight: .semibold)).foregroundStyle(Token.text)
                Text((today.glances["time"]?.fact).map { "\($0), and the clock is stopped" } ?? "Start the clock in Glyph Time")
                    .font(.system(size: 12.5)).foregroundStyle(Token.quiet).lineLimit(1)
            }
            Spacer(minLength: 8)
            if let t = time { Button("Open Glyph Time") { shelf.open(t) }.fixedSize().testFrame("now.idle") }
        }
        .padding(.horizontal, 20).padding(.vertical, 18)
        .glyphCard()
        .testFrame("now.none")
    }

    @ViewBuilder private var markTime: some View {
        if let img = Bundle.main.image(forResource: "mark-time") { Image(nsImage: img).resizable() }
        else { RoundedRectangle(cornerRadius: 10).fill(Color.nativeGreen) }
    }
}

struct TodayNoVault: View {
    let settings: () -> Void
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "externaldrive.badge.questionmark").font(.system(size: 26)).foregroundStyle(Token.quiet).frame(width: 38)
            VStack(alignment: .leading, spacing: 3) {
                Text("Vault not found").font(.system(size: 15, weight: .semibold)).foregroundStyle(Token.text)
                Text("Today reads live information from your vault.").font(.system(size: 12.5)).foregroundStyle(Token.quiet).lineLimit(1)
            }
            Spacer(minLength: 8)
            Button("Open Settings", action: settings).fixedSize().testFrame("today.novault.settings")
        }
        .padding(.horizontal, 20).padding(.vertical, 18)
        .glyphCard()
        .testFrame("today.novault")
    }
}

/// What is being timed, live, as on the iPhone: the clock itself, what it is on, and the day's total.
struct MacNowCard: View {
    let running: Running
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let elapsed = ctx.date.timeIntervalSince(running.start)
            VStack(alignment: .leading, spacing: 6) {
                Text("Timing now").font(.system(size: 11.5, weight: .semibold)).tracking(0.6).textCase(.uppercase)
                    .foregroundStyle(.white.opacity(0.75))
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    Text(clock(elapsed)).font(.system(size: 48, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white)
                    Text(running.project).font(.system(size: 15.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9)).lineLimit(1)
                    Spacer(minLength: 16)
                    Text("today").font(.system(size: 11.5, weight: .semibold)).tracking(0.6).textCase(.uppercase)
                        .foregroundStyle(.white.opacity(0.75))
                    Text(hm(running.today + elapsed))
                        .font(.system(size: 26, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(.white).lineLimit(1)
                }
            }
            .padding(.horizontal, 24).padding(.vertical, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous).fill(
                    LinearGradient(colors: [Color(red: 0.05, green: 0.56, blue: 0.05), Color(red: 0, green: 0.39, blue: 0)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing))
            )
            .shadow(color: .black.opacity(0.2), radius: 12, y: 5)
        }
        .contentShape(Rectangle())
    }
    /// "2h 12m", as every card writes it; TimeLog.span writes "2 h 12 min", which reads as another app.
    private func hm(_ s: TimeInterval) -> String {
        let m = Int(max(0, s) / 60)
        return m < 60 ? "\(m)m" : m % 60 == 0 ? "\(m / 60)h" : "\(m / 60)h \(m % 60)m"
    }
    private func clock(_ s: TimeInterval) -> String { let t = Int(max(0, s)); return String(format: "%d:%02d:%02d", t / 3600, t / 60 % 60, t % 60) }
}
