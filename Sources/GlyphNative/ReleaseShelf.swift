import SwiftUI
import AppKit
import NativeKit

/// The public build's window: a plain 244pt sidebar (no NavigationSplitView: its glass is drawn outside
/// the view tree, where the --picture capture cannot see it) and the apps beside it.
struct ReleaseShelfView: View {
    @EnvironmentObject var shelf: Shelf
    @State private var filter: ShelfFilter = .all
    @State private var search = ""
    @State private var sort: ShelfSort = .group
    @FocusState private var searchFocused: Bool
    // A UI test keeps its own defaults, so it never writes the real window's choice.
    @AppStorage("sidebarShown", store: UITest.on ? UserDefaults(suiteName: "uitest.native") : nil) private var sidebarStored = true
    // `--sidebar hidden` with --picture: the picture of a hidden sidebar without touching the saved choice.
    @State private var pictureHidden = CommandLine.arguments.contains("--picture")
        && CommandLine.arguments.firstIndex(of: "--sidebar").map { $0 + 1 < CommandLine.arguments.count && CommandLine.arguments[$0 + 1] == "hidden" } == true
    @State private var gridWidth: CGFloat = 1000
    @StateObject private var vault = VaultModel.shared
    @State private var showVault = PictureArgs.value("--page") == "vault" || SetupFlow.shared.finishedOnce
    @State private var sub: ShelfSubPage? = PictureArgs.value("--page") == "settings" ? .settings : PictureArgs.value("--page") == "about" ? .about : PictureArgs.value("--page") == "answers" ? .answers : nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scrollY: CGFloat = 0
    @State private var scrollPos = ScrollPosition()
    // The full hero is 196pt under 22pt of padding: pinned once most of it has left the top.
    private var heroGone: Bool { scrollY > 150 }

    private func openSettings() { showVault = false; sub = .settings }
    private var sidebarShown: Bool { sidebarStored && !pictureHidden }
    private func setSidebar(_ on: Bool) {
        let go = { pictureHidden = false; sidebarStored = on }
        if reduceMotion { go() } else { withAnimation(.easeInOut(duration: 0.22)) { go() } }
    }

    private var items: [ShelfItem] {
        shelf.rows.map { r in
            ShelfItem(id: r.id, name: r.app.name, job: r.app.job, group: Release.apps.first { $0.id == r.id }?.group ?? "Tools",
                      installed: r.installed != nil, update: r.needsUpdate,
                      download: r.hasDownload, web: r.site != nil)
        }
    }
    private var sections: [ShelfSection] { ShelfLogic.apply(items, filter: filter, search: search, sort: sort) }
    private var hero: HeroState {
        .from(looked: shelf.rows.contains { $0.looked }, anyLatest: shelf.rows.contains { $0.here != nil },
              total: shelf.rows.filter(\.hasDownload).count, missing: shelf.missing, stale: shelf.stale)
    }
    private var title: String {
        switch filter {
        case .all: "All apps"
        case .installed: "Installed"
        case .updates: "Updates"
        case .missing: "Not installed"
        case .coming: "Coming"
        case .group(let g): g
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            if sidebarShown { sidebar } else { rail }
            Rectangle().fill(Token.hairline).frame(width: 1)
            main
        }
        .clipped()
        .background(Button("") { setSidebar(!sidebarShown) }.keyboardShortcut("s", modifiers: [.control, .command]).opacity(0).allowsHitTesting(false))
        .background(Token.ground.ignoresSafeArea())
        // Cmd-comma, the gear and Today's button all set showSettings; here that opens the page, not a sheet.
        .onChange(of: shelf.showSettings) { _, on in if on { openSettings(); shelf.showSettings = false } }
        .task { vault.start() }
        .onChange(of: uiState, initial: true) { _, st in if UITest.on { UITest.state = st } }
        .onAppear { UITest.setSort = { sort = $0 } }
    }

    private var uiState: UIState {
        UIState(ids: sections.flatMap { $0.items.map(\.id) }, page: sub == .settings ? "settings" : sub == .about ? "about" : sub == .answers ? "answers" : showVault ? "vault" : "apps",
                sidebar: sidebarShown, title: title)
    }

