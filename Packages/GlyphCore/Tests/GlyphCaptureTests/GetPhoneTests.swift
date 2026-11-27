#if os(macOS)
import Testing
@testable import GlyphCapture

@Suite struct GetPhoneTests {
    /// The QR image reads back, as a phone camera would, to the link it was drawn from.
    @Test func qrDecodesBackToTheLink() throws {
        for link in ["https://glyph.fru.dev/time", "https://glyph.fru.dev/jot", "https://glyph.fru.dev"] {
            let image = try #require(GlyphGetPhone.qr(link))
            #expect(GlyphGetPhone.decode(image) == link)
        }
    }
}
#endif
