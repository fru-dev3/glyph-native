import SwiftUI
import AppKit
import NativeKit   // Family.apps: the shelf is counted against the registry, never a written-out number

/// `GlyphNative --uitest <out>` with GLYPH_NATIVE_APPS, GLYPH_NATIVE_VAULT and GLYPH_NATIVE_ENV set to temp
/// folders: real clicks on every button, pictures of each state. scripts/ui-check.sh sets it all up.
/// What the release window shows, for the tests: the cards in order, the page, the sidebar, the title.
struct UIState: Equatable { var ids: [String] = [], page = "", sidebar = true, title = "" }

@MainActor
enum UITest {
    static var state = UIState()
    static var setSort: ((ShelfSort) -> Void)?
    static let on = CommandLine.arguments.contains("--uitest")
    static var shelf: Shelf?
    static var setup: Setup?
    static var openSettings: ((Bool) -> Void)?
    static var frames: [String: CGRect] = [:]
    static var failures = 0, passes = 0
    static var out = URL(fileURLWithPath: NSTemporaryDirectory())

    static func start() {
        guard let i = CommandLine.arguments.firstIndex(of: "--uitest") else { return }
        if i + 1 < CommandLine.arguments.count { out = URL(fileURLWithPath: CommandLine.arguments[i + 1]) }
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        if let a = CommandLine.arguments.firstIndex(of: "--appearance"), a + 1 < CommandLine.arguments.count {
            NSApp.appearance = NSAppearance(named: CommandLine.arguments[a + 1] == "dark" ? .darkAqua : .aqua)
        }
        Task.detached { try? await Task.sleep(for: .seconds(400)); print("UI TIMED OUT"); fflush(stdout); exit(2) }
        Task {
            await wait(1.5)
            NSApp.activate(ignoringOtherApps: true)
            for w in NSApp.windows { w.makeKeyAndOrderFront(nil) }
            await wait(1.0)
            await run()
            print(failures == 0 ? "UI ALL PASSED (\(passes) checks)" : "UI \(failures) FAILED, \(passes) passed")
            fflush(stdout)
            exit(failures == 0 ? 0 : 1)
        }
    }
    static func check(_ ok: Bool, _ what: String) { print(ok ? "  PASS  \(what)" : "  FAIL  \(what)"); fflush(stdout); if ok { passes += 1 } else { failures += 1 } }
    static func wait(_ s: Double) async { try? await Task.sleep(for: .seconds(s)) }
    static func until(_ limit: Double = 5, _ ok: () -> Bool) async -> Bool {
        for _ in 0..<Int(limit * 10) { if ok() { return true }; await wait(0.1) }
        return ok()
    }
    static var window: NSWindow? { NSApp.windows.first { $0.isVisible && $0.frame.width > 400 } }
    static var calls: String { (try? String(contentsOfFile: (ProcessInfo.processInfo.environment["GLYPH_NATIVE_APPS"] ?? "") + "/calls", encoding: .utf8)) ?? "" }

    static func click(_ name: String) async {
        for _ in 0..<30 { if frames[name] != nil { break }; await wait(0.05) }
        if !name.hasPrefix("settings.") { await reach(name) }
        let sheet = window?.attachedSheet
        let w0 = name.hasPrefix("settings.") ? (sheet ?? window) : window
        guard let f = frames[name], let w = w0, let v = w.contentView else { check(false, "the window shows '\(name)'"); return }
        // Other UI checks may share this Mac: take the front back before each click, as a person would.
        if !w.isKeyWindow || !NSApp.isActive { NSApp.activate(ignoringOtherApps: true); w.makeKeyAndOrderFront(nil); await wait(0.4) }
        let p = NSPoint(x: f.midX, y: v.bounds.height - f.midY)
        func ev(_ t: NSEvent.EventType) -> NSEvent? { NSEvent.mouseEvent(with: t, location: p, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: w.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) }
        if let up = ev(.leftMouseUp) { NSApp.postEvent(up, atStart: false) }
        if let down = ev(.leftMouseDown) { w.sendEvent(down) }
        await wait(0.5)
    }
    /// A picture of the app's own window from the window server (the view cache draws this window
    /// blank, as it does Glyph Well's). An app may picture its own windows without Screen Recording
    /// permission; the call is hidden from Swift since macOS 15, so it is looked up by name.
    typealias WindowImage = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
    static let windowImage: WindowImage? = dlsym(dlopen(nil, RTLD_NOW), "CGWindowListCreateImage").map { unsafeBitCast($0, to: WindowImage.self) }

