import SwiftUI
import AppKit
import NativeKit

/// Glyph Labs on the Mac: every Glyph app, whether it is here and how new, and one button
/// to install or update them all from this repo (scripts/install-all.sh). No App Store, no TestFlight.
@main
struct GlyphNativeApp: App {
    @NSApplicationDelegateAdaptor private var delegate: Delegate
    @StateObject private var shelf = Shelf()
    @StateObject private var today = Today()
    var body: some Scene {
        WindowGroup("Glyph Labs") {
            RootView()
                .environmentObject(shelf).environmentObject(today)
                .frame(minWidth: Shelf.releaseMode ? 1040 : 940, minHeight: Shelf.releaseMode ? 680 : 620).tint(.nativeGreen)
                .task { shelf.refresh(); shelf.fetch(); today.refresh(); UITest.shelf = shelf; UITest.today = today }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in shelf.refresh(); today.refresh() }
                .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in today.refresh() }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: Shelf.releaseMode ? 1280 : 1180, height: Shelf.releaseMode ? 820 : 860)
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

/// What is on this Mac and what this repo can build.
@MainActor
final class Shelf: ObservableObject {
    struct Row: Identifiable {
        let app: FamilyApp
        var installed: String?      // version in /Applications
        var here: String?           // version this repo builds (VERSION= in its build.sh)
        var path: URL?
        var release = false         // public build: `here` is the newest GitHub release, not a repo's main
        var looked = false          // release mode: GitHub has been asked
        var id: String { app.id }
        var canInstall: Bool { release ? here != nil && hasDownload : app.folder != nil && here != nil && !app.ownInstall }
        var released: ReleasedApp? { release ? Release.apps.first { $0.id == app.id } : nil }
        var hasDownload: Bool { !release || released?.hasDownload == true }
        var site: URL? { released?.site.flatMap { URL(string: $0) } }
        // A release is only an update when it is newer; a source build treats any difference as one.
        var needsUpdate: Bool {
            guard let i = installed, let h = here else { return false }
            return release ? Release.isNewer(h, than: i) : i != h
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

    /// This repo: baked in by scripts/build.sh; GLYPH_NATIVE_REPO overrides (the UI check).
    static var repo: URL? {
        if let r = ProcessInfo.processInfo.environment["GLYPH_NATIVE_REPO"] { return URL(filePath: r) }
        return (Bundle.main.object(forInfoDictionaryKey: "GlyphNativeRepo") as? String).map { URL(filePath: $0) }
    }
    /// No source checkout: the public build, which downloads signed releases instead of building.
    static var releaseMode: Bool { repo == nil }
    private var latest: [String: String] = [:]   // release mode: app id to newest release version
    private var looked = false
    static var apps: URL { URL(filePath: ProcessInfo.processInfo.environment["GLYPH_NATIVE_APPS"] ?? "/Applications") }

    func refresh() {
        rows = (Self.releaseMode ? Release.apps.map(\.family) : Family.apps).map { a in
            var r = Row(app: a)
            r.release = Self.releaseMode
            r.looked = looked
            if Self.releaseMode { r.here = latest[a.id] }
            if let b = a.macBundle, let url = installedURL(b) {
                r.path = url
                r.installed = Release.installedVersion(Self.info(url))
            }
            if let f = a.folder, let s = Self.mainFile("\(f)/scripts/build.sh"),
               let line = s.split(separator: "\n").first(where: { $0.hasPrefix("VERSION=") }) {
                r.here = line.dropFirst(8).trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
            }
            return r
        }
    }

    /// A file as origin/main has it (what Install builds), else as this checkout has it (the UI check's made-up repo).
    static func mainFile(_ rel: String) -> String? {
        guard let repo else { return nil }
        let p = Process()
        p.executableURL = URL(filePath: "/usr/bin/git")
        p.arguments = ["-C", repo.path, "show", "origin/main:\(rel)"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        if (try? p.run()) != nil {
            let data = out.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            if p.terminationStatus == 0 { return String(decoding: data, as: UTF8.self) }
        }
        return try? String(contentsOf: repo.appending(path: rel), encoding: .utf8)
    }

    /// Brings origin/main up to date in the background, then reads the versions again.
    func fetch() {
        if Self.releaseMode { fetchReleases(); return }
        guard let repo = Self.repo, ProcessInfo.processInfo.environment["GLYPH_NATIVE_SCRIPT"] == nil else { return }
        let p = Process()
        p.executableURL = URL(filePath: "/usr/bin/git")
        p.arguments = ["-C", repo.path, "fetch", "-q", "origin", "main"]
        p.terminationHandler = { _ in Task { @MainActor in self.refresh() } }
        try? p.run()
    }

    /// Asks GitHub for each app's newest tag: the redirect of /releases/latest, no API (it is rate limited).
    private func fetchReleases() {
        Task {
            var found: [String: String] = [:]
            await withTaskGroup(of: (String, String?).self) { g in
                for a in Release.apps where a.hasDownload {
                    g.addTask {
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

    /// Runs install-all.sh with these arguments, the output streamed into `log`.
    func run(_ title: String, _ args: [String]) {
        guard running == nil, Self.repo != nil || Self.releaseMode else { return }
        running = title
        lastResult = nil
        log = ""
        let p = Process()
        p.executableURL = URL(filePath: "/bin/zsh")
        let quoted = args.map { "'\($0)'" }.joined(separator: " ")
        let script: String
        if Self.releaseMode {
            // `args` are app ids. One app after another, past a failure, ending non-zero if any failed.
            script = "install-release.sh"
            let tool = Bundle.main.path(forResource: "install-release", ofType: "sh") ?? "install-release.sh"
            let team = Release.ownTeam().map { " --team '\($0)'" } ?? ""
            let lines = Release.apps.filter { args.contains($0.id) && $0.hasDownload }.map { a in
                "echo '== \(a.name)'; '\(tool)' --repo '\(a.repo!)' --asset '\(a.asset!)' --bundle '\(a.macBundle ?? "")' --apps '\(Self.apps.path)'\(team) || rc=1"
            }
            p.arguments = ["-c", "rc=0\n" + lines.joined(separator: "\n") + "\nexit $rc"]
        } else if let stand = ProcessInfo.processInfo.environment["GLYPH_NATIVE_SCRIPT"] {   // the UI check's stand-in installer
            script = stand
            p.arguments = ["-lc", "'\(stand)' \(quoted)"]
        } else {
            // Always what is on main: a fresh worktree of origin/main, built from and then removed, never this checkout.
            let repo = Self.repo!
            script = "install-all.sh from a fresh checkout of origin/main"
            p.arguments = ["-lc", """
                set -e
                git -C '\(repo.path)' fetch -q origin main
                t=$(mktemp -d /tmp/glyph-native-main.XXXXXX)
                trap 'git -C "\(repo.path)" worktree remove --force "$t" 2>/dev/null; rm -rf "$t"' EXIT
                git -C '\(repo.path)' worktree add -q --detach "$t" origin/main
                echo "Building from origin/main at $(git -C "$t" log -1 --format='%h %s')"
                "$t/Launcher/scripts/install-all.sh" \(quoted)
                """]
        }
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
        if Self.releaseMode { run(missing > 0 ? "Installing" : "Updating", rows.filter { $0.canInstall && ($0.installed == nil || $0.needsUpdate) }.map(\.app.id)); return }
        run(missing > 0 ? "Installing" : "Updating", ["--mac", "--skip", "Launcher"])
    }
    func install(_ r: Row) {
        if Self.releaseMode { run("Installing \(r.app.name)", [r.app.id]); return }
        if let f = r.app.folder { run("Installing \(r.app.name)", ["--mac", "--only", f]) } }
    func installPhone() { run("Installing on the iPhone", ["--iphone"]) }
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


/// The whole window: one column. The date, what is being timed, then every app in the family as a
/// card that carries its own live fact and its one button. An app appears once (Today and Your apps
/// used to list the same apps side by side, with two sets of icons and nothing gained).
struct ShelfView: View {
    @EnvironmentObject var shelf: Shelf
    @EnvironmentObject var today: Today
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                if !Shelf.releaseMode { Hero() }
                apps
                if !Shelf.releaseMode { iphone }
                if shelf.running != nil || shelf.lastResult != nil { LogPanel() }
            }
            .padding(.horizontal, 36).padding(.top, 44).padding(.bottom, 40)
            .frame(maxWidth: 1240).frame(maxWidth: .infinity)   // centred on a wide window, never pinned left
        }
        .scrollEdgeEffectHidden(true, for: .all)
        .background(Token.ground.ignoresSafeArea())
        // The title bar is hidden, so scrolled content would run under the window's own buttons:
        // it fades out into the background before it reaches them.
        .overlay(alignment: .top) {
            let bg = Token.ground
            LinearGradient(stops: [.init(color: bg, location: 0), .init(color: bg, location: 0.6), .init(color: bg.opacity(0), location: 1)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 54).allowsHitTesting(false).ignoresSafeArea()
        }
        .sheet(isPresented: $shelf.showSettings) { SettingsSheet() }
        .onAppear { UITest.openSettings = { shelf.showSettings = $0 } }
    }

    /// The family's one top line: which app, and which page, on the same line, with one control
    /// in the corner. Every Glyph phone screen has read this way since 2026-11-10 ("I don't want
    /// to have a separate line for the title of the page... keep this as a design principle going
    /// forward for all the mobile pages, regardless of the app"), and the Mac was the last screen
    /// still opening with a bare 30pt title of its own and no word of which app you were in.
    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            if let img = Bundle.main.image(forResource: "icon-native") ?? Bundle.main.image(forResource: "mark-jot") {
                Image(nsImage: img).resizable().frame(width: 20, height: 20)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 4 }
            }
            Text("Glyph Native").font(.system(size: 17, weight: .medium)).foregroundStyle(Token.quiet)
            Text("·").font(.system(size: 17)).foregroundStyle(Token.quiet)
            Text(Shelf.releaseMode ? "Apps" : "Today").font(.system(size: 17, weight: .bold)).foregroundStyle(Token.text)
            Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                .font(.system(size: 13)).foregroundStyle(Token.quiet).padding(.leading, 6)
            Spacer(minLength: 8)
            Button { shelf.showSettings = true } label: { Image(systemName: "gearshape").font(.system(size: 17)) }
                .buttonStyle(.borderless).help("Settings").testFrame("settings")
        }
    }

    /// Every app in the family, in the family's order: a card never moves because its number came and went.
    private var apps: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("Your apps").font(.system(size: 11.5, weight: .semibold)).tracking(0.6)
                    .textCase(.uppercase).foregroundStyle(Token.accentLight).fixedSize()
                Text(count).font(.system(size: 11.5, weight: .semibold)).tracking(0.6)
                    .textCase(.uppercase).foregroundStyle(Token.headingMeta).lineLimit(1)
                Spacer(minLength: 8)
                if let t = shelf.running {
                    HStack(spacing: 8) { ProgressView().controlSize(.small); Text(t).foregroundStyle(.secondary).lineLimit(1) }.fixedSize()
                } else if shelf.missing > 0 || shelf.stale > 0 {
                    Button(shelf.missing > 0 ? "Install All" : "Update All") { shelf.installAll() }
                        .buttonStyle(.borderedProminent).controlSize(.large).fixedSize()
                        .testFrame("installAll")
                }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 268, maximum: 460), spacing: 14)], alignment: .leading, spacing: 14) {
                ForEach(shelf.rows) { AppCard(row: $0) }
            }
        }
    }

    /// "11 apps", and what is waiting, so the green button at the right is never the only hint.
    private var count: String {
        let apps = shelf.rows.count
        var s = "\(apps) apps"
        if shelf.missing > 0 { s += ", \(shelf.missing) to install" }
        if shelf.stale > 0 { s += ", \(shelf.stale) to update" }
        return s
    }

    private var iphone: some View {
        HStack(spacing: 14) {
            Image(systemName: "iphone").font(.system(size: 20)).foregroundStyle(Color.nativeGreen).frame(width: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text("iPhone").font(.system(size: 15, weight: .semibold)).foregroundStyle(Token.text).lineLimit(1)
                Text("Every app with an iPhone version, over the same Wi-Fi or a cable")
                    .font(.system(size: 12.5)).foregroundStyle(Token.quiet).lineLimit(1)
            }
            Spacer(minLength: 8)
            Button("Install on iPhone") { shelf.installPhone() }.fixedSize()
                .disabled(shelf.running != nil || Shelf.repo == nil).testFrame("installPhone")
                .help("Every app with an iPhone version, by cable or the same Wi-Fi, iPhone unlocked")
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
        .glyphCard()
    }

}

