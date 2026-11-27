#if os(macOS)
import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI
import GlyphVault
import GlyphAI

/// "Get <App> on your iPhone": a QR code to scan, the same sheet in every Glyph Mac app.
///
/// Fru, 2026-11-26, after another dictation app's "get it on your phone" row: "you can click, and then it will give you
/// the QR code. You scan it, and then you can just install the mobile app from the App Store."
///
/// The link is the app's real install page, passed in by the app, never made up here. There is no
/// "text yourself the link": nothing in the family sends a message on its owner's behalf. The code is
/// drawn natively (Core Image's QR generator, scaled by whole modules with nearest-neighbour so every
/// module edge stays sharp), always dark on a white tile so it scans in light and dark mode alike.
///
/// ```swift
/// // the sidebar, above the vault foot
/// GlyphGetPhoneRow(app: "Glyph Time", link: URL(string: "https://glyph.fru.dev/time")!)
/// // or from a menu: .sheet(isPresented: $show) { GlyphGetPhoneSheet(app: "Glyph Time", link: link) }
/// ```
public enum GlyphGetPhone {
    /// The QR code for `text` as pixels: one whole number of points per module, no smoothing.
    /// `side` is the wanted size in points; the result is the largest whole-module size that fits.
    public static func qr(_ text: String, side: CGFloat = 220, scale: CGFloat = 2) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"
        guard let code = filter.outputImage else { return nil }
        let modules = code.extent.width
        let per = max(1, floor(side * scale / modules))
        let big = code.samplingNearest().transformed(by: CGAffineTransform(scaleX: per, y: per))
        guard let cg = CIContext(options: [.useSoftwareRenderer: true]).createCGImage(big, from: big.extent) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: CGFloat(cg.width) / scale, height: CGFloat(cg.height) / scale))
    }

    /// Reads a QR code's text back out of an image, the way a phone camera would. Used by the check.
    public static func decode(_ image: NSImage) -> String? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        // The generator draws no quiet zone; a camera needs one, so pad it as the sheet does.
        let pad = 24
        let w = cg.width + pad * 2, h = cg.height + pad * 2
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setFillColor(CGColor(gray: 1, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.draw(cg, in: CGRect(x: pad, y: pad, width: cg.width, height: cg.height))
        guard let padded = ctx.makeImage(),
              let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])
        else { return nil }
        let found = detector.features(in: CIImage(cgImage: padded))
        return (found.first as? CIQRCodeFeature)?.messageString
    }
}

public struct GlyphGetPhoneSheet: View {
    private let app: String
    private let link: URL
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false
    @State private var code: GlyphPhonePairing.Code?
    @State private var asked = false

    /// - Parameters:
    ///   - app: the app as the family names it, "Glyph Time".
    ///   - link: its page on the site, used only when the app has no row in `GlyphPhoneApps`.
    public init(app: String, link: URL) {
        self.app = app
        self.link = link
    }

