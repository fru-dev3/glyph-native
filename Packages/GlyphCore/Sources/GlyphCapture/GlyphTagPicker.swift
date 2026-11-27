#if os(iOS)
import SwiftUI

/// The family's tag picker, as Glyph Jot's has been since its 32 tags stopped fitting a screen:
/// a field that both searches and names a new one, a count, and a row per tag carrying the hash,
/// the name, what it covers and a tick when it is on (Fru, 2026-11-10, of Jot's: "why is there no
/// search on this model here for the tags?"; 2026-11-11, of Omega's wall of chips: "compare how
/// Jot allows for tags").
///
/// A screen passes its tags and which are on. It does not pass a size, a spacing or a colour
/// beyond its own tint.
///
/// Glyph Jot still draws its own copy of this (`Jot/Tags.swift`), because that one also carries
/// suggestions from the words, renaming and re-ordering. It is the one to move onto this next.
public struct GlyphTagPicker: View {
    /// One tag: what it is called, and one line on what it covers, so choosing is a decision and
    /// not a memory test.
    public struct Tag: Identifiable, Sendable {
        public let id: String
        public let name: String
        public let covers: String?
        public init(id: String, name: String, covers: String? = nil) {
            self.id = id; self.name = name; self.covers = covers
        }
    }

    /// What the rows are: tags, which carry the family's `#`, or something else that borrowed
    /// this picker and must not pretend to be one. Glyph Omega picks life domains with it, and a
    /// domain drawn with a hash is a fourth meaning for the same mark (Fru, 2026-11-15, on tags
    /// being consistent across the apps).
    public enum Mark: Sendable { case tag, domain }

    private let tags: [Tag]
    @Binding private var on: Set<String>
    private let tint: Color
    /// Naming one that does not exist yet. nil means this screen's tags are a fixed list, and the
    /// field only narrows it.
    private let add: ((String) -> Void)?
    private let mark: Mark
    @State private var typed = ""

    public init(_ tags: [Tag], on: Binding<Set<String>>, tint: Color, mark: Mark = .tag, add: ((String) -> Void)? = nil) {
        self.tags = tags; self._on = on; self.tint = tint; self.mark = mark; self.add = add
    }

    /// The register's own tags, which is what every screen in the family should be passing
    /// (Fru, 2026-11-15: "the CRM is the source of truth"). The id is the slug, so what a screen
    /// stores is the vault's spelling and not whatever case it was typed in.
    public init(_ tags: [GlyphTag], on: Binding<Set<String>>, tint: Color, add: ((String) -> Void)? = nil) {
        self.init(tags.map { Tag(id: $0.name, name: $0.name, covers: $0.covers) }, on: on, tint: tint, mark: .tag, add: add)
    }

