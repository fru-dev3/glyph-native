import Foundation
import SwiftUI
import Testing

@testable import GlyphCapture

@Suite("The tags every app reads from the register", .serialized)
@MainActor
struct TagsTests {
    /// A register as the hub serves it: the two names that used to disagree between Glyph Jot
    /// and the vault, with the old spellings kept as aliases.
    private func register() -> GlyphTags {
        let tags = GlyphTags()
        tags.take([
            GlyphTag(name: "Jokes", covers: "Funny lines.", hex: "#c83a46", aliases: ["Comedy"]),
            GlyphTag(name: "Learning", covers: "Books, courses.", hex: "#62c83a", aliases: ["Knowledge", "Books"]),
            GlyphTag(name: "Real Estate", covers: "Houses and land.", hex: "#983ac8"),
            GlyphTag(name: "Whisper", covers: "Sayings.", hex: "#c86a3a"),
        ])
        return tags
    }

    @Test("An old spelling reads as the tag it became, and an unknown one is left alone")
    func aliases() {
        let tags = register()
        #expect(tags.canonical("Comedy") == "Jokes")
        #expect(tags.canonical("comedy") == "Jokes")
        #expect(tags.canonical("Books") == "Learning")
        // Whisper is a tag of its own: Glyph Jot used to fold it into Content, and the vault
        // said otherwise (Fru has written with it).
        #expect(tags.canonical("Whisper") == "Whisper")
        // A tag made a second ago keeps its own name until the hub registers it.
        #expect(tags.canonical("Flare week") == "Flare week")
    }

    @Test("The slug is the vault's spelling, whatever the case or the spaces")
    func slugs() {
        #expect(GlyphTag.slug("Real Estate") == "real-estate")
        #expect(GlyphTag.slug("real-estate") == "real-estate")
        #expect(GlyphTag.slug("  Flare  week ") == "flare-week")
    }

    @Test("A tag is shown in proper case, and stored as it was")
    func properCase() {
        #expect(GlyphTag.proper("general") == "General")
        #expect(GlyphTag.proper("care-team") == "Care team")
        #expect(GlyphTag.proper("crm") == "CRM")
        #expect(GlyphTag.proper("ai-tools") == "AI tools")
        #expect(GlyphTag.proper("patient id") == "Patient ID")
        // Already proper: unchanged, capitals and all.
        for name in ["Real Estate", "Feelings", "Food", "CRM", "Glyph Jot"] {
            #expect(GlyphTag.proper(name) == name)
        }
        #expect(GlyphTag.proper("") == "")
        // Only what is shown: the slug a tag is stored and found under does not move.
        #expect(GlyphTag.slug(GlyphTag.proper("care-team")) == "care-team")
        #expect(GlyphTag.slug(GlyphTag.proper("crm")) == "crm")
        // Through the register: its spelling first, then proper case over it.
        let tags = register()
        _ = tags
        #expect(GlyphTags.display("real-estate") == "Real Estate")
        #expect(GlyphTags.display("comedy") == "Jokes")
        #expect(GlyphTags.display("flare-week") == "Flare week")
    }

    @Test("A tag's colour is the one its page carries, in every app")
    func colors() {
        let tags = register()
        #expect(tags.color("Jokes") == GlyphTag(name: "x", hex: "#c83a46").color)
        #expect(tags.color("real estate") == GlyphTag(name: "x", hex: "#983ac8").color)
        // One he has just made has no page yet, so it falls back to the family's hash, which is
        // at least the same hash in every app.
        #expect(tags.color("Flare week") == GlyphTagHash.color("Flare week"))
    }

    @Test("The composer's tag sheet puts the most used first, then by name, and narrows by what is typed")
    func sheetOrder() {
        _ = register()
        let counts = ["food": 4, "stool": 9, "meds": 4]
        #expect(GlyphTagSheet.order(["food", "meds", "stool", "dreams", "food"], counts: counts) == ["stool", "food", "meds", "dreams"])
        #expect(GlyphTagSheet.order(["food", "stool", "dreams"], counts: counts, typed: "dre") == ["dreams"])
    }

    // MARK: Archive and New tag (Fru, 2026-11-22: "I need a new dev tag. Then I want to retire or
    // archive tags so they don't show on the lists.") Made-up register, temp folders only.