    // MARK: sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                if let img = Bundle.main.image(forResource: "icon-native") {
                    Image(nsImage: img).resizable().frame(width: 30, height: 30).clipShape(RoundedRectangle(cornerRadius: 7.2, style: .continuous))
                }
                Text("Glyph Native").font(.system(size: 16, weight: .bold)).foregroundStyle(Token.text)
            }
            .padding(.horizontal, 6).padding(.top, 28)   // clears the window's own traffic lights
            searchField
            VStack(spacing: 2) {
                filterRow("All apps", "square.grid.2x2", shelf.rows.count, .all, "filter.all")
                filterRow("Installed", "arrow.down.to.line", shelf.rows.filter { $0.installed != nil }.count, .installed, "filter.installed")
                filterRow("Updates", "arrow.triangle.2.circlepath", shelf.rows.filter(\.needsUpdate).count, .updates, "filter.updates")
                filterRow("Not installed", "circle.dashed", items.filter { ShelfLogic.matches($0, .missing) }.count, .missing, "filter.missing")
                filterRow("Coming", "clock", items.filter { ShelfLogic.matches($0, .coming) }.count, .coming, "filter.coming")
            }
            VStack(spacing: 2) {
                Text("Groups").font(.system(size: 11.5, weight: .semibold)).tracking(0.6).textCase(.uppercase)
                    .foregroundStyle(Token.accentLight).frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 10).padding(.bottom, 6)
                filterRow("Layers", "square.3.layers.3d", items.filter { $0.group == "Layers" }.count, .group("Layers"), "group.layers")
                filterRow("Tools", "wrench.fill", items.filter { $0.group == "Tools" }.count, .group("Tools"), "group.tools")
                filterRow("Your life", "person.crop.circle", items.filter { $0.group == "Your life" }.count, .group("Your life"), "group.life")
            }
            VStack(spacing: 2) { vaultRow }
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 8) {
                Rectangle().fill(Token.hairline).frame(height: 1)
                Text("Signed installs from GitHub").lineLimit(1)
                    .font(.system(size: 12.5)).lineSpacing(2).foregroundStyle(Token.quiet).fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
                HStack {
                    Button { openSettings() } label: {
                        Label("Settings", systemImage: "gearshape").font(.system(size: 13.5, weight: sub != nil ? .semibold : .regular))
                            .foregroundStyle(sub != nil ? Token.tintText : Token.rowText)
                            .padding(.horizontal, 8).frame(height: 30)
                            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(sub != nil ? Token.tint : .clear))
                            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(sub != nil ? Token.tintBorder : .clear))
                    }
                    .buttonStyle(.plain).testFrame("settings")
                    Spacer()
                    Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")
                        .font(.system(size: 12.5).monospacedDigit()).foregroundStyle(Token.quiet)
                }
            }
            .padding(.horizontal, 6)
        }
        .padding(.horizontal, 12).padding(.bottom, 14)
        .frame(width: 244)
        .background(Token.sidebar.ignoresSafeArea())
        .overlay(alignment: .topTrailing) { sidebarToggle.padding(.top, 2).padding(.trailing, 8) }
        .transition(.move(edge: .leading))
    }

    /// The collapsed sidebar: the same places as icons only (Fru: "it should still show the icons"), each with its
    /// name on hover. The ids match the full rows, since only one of the two is ever on screen.
    private var rail: some View {
        let updates = shelf.rows.filter(\.needsUpdate).count
        return VStack(spacing: 14) {
            if let img = Bundle.main.image(forResource: "icon-native") {
                Image(nsImage: img).resizable().frame(width: 30, height: 30).clipShape(RoundedRectangle(cornerRadius: 7.2, style: .continuous))
                    .padding(.top, 40)   // below the window's own traffic lights
            }
            sidebarToggle
            railIcon("magnifyingglass", false, "Search apps", "rail.search") { setSidebar(true); DispatchQueue.main.async { searchFocused = true } }
                .keyboardShortcut("k", modifiers: .command)
            VStack(spacing: 2) {
                railFilter("All apps", "square.grid.2x2", .all, "filter.all")
                railFilter("Installed", "arrow.down.to.line", .installed, "filter.installed")
                railFilter("Updates", "arrow.triangle.2.circlepath", .updates, "filter.updates")
                    .overlay(alignment: .topTrailing) { if updates > 0 { Circle().fill(Token.accentLight).frame(width: 7, height: 7).padding(6) } }
                railFilter("Not installed", "circle.dashed", .missing, "filter.missing")
                railFilter("Coming", "clock", .coming, "filter.coming")
            }
            Rectangle().fill(Token.hairline).frame(width: 24, height: 1)
            VStack(spacing: 2) {
                railFilter("Layers", "square.3.layers.3d", .group("Layers"), "group.layers")
                railFilter("Tools", "wrench.fill", .group("Tools"), "group.tools")
                railFilter("Your life", "person.crop.circle", .group("Your life"), "group.life")
            }
            Rectangle().fill(Token.hairline).frame(width: 24, height: 1)
            railIcon("folder", showVault && sub == nil, "Vault", "nav.vault") { showVault = true; sub = nil }
            Spacer(minLength: 0)
            railIcon("gearshape", sub != nil, "Settings", "settings") { openSettings() }
        }
        .padding(.bottom, 14)
        .frame(width: 68)
        .background(Token.sidebar.ignoresSafeArea())
        .transition(.move(edge: .leading))
    }

    private func railFilter(_ label: String, _ icon: String, _ f: ShelfFilter, _ test: String) -> some View {
        railIcon(icon, filter == f && !showVault && sub == nil, label, test) { filter = f; showVault = false; sub = nil }
    }

    private func railIcon(_ icon: String, _ on: Bool, _ label: String, _ test: String, _ act: @escaping () -> Void) -> some View {
        Button(action: act) {
            Image(systemName: icon).font(.system(size: 15, weight: on ? .semibold : .regular)).foregroundStyle(on ? Token.tintText : Token.quiet)
                .frame(width: 44, height: 34)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(on ? Token.tint : .clear))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(on ? Token.tintBorder : .clear))
                .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain).help(label).accessibilityLabel(label).testFrame(test)
    }

    private var sidebarToggle: some View {
        Button { setSidebar(!sidebarShown) } label: {
            Image(systemName: "sidebar.left").font(.system(size: 15)).foregroundStyle(Token.quiet).frame(width: 36, height: 36).contentShape(Rectangle())
        }
        .buttonStyle(.borderless).help(sidebarShown ? "Hide sidebar" : "Show sidebar").testFrame("sidebar.toggle")
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 13, weight: .semibold)).foregroundStyle(Token.quiet)
            TextField("Search apps", text: $search).textFieldStyle(.plain).font(.system(size: 13.5)).focused($searchFocused)
                .foregroundStyle(Token.text).testFrame("search")
            Text("⌘K").font(.system(size: 11.5)).foregroundStyle(Token.quiet)
                .padding(.horizontal, 6).padding(.vertical, 1)
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Token.border))
        }
        .padding(.horizontal, 10).frame(height: 34)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Token.raised))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Token.border))
        .background(Button("") {
            // A hidden sidebar has no field yet: show it, then focus on the next turn.
            if !sidebarShown { setSidebar(true) }
            DispatchQueue.main.async { searchFocused = true }
        }.keyboardShortcut("k", modifiers: .command).opacity(0).allowsHitTesting(false))
    }

    private func filterRow(_ label: String, _ icon: String, _ count: Int, _ f: ShelfFilter, _ test: String) -> some View {
        let on = filter == f && !showVault && sub == nil
        return Button { filter = f; showVault = false; sub = nil } label: {
            HStack(spacing: 10) {
                Image(systemName: icon).font(.system(size: 13)).frame(width: 16).foregroundStyle(on ? Token.tintText : Token.quiet)
                Text(label).frame(maxWidth: .infinity, alignment: .leading)
                Text("\(count)").monospacedDigit().foregroundStyle(on ? Token.tintText : Token.quiet)
            }
            .font(.system(size: 14, weight: on ? .semibold : .regular))
            .foregroundStyle(on ? Token.tintText : Token.rowText)
            .padding(.horizontal, 10).frame(height: 34)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(on ? Token.tint : .clear))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(on ? Token.tintBorder : .clear))
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain).testFrame(test)
    }

    private var vaultRow: some View {
        Button { showVault = true; sub = nil } label: {
            HStack(spacing: 10) {
                Image(systemName: "folder").font(.system(size: 13)).frame(width: 16).foregroundStyle((showVault && sub == nil) ? Token.tintText : Token.quiet)
                Text("Vault").frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.system(size: 14, weight: (showVault && sub == nil) ? .semibold : .regular))
            .foregroundStyle((showVault && sub == nil) ? Token.tintText : Token.rowText)
            .padding(.horizontal, 10).frame(height: 34)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill((showVault && sub == nil) ? Token.tint : .clear))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder((showVault && sub == nil) ? Token.tintBorder : .clear))
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain).testFrame("nav.vault")
    }

    // MARK: main

    @ViewBuilder private var main: some View {
        if sub != nil { SettingsPage(sidebarShown: true, sub: $sub, toggle: { sidebarToggle }) }
        else if showVault { VaultPage(model: vault, sidebarShown: true, toggle: { sidebarToggle }) } else { appsMain }
    }

    private var titleRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title).font(.system(size: 30, weight: .bold)).tracking(-0.6).foregroundStyle(Token.text)
            Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day())).font(.system(size: 13)).foregroundStyle(Token.quiet)
            Spacer(minLength: 8)
            sortMenu
        }
        .padding(.horizontal, 28).padding(.top, 22).padding(.bottom, 14)
        .background(Token.ground)
        .zIndex(1)
    }

    /// The hero in one line, pinned under the title row once the full hero has scrolled away.
    private var slimHero: some View {
        let h = hero
        return HStack(spacing: 12) {
            if let img = Bundle.main.image(forResource: "icon-native") {
                Image(nsImage: img).resizable().frame(width: 28, height: 28).clipShape(RoundedRectangle(cornerRadius: 6.7, style: .continuous))
            }
            Text(h.headline).font(.system(size: 15, weight: .semibold)).foregroundStyle(heroText).lineLimit(1)
            Spacer(minLength: 8)
            heroButton(h, small: true)
        }
        .padding(.horizontal, 16).frame(height: 52)
        .background(LinearGradient(colors: [Color(NSColor.hex(0x0E2412)), Color(NSColor.hex(0x123A1A))], startPoint: .leading, endPoint: .trailing))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color(NSColor.hex(0x27512F))))
        .shadow(color: .black.opacity(0.28), radius: 10, y: 4)
        .padding(.horizontal, 28).padding(.bottom, 12)
        .testFrame("hero.pinned")
    }

    private var appsMain: some View {
        VStack(spacing: 0) {
            titleRow
            ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                heroPanel
                let secs = sections
                if secs.isEmpty {
                    Text(ShelfLogic.empty(filter: filter, search: search)).font(.system(size: 15)).foregroundStyle(Token.quiet)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                }
                ForEach(secs, id: \.title) { sec in
                    VStack(alignment: .leading, spacing: 10) {
                        if let t = sec.title {
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text(t).foregroundStyle(Token.accentLight)
                                Text(meta(sec)).foregroundStyle(Token.headingMeta).lineLimit(1)
                            }
                            .font(.system(size: 11.5, weight: .semibold)).tracking(0.6).textCase(.uppercase)
                        }
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14, alignment: .top), count: ShelfLogic.columns(count: sec.items.count, fit: ShelfLogic.fit(width: Double(gridWidth - 56)))), alignment: .leading, spacing: 14) {
                            ForEach(sec.items) { i in
                                if let r = shelf.rows.first(where: { $0.id == i.id }) { ReleaseCard(row: r) }
                            }
                        }
                    }
                }
                if shelf.running != nil || shelf.lastResult != nil { LogPanel() }
            }
            .padding(.horizontal, 28).padding(.top, 2).padding(.bottom, 24)
            }
            .scrollPosition($scrollPos)
            .scrollEdgeEffectHidden(true, for: .all)
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { _, y in scrollY = y }
            .overlay(alignment: .top) {
                if heroGone { slimHero.transition(reduceMotion ? .identity : .opacity.combined(with: .move(edge: .top))) }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: heroGone)
            .task {
                // Picture-only: `--scroll 600` scrolls the page so the pinned hero can be pictured.
                if let y = PictureArgs.value("--scroll").flatMap({ Double($0) }) {
                    try? await Task.sleep(for: .seconds(2)); scrollPos.scrollTo(y: y)
                }
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { gridWidth = $0 }
    }

    /// "2 apps · where your agents work, what you know"
    private func meta(_ s: ShelfSection) -> String {
        let n = "\(s.items.count) app\(s.items.count == 1 ? "" : "s")"
        // The group's full blurb only while the whole group is listed.
        let blurb = s.title == "Layers" && s.items.count == 4 ? " · the four layers" : ""
        return n + blurb
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort", selection: $sort) { ForEach(ShelfSort.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.inline)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "line.3.horizontal.decrease").font(.system(size: 12, weight: .semibold)).foregroundStyle(Token.quiet)
                Text("Sort: \(sort.rawValue)").font(.system(size: 13.5)).foregroundStyle(Token.rowText)
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold)).foregroundStyle(Token.quiet)
            }
            .padding(.horizontal, 14).frame(height: 36)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Token.raised))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Token.border))
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize().testFrame("sort")
    }

    // MARK: hero

    /// "Up to date · checked 14:02": the time is only added once a check has really finished.
    private func heroStatus(_ h: HeroState) -> String {
        guard h.isCurrent, let t = shelf.lastChecked else { return h.status }
        return h.status + " · checked " + t.formatted(date: .omitted, time: .shortened)
    }

    private var heroPanel: some View {
        let h = hero
        return ZStack(alignment: .leading) {
            LinearGradient(colors: [Color(NSColor.hex(0x0E2412)), Color(NSColor.hex(0x123A1A)), Color(NSColor.hex(0x0C1E10))], startPoint: UnitPoint(x: 0, y: 0.2), endPoint: UnitPoint(x: 1, y: 0.8))
            RadialGradient(colors: [Color(NSColor.hex(0x1C6B2A)), .clear], center: UnitPoint(x: 0.88, y: 0.4), startRadius: 0, endRadius: 330)
            HeroArt().frame(width: 520, height: 196).frame(maxWidth: .infinity, alignment: .trailing)
            VStack(alignment: .leading, spacing: 8) {
                Text(heroStatus(h)).font(.system(size: 11.5, weight: .semibold)).tracking(0.6).textCase(.uppercase).foregroundStyle(heroGreen)
                Text(h.headline).font(.system(size: 28, weight: .bold)).tracking(-0.5).foregroundStyle(heroText).fixedSize(horizontal: false, vertical: true)
                Text(h.isCurrent ? "Every app and every agent reads the same files you own." : "Every app here shares one vault you own.").font(.system(size: 15)).foregroundStyle(heroSub)
                heroButton(h).padding(.top, 6)
            }
            .frame(maxWidth: 420, alignment: .leading).padding(.horizontal, 32)
        }
        .frame(height: 196)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Color(NSColor.hex(0x27512F))))
    }

    // The hero is dark green in both appearances, so its text is fixed.
    private var heroGreen: Color { Color(NSColor.hex(0x7FD49A)) }
    private var heroText: Color { Color(NSColor.hex(0xF5F5F7)) }
    private var heroSub: Color { Color(NSColor.hex(0xE6E6EA)) }

    @ViewBuilder private func heroButton(_ h: HeroState, small: Bool = false) -> some View {
        if let t = shelf.running {
            HStack(spacing: 8) { ProgressView().controlSize(.small); Text(t).foregroundStyle(heroSub).lineLimit(1) }.fixedSize().frame(height: small ? 30 : 36)
        } else if let label = h.action {
            let installs: Bool = { if case .install = h { true } else if case .updates = h { true } else { false } }()
            Button {
                switch h {
                case .install, .updates: shelf.installAll()
                default: shelf.fetch()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: { if case .install = h { "arrow.down.circle" } else if case .updates = h { "arrow.down.circle" } else { "arrow.clockwise" } }())
                        .font(.system(size: small ? 12 : 13, weight: .semibold))
                    Text(label).font(.system(size: small ? 13 : 14, weight: .semibold))
                }
                .foregroundStyle(heroText).padding(.horizontal, small ? 12 : 16).frame(height: small ? 30 : 36)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.black.opacity(0.25)))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color(NSColor.hex(0x3C7A4A))))
            }
            .buttonStyle(.plain).fixedSize()
            .testFrame(small ? "hero.pinned.action" : "hero.action")
            .testFrame(small ? "hero.pinned.action" : (installs ? "installAll" : "hero.action"))
        }
    }
}