    static func picture(_ name: String, _ w: NSWindow?) {
        guard let w, let grab = windowImage,
              let img = grab(.null, 1 << 3, UInt32(w.windowNumber), 1 | 1 << 3)?.takeRetainedValue() else { check(false, "picture \(name)"); return }
        try? NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])?.write(to: out.appendingPathComponent(name + ".png"))
    }

    /// A click, repeated until it takes. A synthesized click is swallowed now and then (the app has to
    /// be frontmost for AppKit to run its mouse loop, and another app can take the front at any moment),
    /// and a lost click used to read as a broken button. Three tries; a button that really does nothing
    /// still fails.
    static func click(_ name: String, until ok: @escaping () -> Bool, tries: Int = 3) async -> Bool {
        for n in 0..<tries {
            if ok() { return true }
            await click(name)
            if await until(4, ok) { return true }
            if n + 1 < tries {
                let f = frames[name].map { "\(Int($0.midX)),\(Int($0.midY)) \(Int($0.width))x\(Int($0.height))" } ?? "no frame"
                print("    (\(name) at \(f): the click was not taken (active \(NSApp.isActive), key \(window?.isKeyWindow ?? false)), trying again)")
                fflush(stdout)
            }
        }
        return false
    }

    static func shot(_ name: String) async {
        await wait(0.6)
        picture(name, window)
    }

    /// The sheet is its own window: picture that one.
    static func shotSheet(_ name: String) async {
        await wait(0.8)
        picture(name, NSApp.windows.first { $0.isVisible && $0.isSheet } ?? window?.attachedSheet)
    }

    /// The window scrolls now, so a control below the fold is brought into view before it is
    /// clicked: a click at a point outside the window lands nowhere and the check reads as a miss.
    static func reach(_ name: String) async {
        guard let f = frames[name], let v = window?.contentView else { return }
        guard f.maxY > v.bounds.height - 6 || f.minY < 6 else { return }
        guard let s = scrollView(v) else { return }
        let by = f.midY - v.bounds.height / 2
        let top = max(0, min(s.documentView.map { $0.bounds.height - s.contentView.bounds.height } ?? 0, s.contentView.bounds.origin.y + by))
        s.contentView.scroll(to: NSPoint(x: s.contentView.bounds.origin.x, y: top))
        s.reflectScrolledClipView(s.contentView)
        await wait(0.5)
    }

    static func scrollView(_ v: NSView) -> NSScrollView? {
        if let s = v as? NSScrollView { return s }
        for sub in v.subviews { if let s = scrollView(sub) { return s } }
        return nil
    }

    static func run() async {
        _ = await until(10) { shelf != nil }
        print("DEBUG: shelf is \(shelf != nil), windows=\(NSApp.windows.count)")
        guard let s = shelf else { check(false, "the window opened (shelf is nil)"); return }
        window?.setContentSize(NSSize(width: 1180, height: 860))
        await runRelease(s)
    }

    // MARK: the window: GLYPH_NATIVE_APPS and GLYPH_NATIVE_VAULT are temp folders

    static func type(_ text: String) -> Bool {
        guard let tv = window?.firstResponder as? NSTextView else { return false }
        tv.selectAll(nil)
        if text.isEmpty { tv.deleteBackward(nil) } else { tv.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0)) }
        return true
    }
    static func page(_ p: String) async -> Bool { await until(4) { state.page == p } }

    static func runRelease(_ s: Shelf) async {
        let apps = Release.apps
        let groupCount = { (g: String) in apps.filter { $0.group == g }.count }
        _ = await until(10) { s.rows.count == apps.count && state.ids.count == apps.count }
        await shot("r1-all")
        check(state.page == "apps" && state.ids.count == apps.count, "the window opens on all \(apps.count) apps")

        // Search: type, the cards filter, clearing restores.
        await click("search")
        check(type("jot"), "the search field takes typing")
        check(await until { state.ids == ["jot"] }, "searching 'jot' leaves Glyph Jot (\(state.ids))")
        await shot("r2-search")
        _ = type("zzzz")
        check(await until { state.ids.isEmpty }, "a query nothing matches leaves no cards")
        _ = type("")
        check(await until { state.ids.count == apps.count }, "clearing the search restores every card")

        // Sort. The menu itself is a tracking loop a synthesized click cannot drive, so the choice is set through the hook.
        let name = { (id: String) in apps.first { $0.id == id }?.name ?? id }
        for sort in ShelfSort.allCases {
            setSort?(sort); await wait(0.4)
            check(state.ids.count == apps.count, "sort \(sort.rawValue) keeps all \(apps.count) cards")
            switch sort {
            case .group: check(state.ids == ["Layers", "Tools", "Your life"].flatMap { g in apps.filter { $0.group == g }.map(\.id) }, "sort Group lists Layers, Tools, Your life")
            case .name: let n = state.ids.map(name); check(n == n.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }, "sort Name is alphabetical")
            case .status: let first = state.ids.prefix(apps.filter(\.hasDownload).count); check(first.allSatisfy { id in apps.first { $0.id == id }?.hasDownload == true }, "sort Status puts what can be installed first")
            }
        }
        setSort?(.group); await wait(0.3)

        // Every sidebar filter, by its count. Nothing is installed in the temp Applications folder.
        let down = apps.filter(\.hasDownload).count, coming = apps.filter { !$0.hasDownload && $0.site == nil }.count
        for (id, title, n) in [("filter.all", "All apps", apps.count), ("filter.installed", "Installed", 0), ("filter.updates", "Updates", 0),
                               ("filter.missing", "Not installed", down), ("filter.coming", "Coming", coming),
                               ("group.layers", "Layers", groupCount("Layers")), ("group.tools", "Tools", groupCount("Tools")), ("group.life", "Your life", groupCount("Your life"))] {
            await click(id)
            check(await until { state.title == title && state.ids.count == n }, "\(title) shows \(n) cards (\(state.title): \(state.ids.count))")
        }
        await click("filter.all")

        // Settings page, Check for updates, About.
        check(await click("settings", until: { state.page == "settings" }), "the Settings button opens the Settings page")
        await shot("r3-settings")
        let before = s.lastChecked
        await click("settings.check")
        check(await until(40) { s.lastChecked != nil && s.lastChecked != before }, "Check for updates runs and records the time")
        check(await click("settings.about", until: { state.page == "about" }), "Settings opens About")
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        check(SettingsSheet.version.hasPrefix(short) && short != "?", "About shows the version (\(SettingsSheet.version))")
        await shot("r4-about")
        check(await click("about.back", until: { state.page == "settings" }), "About goes back to Settings")

        // Sidebar collapse and expand, then the Vault page.
        await click("filter.all")
        check(await click("sidebar.toggle", until: { !state.sidebar }), "the sidebar collapses")
        await shot("r5-collapsed")
        check(await click("sidebar.toggle", until: { state.sidebar }), "the sidebar expands")
        check(await click("nav.vault", until: { state.page == "vault" }), "the Vault page opens")
        check(await until { frames["vault.again"] != nil }, "the Vault page shows its content")
        await shot("r6-vault")
        await click("filter.all")
        check(await page("apps"), "All apps returns from Vault")

        // The smallest download, Glyph Time: install, uninstall, install, with the real buttons.
        func row() -> Shelf.Row? { s.rows.first { $0.app.id == "time" } }
        func done() async -> Bool { await until(150) { s.running == nil && s.lastResult != nil } }
        check(await click("install.time", until: { s.running != nil || row()?.installed != nil }), "Install on Glyph Time starts")
        check(await done() && row()?.installed != nil, "Glyph Time is installed (\(s.lastResult == true ? "ok" : "failed: " + String(s.log.suffix(160))))")
        await shot("r7-installed")
        s.uiHover = "time"; await wait(0.5)
        // The question is a modal alert: only a timer in the common run-loop modes still fires while it is up.
        let press = Timer(timeInterval: 0.2, repeats: true) { t in
            if let m = NSApp.modalWindow, let b = m.defaultButtonCell { b.performClick(nil); t.invalidate() }
        }
        RunLoop.main.add(press, forMode: .common)
        await click("uninstall.time")
        press.invalidate()
        s.uiHover = nil
        check(await until(10) { row()?.installed == nil }, "the trash button, after its question, removes Glyph Time")
        s.lastResult = nil
        check(await click("install.time", until: { s.running != nil || row()?.installed != nil }), "Install on Glyph Time starts again")
        check(await done() && row()?.installed != nil, "Glyph Time is installed again")
        await shot("r8-reinstalled")
        if row()?.installed != nil { s.uninstall(row()!, confirm: false); _ = await until(10) { row()?.installed == nil } }   // leaves the temp folder as it was
    }

}

extension View {
    @ViewBuilder func testFrame(_ name: String) -> some View {
        if UITest.on { onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { UITest.frames[name] = $0 } } else { self }
    }
}
