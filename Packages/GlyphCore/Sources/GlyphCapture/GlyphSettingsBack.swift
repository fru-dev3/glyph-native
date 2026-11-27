#if os(macOS)
import SwiftUI

/// The way out of Settings, the same in every Glyph Mac app: "‹ Back to <app>" at the top of the
/// settings rail or page, and Esc does the same.
///
/// Fru, 2026-11-27: "going to the settings and coming out back is ridiculous ... you put an X button.
/// It's not very obvious that you have to go back. On every app, there has to be a consistent way to
/// go to the settings and to come back." The gear (bottom left, `GlyphSidebarFoot`) goes in; this
/// comes back out.
///
/// ```swift
/// VStack { GlyphSettingsBack(app: "Glyph Jot") { page = .home }; settingsPanes }
/// ```
public struct GlyphSettingsBack: View {
    private let app: String
    private let action: () -> Void

    public init(app: String, action: @escaping () -> Void) {
        self.app = app
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            // The name whole beats the hint: in a 220-point sidebar "Back to Glyph Wealth" was cut to
            // "Back to Glyph We..." beside "esc" (pictured 2026-11-27). Where both do not fit the hint
            // goes; Esc still works and the help says so.
            ViewThatFits(in: .horizontal) {
                line(hint: true)
                line(hint: false)
            }
            // The app's tint (its green), not Color.accentColor: that is the system accent, blue, in any
            // app without an accent asset (Glyph Omega, pictured 2026-11-27). With no tint, .tint is the accent.
            .foregroundStyle(.tint)
            .padding(.horizontal, 10).frame(height: 32)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.tint.opacity(0.1)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.cancelAction)
        .help("Leave Settings (Esc)")
        .padding(.horizontal, 12).padding(.vertical, 6)
        .glyphProbe("settings.back")
        .accessibilityIdentifier("settings-back")
    }

    private func line(hint: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "chevron.left").font(.system(size: 13, weight: .semibold))
            Text("Back to \(app)").font(.system(size: 13.5, weight: .semibold)).lineLimit(1)
                .minimumScaleFactor(hint ? 1 : 0.85)
            Spacer(minLength: 0)
            if hint { Text("esc").font(.system(size: 11, weight: .medium)).foregroundStyle(.tertiary) }
        }
    }
}
#endif