/// Rings, spokes, the family mark and the five app icons, in the artboard's 520x196 box.
private struct HeroArt: View {
    private let c = CGPoint(x: 330, y: 98)
    private let green = Color(NSColor.hex(0x7FD49A))
    // id, left, top, size, rotation (degrees)
    private let icons: [(String, CGFloat, CGFloat, CGFloat, Double)] = [
        ("studio", 188, 24, 46, -8), ("jot", 214, 138, 44, 6), ("arena", 418, 12, 44, 9), ("cast", 444, 96, 46, -5), ("time", 374, 150, 40, -10),
    ]
    var body: some View {
        ZStack(alignment: .topLeading) {
            Canvas { g, _ in
                func ring(_ r: CGFloat, _ o: Double, dash: [CGFloat] = []) {
                    g.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(green.opacity(o)),
                             style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: dash))
                }
                ring(62, 0.28); ring(112, 0.18, dash: [2, 9]); ring(170, 0.12)
                var spokes = Path()
                for p in [(212, 46), (236, 160), (440, 34), (468, 118), (392, 178)] { spokes.move(to: c); spokes.addLine(to: CGPoint(x: p.0, y: p.1)) }
                g.stroke(spokes, with: .color(green.opacity(0.22)), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
            }
            icon("native", 288, 56, 84, 0, big: true)
            ForEach(icons, id: \.0) { icon($0.0, $0.1, $0.2, $0.3, $0.4, big: false) }
        }
    }

    private func icon(_ id: String, _ x: CGFloat, _ y: CGFloat, _ s: CGFloat, _ rot: Double, big: Bool) -> some View {
        Group {
            if let img = Bundle.main.image(forResource: "icon-\(id)") { Image(nsImage: img).resizable() } else { Color(NSColor.hex(0x1C6B2A)) }
        }
        .frame(width: s, height: s)
        .clipShape(RoundedRectangle(cornerRadius: s * 0.24, style: .continuous))
        .shadow(color: .black.opacity(big ? 0.45 : 0.4), radius: big ? 17 : 10, y: big ? 18 : 10)
        .overlay { if big { RoundedRectangle(cornerRadius: s * 0.24, style: .continuous).strokeBorder(green.opacity(0.16), lineWidth: 6).padding(-3) } }
        .rotationEffect(.degrees(rot))
        .position(x: x + s / 2, y: y + s / 2)
    }
}

