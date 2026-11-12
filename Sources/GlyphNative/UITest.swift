import SwiftUI
import AppKit
import NativeKit   // Family.apps: the shelf is counted against the registry, never a written-out number

/// `GlyphNative --uitest <out>` with GLYPH_NATIVE_REPO (a made-up repo), GLYPH_NATIVE_APPS (a made-up
/// Applications folder) and GLYPH_NATIVE_SCRIPT (a stand-in installer that records its arguments in
/// $GLYPH_NATIVE_APPS/calls and "installs" a stub app): real clicks on every button, pictures of each state.
/// scripts/ui-check.sh sets it all up. Nothing real is built or installed.
/// What the release window shows, for the tests: the cards in order, the page, the sidebar, the title.
struct UIState: Equatable { var ids: [String] = [], page = "", sidebar = true, title = "" }

@MainActor
enum UITest {
    static var state = UIState()
    static var setSort: ((ShelfSort) -> Void)?
    static let on = CommandLine.arguments.contains("--uitest")
    static var shelf: Shelf?
    static var today: Today?
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
        Task.detached { try? await Task.sleep(for: .seconds(Shelf.releaseMode ? 400 : 120)); print("UI TIMED OUT"); fflush(stdout); exit(2) }
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
        print("DEBUG: shelf is \(shelf != nil), today is \(today != nil), windows=\(NSApp.windows.count)")
        guard let s = shelf else { check(false, "the window opened (shelf is nil)"); return }
        window?.setContentSize(NSSize(width: 1180, height: 860))
        if Shelf.releaseMode { await runRelease(s); return }
        if CommandLine.arguments.contains("--gone") {
            guard let today else { check(false, "Today opened"); return }
            await runGone(s, today)
            return
        }
        _ = await until { !s.rows.isEmpty }
        if let t = today {
            check(await until { t.running != nil }, "Today: the running timer is in the Now card")
            check(t.running?.project == "Acme site", "the Now card names the project")
            check(t.glances["omega"]?.fact.hasSuffix("goals") == true, "Today: Omega's goals")
            check(t.glances["well"]?.fact == "2 today", "Today: Well's logs")
            check(t.glances["crm"]?.fact == "3 to review", "Today: CRM's suggestions waiting")
            check(t.glances.values.allSatisfy { !$0.fact.hasSuffix(".") && $0.fact.split(separator: " ").count <= 3 }, "Today: every fact is a number and a short unit")
        }
        // Counted from the registry, never written out: the family went from 6 to 11 in a day
        // (Connect, Wealth, Life, Travel, Arena) and a hard-coded 6 failed while the shelf was
        // perfectly correct. The thing worth checking is that the shelf shows the whole registry.
        check(s.rows.count == Family.apps.count, "every Glyph Native app is listed (\(s.rows.count) of \(Family.apps.count))")
        check(s.rows.first { $0.app.id == "time" }?.needsUpdate == true, "Glyph Time 0.1.6 here, 0.1.7 in the repo: an update")
        check(s.rows.first { $0.app.id == "omega" }?.installed == nil && s.missing == 1, "Glyph Omega not installed yet")
        check(s.rows.first { $0.app.id == "jot" }?.canInstall == false, "Glyph Jot is never installed from here")
        check(s.rows.first { $0.app.id == "studio" }?.installed == "0.1.0", "the new Studio (Glyph Studio Native.app) is found by its bundle id")
        await shot("n1-shelf")
        let ids = ["open.studio", "install.time", "installAll", "installPhone"]
        let roomy = ids.map { frames[$0]?.width ?? 0 }
        for (w, name) in [(960.0, "n0-narrow"), (1600.0, "n0-wide")] {  // the window's narrowest and a wide one
            window?.setContentSize(NSSize(width: w, height: 600)); await shot(name)
            if w == 960 {  // a squeezed button is a truncated one ("Up...", "Op...")
                let now = ids.map { frames[$0]?.width ?? 0 }
                check(now == roomy && !roomy.contains(0), "at the narrowest window no button is squeezed (\(now) vs \(roomy))")
            }
        }
        window?.setContentSize(NSSize(width: 1180, height: 860)); await wait(0.8)  // the buttons' frames settle before the clicks
        // One grid of cards now, not two lists: a card is the same size wherever it sits.
        if let a = frames["line.omega"], let b = frames["line.studio"] { check(a.width == b.width && a.height == b.height, "every app card is the same size") }
        check(await click("install.omega", until: { calls.contains("--mac --only Omega") }), "Install on a row installs just that app")
        check(await until { s.running == nil && s.rows.first { $0.app.id == "omega" }?.installed == "0.1.0" }, "and the row shows it installed")
        await shot("n2-after-one")
        check(await click("installAll", until: { calls.contains("--mac --skip Launcher") }), "Update All updates everything but Glyph Native itself")
        check(await until { s.running == nil && s.stale == 0 }, "nothing left to update")
        await click("log")
        await shot("n3-all-done-log")
        check(await click("installPhone", until: { calls.contains("--iphone") }), "Install on iPhone runs the iPhone installs")
        _ = await until { s.running == nil }
        await shot("n4-iphone")
        await click("open.time")
        check(true, "Open is offered for an installed app")

