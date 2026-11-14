import SwiftUI
import AppKit
import NativeKit

/// Glyph Native on the Mac: every Glyph app, whether it is here and how new, and one button to
/// install or update each from its signed release. Building the apps from source inside this app
/// (Install All, "Glyph Labs") was retired on 2026-11-13, when each app got its own repo.
@main
struct GlyphNativeApp: App {
    @NSApplicationDelegateAdaptor private var delegate: Delegate
    @StateObject private var shelf = Shelf()
    /// Never restore windows from the last run: this app has one window and always opens it. macOS
    /// keys saved windows on the scene's view type, so when that type changed (2026-11-13, the
    /// source build's window removed) the packaged app restored nothing and opened no window at
    /// all, which to someone updating is an app that will not launch. Measured: 0 windows without
    /// this, 1 with it; setting NSQuitAlwaysKeepsWindows here did nothing. A debug binary has no
    /// bundle id and so never showed it.
    init() { UserDefaults.standard.register(defaults: ["ApplePersistenceIgnoreState": true]) }
    var body: some Scene {
        WindowGroup("Glyph Native") {
            RootView()
                .environmentObject(shelf)
                .frame(minWidth: 1040, minHeight: 680).tint(.nativeGreen)
                .task { shelf.refresh(); shelf.fetch(); UITest.shelf = shelf }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in shelf.refresh() }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 820)
        .commands {
            CommandGroup(replacing: .appSettings) { Button("Settings…") { shelf.showSettings = true }.keyboardShortcut(",") }
        }
    }
}

final class Delegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ n: Notification) {
        if UITest.on { UITest.start() }
        // `GlyphNative --picture <folder>`: the window as it opens, saved as window.png, then quit (the site's screenshot).
        if let i = CommandLine.arguments.firstIndex(of: "--picture"), i + 1 < CommandLine.arguments.count {
            UITest.out = URL(fileURLWithPath: CommandLine.arguments[i + 1])
            // `--appearance light|dark` (with --picture only): force the system look for the picture.
            if let a = PictureArgs.value("--appearance") { NSApp.appearance = NSAppearance(named: a == "dark" ? .darkAqua : .aqua) }
            // `--size 1040x680` (with --picture only): the window at that content size, for the minimum-size picture.
            let size = CommandLine.arguments.firstIndex(of: "--size").flatMap { j in
                j + 1 < CommandLine.arguments.count ? CommandLine.arguments[j + 1].split(separator: "x").compactMap { Double($0) } : nil }
            Task {
                if let size, size.count == 2 { try? await Task.sleep(for: .seconds(1.5)); UITest.window?.setContentSize(NSSize(width: size[0], height: size[1])) }
                // `--do install:<id>` / `--do uninstall:<id>` run the buttons' own code after 2s; `--after <s>` times the picture.
                if let d = CommandLine.arguments.firstIndex(of: "--do").map({ CommandLine.arguments[$0 + 1] }) {
                    try? await Task.sleep(for: .seconds(2))
                    await MainActor.run {
                        let p = d.split(separator: ":").map(String.init)
                        if p.count == 2, let sh = UITest.shelf, let r = sh.rows.first(where: { $0.app.id == p[1] }) {
                            if p[0] == "install" { sh.install(r) } else { sh.uninstall(r, confirm: false) }
                        }
                    }
                }
                let after = CommandLine.arguments.firstIndex(of: "--after").flatMap { Double(CommandLine.arguments[$0 + 1]) } ?? 6
                try? await Task.sleep(for: .seconds(after)); UITest.picture("window", UITest.window); exit(0) }
        }
        // `GlyphNative --rows`: what the window would list (installed version, version on main), then quit.
        if CommandLine.arguments.contains("--rows") {
            MainActor.assumeIsolated {
                let s = Shelf(); s.refresh()
                for r in s.rows { print("\(r.app.name)\t\(r.installed ?? "-")\t\(r.here ?? "-")\t\(r.path?.path ?? "")") }
            }
            exit(0)
        }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { true }
}