    private var matching: [Tag] {
        let q = typed.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return tags }
        return tags.filter { $0.name.localizedCaseInsensitiveContains(q) || ($0.covers?.localizedCaseInsensitiveContains(q) ?? false) }
    }

    private var exists: Bool {
        let q = typed.trimmingCharacters(in: .whitespaces)
        return !q.isEmpty && tags.contains { $0.name.caseInsensitiveCompare(q) == .orderedSame }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                leadingMark("tag")
                TextField(add == nil ? (mark == .domain ? "Search your domains" : "Search your tags")
                                     : "Search or add a tag", text: $typed)
                    .textFieldStyle(.plain).autocorrectionDisabled()
                    .accessibilityIdentifier("tag.search")
                if !typed.isEmpty {
                    Button { typed = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }
                        .accessibilityLabel("Clear")
                }
            }
            .padding(.horizontal, 14).frame(height: 44)
            .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 14, style: .continuous))

            // How many are picked, beside how many there are (Fru, 2026-11-24: "Show number of
            // selected tags"): with several picked and the list long, the ticks scroll out of sight.
            Text((typed.trimmingCharacters(in: .whitespaces).isEmpty
                  ? "\(mark == .domain ? "Your domains" : "Your tags") \u{00b7} \(tags.count)" : "\(matching.count) of \(tags.count)")
                 + (on.isEmpty ? "" : " \u{00b7} \(on.count) selected"))
                .font(.system(size: 11.5, weight: .semibold)).tracking(0.5).textCase(.uppercase)
                .foregroundStyle(tint)
                .accessibilityIdentifier("tag.count")

            // The picked ones on their own, above the list (Fru, 2026-11-27: "if I had 7 tags selected,
            // I kind of have to scroll to figure out which one was selected ... if I want to unselect
            // everything ... or if I just want to see just the selected tags"). A tap on a chip takes
            // it off; Clear takes them all off. The list keeps its order, so nothing jumps under a finger.
            if !on.isEmpty { picked }

            if let add, !exists, !typed.trimmingCharacters(in: .whitespaces).isEmpty {
                Button {
                    let name = typed.trimmingCharacters(in: .whitespaces)
                    add(name); typed = ""
                } label: {
                    Label("Create \u{201c}\(typed.trimmingCharacters(in: .whitespaces))\u{201d}", systemImage: "plus")
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(tint)
                }
                .buttonStyle(.plain).accessibilityIdentifier("tag.create")
            }

            if matching.isEmpty {
                Text(add == nil ? "No tag has those words." : "No tag has those words. Create takes the name as you typed it.")
                    .font(.system(size: 13.5)).foregroundStyle(.secondary)
                    .accessibilityIdentifier("tag.none")
            }
            ForEach(matching) { row($0) }
        }
    }

    /// The picked ones, in the list's order, as green chips with an x, and Clear at the end.
    private var picked: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(tags.filter { on.contains($0.id) }) { t in
                    Button { withAnimation(.snappy) { _ = on.remove(t.id) } } label: {
                        GlyphTagPill(t.name, on: true, all: mark == .domain, tint: tint, removable: true)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("tag.on." + t.id)
                    .accessibilityLabel("Remove \(shown(t.name))")
                }
                Button { withAnimation(.snappy) { on.removeAll() } } label: {
                    Text("Clear").font(.system(size: 14.5, weight: .semibold)).foregroundStyle(tint)
                        .padding(.horizontal, 12).frame(height: 42).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("tag.clear")
                .accessibilityLabel("Clear all \(on.count) selected")
            }
        }
        .scrollClipDisabled()
    }

    /// A tag is written in proper case, as everywhere a tag is drawn; a row that is not a tag
    /// (a vault domain) is written as given.
    private func shown(_ name: String) -> String {
        if case .tag = mark { return GlyphTags.display(name) }
        return name
    }

    /// The family's `#` for a tag, and a plain mark for rows that are not tags: the hash means
    /// one thing across the apps or it means nothing.
    @ViewBuilder private func leadingMark(_ name: String) -> some View {
        switch mark {
        case .tag: GlyphTagHash(name: name, size: 15)
        case .domain:
            Image(systemName: "circle.grid.2x2.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 16)
                .accessibilityHidden(true)
        }
    }

    private func row(_ t: Tag) -> some View {
        let here = on.contains(t.id)
        return Button { if here { on.remove(t.id) } else { on.insert(t.id) } } label: {
            HStack(alignment: .top, spacing: 10) {
                leadingMark(t.name)
                VStack(alignment: .leading, spacing: 2) {
                    Text(shown(t.name)).font(.system(size: 15, weight: .semibold)).foregroundStyle(.primary)
                    if let covers = t.covers, !covers.isEmpty {
                        Text(covers).font(.system(size: 12)).lineSpacing(4).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "checkmark").font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(here ? tint : .clear).frame(width: 16)
            }
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("tag." + t.id)
        .accessibilityLabel(shown(t.name))
        .accessibilityAddTraits(here ? .isSelected : [])
    }
}
#endif
