import SwiftUI

/// The family's corner control: one tappable thing a corner, on a dark disc.
///
/// It was drawn three times over (Glyph Time's chat header, Glyph CRM's `DrawerButton`, and plain
/// toolbar glyphs on the Timer), so it lives here once. A caller passes the symbol, what it does
/// and what it is called. It does not pass a size.
public struct GlyphDisc: View {
    private let symbol: String
    private let label: String
    private let id: String?
    private let tint: Color?
    private let action: () -> Void

    /// - Parameters:
    ///   - symbol: an SF Symbol.
    ///   - label: what a screen reader says, "Open the drawer".
    ///   - id: an accessibility identifier for the UI tests, when the screen has one.
    ///   - tint: the glyph's colour; the app's green when it is the screen's own control, else the
    ///     default foreground.
    public init(_ symbol: String, label: String, id: String? = nil, tint: Color? = nil,
                action: @escaping () -> Void) {
        self.symbol = symbol
        self.label = label
        self.id = id
        self.tint = tint
        self.action = action
    }

    public var body: some View {
        Button(action: action) { GlyphDiscLabel(symbol, tint: tint) }
            .buttonStyle(.plain)
            .accessibilityLabel(label)
            .accessibilityIdentifier(id ?? label)
    }
}

/// The disc itself, with nothing attached to it. A corner that opens a menu rather than doing one
/// thing (Glyph Jot's More) wears this, so there is still one drawing of the disc and not two.
public struct GlyphDiscLabel: View {
    private let symbol: String
    private let tint: Color?

    public init(_ symbol: String, tint: Color? = nil) { self.symbol = symbol; self.tint = tint }

    public var body: some View {
        Image(systemName: symbol).font(.system(size: 16, weight: .semibold))
            .foregroundStyle(tint ?? .primary)
            .frame(width: 36, height: 36)
            .background(Color.glyphDisc, in: Circle())
            .contentShape(Circle())
            // The disc is dark in both appearances, as the composer is (2026-11-18), so what is
            // drawn on it resolves for dark: under a light system `.primary` was black on the
            // near-black disc and the brand green its darker half (Glyph Time, pictured 2026-11-20).
            .environment(\.colorScheme, .dark)
    }
}

/// The family's segmented control: a full-width pill, the chosen half filled with the app's tint,
/// its glyph and word in that tint, the others grey.
///
/// Glyph Time's Timer | Alarm is the first use (Fru, 2026-11-09: "you can simply toggle between
/// timer and alarm"). A caller passes the words, their symbols and which one is on; the height,
/// the shape, the fill and the spacing belong here.
public struct GlyphSegments: View {
    /// One segment: what it is called and the symbol ahead of it.
    public struct Segment {
        public let label: String
        public let symbol: String
        public init(_ label: String, symbol: String) { self.label = label; self.symbol = symbol }
    }

    private let segments: [Segment]
    @Binding private var selection: Int
    private let tint: Color

    public init(_ segments: [Segment], selection: Binding<Int>, tint: Color = .officeGreen) {
        self.segments = segments
        self._selection = selection
        self.tint = tint
    }