extension Color {
    static let nativeGreen = Color(NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        ? NSColor(red: 0.18, green: 0.68, blue: 0.18, alpha: 1) : NSColor(red: 0, green: 128 / 255, blue: 0, alpha: 1) })

    /// One token, two appearances: the family's Mac value in the dark, the Mac's own colour in the
    /// light. Light is held as it is until Fru says whether the launcher stays light at all.
    static func token(_ dark: NSColor, _ light: NSColor) -> Color {
        Color(NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light })
    }
}

extension NSColor {
    /// A token written the way the design system writes it: #1c1c1e.
    static func hex(_ v: Int) -> NSColor {
        NSColor(srgbRed: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255, alpha: 1)
    }
}

/// The family's Mac tokens, from the vault skill apply-glyph-app-design-system: the launcher is the
/// one screen where every app is seen at once, so a drift here reads as the family being inconsistent.
enum Token {
    static let ground = Color.token(.hex(0x1C1C1E), .windowBackgroundColor)
    static let raised = Color.token(.hex(0x232325), NSColor(calibratedWhite: 0, alpha: 0.04))
    static let raisedLifted = Color.token(.hex(0x2A2A2D), NSColor(calibratedWhite: 0, alpha: 0.075))
    static let hairline = Color.token(.hex(0x242427), NSColor(calibratedWhite: 0, alpha: 0.07))
    static let sunken = Color.token(.hex(0x141416), NSColor(calibratedWhite: 0, alpha: 0.05))
    static let text = Color.token(.hex(0xF5F5F7), .labelColor)
    static let quiet = Color.token(.hex(0x8E8E93), .secondaryLabelColor)
    static let faint = Color.token(.hex(0x6E6E73), .tertiaryLabelColor)
    /// Green on dark: section headings and what is waiting. Office green itself is too dark to read there.
    static let accentLight = Color.token(.hex(0x4AA96C), .hex(0x008000))
    // The release window's extra tokens (dark values from its approved artboard).
    static let sidebar = Color.token(.hex(0x161618), NSColor(calibratedWhite: 0, alpha: 0.035))
    static let border = Color.token(.hex(0x2C2C2E), NSColor(calibratedWhite: 0, alpha: 0.1))
    static let rowText = Color.token(.hex(0xE6E6EA), .labelColor)
    static let tint = Color.token(.hex(0x10240F), NSColor(srgbRed: 0, green: 0.5, blue: 0, alpha: 0.12))
    static let tintBorder = Color.token(.hex(0x27512F), NSColor(srgbRed: 0, green: 0.5, blue: 0, alpha: 0.3))
    static let tintText = Color.token(.hex(0x7FD49A), .hex(0x0A6B0A))
    static let headingMeta = Color.token(.hex(0x6A9E7A), .hex(0x4B7A58))
}

/// What is on this Mac and what is newest.
@MainActor
final class Shelf: ObservableObject {
    struct Row: Identifiable {
        let app: FamilyApp
        var installed: String?      // version in /Applications
        var here: String?           // the newest GitHub release
        var path: URL?
        var looked = false          // GitHub has been asked
        var retiredHere = false     // the earlier app this one replaces is installed (never touched)
        var id: String { app.id }
        var canInstall: Bool { here != nil && hasDownload }
        var released: ReleasedApp? { Release.apps.first { $0.id == app.id } }
        var hasDownload: Bool { released?.hasDownload == true }
        var site: URL? { released?.site.flatMap { URL(string: $0) } }
        // A release is only an update when it is newer.
        var needsUpdate: Bool {
            guard let i = installed, let h = here else { return false }
            return Release.isNewer(h, than: i)
        }
    }
    @Published var rows: [Row] = []
    @Published var running: String?          // what is being installed now
    @Published var log = ""
    @Published var lastResult: Bool?
    @Published var uiHover: String?          // a UI test's stand-in for the pointer resting on a card
    @Published var lastChecked: Date?        // when the last GitHub check finished
    @Published var showSettings = false      // the gear and Cmd-,
    @Published var notes: [String: String] = [:]   // app id to a short line on its card for a few seconds
    private var noteSeq: [String: Int] = [:]

