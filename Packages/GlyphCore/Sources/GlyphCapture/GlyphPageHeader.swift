#if canImport(SwiftUI)
import SwiftUI

/// The family's one top line: the app's mark, the app's name, and the page's name, all on the row
/// the navigation bar already owns.
///
/// Fru, 2026-11-10: "I don't want to have a separate line for the title of the page because it
/// should be on that first header where the logo is to make it more compact. So keep this as a
/// design principle going forward for all the mobile pages, regardless of the app."
///
/// Glyph Wealth has drawn this since; Glyph Life and Glyph Travel were still handing the page's
/// name to `navigationTitle`, which draws the name on its own and says nothing about which app you
/// are in (Fru, 2026-11-18, looking at the family's phone screens). Used as the principal item of
/// the navigation bar, so a pushed page keeps its own back chevron and nothing else moves:
///
///     .toolbar { ToolbarItem(placement: .principal) { GlyphPageHeader("Glyph Life", mark: "tray.full", page: "Due", tint: Look.green) } }
public struct GlyphPageHeader: View {
    let app: String
    let mark: String
    let page: String
    let tint: Color
    let home: (() -> Void)?
    @Environment(\.glyphHome) private var shellHome

    /// `home` makes the mark and the app's name one button that goes to the app's home screen
    /// (Fru, 2026-11-23: tapping the app's name takes you home, from every screen). Left nil, the
    /// header takes the one the shell put in `\.glyphHome`; with neither, it is plain text.
    public init(_ app: String, mark: String, page: String, tint: Color, home: (() -> Void)? = nil) {
        self.app = app; self.mark = mark; self.page = page; self.tint = tint; self.home = home
    }

    public var body: some View {
        GlyphHeaderLine(app: app, page: page, home: home ?? shellHome) {
            Image(systemName: mark)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(tint, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
    }
}

/// The top line's layout, for any mark: the mark, the app's name, a dot and the page's name, on one
/// line. Where that does not fit (a sheet's bar with Cancel and Save either side, an iPhone SE,
/// the largest text), it gives up the app's words before the page's: first the full line, then
/// the mark and the page alone, the mark still saying which app this is. Never two lines, never a
/// page name cut to "New Obj..." (Fru, 2026-11-24: titles squeezed between Cancel and Save).
/// `GlyphPageHeader` draws it with an SF Symbol; an app with its own drawn mark (Glyph Wealth's
/// coin) passes that instead, so the fitting lives in one place.
public struct GlyphHeaderLine<Mark: View>: View {
    let app: String
    let page: String
    let home: (() -> Void)?
    let mark: Mark
    public init(app: String, page: String, home: (() -> Void)? = nil, @ViewBuilder mark: () -> Mark) {
        self.app = app; self.page = page; self.home = home; self.mark = mark()
    }

    public var body: some View {
        ViewThatFits(in: .horizontal) {
            line(named: true)
            line(named: false)
        }
    }

    @ViewBuilder func line(named: Bool) -> some View {
        let brand = HStack(spacing: 8) {
            mark
            if named {
                Text(app)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        if let go = home {
            HStack(spacing: 8) {
                GlyphHomeButton(app: app, go: go) { brand }
                dot
                pageName(fixed: named)
            }
        } else {
            HStack(spacing: 8) { brand; dot; pageName(fixed: named) }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(app), \(page)")
        }
    }

    // The dot keeps the two from reading as one phrase ("Glyph Life Due").
    var dot: some View { Circle().fill(.secondary.opacity(0.6)).frame(width: 3, height: 3).accessibilityHidden(true) }

    /// Whole on the named line, so ViewThatFits can tell it does not fit and drop the name; on the
    /// last line it may shrink a little, since there is nothing left to give up.
    @ViewBuilder func pageName(fixed: Bool) -> some View {
        let t = Text(page).font(.system(size: 15, weight: .semibold)).lineLimit(1)
        if fixed { t.fixedSize() } else { t.minimumScaleFactor(0.7) }
    }
}

/// Which app this is, set once by the app's shell beside `\.glyphHome`, so a sheet GlyphCore
/// draws for every app (New tag, Past chats) can say whose it is on its top line. nil leaves the
/// sheet's plain title.
public struct GlyphApp {
    public let name: String
    public let mark: String
    public let tint: Color
    /// An app whose mark is drawn rather than a symbol (Glyph Wealth's coin) hands that in, so a
    /// sheet's line carries the same mark as the app's own top bar.
    public let drawn: AnyView?
    public init(name: String, mark: String, tint: Color) { self.name = name; self.mark = mark; self.tint = tint; drawn = nil }
    public init<M: View>(name: String, tint: Color, @ViewBuilder drawn: () -> M) {
        self.name = name; mark = ""; self.tint = tint; self.drawn = AnyView(drawn())
    }
}

public struct GlyphAppKey: EnvironmentKey {
    // Made and read on the main actor, as every SwiftUI view body is (as GlyphHomeKey).
    nonisolated(unsafe) public static let defaultValue: GlyphApp? = nil
}

public extension EnvironmentValues {
    var glyphApp: GlyphApp? {
        get { self[GlyphAppKey.self] }
        set { self[GlyphAppKey.self] = newValue }
    }
}

/// A shared sheet's title: the app's top line when the shell said which app this is, else the
/// sheet's name alone. Not a way home: a sheet closes with Cancel or its drag, and going home
/// under it would change the screen it returns to.
public struct GlyphSheetTitle: View {
    let page: String
    @Environment(\.glyphApp) private var app
    public init(_ page: String) { self.page = page }
    public var body: some View {
        if let app, let drawn = app.drawn {
            GlyphHeaderLine(app: app.name, page: page) { drawn }
        } else if let app {
            GlyphPageHeader(app.name, mark: app.mark, page: page, tint: app.tint)
                .environment(\.glyphHome, nil)
        } else {
            Text(page).font(.system(size: 17, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
        }
    }
}

/// The mark and the app's name as one button home: `chrome.home`, 44 points tall at least, named
/// "<App>, home" for a screen reader. The page's name beside it stays plain text. An app that
/// draws its own top line wraps its mark and name in this, so every app answers the same tap.
public struct GlyphHomeButton<Label: View>: View {
    let app: String
    let go: () -> Void
    let label: Label
    public init(app: String, go: @escaping () -> Void, @ViewBuilder label: () -> Label) {
        self.app = app; self.go = go; self.label = label()
    }
    public var body: some View {
        Button(action: go) { label.frame(minHeight: 44).contentShape(.rect) }
            .buttonStyle(.plain)
            .accessibilityLabel("\(app), home")
            .accessibilityHint("Goes to the home screen")
            .accessibilityIdentifier("chrome.home")
    }
}

/// How a screen's top line goes home. The shell sets it once at its root (pop the stack, pick the
/// home place); every `GlyphPageHeader` under it, and an app's own top line, reads it. Default
/// nil: an app that sets nothing keeps a header with no action.
public struct GlyphHomeKey: EnvironmentKey {
    // Made and read on the main actor, as every SwiftUI view body is (as GlyphDrawerOpenKey).
    nonisolated(unsafe) public static let defaultValue: (() -> Void)? = nil
}

public extension EnvironmentValues {
    var glyphHome: (() -> Void)? {
        get { self[GlyphHomeKey.self] }
        set { self[GlyphHomeKey.self] = newValue }
    }
}
#endif