    public var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(segments.enumerated()), id: \.offset) { i, s in
                let on = i == selection
                Button { selection = i } label: {
                    HStack(spacing: 8) {
                        Image(systemName: s.symbol).font(.system(size: 17, weight: .semibold))
                        Text(s.label).font(.system(size: 18, weight: .semibold))
                    }
                    .foregroundStyle(on ? tint : Color.secondary)
                    .frame(maxWidth: .infinity).frame(height: 52)
                    .background {
                        if on {
                            Capsule().fill(tint.opacity(0.18))
                                .overlay(Capsule().stroke(tint.opacity(0.35), lineWidth: 1))
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("segment-\(s.label.lowercased())")
                .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(3)
        .background(Color.glyphDisc, in: Capsule())
        // Dark in both appearances, like the disc above: under a light system the unchosen half
        // was dark grey on the near-black pill.
        .environment(\.colorScheme, .dark)
        .animation(.snappy(duration: 0.18), value: selection)
    }
}

public extension Color {
    /// The dark fill under the family's chrome: a corner disc, a segmented control, a quiet bar.
    /// Dark under a light system too, so whatever sits on it takes `.environment(\.colorScheme, .dark)`.
    static let glyphDisc = Color(white: 0.11)
}

/// The top of every Glyph phone screen: one control a corner, the app's mark and full name
/// centred between them.
///
/// Fru, 2026-11-09, on Glyph Time's Timer screen carrying a bare large "Time": "remove the text
/// time from there... Bring it up to the menu at the header where you have the logo, leave time.
/// That's what the other apps have. So I don't know why you put in time there." It was already
/// drawn inline on Glyph Time's chat; it lives here once, and the screen gets the height back.
public struct GlyphAppHeader<Leading: View, Trailing: View>: View {
    private let name: String
    private let mark: String
    private let tint: Color
    private let page: String?
    private let leading: Leading
    private let trailing: Trailing

    /// - Parameters:
    ///   - name: the app as the family names it, "Glyph Time". Never the bare word.
    ///   - mark: the app's SF Symbol, on a small tinted square.
    ///   - tint: the app's green.
    ///   - leading / trailing: one control each, usually a `GlyphDisc`.
    public init(name: String, mark: String, tint: Color = .officeGreen, page: String? = nil,
                @ViewBuilder leading: () -> Leading, @ViewBuilder trailing: () -> Trailing) {
        self.name = name
        self.mark = mark
        self.tint = tint
        self.page = page
        self.leading = leading()
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(spacing: 0) {
            leading
            Spacer(minLength: 0)
            GlyphAppMark(name: name, mark: mark, tint: tint, page: page)
            Spacer(minLength: 0)
            trailing
        }
        .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 6)
    }
}

/// The app block alone: the mark on its tinted square and the full name beside it.
///
/// `GlyphAppHeader` is this between two corners, for a screen that draws its own top bar. A screen
/// that keeps the navigation bar (Glyph Jot's library, because `.searchable` lives there and 283
/// memos need searching) puts this in the bar's principal slot instead. Either way the block is
/// drawn once, so the apps cannot drift apart on the one thing that tells them apart.
public struct GlyphAppMark: View {
    private let name: String
    private let mark: String
    private let tint: Color
    private let page: String?

    /// - Parameters:
    ///   - page: the screen's own name, on this same line. Fru, 2026-11-10: "I don't want to have
    ///     a separate line for the title of the page because it should be on that first header
    ///     where the logo is to make it more compact. So keep this as a design principle going
    ///     forward for all the mobile pages, regardless of the app." A screen that draws a large
    ///     navigation title, or its own title row under this bar, is the bug: two lines of chrome
    ///     before any content, on a phone, on every screen.
    public init(name: String, mark: String, tint: Color = .officeGreen, page: String? = nil) {
        self.name = name; self.mark = mark; self.tint = tint; self.page = page
    }

    @Environment(\.glyphHome) private var home

    public var body: some View {
        if let home {
            // The mark and name go home (Fru, 2026-11-23); the line stays one container named
            // "glyph.page", so a check still reads which app and page it is on.
            HStack(spacing: 8) {
                GlyphHomeButton(app: name, go: home) { appBlock }
                pageName
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(page.map { "\(name), \($0)" } ?? name)
            .accessibilityIdentifier("glyph.page")
        } else {
            HStack(spacing: 8) { appBlock; pageName }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(page.map { "\(name), \($0)" } ?? name)
                // One name for the family's top line, so a check can ask which app and which page it is
                // on without hunting for a navigation bar that no Glyph screen draws any more.
                .accessibilityIdentifier("glyph.page")
        }
    }

    private var appBlock: some View {
        HStack(spacing: 8) {
            Image(systemName: mark).font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white).frame(width: 20, height: 20)
                .background(tint, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            Text(name).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var pageName: some View {
        if let page {
            // The app says which app, the page says which screen, and the dot keeps them
            // from reading as one phrase ("Glyph CRM Orgs").
            Circle().fill(.tertiary).frame(width: 3, height: 3).accessibilityHidden(true)
            Text(page).font(.system(size: 15, weight: .semibold)).foregroundStyle(.primary)
                .lineLimit(1).minimumScaleFactor(0.8)
        }
    }
}