/// One app: icon, full name, job, status in words and one button.
struct ReleaseCard: View {
    @EnvironmentObject var shelf: Shelf
    let row: Shelf.Row
    @State private var hover = false
    @State private var cardW: CGFloat = 400
    @State private var nameW: CGFloat = 120
    @FocusState private var linkFocus: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    // Which of this card's controls have keyboard focus: the trash icon shows while any does.
    @State private var focused: Set<String> = []
    // Picture-only switch so a screenshot can show the link on every card.
    private static let forceLink = PictureArgs.on && CommandLine.arguments.contains("--show-site-links")
    private var page: URL? { Release.apps.first { $0.id == row.app.id }.flatMap { URL(string: $0.page) } }
    private var here: Bool { row.path != nil }
    // Hovered, keyboard-focused, or forced by `--hover <id>` with --picture: the card fills green.
    private var lit: Bool { hover || shelf.uiHover == row.app.id || !focused.isEmpty || linkFocus || PictureArgs.value("--hover") == row.app.id }
    private static let fillTop = Color(NSColor.hex(0x0A9A12)), fillBottom = Color(NSColor.hex(0x006B06))
    private static let fillBorder = Color(NSColor.hex(0x4AC456))
    private var updatePrimary: Bool { row.canInstall && row.installed != nil && row.needsUpdate }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                mark.frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 10.6, style: .continuous)).opacity(here || row.site != nil ? 1 : 0.5)
                VStack(alignment: .leading, spacing: 3) {
                    Text(row.app.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(lit ? Color.white : Token.text).fixedSize(horizontal: false, vertical: true)
                        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { nameW = $0 }
                    Text(row.app.job).font(.system(size: 12.5)).foregroundStyle(lit ? Color.white.opacity(0.85) : Token.quiet).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            Spacer(minLength: 8)
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(status).font(.system(size: 12.5).monospacedDigit()).foregroundStyle(lit ? Color.white : (row.needsUpdate ? Token.tintText : Token.quiet)).lineLimit(1)
                    if let old = Release.retiredLine(retiredInstalled: row.retiredHere, installed: row.installed != nil, name: row.app.name) {
                        Text(old).font(.system(size: 11)).foregroundStyle(lit ? Color.white.opacity(0.85) : Token.quiet).lineLimit(1).minimumScaleFactor(0.85)
                    }
                }
                Spacer(minLength: 4)
                action
            }
        }
        .padding(16)
        .frame(height: 132, alignment: .topLeading)
        .background {
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Token.raised)
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(LinearGradient(colors: [Self.fillTop, Self.fillBottom], startPoint: .top, endPoint: .bottom))
                    .opacity(lit ? 1 : 0)
                // Faint motif, off the right and top edges, behind the text and clear of the button at the bottom right; clipped to the card.
                if let sym = Release.motifs[row.app.id] {
                    Image(systemName: sym).symbolRenderingMode(.hierarchical).font(.system(size: 104))
                        .foregroundStyle(lit ? Color.white : Color.nativeGreen)
                        .opacity(lit ? 0.16 : (scheme == .dark ? 0.07 : 0.06))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .offset(x: 30, y: -34).allowsHitTesting(false)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(lit ? Self.fillBorder : Token.border))
        .shadow(color: Self.fillTop.opacity(lit ? 0.35 : 0), radius: 14, y: 6)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(alignment: .topTrailing) { siteLink }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { cardW = $0 }
        .contextMenu {
            if let u = page { Button("Open Website") { NSWorkspace.shared.open(u) } }
            if let p = row.path { Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([p]) } }
        }
        .onTapGesture { if let u = row.site { NSWorkspace.shared.open(u) } else if here { shelf.open(row) } }
        .offset(y: lit && !reduceMotion ? -2 : 0)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: lit)
        .onHover { if !PictureArgs.on { hover = $0 } }   // a picture must not depend on the real pointer
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(here ? .isButton : [])
        .testFrame("line.\(row.app.id)")
    }

    /// Quiet "Website" link, drawn over the top right corner so nothing else moves.
    @ViewBuilder private var siteLink: some View {
        if let u = page {
            let shown = lit || Self.forceLink
            // 16 padding + 44 icon + 12 gap + name, then 10 clear before the full link (about 82pt wide).
            let symbolOnly = 16 + 44 + 12 + nameW + 10 + 82 > cardW - 12
            Button { NSWorkspace.shared.open(u) } label: {
                SiteLinkLabel(symbolOnly: symbolOnly, lit: lit)
            }
            .buttonStyle(.plain).focused($linkFocus)
            .onChange(of: linkFocus) { _, on in setFocus("site", on) }
            .help("Open \(row.app.name)'s page").testFrame("site.\(row.app.id)")
            .padding(.top, 10).padding(.trailing, 12)
            .opacity(shown ? 1 : 0).allowsHitTesting(shown)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: shown)
        }
    }

    private func setFocus(_ id: String, _ on: Bool) {
        if on { focused.insert(id) } else { focused.remove(id) }
    }

    @ViewBuilder private var mark: some View {
        if let img = Bundle.main.image(forResource: "icon-\(row.app.id)") { Image(nsImage: img).resizable() }
        else if let p = row.path { Image(nsImage: NSWorkspace.shared.icon(forFile: p.path)).resizable() }
        else { RoundedRectangle(cornerRadius: 10.6, style: .continuous).fill(Color.nativeGreen.opacity(0.5)) }
    }

    private var status: String {
        if row.site != nil { return "On the web" }
        if !row.hasDownload { return row.installed.map(Release.installedLabel) ?? "Coming" }
        return Release.cardLine(installed: row.installed, latest: row.here, needsUpdate: row.needsUpdate, looked: row.looked, note: shelf.notes[row.app.id])
    }

    /// A written primary button at the far right; the trash sits to its left, hidden at rest but holding its space.
    /// Nothing for web entries or apps that are only coming.
    @ViewBuilder private var action: some View {
        if row.site == nil {
            HStack(spacing: 6) {
                if here && row.app.macBundle != Bundle.main.bundleIdentifier {
                    let showTrash = lit
                    IconButton(symbol: "trash", tip: "Uninstall \(row.app.name)", green: false, lit: lit, run: { shelf.uninstall(row) }, onFocus: { setFocus("uninstall", $0) })
                        .testFrame("uninstall.\(row.app.id)")
                        .disabled(shelf.running != nil)
                        .opacity(showTrash ? 1 : 0).allowsHitTesting(showTrash)
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: showTrash)
                }
                if updatePrimary {
                    textButton("Update", "Update to \(row.here ?? "")", "install.\(row.app.id)", solid: true) { shelf.install(row) }
                        .disabled(shelf.running != nil)
                } else if row.canInstall && row.installed == nil {
                    textButton("Install", "Install \(row.app.name)", "install.\(row.app.id)") { shelf.install(row) }
                        .disabled(shelf.running != nil)
                } else if here {
                    textButton("Open", "Open \(row.app.name)", "open.\(row.app.id)") { shelf.open(row) }
                }
            }
        }
    }

    private func textButton(_ label: String, _ tip: String, _ id: String, solid: Bool = false, _ run: @escaping () -> Void) -> some View {
        TextAction(label: label, tip: tip, solid: solid, lit: lit, run: run, onFocus: { setFocus(id, $0) }).testFrame(id)
    }
}

