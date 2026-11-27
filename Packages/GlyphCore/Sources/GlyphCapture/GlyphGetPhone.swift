#if os(macOS)
import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI

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

    /// - Parameters:
    ///   - app: the app as the family names it, "Glyph Time".
    ///   - link: its real install page for the iPhone. Never a link the app has not got.
    public init(app: String, link: URL) {
        self.app = app
        self.link = link
    }

    public var body: some View {
        VStack(spacing: 18) {
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable().interpolation(.high).frame(width: 44, height: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Get \(app) on your iPhone").font(.system(size: 17, weight: .semibold))
                    Text("Point your iPhone's camera at the code.").font(.callout).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            Group {
                if let code = GlyphGetPhone.qr(link.absoluteString) {
                    Image(nsImage: code).interpolation(.none).resizable().scaledToFit().frame(width: code.size.width, height: code.size.height)
                } else {
                    Text("The code could not be drawn.").foregroundStyle(.secondary).frame(width: 220, height: 220)
                }
            }
            .padding(16)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.12), lineWidth: 1))
            .glyphProbe("get-phone-qr")
            Text(link.absoluteString).font(.footnote).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                .textSelection(.enabled)
            HStack(spacing: 10) {
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(link.absoluteString, forType: .string)
                    copied = true
                } label: {
                    Label(copied ? "Copied" : "Copy link", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .glyphProbe("get-phone-copy")
                Button { NSWorkspace.shared.open(link) } label: { Label("Open in browser", systemImage: "safari") }
                    .glyphProbe("get-phone-open")
                Spacer(minLength: 0)
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction).tint(.officeGreen)
                    .glyphProbe("get-phone-done")
            }
            .controlSize(.large)
        }
        .padding(24)
        .frame(width: 400)
        .accessibilityIdentifier("get-phone-sheet")
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
