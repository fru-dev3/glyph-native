#if os(macOS)
import SwiftUI

/// The search under the app's name in every Glyph Mac sidebar: always there, never a button that opens a palette.
///
/// Fru, 2026-11-27: the logo top left, the search bar, the collapse, the settings "must be consistent on every
/// app". Glyph Jot's field (28pt tall, 7pt corners, the magnifier, a clear button, Command-F) is the one; Glyph
/// CRM and Glyph Arena had a Search row inside the list that opened a sheet, and every other app drew its own
/// copy of Jot's a little differently. It goes right under `GlyphSidebarHeader`:
///
/// ```swift
/// .safeAreaInset(edge: .top, spacing: 0) {
///     VStack(spacing: 0) { GlyphSidebarHeader(name: "Glyph Life") { page = .settings }; GlyphSidebarSearch(text: $find) }
/// }
/// ```
///
/// Only the field is shared: what the words find stays each app's own.
public struct GlyphSidebarSearch: View {
    @Binding private var text: String
    private let prompt: String
    private let focus: Binding<Bool>?
    private let onSubmit: (() -> Void)?
    @FocusState private var focused: Bool

    /// - Parameters:
    ///   - text: the app's own search words.
    ///   - prompt: the grey words in the empty field.
    ///   - focus: set it true to put the cursor in the field (a menu's Command-K, say); it is set back to false.
    ///     Command-F does the same with no wiring.
    ///   - onSubmit: Return in the field, when the app opens its first result.
    public init(text: Binding<String>, prompt: String = "Search", focus: Binding<Bool>? = nil, onSubmit: (() -> Void)? = nil) {
        _text = text
        self.prompt = prompt
        self.focus = focus
        self.onSubmit = onSubmit
    }

    public var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain).font(.system(size: 13))
                .focused($focused)
                .onSubmit { onSubmit?() }
                .onExitCommand { text = ""; focused = false }
                .accessibilityIdentifier("search")
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain).help("Clear the search")
            }
        }
        .padding(.horizontal, 9).frame(height: 28)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.primary.opacity(0.06)))
        // Command-F, from anywhere in the window: a button with no size, since a hidden one takes no keys.
        .background(Button("") { focused = true }.keyboardShortcut("f").opacity(0).frame(width: 0, height: 0).accessibilityHidden(true))
        .padding(.horizontal, 12).padding(.bottom, 8)
        .onChange(of: focus?.wrappedValue ?? false, initial: true) { _, now in
            if now { focused = true; focus?.wrappedValue = false }
        }
    }
}
#endif
