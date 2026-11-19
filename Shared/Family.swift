import Foundation
@_exported import GlyphCapture

/// The Glyph Native family: every app and how to open it on the iPhone (its URL scheme). The list
/// the iPhone launcher shows.
public struct FamilyApp: Identifiable, Hashable, Sendable {
    public let id: String          // also the icon's asset name ("icon-<id>")
    public let name: String
    public let job: String
    public let scheme: String      // opens the iPhone app: "<scheme>://"
    public let iosBundle: String?
    public let macBundle: String?
    /// This app has a build on TestFlight, so the iPhone can install it by itself. An app with no
    /// record in App Store Connect has nowhere to install it from but a Mac, and says so.
    /// Checked 2026-11-13: only Glyph Jot ("Glyph Labs") has one, with five valid builds.
    public let onTestFlight: Bool
    /// A layer of the family that is not an app at all: Glyph Ibis is the context sources on the
    /// web. Fru, 2026-11-15: "Why is glyph ibis not an app on mobile launcher glyph native?" It
    /// was missing because this list only held things with a bundle to launch. A web entry opens
    /// its address and is never offered as an install.
    public let site: String?
    public var url: URL { site.flatMap { URL(string: $0) } ?? URL(string: "\(scheme)://")! }
    public var isWeb: Bool { site != nil }

    public init(id: String, name: String, job: String, scheme: String, iosBundle: String?, macBundle: String?,
                onTestFlight: Bool, site: String? = nil) {
        self.id = id; self.name = name; self.job = job; self.scheme = scheme
        self.iosBundle = iosBundle; self.macBundle = macBundle; self.onTestFlight = onTestFlight; self.site = site
    }
}

public enum Family {
    public static let apps: [FamilyApp] = [
        FamilyApp(id: "jot", name: "Glyph Jot", job: "Capture your ideas locally", scheme: "jot",
                  iosBundle: "dev.fru.jot", macBundle: "dev.fru.jot.mac", onTestFlight: true),
        FamilyApp(id: "time", name: "Glyph Time", job: "Time tracking that tracks itself", scheme: "glyph-time",
                  iosBundle: "dev.fru.time.ios", macBundle: "dev.fru.time", onTestFlight: false),
        FamilyApp(id: "well", name: "Glyph Well", job: "Wellness, fitness and health, in one log", scheme: "glyph-well",
                  iosBundle: "dev.fru.well.ios", macBundle: "dev.fru.well", onTestFlight: false),
        FamilyApp(id: "crm", name: "Glyph CRM", job: "Everyone and everything you know", scheme: "glyph-crm",
                  iosBundle: "dev.fru.crm.ios", macBundle: "dev.fru.crm", onTestFlight: false),
        FamilyApp(id: "omega", name: "Glyph Omega", job: "Your mission, where agents can read it", scheme: "glyph-omega",
                  iosBundle: "dev.fru.omega.ios", macBundle: "dev.fru.omega", onTestFlight: false),
        FamilyApp(id: "studio", name: "Glyph Bot", job: "Where your agents get to work", scheme: "glyph-studio",
                  iosBundle: "dev.fru.studio.ios", macBundle: "dev.fru.studio", onTestFlight: false),
        // Mac only, and its own repo (a Tauri app): no iPhone app, and
        // Install All never builds it. It is listed so its version and its routes are visible here.
        FamilyApp(id: "arena", name: "Glyph Arena", job: "Stop guessing which model", scheme: "glyph-arena",
                  iosBundle: nil, macBundle: "dev.fru.glyph.arena", onTestFlight: false),
        // Not an app: the context sources, on the web. It belongs on this page because it is one
        // of the family's four layers, and leaving it off was the page saying it does not exist.
        FamilyApp(id: "ibis", name: "Glyph Ibis", job: "Global context for your agents", scheme: "",
                  iosBundle: nil, macBundle: nil, onTestFlight: false, site: "https://glyph.fru.dev/ibis"),
        FamilyApp(id: "connect", name: "Glyph Connect", job: "Plug your agents into the apps you use", scheme: "glyph-connect",
                  iosBundle: "dev.fru.connect.ios", macBundle: "dev.fru.connect", onTestFlight: false),
        FamilyApp(id: "wealth", name: "Glyph Wealth", job: "The AI ledger that never guesses", scheme: "glyph-wealth",
                  iosBundle: "dev.fru.wealth.ios", macBundle: "dev.fru.wealth", onTestFlight: false),
        FamilyApp(id: "life", name: "Glyph Life", job: "The paperwork handles itself", scheme: "glyph-life",
                  iosBundle: "dev.fru.life.ios", macBundle: "dev.fru.life", onTestFlight: false),
        FamilyApp(id: "travel", name: "Glyph X", job: "Travel and exploration", scheme: "glyph-travel",
                  iosBundle: "dev.fru.travel.ios", macBundle: "dev.fru.travel", onTestFlight: false),
    ]
}

#if os(iOS)
import SwiftUI
import UIKit

/// An app's own icon, the one on its Home screen tile: the family figure with that app's head
/// (`icon-<id>` in this app's catalogue, rendered by scripts/icons.sh from each app's master).
///
/// Drawn wherever the app is shown big. The other asset, `mark-<id>`, is the head alone with the
/// figure cut away: it was made for the 36pt rows the Apps page used to be, where six whole
/// figures read as one shape. On a tile it is not the app's logo, it is a crop of it, which is
/// why Glyph Jot showed as a bare capsule and Glyph Well as a plain heart (Fru, 2026-11-11: "use
/// the correct Glyph logos"). The crop is still right where the picture is tiny, as on the Now
/// card's 24pt badge, and nowhere else.
///
/// Three of the family (Connect, Wealth, Life) have no artwork in this catalogue yet, and a
/// missing image draws as nothing at all, so those fall back to a plain tile in the app's colour
/// rather than a hole.
public struct GlyphAppIcon: View {
    private let id: String
    private let size: CGFloat
    private let fallback: Color

    public init(_ id: String, size: CGFloat, fallback: Color = .officeGreen) {
        self.id = id; self.size = size; self.fallback = fallback
    }

    public var body: some View {
        let corner = RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
        Group {
            if UIImage(named: "icon-\(id)") != nil {
                Image("icon-\(id)").resizable()
            } else {
                corner.fill(fallback)
            }
        }
        .frame(width: size, height: size)
        .clipShape(corner)
    }
}
#endif
