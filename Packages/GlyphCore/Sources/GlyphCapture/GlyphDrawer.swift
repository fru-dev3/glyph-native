import SwiftUI
#if os(iOS)

/// The family's sidebar: the panel that slides in from the left edge, with the app's block at the
/// top, the ways in as tiled rows, the rest in quiet groups under their headings, and whatever the
/// app wants to say at the foot.
///
/// Fru, 2026-11-10, opening Glyph Omega: "Omega is missing the sidebar." It was the fifth drawer
/// in the family and the first that did not exist: Glyph Jot, Glyph Well, Glyph CRM and Glyph
/// Wealth each drew their own. This is Glyph Wealth's, which is the one he last approved, with its
/// colours taken from the system so an app that follows the phone into light mode is not handed a
/// black panel. The four that came first should come here too; until they do, this is the one any
/// new app uses, and the shape they are measured against.
///
/// An app passes its places and their names. It does not pass a width, a row height, a corner
/// radius or a padding: those are the drawer, not the content.
///
/// Accessibility identifiers: `drawer` (the panel), `drawer.<id>` (a row), `drawer.scrim`.
public struct GlyphDrawer: View {
    /// One place in the drawer. `figure` is a number or a word at the trailing edge, for a row
    /// that has one worth showing.
    public struct Row: Identifiable, Sendable {
        public let id: String
        public let name: String
        public let symbol: String
        public let figure: String?
        public init(id: String, name: String, symbol: String, figure: String? = nil) {
            self.id = id; self.name = name; self.symbol = symbol; self.figure = figure
        }
    }

    /// A group of places. A section with no title holds the ways in and is drawn as tiles; a
    /// titled one is a quiet list under its heading.
    public struct Section: Identifiable, Sendable {
        public let id: String
        public let title: String?
        public let rows: [Row]
        /// The ways in, at the top, drawn as tiles.
        public init(_ rows: [Row]) { self.id = "ways-in"; self.title = nil; self.rows = rows }
        /// A group under its heading.
        public init(_ title: String, _ rows: [Row]) { self.id = title; self.title = title; self.rows = rows }
    }

    let name: String
    let mark: String
    let tint: Color
    let sections: [Section]
    /// The place the app is on, so the drawer can say where you are.
    let here: String
    /// A line at the foot: the version, whether the hub was reached, whatever the app keeps there.
    let foot: AnyView?
    /// The tags, under the places: the same section in every app's drawer (`GlyphDrawerTags`).
    let tags: GlyphDrawerTags?
    let choose: (String) -> Void

    public init(name: String, mark: String, tint: Color, sections: [Section], here: String,
                tags: GlyphDrawerTags? = nil, foot: AnyView? = nil, choose: @escaping (String) -> Void) {
        self.name = name; self.mark = mark; self.tint = tint; self.sections = sections
        self.here = here; self.tags = tags; self.foot = foot; self.choose = choose
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 10) {
                Image(systemName: mark).font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white).frame(width: 28, height: 28)
                    .background(tint, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                Text(name).font(.system(size: 15, weight: .semibold))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 4)