/// 28pt text button. Chip on a dark card, solid green for Update; white with dark green text on the filled card.
private struct TextAction: View {
    let label: String, tip: String, solid: Bool, lit: Bool, run: () -> Void
    var onFocus: (Bool) -> Void = { _ in }
    @FocusState private var focus: Bool
    var body: some View {
        Button(action: run) {
            Text(label).font(.system(size: 13, weight: .semibold))
                .foregroundStyle(lit ? Color(NSColor.hex(0x006B06)) : (solid ? Color.white : Token.tintText))
                .padding(.horizontal, 12).frame(height: 28)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(lit ? Color.white : (solid ? Color(NSColor.hex(0x0A7A12)) : Token.tint)))
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain).focused($focus).onChange(of: focus) { _, on in onFocus(on) }
        .help(tip).accessibilityLabel(tip)
    }
}

/// 28pt borderless icon: quiet until hovered, then the green accent.
private struct IconButton: View {
    let symbol: String, tip: String, green: Bool, lit: Bool, run: () -> Void
    var onFocus: (Bool) -> Void = { _ in }
    @State private var over = false
    @FocusState private var focus: Bool
    var body: some View {
        Button(action: run) {
            Image(systemName: symbol).font(.system(size: 14)).frame(width: 28, height: 28).contentShape(Rectangle())
        }
        .buttonStyle(.borderless).focused($focus).onChange(of: focus) { _, on in onFocus(on) }
        .foregroundStyle(lit ? Color.white : (over || green ? Token.accentLight : Token.quiet))
        .onHover { over = $0 }
        .help(tip).accessibilityLabel(tip)
    }
}

private struct SiteLinkLabel: View {
    let symbolOnly: Bool, lit: Bool
    @State private var over = false
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "arrow.up.right").font(.system(size: 12.5))
            if !symbolOnly { Text("Website").font(.system(size: 12.5)) }
        }
        .foregroundStyle(lit ? Color.white : (over ? Token.accentLight : Token.quiet))
        .padding(4).contentShape(Rectangle())
        .onHover { over = $0 }
    }
}