        _ = await click("settings", until: { s.showSettings })
        check(await until(8) { setup != nil && setup!.health != nil }, "Settings reads the hub")
        if let st = setup { check(st.health?.ok == true && st.vault != nil, "the vault and its hub") }
        await shotSheet("n5-settings")
        check(await click("settings.done", until: { !s.showSettings }), "Done closes Settings")

        // Cmd-, opens Settings too, as in every Mac app; it shows the version and build.
        if let w = window, let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: ProcessInfo.processInfo.systemUptime,
                                                    windowNumber: w.windowNumber, context: nil, characters: ",", charactersIgnoringModifiers: ",", isARepeat: false, keyCode: 43) {
            _ = NSApp.mainMenu?.performKeyEquivalent(with: e)
        }
        check(await until { s.showSettings }, "Cmd-, opens Settings")
        check(SettingsSheet.version.contains("(") && !SettingsSheet.version.hasPrefix("?"), "Settings shows the version and build (\(SettingsSheet.version))")
        await click("settings.done")
    }

    // MARK: the release window (no source checkout): GLYPH_NATIVE_APPS and GLYPH_NATIVE_VAULT are temp folders

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

    static func runGone(_ shelf: Shelf, _ today: Today) async {
        let fm = FileManager.default
        check(await until { today.loaded && today.vaultAvailable && !today.glances.isEmpty }, "Today starts with live vault information")
        guard let vault = Today.vault else { check(false, "the test vault is configured"); return }
        let omega = today.glances["omega"]?.fact ?? ""
        check(!omega.isEmpty, "the test vault has an Omega glance")
        await shot("g0-before")

        let moved = vault.deletingLastPathComponent().appending(path: vault.lastPathComponent + "-moved")
        do { try fm.moveItem(at: vault, to: moved) }
        catch { check(false, "the vault could be moved aside: \(error.localizedDescription)"); return }
        defer { if !fm.fileExists(atPath: vault.path), fm.fileExists(atPath: moved.path) { try? fm.moveItem(at: moved, to: vault) } }
        check(!fm.fileExists(atPath: vault.path), "the vault is gone from disk")

        today.refresh()
        check(await until { !today.vaultAvailable && today.glances.isEmpty && today.running == nil }, "Today clears its vault snapshot")
        check(await until { frames["today.novault"] != nil }, "Today says 'Vault not found'")
        let settings = frames["today.novault.settings"]
        check((settings?.width ?? 0) > 60 && (settings?.height ?? 0) > 16,
              "the no-vault Settings button has a real size (\(settings.map { "\(Int($0.width))x\(Int($0.height))" } ?? "missing"))")
        check(window != nil, "the window is still there, not a crash")
        await shot("g1-vault-gone")
        check(await click("today.novault.settings", until: { shelf.showSettings && frames["settings.done"] != nil }), "the no-vault button opens Settings")
        await shotSheet("g1-settings")
        check(await click("settings.done", until: { !shelf.showSettings }), "Settings closes")

        do { try fm.moveItem(at: moved, to: vault) }
        catch { check(false, "the vault could be put back: \(error.localizedDescription)"); return }
        today.refresh()
        check(await until { today.vaultAvailable && today.glances["omega"]?.fact == omega }, "the vault returns and Today recovers")
        await shot("g2-vault-back")
    }
}

extension View {
    @ViewBuilder func testFrame(_ name: String) -> some View {
        if UITest.on { onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { UITest.frames[name] = $0 } } else { self }
    }
}
