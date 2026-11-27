#if os(macOS)
import AppKit
import SwiftUI

/// The support button at the foot of every Glyph Mac app's sidebar: a solid green bar, a coffee cup and
/// "Buy me a coffee", opening the support page (glyph.fru.dev/support) in the browser, where the coffee is.
/// Not Buy Me a Coffee directly (Fru, same day: "this doesn't go to support page").
///
/// Fru, 2026-11-26: the support page "needs to be very prominent almost everywhere. Like, you cannot
/// miss it", then, of Glyph Jot's sidebar, bring it into the apps. The websites carry the same green
/// button (glyph.fru.dev/support.js). Not a heart (Fru, same day: it must read as paying at a glance;
/// the coffee cup is the pattern people already know). It is one full-width row, never a second control beside the gear.
/// Mac only: the App Store does not allow a donation link in an iPhone app.
public struct GlyphSupportRow: View {
    private let link: URL
    /// Each app's own choice, shown by default (Fru, 2026-11-27: "you're not forcing users to see it
    /// all the time"). Turned off with `GlyphSupportToggle` in the app's Settings, or Hide on a right-click.
    @AppStorage(GlyphSupportRow.shownKey) private var shown = true
    public static let shownKey = "glyph.showSupport"

    /// - Parameter app: the app's name, sent as `?from=` so the page knows where the tap came from.
    public init(app: String? = nil) {
        var c = URLComponents(string: "https://glyph.fru.dev/support")!
        if let app { c.queryItems = [URLQueryItem(name: "from", value: app)] }
        link = c.url!
    }

    public var body: some View {
        if shown { bar }
    }

    private var bar: some View {
        Button { NSWorkspace.shared.open(link) } label: {
            HStack(spacing: 7) {
                Image(systemName: "cup.and.saucer.fill").font(.system(size: 13, weight: .semibold))
                Text("Buy me a coffee").font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .bold)).opacity(0.8)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12).frame(height: 32)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.officeGreen))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Everything in Glyph is free, built by one person. Buy me a coffee to keep it going.")
        .padding(.horizontal, 12).padding(.top, 6).padding(.bottom, 2)
        .glyphProbe("support")
        .accessibilityIdentifier("support-row")
        .contextMenu { Button("Hide (Settings can show it again)") { shown = false } }
    }
}

/// The coffee as a round button, at the end of the sidebar foot's one row (Fru, 2026-11-27, design A):
/// a 32-point office green circle with a white cup, opening the same support page. Hidden by the same
/// Settings switch, and Hide on a right-click.
public struct GlyphSupportButton: View {
    private let link: URL
    @AppStorage(GlyphSupportRow.shownKey) private var shown = true

    /// - Parameter app: the app's name, sent as `?from=`.
    public init(app: String? = nil) {
        var c = URLComponents(string: "https://glyph.fru.dev/support")!
        if let app { c.queryItems = [URLQueryItem(name: "from", value: app)] }
        link = c.url!
    }

    public var body: some View {
        if shown {
            Button { NSWorkspace.shared.open(link) } label: {
                Image(systemName: "cup.and.saucer.fill").font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color.officeGreen))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Buy me a coffee: everything in Glyph is free, built by one person")
            .glyphProbe("support")
            .accessibilityIdentifier("support-button")
            .contextMenu { Button("Hide (Settings can show it again)") { shown = false } }
        }
    }
}

/// The Settings switch for the coffee bar: one line, for every Glyph Mac app's Settings page.
public struct GlyphSupportToggle: View {
    @AppStorage(GlyphSupportRow.shownKey) private var shown = true
    public init() {}
    public var body: some View {
        Toggle("Show the Buy me a coffee button", isOn: $shown)
            .help("The green button at the foot of the sidebar. Everything in Glyph stays free either way.")
            .accessibilityIdentifier("support-toggle")
    }
}
#endif