    /// One link for install and pairing: glyph.fru.dev/pair with this app, this Mac's address and a fresh code.
    /// With no phone link on this Mac it is the install page alone.
    var pairLink: String {
        let id = GlyphPhoneApps.find(app)?.id
        guard let c = code, let a = c.address else { return id.map { GlyphHub.pairLink(app: $0, address: nil, name: "", code: nil) } ?? link.absoluteString }
        return GlyphHub.pairLink(app: id, address: a, name: c.name, code: c.code.isEmpty ? nil : c.code, bonjour: c.name)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable().interpolation(.high).frame(width: 44, height: 44)
                Text("Get \(app) on your iPhone").font(.system(size: 17, weight: .semibold))
                Spacer(minLength: 0)
            }
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                let gone = code.map { !$0.code.isEmpty && $0.expires <= ctx.date } ?? false
                VStack(spacing: 10) {
                    Group {
                        if let image = GlyphGetPhone.qr(pairLink) {
                            Image(nsImage: image).interpolation(.none).resizable().scaledToFit().frame(width: image.size.width, height: image.size.height)
                        } else {
                            Text("The code could not be drawn.").foregroundStyle(.secondary).frame(width: 220, height: 220)
                        }
                    }
                    .padding(16)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.12), lineWidth: 1))
                    .opacity(gone ? 0.25 : 1)
                    .glyphProbe("get-phone-qr")
                    if let c = code, !c.code.isEmpty {
                        if gone {
                            Button("Make a new code") { Task { await ask() } }.glyphProbe("get-phone-newcode")
                        } else {
                            Text("Good for \(max(1, Int(c.expires.timeIntervalSince(ctx.date) / 60))) min, pairs one phone").font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }.frame(maxWidth: .infinity)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Point your iPhone's camera at it.").font(.system(size: 15, weight: .medium))
                Text(code?.address != nil ? "It installs the app if you don't have it, then pairs it with this Mac."
                     : asked ? "It installs the app. To pair it, open Glyph Native on this Mac and turn on Share with my iPhone." : "Asking this Mac for a code.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if let c = code, c.address != nil {
                VStack(alignment: .leading, spacing: 6) {
                    status(true, "This Mac is ready for your phone")
                    if c.tailnet { status(true, "Works away from home through Tailscale") }
                    else {
                        HStack(spacing: 8) {
                            status(false, "Away from home needs Tailscale on this Mac")
                            Link("Set up", destination: URL(string: "https://tailscale.com/download")!).font(.callout.weight(.semibold)).tint(.officeGreen)
                                .glyphProbe("get-phone-tailscale")
                        }
                    }
                }
            }
            HStack(spacing: 10) {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(pairLink, forType: .string)
                    copied = true
                } label: {
                    Label(copied ? "Copied" : "Copy link", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .glyphProbe("get-phone-copy")
                Spacer(minLength: 0)
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction).tint(.officeGreen)
                    .glyphProbe("get-phone-done")
            }
            .controlSize(.large)
        }
        .padding(24)
        .frame(width: 420)
        .accessibilityIdentifier("get-phone-sheet")
        .task { await ask() }
    }

    private func ask() async { code = await GlyphPhonePairing.code(); asked = true }

    private func status(_ ok: Bool, _ s: String) -> some View {
        HStack(spacing: 8) {
            Circle().fill(ok ? Color.officeGreen : Color.secondary.opacity(0.5)).frame(width: 8, height: 8)
            Text(s).font(.callout).foregroundStyle(ok ? .primary : .secondary)
        }
    }
}

/// The sidebar row, or any list row, that opens the sheet: "Get the iPhone app".
public struct GlyphGetPhoneRow: View {
    private let app: String
    private let link: URL
    private let compact: Bool
    @State private var shown = false

    /// - Parameter compact: the phone icon alone, for the end of the gear's line (Fru, 2026-11-27:
    ///   "I don't think we need those 2 rows separate"). The words move to the tooltip.
    public init(app: String, link: URL, compact: Bool = false) {
        self.app = app
        self.link = link
        self.compact = compact
    }

    public var body: some View {
        Button { shown = true } label: {
            if compact {
                Image(systemName: "iphone").font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 26, height: 26).contentShape(Rectangle())
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "iphone").font(.system(size: 13)).frame(width: 16)
                    Text("Get the iPhone app").font(.footnote)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 18).padding(.vertical, 6)
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .help("Get the iPhone app: \(app) on your iPhone")
        .glyphProbe("get-phone")
        .sheet(isPresented: $shown) { GlyphGetPhoneSheet(app: app, link: link) }
        // For the UI checks: GLYPH_PHONE_SHEET=1 opens the sheet at launch, so it can be pictured.
        .onAppear { if ProcessInfo.processInfo.environment["GLYPH_PHONE_SHEET"] == "1" { shown = true } }
        .accessibilityIdentifier("get-phone-row")
    }
}
#endif
