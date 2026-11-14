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
    /// Checked 2026-11-13: only Glyph Jot ("Glyph by fru.dev") has one, with five valid builds.
    public let onTestFlight: Bool
    public var url: URL { URL(string: "\(scheme)://")! }
}

public enum Family {
    public static let apps: [FamilyApp] = [
        FamilyApp(id: "jot", name: "Glyph Jot", job: "Personal context", scheme: "jot",
                  iosBundle: "dev.fru.jot", macBundle: "dev.fru.jot.mac", onTestFlight: true),
        FamilyApp(id: "time", name: "Glyph Time", job: "Where your hours go", scheme: "glyph-time",
                  iosBundle: "dev.fru.time.ios", macBundle: "dev.fru.time", onTestFlight: false),
        FamilyApp(id: "well", name: "Glyph Well", job: "Fitness, nutrition and mood", scheme: "glyph-well",
                  iosBundle: "dev.fru.well.ios", macBundle: "dev.fru.well", onTestFlight: false),
        FamilyApp(id: "crm", name: "Glyph CRM", job: "People, places, products, things", scheme: "glyph-crm",
                  iosBundle: "dev.fru.crm.ios", macBundle: "dev.fru.crm", onTestFlight: false),
        FamilyApp(id: "omega", name: "Glyph Omega", job: "Mission, vision, values and goals", scheme: "glyph-omega",
                  iosBundle: "dev.fru.omega.ios", macBundle: "dev.fru.omega", onTestFlight: false),
        FamilyApp(id: "studio", name: "Glyph Bot", job: "Your agents, with all of it", scheme: "glyph-studio",
                  iosBundle: "dev.fru.studio.ios", macBundle: "dev.fru.studio", onTestFlight: false),
        // Mac only, and its own repo (a Tauri app): no iPhone app, and
        // Install All never builds it. It is listed so its version and its routes are visible here.
        FamilyApp(id: "arena", name: "Glyph Arena", job: "The best recipe for each task", scheme: "glyph-arena",
                  iosBundle: nil, macBundle: "dev.fru.glyph.arena", onTestFlight: false),
        FamilyApp(id: "connect", name: "Glyph Connect", job: "Where tools plug in", scheme: "glyph-connect",
                  iosBundle: "dev.fru.connect.ios", macBundle: "dev.fru.connect", onTestFlight: false),
        FamilyApp(id: "wealth", name: "Glyph Wealth", job: "Accounts, spending and what it means", scheme: "glyph-wealth",
                  iosBundle: "dev.fru.wealth.ios", macBundle: "dev.fru.wealth", onTestFlight: false),
        FamilyApp(id: "life", name: "Glyph Life", job: "Personal administration", scheme: "glyph-life",
                  iosBundle: "dev.fru.life.ios", macBundle: "dev.fru.life", onTestFlight: false),
        FamilyApp(id: "travel", name: "Glyph X", job: "Trips, bookings and documents", scheme: "glyph-travel",
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