    /// Shows `text` on the card for 4 seconds, then lets the card say what is true again.
    func say(_ id: String, _ text: String) {
        notes[id] = text; let n = (noteSeq[id] ?? 0) + 1; noteSeq[id] = n
        Task { try? await Task.sleep(for: .seconds(4)); if noteSeq[id] == n { notes[id] = nil } }
    }

    private var latest: [String: String] = [:]   // app id to newest release version
    private var looked = false
    static var apps: URL { URL(filePath: ProcessInfo.processInfo.environment["GLYPH_NATIVE_APPS"] ?? "/Applications") }

    func refresh() {
        rows = Release.apps.map(\.family).map { a in
            var r = Row(app: a)
            r.looked = looked
            r.here = latest[a.id]
            if r.app.macBundle != nil, let old = Release.apps.first(where: { $0.id == a.id })?.retiredBundle {
                r.retiredHere = installedURL(old) != nil
            }
            if let b = a.macBundle, let url = installedURL(b) {
                r.path = url
                r.installed = Release.installedVersion(Self.info(url))
            }
            return r
        }
    }

    /// Asks GitHub again for what is newest.
    func fetch() { fetchReleases() }

    /// Asks GitHub for each app's newest tag: the redirect of /releases/latest, no API (it is rate limited).
    private func fetchReleases() {
        Task {
            var found: [String: String] = [:]
            await withTaskGroup(of: (String, String?).self) { g in
                for a in Release.apps where a.hasDownload {
                    g.addTask {
                        if let v = a.versionURL {   // hosted on Glyph Native's repo: the version is a small text file
                            let text = (try? await URLSession.shared.data(from: v)).flatMap { String(data: $0.0, encoding: .utf8) }?.trimmingCharacters(in: .whitespacesAndNewlines)
                            return (a.id, text.flatMap { Release.numbers($0) == nil ? nil : $0 })
                        }
                        var req = URLRequest(url: a.latestURL!, timeoutInterval: 15)
                        req.httpMethod = "HEAD"
                        let url = (try? await URLSession.shared.data(for: req))?.1.url
                        return (a.id, url.flatMap(Release.tag(from:)))
                    }
                }
                for await (id, v) in g { if let v { found[id] = v } }
            }
            latest = found; looked = true; lastChecked = .now; refresh()
        }
    }

    private func installedURL(_ bundle: String) -> URL? {
        if ProcessInfo.processInfo.environment["GLYPH_NATIVE_APPS"] == nil, let u = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle),
           u.path.hasPrefix("/Applications"), Self.info(u) != nil { return u }   // LaunchServices keeps the path of an app already trashed
        let dir = Self.apps
        for name in (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [] where name.hasSuffix(".app") {
            let u = dir.appending(path: name)
            if Self.info(u)?["CFBundleIdentifier"] as? String == bundle { return u }
        }
        return nil
    }

    /// The app's Info.plist read fresh (Bundle caches it, so an update would still show the old version).
    static func info(_ app: URL) -> [String: Any]? {
        NSDictionary(contentsOf: app.appending(path: "Contents/Info.plist")) as? [String: Any]
    }

    var missing: Int { rows.filter { $0.canInstall && $0.installed == nil }.count }
    var stale: Int { rows.filter { $0.canInstall && $0.needsUpdate }.count }

