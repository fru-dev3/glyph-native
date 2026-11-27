#if os(macOS)
import SwiftUI

/// The foot of every Glyph Mac app's sidebar: the gear (bottom left), and whether the vault is answering, in one line.
///
/// Fru, 2026-11-15, going through the family app by app: "Where you paste showing that is connected
/// to the vault should be consistent." Glyph Travel had this line, Glyph Wealth said it only inside
/// its settings, and most of the others never said it at all, so the one question every app can
/// answer differently got a different answer in each.
///
/// It sits under the sidebar's list, opposite `GlyphSidebarHeader` at the top, and says only what is
/// true right now: the vault, or this Mac. Tapping it goes to the app's settings, where the vault
/// panel can be read in full.
///
/// ```swift
/// List(selection: $page) { ... }
///     .safeAreaInset(edge: .top, spacing: 0) { GlyphSidebarHeader(name: "Glyph Life") { page = .settings } }
///     .safeAreaInset(edge: .bottom, spacing: 0) { GlyphSidebarFoot(live: store.vault != nil) { page = .settings } }
/// ```
public struct GlyphSidebarFoot: View {
    private let live: Bool
    private let says: String?
    private let reads: Bool
    private let detail: String?
    private let refresh: (() -> Void)?
    private let waiting: Int
    private let app: String?
    private let action: (() -> Void)?
    private let back: (() -> Void)?
    private let iphone: (app: String, link: URL)?
    private let settingsOpen: Bool
    @State private var hovering = false

    /// - Parameters:
    ///   - live: true when the vault is reachable right now. Never a remembered answer.
    ///   - says: an app's own words for the live case, when neither of the family's two is right. Leave it
    ///     out: the family says "Saving to your vault", or "Reading your vault" with `reads`.
    ///   - reads: the app only reads the vault (Glyph Connect, Glyph Life, Glyph Rig): "Reading your vault",
    ///     and "Vault not found" when it is away, since nothing is saved on this Mac instead.
    ///   - detail: the app's own status, after the words ("Reading your vault · 1 h old"). Never a row of its own.
    ///   - refresh: when set, a click on the words runs it, and a refresh mark shows on hover.
    ///   - waiting: how many entries have not reached the vault yet, at the end of the words in the family's
    ///     warm colour; nothing when it is zero.
    ///   - app: the app's name, sent to the support page as `?from=` (the iPhone entry's name when left out).
    ///   - iphone: the app's name and its real iPhone install page; adds the iPhone icon. Nil when the app has
    ///     no public install page.
    ///   - settingsOpen: true while the app shows its settings. The gear is then an X that says "Back" and
    ///     runs `back` (Fru, 2026-11-27, design A: one control both ways).
    ///   - back: where the X goes, normally the app's first page. Without it the X runs `action`.
    ///   - action: where the gear and the words go, the app's settings page.
    public init(live: Bool, says: String? = nil, reads: Bool = false, detail: String? = nil, refresh: (() -> Void)? = nil,
                waiting: Int = 0, app: String? = nil, iphone: (app: String, link: URL)? = nil,
                settingsOpen: Bool = false, back: (() -> Void)? = nil,
                action: (() -> Void)? = nil) {
        self.live = live
        self.says = says
        self.reads = reads
        self.detail = detail
        self.refresh = refresh
        self.waiting = waiting
        self.app = app ?? iphone?.app
        self.iphone = iphone
        self.settingsOpen = settingsOpen
        self.back = back
        self.action = action
    }

    /// Two words, so they fit the narrowest sidebar (220pt) beside the gear, the iPhone and the coffee:
    /// "Saving to your vault" was cut to "Saving to y..." (Fru's foot, 2026-11-27). The full sentence is the tooltip.
    private var words: String {
        let base = live ? (says ?? "Your vault") : (reads ? "No vault" : "This Mac")
        return detail.map { "\(base) · \($0)" } ?? base
    }

    private var sentence: String {
        live ? (reads ? "Reading your vault" : "Saving to your vault")
             : (reads ? "Vault not found" : "Saving on this Mac only; your vault is not reachable")
    }

    /// One row, about 44 points, under a hairline (Fru, 2026-11-27, design A of the foot board): the gear,
    /// the vault's state filling the middle, the iPhone, and the round coffee button. It was two rows, the
    /// coffee bar above the gear's line.
    public var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 2) {
                if let action {
                    Button(action: settingsOpen ? (back ?? action) : action) {
                        Image(systemName: settingsOpen ? "xmark" : "gearshape")
                            .font(.system(size: 14, weight: .medium)).foregroundStyle(.secondary)
                            .frame(width: 32, height: 32).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(settingsOpen ? "Back" : "Settings")
                    .glyphProbe("settings")
                }
                status
                if let iphone {
                    GlyphGetPhoneRow(app: iphone.app, link: iphone.link, compact: true).frame(width: 32, height: 32)
                }
                GlyphSupportButton(app: app)
            }
            .padding(.horizontal, 8)
            .frame(height: 44)
        }
    }

    private var status: some View {
        let line = HStack(spacing: 7) {
            Circle().fill(live ? Color.glyphGreen : Color.secondary).frame(width: 7, height: 7)
            Text(words).font(.system(size: 12.5)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
            if waiting > 0 {
                Text("\(waiting) waiting")
                    .font(.system(size: 12.5).monospacedDigit())
                    .foregroundStyle(Color.glyphWarm)
                    .fixedSize()
                    .accessibilityIdentifier("vault-waiting")
            }
            if refresh != nil, hovering {
                Image(systemName: "arrow.clockwise").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, action == nil ? 8 : 2)
        .frame(maxWidth: .infinity, minHeight: 32)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .accessibilityIdentifier("vault-foot")
        return Group {
            if let run = refresh ?? action {
                Button(action: run) { line }.buttonStyle(.plain)
                    .help(refresh != nil ? "\(sentence). Click to read it again" : "\(sentence). Click for Settings")
            } else {
                line.help(sentence)
            }
        }
    }
}
#endif
