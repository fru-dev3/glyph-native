import SwiftUI

/// Where a shared control is on screen, for an app's own screen check.
///
/// Each app's check finds its controls by a frame the control reports, because a click has to
/// land somewhere. The controls that moved into this package (the sidebar's gear, an empty
/// page's button) kept their names and lost their frames, so every check that pressed one
/// failed on a control that was plainly on screen (Glyph Wealth, 2026-11-19: sixteen failures,
/// two controls). An app's check sets `record` once; nothing is measured when it is nil.
public enum GlyphTestFrames {
    /// The name, and the frame in the window, or nil when the control has gone.
    @MainActor public static var record: ((String, CGRect?) -> Void)?
}

public extension View {
    /// The control's name for accessibility and checks, and its frame for a check that asked.
    func glyphProbe(_ id: String) -> some View { modifier(GlyphProbeFrame(id: id)) }
}

struct GlyphProbeFrame: ViewModifier {
    let id: String
    func body(content: Content) -> some View {
        content
            .accessibilityIdentifier(id)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { f in
                MainActor.assumeIsolated { GlyphTestFrames.record?(id, f) }
            }
            .onDisappear { MainActor.assumeIsolated { GlyphTestFrames.record?(id, nil) } }
    }
}
