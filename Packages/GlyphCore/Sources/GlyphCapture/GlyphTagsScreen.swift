import SwiftUI

/// The Tags place every Glyph app has: this app's own tags, what each covers, and how much of
/// this app's log carries it.
///
/// Fru, 2026-11-15, after opening Glyph Well and finding none: "every app will have tags, like
/// for well, which is health... and this is a subset of the tags in CRM. So you have things like
/// tag for stool, tag for food, tag for a workout, tag for feeling. So that is now tracked by
/// tags... If I open an app again on my phone and it doesn't have tags, they're implemented as a
/// subset of the tags relevant to the context of that app, there'll be a problem."
///
/// Which tags are this app's is written on each tag's page in the vault (`apps: ["well"]`), read
/// through `GlyphTags.forApp`. The app supplies only its own counts, so nothing here knows what
/// any app keeps.
///
/// ```swift
/// GlyphTagsScreen(app: "wealth", tint: .wealthGreen, counts: store.tagCounts) { tag in
///     open(tag)
/// }
/// ```
public struct GlyphTagsScreen: View {
    private let app: String
    private let tint: Color
    private let counts: [String: Int]
    private let empty: String
    private let open: ((String) -> Void)?
    /// Watched, so a tag made, archived or restored here (or the register arriving) redraws the list.
    @ObservedObject private var register = GlyphTags.shared

    /// - Parameters:
    ///   - app: the family id, "well" or "wealth". It picks the subset and nothing else.
    ///   - counts: how many of this app's own things carry each tag, keyed by `GlyphTag.slug`.
    ///     A tag with none is still shown: it exists, and it is one he can file to.
    ///   - empty: what to say when the register has nothing for this app yet.
    ///   - open: what a tapped tag does. Nothing when the app has no page for one yet.
    public init(app: String, tint: Color, counts: [String: Int] = [:],
                empty: String = "They arrive with your vault, and anything you say under a hashtag joins them.",
                open: ((String) -> Void)? = nil) {
        self.app = app
        self.tint = tint
        self.counts = counts
        self.empty = empty
        self.open = open
    }

    /// This app's tags, the ones in use first so the list opens on what he actually files.
    var rows: [(tag: GlyphTag, count: Int)] {
        let mine: [(tag: GlyphTag, count: Int)] = register.forApp(app).map { ($0, counts[$0.id] ?? 0) }
        return mine.sorted { a, b in
            if a.count != b.count { return a.count > b.count }
            return a.tag.name.localizedCaseInsensitiveCompare(b.tag.name) == .orderedAscending
        }
    }

    private func line(_ row: (tag: GlyphTag, count: Int)) -> GlyphTagRow {
        GlyphTagRow(name: row.tag.name, covers: row.tag.covers, count: row.count, tint: tint)
    }

    public var body: some View {
        let rows = rows
        ScrollView {
            // Making one, at the top (Fru, 2026-11-22: "Where do I add or manage tags. Eg I need a
            // new dev tag"); retiring one, on its row; the retired ones, folded at the end.
            GlyphNewTagRow(app: app, tint: tint)
                .padding(.horizontal, 14).frame(maxWidth: 760)
            if rows.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "number").font(.system(size: 30, weight: .light)).foregroundStyle(.secondary)
                    Text("No tags here yet").font(.headline)
                    Text(empty).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: 420).padding(.top, 60).padding(.horizontal, 20)
                .accessibilityIdentifier("tags.empty")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.tag.id) { i, row in
                        // With nowhere to open, a row is a plain line. It was a disabled button,
                        // which greys the whole row: every tag in an app that passes no `open`
                        // read as switched off (Glyph Omega, seen in a picture, 2026-11-19).
                        if let open {
                            Button { open(row.tag.id) } label: { line(row) }
                                .buttonStyle(.plain)
                                // glyphProbe, not a bare identifier: an app's Mac check clicks
                                // where a control says it is, and a tag row said nothing, so no
                                // check could press one (2026-11-20).
                                .glyphProbe("tags.row.\(row.tag.id)")
                                .glyphTagActions(row.tag.id, tint: tint)
                        } else {
                            line(row).glyphProbe("tags.row.\(row.tag.id)")
                                .glyphTagActions(row.tag.id, tint: tint)
                        }
                        if i < rows.count - 1 { Divider().padding(.leading, 40) }
                    }
                }
                .padding(.horizontal, 14)
                .frame(maxWidth: 760)
                .padding(.vertical, 6)
            }
            GlyphArchivedTags(app: app, tint: tint, counts: counts, open: open)
                .padding(.horizontal, 14).frame(maxWidth: 760).padding(.bottom, 24)
        }
        .accessibilityIdentifier("tags.page")
    }

}

