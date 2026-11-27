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
    private let waiting: Int
    private let action: (() -> Void)?
    private let iphone: (app: String, link: URL)?

    /// - Parameters:
    ///   - live: true when the vault is reachable right now. Never a remembered answer.
    ///   - says: an app's own words for the live case, when "Saving to your vault" is wrong for it
    ///     (Glyph Rig reads, it does not save). The away case is the same sentence everywhere.
    ///   - waiting: how many entries have not reached the vault yet. The one number on a sidebar
    ///     that means something is not safe yet, so it is shown in the family's warm colour and
    ///     nothing is drawn when it is zero.
    ///   - action: where the line goes, normally the app's settings page.
    ///   - iphone: the app's name and its real iPhone install page; adds the iPhone icon at the end of the
    ///     gear's line (the QR sheet, `GlyphGetPhoneRow`). Nil when the app has no public install page.
    public init(live: Bool, says: String? = nil, waiting: Int = 0, iphone: (app: String, link: URL)? = nil,
                action: (() -> Void)? = nil) {
        self.iphone = iphone
        self.live = live
        self.says = says
        self.waiting = waiting
        self.action = action
    }

    public var body: some View {
        let line = HStack(spacing: 8) {
            Circle().fill(live ? Color.glyphGreen : Color.secondary).frame(width: 7, height: 7)
            Text(live ? (says ?? "Saving to your vault") : "Saving on this Mac")
                .font(.footnote).foregroundStyle(.secondary).lineLimit(1)
            Spacer(minLength: 0)
            if waiting > 0 {
                Text("\(waiting) waiting")
                    .font(.system(size: 11.5).monospacedDigit())
                    .foregroundStyle(Color.glyphWarm)
                    .accessibilityIdentifier("vault-waiting")
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityIdentifier("vault-foot")

        // Two rows (Fru, 2026-11-27: make it "more compact as opposed to having 3 levels"): the coffee
        // bar, then one line with the gear at the left, the vault in the middle and the iPhone at the right.
        VStack(spacing: 0) {
            GlyphSupportRow()
            HStack(spacing: 0) {
                if let action {
                    Button(action: action) {
                        Image(systemName: "gearshape").font(.system(size: 14, weight: .medium)).foregroundStyle(.secondary)
                            .frame(width: 26, height: 26).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Settings")
                    .glyphProbe("settings")
                    .padding(.leading, 12)
                    Button(action: action) { line.padding(.leading, -10) }.buttonStyle(.plain).help("Your vault, in Settings")
                } else {
                    line
                }
                if let iphone {
                    GlyphGetPhoneRow(app: iphone.app, link: iphone.link, compact: true).padding(.trailing, 12)
                }
            }
            .padding(.top, 4).padding(.bottom, 8)
        }
    }
}
#endif