/// The install log panel, shared by both windows.
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

/// One app: its mark, what it is for, its one live fact, the version, and a single button that says
/// what is to be done (Install, Update, or Open). The card itself opens the app.
struct AppCard: View {
    @EnvironmentObject var shelf: Shelf
    @EnvironmentObject var today: Today
    let row: Shelf.Row
    @State private var hover = false

    private var here: Bool { row.path != nil }
    private var short: String { row.app.name.replacingOccurrences(of: "Glyph ", with: "") }
    private var glance: Glance? { here ? today.glances[row.app.id] : nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                mark.frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .opacity(here ? 1 : 0.4)
                VStack(alignment: .leading, spacing: 2) {
                    Text(short).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                        .foregroundStyle(here ? Token.text : Token.quiet)
                    Text(row.app.job).font(.system(size: 12.5)).foregroundStyle(Token.quiet).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            Spacer(minLength: 8)
            HStack(alignment: .bottom, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    if let f = glance?.fact {
                        Text(f).font(.system(size: 19, weight: .semibold, design: .rounded).monospacedDigit())
                            .foregroundStyle(Token.text)
                            .lineLimit(1).minimumScaleFactor(0.8)
                    }
                    Text(status).font(.system(size: 11.5).monospacedDigit())
                        .foregroundStyle(row.needsUpdate ? Token.accentLight : Token.faint).lineLimit(1)
                }
                Spacer(minLength: 4)
                action
            }
        }
        .padding(16)
        .frame(height: 120, alignment: .topLeading)
        .glyphCard(lifted: hover && here)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture { if here { shelf.open(row) } }
        .onHover { hover = $0 }
        .help(here ? glance?.detail.map { "\(row.app.name): \($0)" } ?? "Open \(row.app.name)" : "\(row.app.name) isn't on this Mac")
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(here ? .isButton : [])
        .testFrame("line.\(row.app.id)")
    }

    /// The family's own mark for every app (the same head as on the iPhone), dimmed when it isn't here.
    @ViewBuilder private var mark: some View {
        // The app's own icon, as the Home screen and the Apps page draw it. It drew `mark-`,
        // which is the head alone with the figure cut away: that asset is for a 36pt row, and on
        // a card it is a crop of the logo, not the logo (Fru, 2026-11-11, of the same defect on
        // the phone: "use the correct Glyph logos"). `icon-` is complete here for all eleven.
        if let img = Bundle.main.image(forResource: "icon-\(row.app.id)") ?? Bundle.main.image(forResource: "mark-\(row.app.id)") {
            Image(nsImage: img).resizable()
        } else if let p = row.path {
            Image(nsImage: NSWorkspace.shared.icon(forFile: p.path)).resizable()
        } else {
            RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color.nativeGreen.opacity(0.5))
        }
    }

    private var status: String {
        if row.release {
            switch (row.installed, row.here) {
            case let (i?, _) where row.needsUpdate: return "\(i) to \(row.here ?? "")"
            case let (i?, _): return i
            case (nil, _?): return "Not installed"
            case (nil, nil): return row.looked ? "Can't reach GitHub" : "Checking GitHub"
            }
        }
        return switch (row.installed, row.here) {
        case let (i?, h?) where i != h: "\(i) to \(h)"
        case let (i?, _): i
        case (nil, _?) where row.canInstall: "Not installed"
        case (nil, _): row.app.ownInstall ? "Not on this Mac" : "Coming"
        }
    }

    /// One button per card, never two: what is to be done now. The card itself is Open.
    @ViewBuilder private var action: some View {
        if row.canInstall && (row.installed == nil || row.needsUpdate) {
            Button(row.installed == nil ? "Install" : "Update") { shelf.install(row) }
                .tint(.nativeGreen).fixedSize()
                .disabled(shelf.running != nil).testFrame("install.\(row.app.id)")
        } else if here {
            Button("Open") { shelf.open(row) }.fixedSize().testFrame("open.\(row.app.id)")
        }
    }
}

extension View {
    /// Every panel in the window: the same quiet fill and hairline, a touch lighter under the pointer.
    func glyphCard(lifted: Bool = false) -> some View {
        background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(lifted ? Token.raisedLifted : Token.raised))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Token.hairline))
    }
}