    @Test("An archived tag leaves every list, and is still found by its name")
    func archiveFiltering() {
        let tags = GlyphTags()
        tags.take([
            GlyphTag(name: "Stool", hex: "#7a7f87", apps: ["well"]),
            GlyphTag(name: "Food", apps: ["well"]),
            GlyphTag(name: "Flare week", covers: "Bad weeks.", hex: "#c83a46", aliases: ["Flare"], apps: ["well"], archived: true),
        ])
        #expect(tags.all.map(\.id) == ["stool", "food"])
        #expect(GlyphTags.all.map(\.id) == ["stool", "food"])
        #expect(GlyphTags.forApp("well").map(\.id) == ["stool", "food"])
        #expect(tags.forApp("jot").map(\.id) == ["stool", "food"])
        #expect(GlyphTags.everything.count == 3)
        #expect(GlyphTags.archived(forApp: "well").map(\.id) == ["flare-week"])
        #expect(tags.archived(forApp: "wealth").isEmpty)
        #expect(GlyphTags.isArchived("flare week") && GlyphTags.isArchived("Flare") && !GlyphTags.isArchived("Stool"))
        #expect(!GlyphTags.isArchived("never-seen"))
        // What was filed under it keeps reading as it did: its spelling, colour and meaning.
        #expect(GlyphTags.display("flare-week") == "Flare week")
        #expect(GlyphTags.color("flare-week") == GlyphTag(name: "x", hex: "#c83a46").color)
        #expect(GlyphTags.covers("flare-week") == "Bad weeks.")
        // The composer's sheet never offers it, whatever list the app handed in.
        #expect(GlyphTagSheet.order(["stool", "flare-week", "Flare", "food"], counts: ["flare-week": 9]) == ["food", "stool"])
        // A device that kept tags before the field existed reads them as in use.
        let old = try! JSONDecoder().decode(GlyphTag.self, from: Data(#"{"name":"Old","aliases":[]}"#.utf8))
        #expect(!old.archived)
    }

    @Test("A name matches its tag by any case, spacing or alias, archived or not")
    func matching() {
        let tags = GlyphTags()
        tags.take([GlyphTag(name: "Jokes", aliases: ["Comedy"]), GlyphTag(name: "Dev", archived: true)])
        #expect(GlyphTags.match("jokes")?.name == "Jokes")
        #expect(GlyphTags.match("  COMEDY ")?.name == "Jokes")
        #expect(GlyphTags.match("dev")?.archived == true)
        #expect(GlyphTags.match("Dev work") == nil)
        #expect(GlyphTags.match("--") == nil)
    }

    /// A made-up vault as moved on 2026-11-22: one tag page and one tag folder with no page yet in
    /// data/tags, the two old names links to it.
    private func vault() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appending(path: "glyph-tags-\(UUID().uuidString)")
        let fm = FileManager.default
        let jokes = root.appending(path: "data/tags/jokes")
        try fm.createDirectory(at: jokes, withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appending(path: "data/tags/health/memory"), withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appending(path: "data/entities"), withIntermediateDirectories: true)
        try fm.createSymbolicLink(atPath: root.appending(path: "data/domains").path, withDestinationPath: "tags")
        try fm.createSymbolicLink(atPath: root.appending(path: "data/entities/tags").path, withDestinationPath: "../tags")
        try Data("---\nname: \"Jokes\"\nkind: tag\naliases: [\"Comedy\"]\ncolor: \"#c83a46\"\napps: [\"jot\"]\nid: tags/jokes\n---\n\n## Your notes\n\nKept.\n".utf8)
            .write(to: jokes.appending(path: "entity.md"))
        return root
    }

    @Test("New tag on a Mac writes the tag's own page; a taken name or alias offers that tag instead")
    func createOnTheMac() async throws {
        let root = try vault()
        defer { try? FileManager.default.removeItem(at: root) }
        let tags = GlyphTags()
        #expect(tags.readVault(root))
        #expect(await tags.create("dev", covers: "Code and builds.", color: "#3A7BC8", apps: ["well"]) == .made("dev"))
        let page = try String(contentsOf: root.appending(path: "data/tags/dev/entity.md"), encoding: .utf8)
        for line in [#"name: "dev""#, "kind: tag", "aliases: []", #"covers: "Code and builds.""#, ##"color: "#3a7bc8""##,
                     #"apps: ["well"]"#, "id: tags/dev", "created: 20", "updated: 20"] {
            #expect(page.contains(line), "\(line) in \(page)")
        }
        // Read back: in this app's list at once, in proper case.
        #expect(tags.forApp("well").map(\.id) == ["dev"])
        #expect(GlyphTags.display("dev") == "Dev")
        // Never a second one.
        guard case .existing(let same) = await tags.create("DEV", apps: ["well"]) else { Issue.record("made a second Dev"); return }
        #expect(same.id == "dev")
        guard case .existing(let alias) = await tags.create("comedy", apps: ["well"]) else { Issue.record("made a tag over an alias"); return }
        #expect(alias.id == "jokes")
        #expect(await tags.create("  ", apps: []) == .failed("Give it a name."))
        let made = try FileManager.default.contentsOfDirectory(atPath: root.appending(path: "data/tags").path())
        #expect(made.sorted() == ["dev", "health", "jokes"])
        #expect(!tags.all.map(\.id).contains("health"), "a folder with no page is no tag")
    }

    @Test("Archive and restore on a Mac flag the page in place; edit changes meaning, colour and apps")
    func archiveOnTheMac() async throws {
        let root = try vault()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appending(path: "data/tags/jokes/entity.md")
        let tags = GlyphTags()
        #expect(tags.readVault(root))
        #expect(await tags.setArchived("jokes", true))
        var page = try String(contentsOf: file, encoding: .utf8)
        #expect(page.contains("archived: true") && page.contains("archived_at: 20") && page.hasSuffix("## Your notes\n\nKept.\n"))
        #expect(tags.all.isEmpty && tags.archived(forApp: "jot").map(\.id) == ["jokes"])
        // Archived, the name still answers, so "New tag" offers Restore rather than a duplicate.
        guard case .existing(let hit) = await tags.create("Jokes", apps: ["jot"]) else { Issue.record("duplicated an archived tag"); return }
        #expect(hit.archived)
        #expect(await tags.setArchived("jokes", false))
        page = try String(contentsOf: file, encoding: .utf8)
        #expect(!page.contains("archived") && page.contains(#"name: "Jokes""#) && page.hasSuffix("Kept.\n"))
        #expect(tags.forApp("jot").map(\.id) == ["jokes"])
        #expect(await tags.edit("jokes", covers: "Funny lines.", color: "#2a9d8f", apps: ["jot", "well"]))
        page = try String(contentsOf: file, encoding: .utf8)
        #expect(page.contains(#"covers: "Funny lines.""#) && page.contains(##"color: "#2a9d8f""##) && page.contains(#"apps: ["jot", "well"]"#))
        #expect(GlyphTags.forApp("well").first?.covers == "Funny lines.")
        #expect(await tags.edit("jokes", covers: "", color: nil, apps: ["jot"]))
        #expect(!(try String(contentsOf: file, encoding: .utf8)).contains("covers:"))
        #expect(!(await tags.setArchived("../jokes", true)))
        #expect(!(await tags.setArchived("missing", true)))
    }

    @Test("Front matter is changed key by key, the rest of the page byte for byte")
    func frontMatter() {
        let page = "---\nname: \"A\"\nkind: tag\n---\n\nBody: with a colon.\n"
        #expect(GlyphTags.setFront(page, ["archived": "true"]) == "---\nname: \"A\"\nkind: tag\narchived: true\n---\n\nBody: with a colon.\n")
        #expect(GlyphTags.setFront(GlyphTags.setFront(page, ["archived": "true"]), ["archived": nil]) == page)
        #expect(GlyphTags.setFront("no front matter", ["x": "1"]) == "no front matter")
    }

    @Test("The app a tag is made in is read off the bundle id")
    func appHere() {
        // The test runner is not a family app.
        #expect(GlyphTags.appHere == nil)
        #expect(GlyphTags.familyApps.contains { $0.id == "well" } && !GlyphTags.palette.contains { $0.lowercased() == "#ffd700" })
    }
}