    /// Installs these apps (ids) from their signed releases, one after another, the output streamed into `log`.
    func run(_ title: String, _ args: [String]) {
        guard running == nil else { return }
        running = title
        lastResult = nil
        log = ""
        let p = Process()
        p.executableURL = URL(filePath: "/bin/zsh")
        // `args` are app ids. One app after another, past a failure, ending non-zero if any failed.
        let script = "install-release.sh"
        let tool = Bundle.main.path(forResource: "install-release", ofType: "sh") ?? "install-release.sh"
        let team = Release.ownTeam().map { " --team '\($0)'" } ?? ""
        let lines = Release.apps.filter { args.contains($0.id) && $0.hasDownload }.map { a in
            "echo '== \(a.name)'; '\(tool)' --repo '\(a.repo!)' --asset '\(a.asset!)'\(a.tag.map { " --tag '\($0)'" } ?? "") --bundle '\(a.macBundle ?? "")' --apps '\(Self.apps.path)'\(team) || rc=1"
        }
        p.arguments = ["-c", "rc=0\n" + lines.joined(separator: "\n") + "\nexit $rc"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { h in
            let s = String(decoding: h.availableData, as: UTF8.self)
            if !s.isEmpty { Task { @MainActor in self.log += s } }
        }
        p.terminationHandler = { proc in
            Task { @MainActor in
                pipe.fileHandleForReading.readabilityHandler = nil
                self.lastResult = proc.terminationStatus == 0
                self.running = nil
                self.refresh()
            }
        }
        do { try p.run() } catch { log = "Couldn't start \(script): \(error.localizedDescription)"; running = nil; lastResult = false }
    }

    func installAll() {
        run(missing > 0 ? "Installing" : "Updating", rows.filter { $0.canInstall && ($0.installed == nil || $0.needsUpdate) }.map(\.app.id))
    }
    func install(_ r: Row) { run("Installing \(r.app.name)", [r.app.id]) }
    /// Moves an installed app to the Trash (recoverable) after one question; never a running app, never this one.
    func uninstall(_ r: Row, confirm: Bool = true) {
        guard running == nil, let url = r.path else { return }
        let name = r.app.name
        let verdict = Uninstall.check(installed: true,
            running: r.app.macBundle.map { !NSRunningApplication.runningApplications(withBundleIdentifier: $0).isEmpty } ?? false,
            bundle: r.app.macBundle, launcherBundle: Bundle.main.bundleIdentifier)
        switch verdict {
        case .launcher, .notInstalled: return
        case .running: say(r.app.id, "Quit \(name) first."); return
        case .allowed: break
        }
        if confirm {
            let a = NSAlert()
            a.messageText = "Move \(name) to the Trash?"
            a.informativeText = "Your vault and the app's data are not touched."
            a.addButton(withTitle: "Move to Trash"); a.addButton(withTitle: "Cancel")
            guard a.runModal() == .alertFirstButtonReturn else { return }
        }
        NSWorkspace.shared.recycle([url]) { _, error in
            Task { @MainActor in
                if let error {
                    self.log = "Couldn't move \(name) to the Trash: \(error.localizedDescription)"; self.lastResult = false
                } else {
                    self.say(r.app.id, "Moved to the Trash")   // the card is the not-installed card at once, no log panel
                }
                self.refresh()
            }
        }
    }
    func open(_ r: Row) { if let u = r.path { NSWorkspace.shared.openApplication(at: u, configuration: .init()) } }
}


/// The install log panel.
struct LogPanel: View {
    @EnvironmentObject var shelf: Shelf
    @State private var showLog = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                if let ok = shelf.lastResult {
                    Label(ok ? "Done" : "Failed", systemImage: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(ok ? Color.nativeGreen : .red).font(.headline)
                } else { Text("Working").font(.headline) }
                Spacer()
                Button(showLog ? "Hide Log" : "Show Log") { showLog.toggle() }.buttonStyle(.borderless).testFrame("log")
            }
            if showLog || shelf.lastResult == false {
                ScrollView {
                    Text(shelf.log.isEmpty ? " " : shelf.log).font(.system(size: 11, design: .monospaced)).frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(height: 170)
                .padding(10).background(RoundedRectangle(cornerRadius: 10).fill(Token.sunken))
            }
        }
        .padding(18)
        .glyphCard()
    }
}

extension View {
    /// Every panel in the window: the same quiet fill and hairline, a touch lighter under the pointer.
    func glyphCard(lifted: Bool = false) -> some View {
        background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(lifted ? Token.raisedLifted : Token.raised))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Token.hairline))
    }
}