            // Everything between the name and the foot scrolls, the places included. They stood
            // outside the scroll until 2026-11-22, and once an app folded more rows into them (a
            // More opened in Omega) they outgrew the panel and pushed the name up into the clock.
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let ways = sections.first(where: { $0.title == nil }) {
                        VStack(spacing: 4) { ForEach(ways.rows) { tile($0) } }
                            .padding(.bottom, 6)
                    }
                    ForEach(sections.filter { $0.title != nil }) { s in
                        VStack(alignment: .leading, spacing: 9) {
                            Text((s.title ?? "").uppercased())
                                .font(.system(size: 11.5, weight: .semibold)).tracking(0.5)
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 8)
                            VStack(spacing: 2) { ForEach(s.rows) { quiet($0) } }
                        }
                    }
                    if let tags { tags }
                }
            }
            .scrollIndicators(.hidden)

            if let foot {
                VStack(alignment: .leading, spacing: 2) {
                    Divider()
                    foot.padding(.horizontal, 8).padding(.vertical, 7)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 58)
        .padding(.bottom, 20)
        .frame(width: 296)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(uiColor: .secondarySystemBackground))
        .overlay(alignment: .trailing) { Rectangle().fill(.separator).frame(width: 1) }
        .ignoresSafeArea()
        // Named, with its rows still their own elements. An identifier on a container alone left
        // a check able to see the panel and none of the places in it.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("drawer")
    }

    /// A way in: the 54pt row with the filled tile, as Glyph Wealth draws Chat, Today and Jot.
    /// Without `contentShape` the hit area is the glyphs themselves and not the row, so a row that
    /// looked 54 tall was 17.
    func tile(_ r: Row) -> some View {
        let on = r.id == here
        return Button { choose(r.id) } label: {
            HStack(spacing: 12) {
                Image(systemName: r.symbol)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(on ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                    .frame(width: 30, height: 30)
                    .background(on ? AnyShapeStyle(tint) : AnyShapeStyle(.quaternary),
                                in: .rect(cornerRadius: 9, style: .continuous))
                Text(r.name).font(.system(size: 17, weight: on ? .semibold : .regular))
                Spacer(minLength: 0)
                if let f = r.figure { Text(f).font(.system(size: 13)).foregroundStyle(.tertiary).monospacedDigit() }
            }
            .padding(.horizontal, 12)
            .frame(height: 54)
            .background(on ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear),
                        in: .rect(cornerRadius: 13, style: .continuous))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("drawer.\(r.id)")
        // Which place you are in was said only by a darker row: nothing a screen reader, or a check, could hear.
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// Everything else: a quieter row, the same tap, no tile.
    func quiet(_ r: Row) -> some View {
        let on = r.id == here
        return Button { choose(r.id) } label: {
            HStack(spacing: 11) {
                Image(systemName: r.symbol).font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.tertiary).frame(width: 22)
                Text(r.name).font(.system(size: 15, weight: on ? .semibold : .regular))
                Spacer(minLength: 0)
                if let f = r.figure { Text(f).font(.system(size: 13)).foregroundStyle(.tertiary).monospacedDigit() }
            }
            .padding(.horizontal, 8)
            .frame(height: 38)
            .background(on ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear),
                        in: .rect(cornerRadius: 10, style: .continuous))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("drawer.\(r.id)")
        // Which place you are in was said only by a darker row: nothing a screen reader, or a check, could hear.
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// The tags in the drawer, the same in every app (Fru, 2026-11-23, of the sidebars: "I should see
/// the chat, the app, and then the tags visible, showing all on the side, expanded. And then I can
/// choose to collapse it or not... in every single app"). Every tag this app holds, from the
/// register (`GlyphTags.forApp`), open by default; the heading folds it away and the choice is kept
/// on this phone, per app. A tag opens that tag's page in the app, where you chat with it and act on
/// it (a tag is a domain with its own context). The register is managed in Glyph CRM, so every
/// other app ends the list with Manage tags, which opens CRM's tags.
///
/// Its own view so a drawer an app still draws itself (Jot, Well, Wealth, Time, CRM) embeds the
/// same section `GlyphDrawer` draws, never a copy.
///
/// Accessibility identifiers: `drawer.tagsection` (the heading), `drawer.tag.<slug>`, `drawer.tagsection.manage`. Never `drawer.tags`: that is every app's Tags place row.
public struct GlyphDrawerTags: View {
    let app: String
    let tint: Color
    let here: String?
    let open: (GlyphTag) -> Void
    /// How many things carry each tag, by slug, drawn at the row's end. Empty draws none.
    let counts: [String: Int]
    /// The app's own order of its tags, by name (Glyph Jot's Edit Order); nil is the register's.
    let order: [String]?
    /// What a long press on a tag offers (Glyph Jot's rename, describe, delete); nil offers nothing.
    let menu: ((GlyphTag) -> AnyView)?
    /// One more row under the tags, for an app's own tag action (Glyph Jot's Edit Order).
    let extra: AnyView?
    @ObservedObject private var register = GlyphTags.shared
    @AppStorage("glyph.drawer.tags.open") private var expanded = true
    @Environment(\.openURL) private var openURL

    /// - app: the family id ("well"), which picks the subset. - here: the tag on screen, if any.
    /// - open: shows that tag's page (its `id` is the slug, its `name` the register's spelling).
    public init(app: String, tint: Color, here: String? = nil, counts: [String: Int] = [:], order: [String]? = nil,
                menu: ((GlyphTag) -> AnyView)? = nil, extra: AnyView? = nil, open: @escaping (GlyphTag) -> Void) {
        self.app = app; self.tint = tint; self.here = here; self.open = open
        self.counts = counts; self.order = order; self.menu = menu; self.extra = extra
    }

    /// The tags in the order shown: the app's own order first, then any the register has that it lacks.
    private var shown: [GlyphTag] {
        let mine = register.forApp(app)
        guard let order else { return mine }
        let byName = Dictionary(mine.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let first = order.compactMap { byName[GlyphTag.slug($0)] ?? GlyphTag(name: $0) }
        let seen = Set(first.map(\.id))
        return first + mine.filter { !seen.contains($0.id) }
    }

    public var body: some View {
        let tags = shown
        VStack(alignment: .leading, spacing: 9) {
            Button { withAnimation(.snappy) { expanded.toggle() } } label: {
                HStack(spacing: 6) {
                    Text("TAGS").font(.system(size: 11.5, weight: .semibold)).tracking(0.5)
                    Text("\(tags.count)").font(.system(size: 11.5)).monospacedDigit()
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                }
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 8).frame(height: 28).contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(expanded ? "Tags, shown. Hide them" : "Tags, hidden. Show them")
            .accessibilityIdentifier("drawer.tagsection")
            if expanded {
                VStack(spacing: 2) {
                    if tags.isEmpty {
                        Text("No tags yet").font(.system(size: 15)).foregroundStyle(.tertiary)
                            .padding(.horizontal, 8).frame(height: 38)
                    }
                    ForEach(tags) { t in
                        if let menu { row(t).contextMenu { menu(t) } } else { row(t) }
                    }
                    if let extra { extra }
                    if app != "crm" {
                        Button { if let u = URL(string: "glyph-crm://tags") { openURL(u) } } label: {
                            HStack(spacing: 11) {
                                Image(systemName: "slider.horizontal.3").font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(.tertiary).frame(width: 22)
                                Text("Manage tags").font(.system(size: 15)).foregroundStyle(.secondary)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 8).frame(height: 38).contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Opens Glyph CRM, where the tags are kept")
                        .accessibilityIdentifier("drawer.tagsection.manage")
                    }
                }
            }
        }
    }

    private func row(_ t: GlyphTag) -> some View {
        let on = here.map { GlyphTag.slug($0) == t.id } ?? false
        return Button { open(t) } label: {
            HStack(spacing: 11) {
                Text("#").font(.system(size: 15, weight: .bold))
                    .foregroundStyle(t.color ?? tint).frame(width: 22)
                Text(GlyphTags.display(t.name)).font(.system(size: 15, weight: on ? .semibold : .regular))
                    .lineLimit(1)
                Spacer(minLength: 0)
                if let n = counts[t.id] { Text("\(n)").font(.system(size: 13)).foregroundStyle(.tertiary).monospacedDigit() }
            }
            .padding(.horizontal, 8).frame(height: 38)
            .background(on ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.clear),
                        in: .rect(cornerRadius: 10, style: .continuous))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(GlyphTags.display(t.name))
        .accessibilityIdentifier("drawer.tag.\(t.id)")
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// Words said on a tag's page, for the app's chat to say with that tag.
public struct GlyphAsk: Equatable, Sendable {
    public let id = UUID()
    public let words: String
    /// The tag, by slug.
    public let tag: String?
    public init(words: String, tag: String?) { self.words = words; self.tag = tag }
}

public struct GlyphChatAskKey: EnvironmentKey {
    // Made and read on the main actor, as every view body is; see GlyphDrawerOpenKey.
    nonisolated(unsafe) public static let defaultValue: Binding<GlyphAsk?>? = nil
}

public struct GlyphAskInChatKey: EnvironmentKey {
    nonisolated(unsafe) public static let defaultValue: ((GlyphAsk) -> Void)? = nil
}

public extension EnvironmentValues {
    /// The words a tag's page sent, which the app's `GlyphChat` says and clears. Set by the shell.
    var glyphChatAsk: Binding<GlyphAsk?>? {
        get { self[GlyphChatAskKey.self] }
        set { self[GlyphChatAskKey.self] = newValue }
    }
    /// What a tag's page does with words: the shell stores them in `glyphChatAsk` and shows its chat.
    var glyphAskInChat: ((GlyphAsk) -> Void)? {
        get { self[GlyphAskInChatKey.self] }
        set { self[GlyphAskInChatKey.self] = newValue }
    }
}

/// The composer at the foot of a tag's page in an app whose talking is its chat (Life, Glyph X,
/// Connect, Omega, Native, Bot): the family's composer, and what is said goes to the app's chat as
/// the next turn with this tag on it, so the hub reads it in the tag's context and files it there.
/// Fru, 2026-11-23: "when I click on the tag, I can just chat or interact with that tag." An app
/// whose tag pages already capture under the tag (Jot, Well, Wealth, Time) keeps its own.
public struct GlyphTagComposer: View {
    let tag: String
    let tint: Color
    @Environment(\.glyphAskInChat) private var askInChat
    /// - tag: the tag's slug or name.
    public init(tag: String, tint: Color) { self.tag = tag; self.tint = tint }
    public var body: some View {
        GlyphComposer(tint: tint, placeholder: "Ask or add to #\(GlyphTags.display(tag))") { words, _ in
            askInChat?(GlyphAsk(words: words, tag: GlyphTag.slug(tag)))
        }
    }
}

/// How a screen asks for the drawer. The shell owns whether it is open; a screen only asks, so a
/// screen never has to be handed a binding it has no business holding.
public struct GlyphDrawerOpenKey: EnvironmentKey {
    // The default is nil, which has nothing to share; the closure an app puts here is made and read
    // on the main actor, as every SwiftUI view body is.
    nonisolated(unsafe) public static let defaultValue: (() -> Void)? = nil
}

public extension EnvironmentValues {
    var glyphDrawerOpen: (() -> Void)? {
        get { self[GlyphDrawerOpenKey.self] }
        set { self[GlyphDrawerOpenKey.self] = newValue }
    }
}

/// Whether the bottom bar is on screen and carrying the drawer button. An app sets it with the
/// same condition it draws its bar under, so the top corner gives the control up while the bar
/// has it and takes it back when the bar steps aside (for the keyboard, or on a screen with no
/// bar). Default false, so a screen that says nothing keeps the corner control it always had.
public struct GlyphDrawerAtBottomKey: EnvironmentKey {
    public static let defaultValue = false
}

public extension EnvironmentValues {
    var glyphDrawerAtBottom: Bool {
        get { self[GlyphDrawerAtBottomKey.self] }
        set { self[GlyphDrawerAtBottomKey.self] = newValue }
    }
}

/// The corner control that opens the drawer, drawn only where there is one to open and the bottom
/// bar is not already offering it. Fru, 2026-11-14: the way in belongs at the bottom left, where a
/// thumb is, not in the one corner it cannot reach. Two hamburgers on one screen is not the answer.
public struct GlyphDrawerButton: View {
    @Environment(\.glyphDrawerOpen) private var open
    @Environment(\.glyphDrawerAtBottom) private var atBottom
    public init() {}
    public var body: some View {
        if let open, !atBottom {
            GlyphDisc("line.3.horizontal", label: "Open the drawer", id: "chrome.drawer", action: open)
        }
    }
}

public extension View {
    /// The drawer over this screen: the scrim, the slide, the swipe from the left edge to open and
    /// the tap or swipe back to close. The gesture lives on a narrow strip of its own, never on
    /// the whole screen: a drag gesture on the container competes with every button inside it for
    /// the same touch, and a tap that loses that race simply does nothing.
    func glyphDrawer(open: Binding<Bool>, @ViewBuilder drawer: () -> GlyphDrawer) -> some View {
        let panel = drawer()
        return ZStack(alignment: .leading) {
            self
            if !open.wrappedValue {
                Color.clear.frame(width: 24).frame(maxHeight: .infinity).contentShape(.rect)
                    .gesture(DragGesture(minimumDistance: 20).onEnded { g in
                        if g.translation.width > 50 { open.wrappedValue = true }
                    })
            }
            if open.wrappedValue {
                Color.black.opacity(0.55).ignoresSafeArea()
                    .onTapGesture { open.wrappedValue = false }
                    .gesture(DragGesture(minimumDistance: 20).onEnded { g in
                        if g.translation.width < -50 { open.wrappedValue = false }
                    })
                    .accessibilityLabel("Close the drawer")
                    .accessibilityIdentifier("drawer.scrim")
                panel.transition(.move(edge: .leading))
            }
        }
        .animation(.easeOut(duration: 0.22), value: open.wrappedValue)
    }
}
#endif
