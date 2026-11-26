import SwiftUI

/// The family's tag mark: a bold `#` in the tag's own colour, 16 wide so every name in a list
/// starts at the same place. Glyph Jot has drawn tags this way all along, and Fru asked for the
/// same in Glyph Wealth: "Look at how I did it for Jot and the Well app. It should be obvious what
/// you need to do there, so you're not reinventing the wheel."
///
/// The colour: an app that knows a tag's own colour passes it. Otherwise one is picked from the
/// palette by the same hash Glyph Jot uses, so a tag keeps its colour across launches and across
/// apps, and two apps showing the same tag show it the same.
public struct GlyphTagHash: View {
    private let name: String
    private let size: CGFloat
    private let known: Color?

    public init(name: String, size: CGFloat = 15.5, color: Color? = nil) {
        self.name = name; self.size = size; self.known = color
    }

    nonisolated public static let palette: [Color] = [.officeGreen, .blue, .indigo, .purple, .pink, .teal, .red, .brown, .cyan, .mint]

    /// djb2 over the lowercased name, which is what Glyph Jot has used since its tags began. The
    /// same name must land on the same colour in every app, so the algorithm is the shared thing
    /// here, not a table someone has to keep in step.
    nonisolated public static func index(_ name: String, of count: Int) -> Int {
        let hash = name.lowercased().unicodeScalars.reduce(5381) { ($0 &* 33 &+ Int($1.value)) & 0x7fffffff }
        return hash % max(count, 1)
    }

    nonisolated public static func color(_ name: String) -> Color { palette[index(name, of: palette.count)] }

    /// The tags at the head of a row's quiet line, each as "#Name" in its own colour, up to
    /// `most`, then "+N": how Glyph Jot has always said what a jot is filed under, on the row
    /// itself (`MemoRow.tagHead`), and how Glyph Wealth writes a category. Shared so the third app
    /// to draw it (Glyph Well, 2026-11-21) does not carry a third copy; Jot's and Wealth's are the
    /// ones to move onto this next.
    ///
    /// Each name is written in proper case, in the register's spelling (`GlyphTags.display`), so
    /// a caller passes the tag as it is stored. `dot` follows each one, in
    /// the tag's colour as Jot draws it, for a line that carries on with a time or a detail; a
    /// line that is the tags alone passes spaces.
    nonisolated public static func line(_ names: [String], most: Int = 2, dot: String = "  \u{00B7}  ") -> Text {
        var text = Text("")
        for name in names.prefix(most) {
            let tag = Text("#\(GlyphTags.display(name))\(dot)").fontWeight(.semibold).foregroundStyle(GlyphTags.color(name))
            text = Text("\(text)\(tag)")
        }
        return names.count > most ? Text("\(text)+\(names.count - most)\(dot)") : text
    }

    public var body: some View {
        // The register's colour first, so a tag is the same colour in every app; then one an app
        // passed in; then the hash, for a tag made a second ago that the vault has not seen yet.
        Text("#")
            .font(.system(size: size, weight: .bold))
            .foregroundStyle(known ?? GlyphTags.shared.color(name))
            .frame(width: 16)
            .accessibilityHidden(true)
    }
}