/// One tag as a row: the family's `#` in the tag's own colour, its name, what it covers, and how
/// many things carry it. `GlyphTagsScreen` is a list of these, and an app whose Tags place sits
/// inside a page of its own (Glyph Well) draws the same row there, so a tag reads the same on
/// every Tags screen in the family.
///
/// What a tag covers is never cut. It was held to two lines, and a third ended in "...", on the
/// one line that says what belongs under the tag (Fru, 2026-11-21, of Glyph Well's list). It
/// wraps for as long as it needs to; the register keeps these lines short.
public struct GlyphTagRow: View {
    private let name: String
    private let covers: String?
    private let count: Int
    private let tint: Color

    public init(name: String, covers: String? = nil, count: Int = 0, tint: Color = .officeGreen) {
        self.name = name; self.covers = covers; self.count = count; self.tint = tint
    }

    public var body: some View {
        HStack(spacing: 10) {
            GlyphTagHash(name: name, size: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(GlyphTags.display(name)).font(.system(size: 15, weight: .medium))
                if let covers, !covers.isEmpty {
                    Text(covers).font(.system(size: 12)).foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            Text(count == 0 ? "" : "\(count)")
                .font(.system(size: 13).monospacedDigit())
                .foregroundStyle(count == 0 ? .secondary : tint)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

/// The sheet the composer's `#` opens: the app's tags as big rows, the most used first, one tap
/// to pick (Fru, 2026-11-21: "one button, see the tags, pick my tag, and begin logging"). A search
/// field at the top once there are more than twelve. The rows are `GlyphTagRow`, so a tag reads
/// here as it reads on the app's Tags screen.
///
/// Accessibility identifiers: `tagsheet`, `tagsheet.row.<slug>`, `tagsheet.search`, `tagsheet.close`.
public struct GlyphTagSheet: View {
    private let tags: [String]
    private let counts: [String: Int]
    private let tint: Color
    private let pick: (String) -> Void
    private let app: String?
    @State private var typed = ""
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var register = GlyphTags.shared

    /// - Parameter app: the family id a tag made here is shown in. Read off the bundle when nil.
    public init(_ tags: [String], counts: [String: Int] = [:], tint: Color = .officeGreen, app: String? = nil,
                pick: @escaping (String) -> Void) {
        self.tags = tags; self.counts = counts; self.tint = tint; self.pick = pick
        self.app = app ?? GlyphTags.appHere
    }

    /// The app's tags plus any of its own made since it drew them, less the archived ones.
    var offered: [String] {
        let mine = app.map { register.forApp($0).map(\.id) } ?? []
        return (tags + mine.filter { m in !tags.contains { GlyphTag.slug($0) == m } }).filter { !GlyphTags.isArchived($0) }
    }

    /// Most used first, then by the name as shown; narrowed by what is typed. A retired tag is
    /// never offered (Fru, 2026-11-22), whatever list the app handed in.
    static func order(_ tags: [String], counts: [String: Int], typed: String = "") -> [String] {
        var seen = Set<String>()
        let unique = tags.filter { !GlyphTags.isArchived($0) && seen.insert(GlyphTag.slug($0)).inserted }
        let q = typed.trimmingCharacters(in: .whitespaces)
        let matching = q.isEmpty ? unique : unique.filter {
            GlyphTags.display($0).localizedCaseInsensitiveContains(q) || (GlyphTags.covers($0)?.localizedCaseInsensitiveContains(q) ?? false)
        }
        return matching.sorted { a, b in
            let na = counts[a] ?? 0, nb = counts[b] ?? 0
            if na != nb { return na > nb }
            return GlyphTags.display(a).localizedCaseInsensitiveCompare(GlyphTags.display(b)) == .orderedAscending
        }
    }

    public var body: some View {
        let tags = offered
        let rows = Self.order(tags, counts: counts, typed: typed)
        VStack(alignment: .leading, spacing: 12) {
            // One header line: what this is, and the way out.
            HStack {
                Text("Log to a tag").font(.system(size: 17, weight: .semibold))
                Spacer()
                Button("Close") { dismiss() }
                    .font(.system(size: 16, weight: .medium)).foregroundStyle(tint)
                    .accessibilityIdentifier("tagsheet.close")
            }
            .padding(.top, 20)
            if tags.count > 12 {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search your tags", text: $typed)
                        .textFieldStyle(.plain).autocorrectionDisabled()
                        .accessibilityIdentifier("tagsheet.search")
                }
                .padding(.horizontal, 14).frame(height: 44)
                .background(Color.secondary.opacity(0.15), in: .rect(cornerRadius: 14, style: .continuous))
            }
            ScrollView {
                VStack(spacing: 0) {
                    // A tag that is not there yet, made and picked in one go.
                    GlyphNewTagRow(app: app, tint: tint) { slug in pick(slug) }
                    Divider().padding(.leading, 26)
                    ForEach(Array(rows.enumerated()), id: \.element) { i, tag in
                        Button { pick(GlyphTag.slug(tag)) } label: {
                            GlyphTagRow(name: tag, covers: GlyphTags.covers(tag), count: counts[tag] ?? 0, tint: tint)
                                .frame(minHeight: 52)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("tagsheet.row.\(GlyphTag.slug(tag))")
                        if i < rows.count - 1 { Divider().padding(.leading, 26) }
                    }
                    if rows.isEmpty {
                        Text(tags.isEmpty ? "No tags here yet." : "No tag has those words.")
                            .font(.footnote).foregroundStyle(.secondary).padding(.top, 20)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .padding(.horizontal, 20)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tagsheet")
    }
}

// MARK: Managing tags (Fru, 2026-11-22: "Where do I add or manage tags. Eg I need a new dev tag.
// Then I want to retire or archive tags so they don't show on the lists.")
//
// One set of pieces for every app: the "New tag" row (the Tags page and the composer's sheet), the
// form it opens, Archive and Edit on a row (a swipe and a context menu), and the folded Archived
// list with Restore. An app's own Tags page (Glyph Well's) uses the same three, so the identifiers
// are the same in every app:
//
//   tags.new                       the New tag row
//   tagform, tagform.name, tagform.covers, tagform.color.<hex>, tagform.app.<id>,
//   tagform.save, tagform.cancel, tagform.taken, tagform.use, tagform.restore, tagform.error
//   tags.swipe.archive.<slug>      the button a left swipe on a row shows ("Archive")
//   tags.archived                  the Archived fold;  tags.archived.row.<slug>, tags.restore.<slug>

/// "New tag", a row that opens `GlyphTagForm`. `made` gets the slug of the tag made, or of the
/// one the name already was (used or restored), so the composer's sheet can pick it at once.
public struct GlyphNewTagRow: View {
    private let app: String?
    private let tint: Color
    private let made: ((String) -> Void)?
    @State private var making = false
    @State private var result: String?

    public init(app: String?, tint: Color = .officeGreen, made: ((String) -> Void)? = nil) {
        self.app = app; self.tint = tint; self.made = made
    }

    public var body: some View {
        Button { making = true } label: {
            HStack(spacing: 10) {
                Image(systemName: "plus").font(.system(size: 14, weight: .bold)).foregroundStyle(.white)
                    .frame(width: 24, height: 24).background(tint, in: Circle())
                Text("New tag").font(.system(size: 15, weight: .semibold)).foregroundStyle(tint)
                Spacer()
            }
            .padding(.vertical, 10).frame(minHeight: 48).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .glyphProbe("tags.new")
        .sheet(isPresented: $making, onDismiss: {
            if let result { made?(result) }
            result = nil
        }) {
            GlyphTagForm(app: app, tint: tint) { slug in result = slug; making = false }
        }
    }
}

/// Making a tag, or changing one: a name (new only, shown in proper case as it will read), one
/// optional line on what belongs under it, a colour from the family's palette, and the apps that
/// show it (the app it was made in, to start). A name that is already a tag or an alias of one,
/// archived or not, offers that tag instead: Use it, or Restore it.
public struct GlyphTagForm: View {
    private let editing: GlyphTag?
    private let tint: Color
    private let done: (String?) -> Void
    @State private var name = ""
    @State private var covers: String
    @State private var color: String
    @State private var apps: Set<String>
    @State private var busy = false
    @State private var problem: String?
    @Environment(\.dismiss) private var dismiss

    /// A new tag. `done` gets the slug made or chosen, or nil when it was cancelled.
    public init(app: String?, tint: Color = .officeGreen, done: @escaping (String?) -> Void) {
        editing = nil; self.tint = tint; self.done = done
        _covers = State(initialValue: "")
        _color = State(initialValue: GlyphTags.palette[1])
        _apps = State(initialValue: app.map { [$0] } ?? [])
    }

    /// Changing an existing tag's meaning, colour and apps.
    public init(editing tag: GlyphTag, tint: Color = .officeGreen, done: @escaping (String?) -> Void) {
        editing = tag; self.tint = tint; self.done = done
        _covers = State(initialValue: tag.covers ?? "")
        _color = State(initialValue: tag.hex?.lowercased() ?? GlyphTags.palette[1])
        _apps = State(initialValue: Set(tag.apps))
    }

    /// The tag the typed name already is, while it is typed.
    private var taken: GlyphTag? { editing == nil ? GlyphTags.match(name) : nil }
    private var shown: String { editing.map { GlyphTags.display($0.name) } ?? GlyphTag.proper(name.split(whereSeparator: \.isWhitespace).joined(separator: " ")) }
    private var ready: Bool { !busy && taken == nil && !GlyphTag.slug(editing?.name ?? name).isEmpty }

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Button("Cancel") { done(nil); dismiss() }
                    .font(.system(size: 16)).foregroundStyle(.secondary)
                    .fixedSize()
                    .accessibilityIdentifier("tagform.cancel")
                Spacer(minLength: 8)
                GlyphSheetTitle(editing == nil ? "New tag" : "Edit tag")
                Spacer(minLength: 8)
                Button("Save") { Task { await save() } }
                    .font(.system(size: 16, weight: .semibold)).foregroundStyle(ready ? tint : .secondary)
                    .fixedSize()
                    .disabled(!ready)
                    .accessibilityIdentifier("tagform.save")
            }
            .padding(.top, 20)

            // How it will read everywhere, in its colour.
            HStack(spacing: 4) {
                Text("#").font(.system(size: 26, weight: .black, design: .rounded)).foregroundStyle(GlyphTag(name: "x", hex: color).color ?? tint)
                Text(shown.isEmpty ? "Name" : shown).font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(shown.isEmpty ? .secondary : .primary).lineLimit(1)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("tagform.preview")

            if editing == nil {
                field("Name", text: $name, id: "tagform.name")
            }
            if let taken {
                // Never a second one: the tag that name already is, and what to do with it.
                HStack(spacing: 10) {
                    Text(taken.archived ? "#\(GlyphTags.display(taken.name)) is archived." : "#\(GlyphTags.display(taken.name)) already exists.")
                        .font(.system(size: 14)).foregroundStyle(.secondary)
                        .accessibilityIdentifier("tagform.taken")
                    Spacer()
                    Button(taken.archived ? "Restore" : "Use it") {
                        Task {
                            busy = true
                            if taken.archived, !(await GlyphTags.shared.setArchived(taken.id, false)) {
                                busy = false; problem = "It could not be restored. Try again in a moment."; return
                            }
                            done(taken.id); dismiss()
                        }
                    }
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(tint)
                    .accessibilityIdentifier(taken.archived ? "tagform.restore" : "tagform.use")
                }
            }
            field("What belongs under it (optional)", text: $covers, id: "tagform.covers")

            Text("Colour").font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                ForEach(GlyphTags.palette, id: \.self) { hex in
                    Button { color = hex } label: {
                        Circle().fill(GlyphTag(name: "x", hex: hex).color ?? tint).frame(width: 28, height: 28)
                            .overlay(Circle().strokeBorder(.primary, lineWidth: color == hex ? 2.5 : 0).padding(-4))
                            .frame(width: 36, height: 36).contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Colour \(hex)")
                    .accessibilityAddTraits(color == hex ? .isSelected : [])
                    .accessibilityIdentifier("tagform.color.\(hex.dropFirst())")
                }
            }

            Text("Shows in").font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
            FlowRow(spacing: 8) {
                ForEach(GlyphTags.familyApps, id: \.id) { a in
                    let on = apps.contains(a.id)
                    Button { if on { apps.remove(a.id) } else { apps.insert(a.id) } } label: {
                        Text(a.name).font(.system(size: 14, weight: .medium))
                            .foregroundStyle(on ? .white : .primary)
                            .padding(.horizontal, 12).frame(height: 32)
                            .background(on ? tint : Color.secondary.opacity(0.18), in: Capsule())
                            .frame(minHeight: 40).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                    .accessibilityIdentifier("tagform.app.\(a.id)")
                }
            }
            if let problem {
                Text(problem).font(.footnote).foregroundStyle(.red).accessibilityIdentifier("tagform.error")
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("tagform")
    }

    private func field(_ prompt: String, text: Binding<String>, id: String) -> some View {
        TextField(prompt, text: text)
            .textFieldStyle(.plain).autocorrectionDisabled()
            #if os(iOS)
            .textInputAutocapitalization(.sentences)
            #endif
            .padding(.horizontal, 14).frame(height: 46)
            .background(Color.secondary.opacity(0.15), in: .rect(cornerRadius: 12, style: .continuous))
            .accessibilityIdentifier(id)
    }

    private func save() async {
        busy = true; problem = nil
        let apps = GlyphTags.familyApps.map(\.id).filter { self.apps.contains($0) }
        if let editing {
            if await GlyphTags.shared.edit(editing.id, covers: covers, color: color, apps: apps) { done(editing.id); dismiss() }
            else { problem = "The change could not be saved. Try again in a moment." }
        } else {
            switch await GlyphTags.shared.create(name, covers: covers, color: color, apps: apps) {
            case .made(let slug): done(slug); dismiss()
            case .existing(let tag): name = tag.name   // the line above now offers it
            case .failed(let why): problem = why
            }
        }
        busy = false
    }
}

/// Lays its children out in rows that wrap, for the app chips.
struct FlowRow: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = place(proposal.width ?? 360, subviews)
        return CGSize(width: proposal.width ?? rows.width, height: rows.height)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (i, p) in place(bounds.width, subviews).points.enumerated() {
            subviews[i].place(at: CGPoint(x: bounds.minX + p.x, y: bounds.minY + p.y), proposal: .unspecified)
        }
    }
    private func place(_ width: CGFloat, _ subviews: Subviews) -> (points: [CGPoint], width: CGFloat, height: CGFloat) {
        var points: [CGPoint] = [], x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0, widest: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0, x + s.width > width { x = 0; y += line + spacing; line = 0 }
            points.append(CGPoint(x: x, y: y))
            x += s.width + spacing; line = max(line, s.height); widest = max(widest, x - spacing)
        }
        return (points, widest, y + line)
    }
}

public extension View {
    /// Archive and Edit on a tag's row: a left swipe shows Archive (a long one archives at once),
    /// and a press and hold offers Archive and Edit. The same on every Tags page in the family.
    func glyphTagActions(_ slug: String, tint: Color = .officeGreen) -> some View {
        modifier(GlyphTagActions(slug: slug, tint: tint))
    }
}

struct GlyphTagActions: ViewModifier {
    let slug: String
    let tint: Color
    @State private var shift: CGFloat = 0
    @State private var editing: GlyphTag?
    /// Archive is showing (the drag began from there).
    @State private var open = false
    private static let reveal: CGFloat = 92

    private func archive() {
        withAnimation(.snappy) { shift = 0 }
        open = false
        Task { await GlyphTags.shared.setArchived(slug, true) }
    }

    func body(content: Content) -> some View {
        content
            .offset(x: shift)
            .background(alignment: .trailing) {
                if shift < 0 {
                    Button(action: archive) {
                        Label("Archive", systemImage: "archivebox.fill").labelStyle(.titleAndIcon)
                            .font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                            .frame(width: Self.reveal).frame(maxHeight: .infinity)
                            .background(Color(white: 0.38))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("tags.swipe.archive.\(slug)")
                }
            }
            .clipped()
            #if os(iOS)
            // A UIKit pan that only begins on a sideways swipe. A SwiftUI DragGesture here, even a
            // simultaneous one, held the ScrollView's own pan, so the Tags page stopped scrolling
            // (seen in Glyph Well's phone test, 2026-11-22: a tag below the fold could not be reached).
            .gesture(SideSwipe(changed: { dx in
                let start: CGFloat = open && dx > 0 ? -Self.reveal : 0
                shift = min(0, max(-Self.reveal * 2.2, start + dx))
            }, ended: { dx in
                if dx < -Self.reveal * 1.9 { archive(); return }
                withAnimation(.snappy) { shift = (open ? -Self.reveal : 0) + dx < -40 ? -Self.reveal : 0 }
                open = shift < 0
            }))
            #endif
            .contextMenu {
                Button { archive() } label: { Label("Archive", systemImage: "archivebox") }
                Button { editing = GlyphTags.match(slug) } label: { Label("Edit meaning, colour and apps", systemImage: "pencil") }
            }
            .sheet(item: $editing) { tag in GlyphTagForm(editing: tag, tint: tint) { _ in editing = nil } }
    }
}

/// The archived tags of an app, folded at the end of its Tags page: each with Restore, and still
/// opening onto what carries it. Draws nothing when none are archived.
public struct GlyphArchivedTags: View {
    private let app: String
    private let tint: Color
    private let counts: [String: Int]
    private let open: ((String) -> Void)?
    @ObservedObject private var register = GlyphTags.shared
    @State private var unfolded = false

    public init(app: String, tint: Color = .officeGreen, counts: [String: Int] = [:], open: ((String) -> Void)? = nil) {
        self.app = app; self.tint = tint; self.counts = counts; self.open = open
    }

    public var body: some View {
        let gone = register.archived(forApp: app).sorted { GlyphTags.display($0.name) < GlyphTags.display($1.name) }
        if !gone.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Button { withAnimation(.snappy) { unfolded.toggle() } } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold))
                            .rotationEffect(.degrees(unfolded ? 90 : 0))
                        Text("Archived").font(.system(size: 15, weight: .semibold))
                        Text("\(gone.count)").font(.system(size: 13).monospacedDigit())
                        Spacer()
                    }
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 12).frame(minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityValue(unfolded ? "open" : "folded")
                .glyphProbe("tags.archived")
                if unfolded {
                    ForEach(gone) { tag in
                        HStack(spacing: 8) {
                            Group {
                                if let open {
                                    Button { open(tag.id) } label: { row(tag) }.buttonStyle(.plain)
                                } else { row(tag) }
                            }
                            .glyphProbe("tags.archived.row.\(tag.id)")
                            Button("Restore") { Task { await GlyphTags.shared.setArchived(tag.id, false) } }
                                .font(.system(size: 14, weight: .semibold)).foregroundStyle(tint)
                                .frame(minWidth: 64, minHeight: 44)
                                .glyphProbe("tags.restore.\(tag.id)")
                        }
                        .opacity(0.75)
                    }
                }
            }
            .padding(.top, 10)
        }
    }

    private func row(_ tag: GlyphTag) -> some View {
        GlyphTagRow(name: tag.name, covers: tag.covers, count: counts[tag.id] ?? 0, tint: tint)
    }
}

#if os(iOS)

/// A horizontal pan for a row inside a ScrollView: it declines to begin unless the swipe is
/// mostly sideways, so vertical scrolling is never taken from the page.
struct SideSwipe: UIGestureRecognizerRepresentable {
    let changed: (CGFloat) -> Void
    let ended: (CGFloat) -> Void

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.delegate = context.coordinator
        return pan
    }

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Sideways { Sideways() }

    func handleUIGestureRecognizerAction(_ pan: UIPanGestureRecognizer, context: Context) {
        let dx = pan.translation(in: pan.view).x
        switch pan.state {
        case .changed: changed(dx)
        case .ended, .cancelled, .failed: ended(dx)
        default: break
        }
    }

    final class Sideways: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
            guard let pan = g as? UIPanGestureRecognizer else { return false }
            let v = pan.velocity(in: pan.view)
            return abs(v.x) > abs(v.y) * 1.5
        }
    }
}
#endif
