import SwiftUI
import AppKit
import NativeKit

/// Where everything is: the vault, the hub it syncs through, and where apps are built from. Addresses come from
/// ~/.config/glyph/env (personal setup, outside the repo); GLYPH_NATIVE_ENV points elsewhere in tests.
@MainActor
final class Setup: ObservableObject {
    struct Health: Decodable { let ok: Bool; let domains: [String]?; let vault: String? }

    @Published var env: [String: String] = [:]
    @Published var vault: String?
    @Published var health: Health?

    static var envFile: URL {
        URL(filePath: ProcessInfo.processInfo.environment["GLYPH_NATIVE_ENV"] ?? (NSHomeDirectory() + "/.config/glyph/env"))
    }

    /// The vault: Glyph Bot's own config says where it is (LocalVault); GLYPH_NATIVE_VAULT in tests.
    nonisolated static var vaultPath: String? {
        ProcessInfo.processInfo.environment["GLYPH_NATIVE_VAULT"] ?? LocalVault.path
    }

    /// The hub's address from the personal env file (nil when none is set).
    static var hubURL: URL? {
        for line in ((try? String(contentsOf: envFile, encoding: .utf8)) ?? "").split(separator: "\n") where line.hasPrefix("GLYPH_VAULT_URL=") {
            return URL(string: String(line.dropFirst("GLYPH_VAULT_URL=".count)).trimmingCharacters(in: .whitespaces))
        }
        return nil
    }

    func load() async {
        env = [:]
        for line in ((try? String(contentsOf: Self.envFile, encoding: .utf8)) ?? "").split(separator: "\n") {
            let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
            if parts.count == 2, !parts[0].hasPrefix("#") { env[parts[0]] = parts[1] }
        }
        vault = Self.vaultPath
        health = await get(env["GLYPH_VAULT_URL"], "health")
    }

    private func get<T: Decodable>(_ base: String?, _ path: String) async -> T? {
        guard let base, let url = URL(string: base)?.appending(path: path) else { return nil }
        var req = URLRequest(url: url, timeoutInterval: 8)
        req.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (data, resp) = try? await URLSession.shared.data(for: req), (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

}

struct SettingsSheet: View {
    @StateObject private var setup = Setup()
    @EnvironmentObject var shelf: Shelf
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Settings").font(.system(size: 24, weight: .bold))
                Spacer()
                Button("Refresh") { Task { await setup.load() } }.testFrame("settings.refresh")
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction).testFrame("settings.done")
            }
            .padding(24)
            Form {
                Section {
                    row("Folder", setup.vault.map { ($0 as NSString).abbreviatingWithTildeInPath } ?? "Not found", "settings.vault")
                    row("Hub", setup.health?.ok == true ? "Reachable, \(setup.health?.domains?.count ?? 0) domains" : "Not reachable", "settings.hub")
                    row("Hub address", setup.env["GLYPH_VAULT_URL"] ?? "Not set", "settings.hubURL")
                } header: { Text("Vault") }
                Section("This Mac") {
                    row(Shelf.releaseMode ? "Installs apps from" : "Builds apps from", Shelf.repo.map { ($0.path as NSString).abbreviatingWithTildeInPath } ?? "GitHub releases", "settings.repo")
                }
                if Shelf.releaseMode {
                    Section("Updates") {
                        LabeledContent("Check for updates") {
                            HStack(spacing: 12) {
                                Text(shelf.lastChecked.map { "Last checked at " + $0.formatted(date: .omitted, time: .shortened) } ?? "Not checked yet")
                                    .foregroundStyle(.secondary)
                                Button("Check now") { shelf.fetch() }.testFrame("settings.check")
                            }
                        }
                    }
                }
                Section("About") {
                    row(Shelf.releaseMode ? "Glyph Native" : "Glyph Labs", Self.version, "settings.version")
                }
            }
            .formStyle(.grouped)
        }
        .frame(width: 560, height: 540)
        .background(Color(nsColor: .windowBackgroundColor))
        .task { await setup.load(); UITest.setup = setup }
    }
    static var version: String {
        let i = Bundle.main.infoDictionary ?? [:]
        return "\(i["CFBundleShortVersionString"] as? String ?? "?") (\(i["CFBundleVersion"] as? String ?? "?"))"
    }
    private func row(_ k: String, _ v: String, _ id: String) -> some View {
        LabeledContent(k) { Text(v).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle).textSelection(.enabled) }
    }
}

enum ShelfSubPage { case settings, about, answers }

/// Settings as a page in the release window (the other window keeps SettingsSheet).
struct SettingsPage<Toggle: View>: View {
    @EnvironmentObject var shelf: Shelf
    let sidebarShown: Bool
    @Binding var sub: ShelfSubPage?
    @ViewBuilder let toggle: () -> Toggle
    @StateObject private var answers = AnswersModel(base: Setup.hubURL, model: "Mac")
    @State private var pageW: CGFloat = 1000

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if sub == .about { aboutBody } else if sub == .answers { answersBody } else { settingsBody }
            }
            .padding(.horizontal, 28).padding(.top, 22).padding(.bottom, 24)
        }
        .scrollEdgeEffectHidden(true, for: .all)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { pageW = $0 }
        .task(id: sub) { if sub == .answers || sub == .settings { await answers.load() } }
    }

    private func title(_ t: String, trailing: String = "") -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            if !sidebarShown { toggle().padding(.leading, 48).alignmentGuide(.firstTextBaseline) { $0[.bottom] - 4 } }
            Text(t).font(.system(size: 30, weight: .bold)).tracking(-0.6).foregroundStyle(Token.text).lineLimit(1)
            Spacer(minLength: 8)
            if !trailing.isEmpty {
                Text(trailing).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Token.tintText).lineLimit(1)
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(Capsule().fill(Token.tint)).overlay(Capsule().strokeBorder(Token.tintBorder))
                    .testFrame("answers.chip")
            }
        }
    }
    private func heading(_ t: String) -> some View {
        Text(t).font(.system(size: 11.5, weight: .semibold)).tracking(0.6).textCase(.uppercase).foregroundStyle(Token.accentLight)
    }
    private func card<C: View>(@ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 0) { c() }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Token.raised))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Token.border))
    }
    private func line(_ k: String, @ViewBuilder _ v: () -> some View) -> some View {
        HStack(spacing: 12) {
            Text(k).font(.system(size: 14.5)).foregroundStyle(Token.text)
            Spacer(minLength: 8)
            v()
        }
    }
    private func quiet(_ t: String) -> some View { Text(t).font(.system(size: 13)).foregroundStyle(Token.quiet).lineLimit(1) }

    @ViewBuilder private var settingsBody: some View {
        title("Settings")
        heading("Updates")
        card {
            line("Check for updates") {
                quiet(shelf.lastChecked.map { "Last checked at " + $0.formatted(date: .omitted, time: .shortened) } ?? "Not checked yet")
                Button("Check now") { shelf.fetch() }.testFrame("settings.check")
            }
        }
        heading("Chats")
        Button { sub = .answers } label: {
            card {
                line("Answers come from") {
                    quiet(answers.defaultWords)
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Token.quiet)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).testFrame("settings.answers")
        heading("This Mac")
        card { line("Installs apps from") { quiet("GitHub releases") } }
        heading("About")
        Button { sub = .about } label: {
            card {
                line("About Glyph Native") {
                    quiet(SettingsSheet.version)
                    Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Token.quiet)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain).testFrame("settings.about")
    }

    @ViewBuilder private var answersBody: some View {
        Button { sub = .settings } label: {
            Label("Settings", systemImage: "chevron.left").font(.system(size: 13.5)).foregroundStyle(Token.quiet)
                .padding(.leading, sidebarShown ? 0 : 48)
        }
        .buttonStyle(.plain).testFrame("answers.back")
        title("Answers come from", trailing: answers.defaultWords)
        Text(AnswersModel.intro).font(.system(size: 14.5)).foregroundStyle(Token.rowText).lineLimit(1)
        if answers.away {
            HStack(spacing: 12) {
                Image(systemName: "wifi.slash").foregroundStyle(Token.quiet)
                Text(AnswersModel.awayLine).font(.system(size: 13.5)).foregroundStyle(Token.rowText).lineLimit(1)
                Spacer(minLength: 8)
                Button("Try again") { Task { await answers.load() } }.testFrame("answers.retry")
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Token.raised))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Token.border))
        } else if answers.saveFailed {
            Text("Couldn't save. Showing what your vault computer has.").font(.system(size: 13.5)).foregroundStyle(Token.quiet).lineLimit(1)
        }
        let width = pageW - 56
        let engineCols = width >= 5 * 150 + 4 * 14 ? 5 : 3
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14, alignment: .top), count: engineCols), alignment: .leading, spacing: 14) {
            ForEach(["auto"] + AnswerSettings.engineIds, id: \.self) { id in
                EngineTile(id: id, answers: answers)
            }
        }
        VStack(spacing: 0) {
            if answers.severalTicked {
                HStack(spacing: 10) {
                    Image(systemName: "person.3.fill").font(.system(size: 14)).foregroundStyle(Token.tintText)
                    Text(answers.councilBanner).font(.system(size: 13.5, weight: .medium)).foregroundStyle(Token.tintText).lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16).padding(.vertical, 11)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Token.tint))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Token.tintBorder))
                .transition(.opacity.combined(with: .move(edge: .top)))
                .testFrame("answers.council")
            }
        }
        .animation(.easeOut(duration: 0.2), value: answers.severalTicked)
        heading("Per app")
        let cols = ShelfLogic.columns(count: answers.apps.count, fit: ShelfLogic.fit(width: Double(width)))
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14, alignment: .top), count: cols), alignment: .leading, spacing: 14) {
            ForEach(answers.apps, id: \.id) { app in AppAnswerCard(app: app, answers: answers) }
        }
    }

    @ViewBuilder private var aboutBody: some View {
        Button { sub = .settings } label: {
            Label("Settings", systemImage: "chevron.left").font(.system(size: 13.5)).foregroundStyle(Token.quiet)
                .padding(.leading, sidebarShown ? 0 : 48)
        }
        .buttonStyle(.plain).testFrame("about.back")
        title("About")
        VStack(spacing: 8) {
            if let img = Bundle.main.image(forResource: "icon-native") {
                Image(nsImage: img).resizable().frame(width: 72, height: 72).clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
            }
            Text("Glyph Native").font(.system(size: 24, weight: .bold)).foregroundStyle(Token.text)
            Text("Version \(SettingsSheet.version)").font(.system(size: 13.5)).foregroundStyle(Token.quiet)
            Text("One install for every Glyph app.").font(.system(size: 14.5)).foregroundStyle(Token.rowText)
            LabsLink().testFrame("about.labs")
        }
        .frame(maxWidth: .infinity)
        card {
            link("glyph.fru.dev", "https://glyph.fru.dev", "about.site")
            Rectangle().fill(Token.hairline).frame(height: 1).padding(.vertical, 10)
            link("Source on GitHub", "https://github.com/fru-dev3/glyph-native", "about.source")
            Rectangle().fill(Token.hairline).frame(height: 1).padding(.vertical, 10)
            link("License: MIT", "https://github.com/fru-dev3/glyph-native/blob/main/LICENSE", "about.license")
        }
        if let c = Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String {
            Text(c).font(.system(size: 12)).foregroundStyle(Token.quiet).frame(maxWidth: .infinity)
        }
    }

    private func link(_ t: String, _ url: String, _ id: String) -> some View {
        Button { NSWorkspace.shared.open(URL(string: url)!) } label: {
            line(t) { Image(systemName: "arrow.up.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Token.quiet) }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).testFrame(id)
    }
}


private let tileTop = Color(NSColor.hex(0x0A9A12)), tileBottom = Color(NSColor.hex(0x006B06)), tileEdge = Color(NSColor.hex(0x4AC456))

/// One engine as a selectable tile: filled green when ticked (like the active card), green on hover, dimmed when the
/// vault computer does not have it.
private struct EngineTile: View {
    let id: String
    @ObservedObject var answers: AnswersModel
    @State private var hover = false
    var body: some View {
        let s = answers.settings
        let ticked = s?.choice.contains(id) == true
        let there = answers.available(id)
        let off = s == nil || (!there && !ticked)
        let lit = ticked || (hover && !off && answers.enabled && !PictureArgs.on)
        let line = s == nil ? "" : id == "auto" ? "The usual order" : there ? (s?.engines[id]?.detail ?? "") : AnswersModel.missing
        Button { Task { await answers.tick(id) } } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    Image(systemName: AnswersModel.symbol(id)).font(.system(size: 18, weight: .medium))
                        .foregroundStyle(lit ? Color.white : Token.accentLight)
                        .frame(width: 38, height: 38)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(lit ? Color.white.opacity(0.18) : Token.tint))
                    Spacer(minLength: 0)
                    if ticked { Image(systemName: "checkmark.circle.fill").font(.system(size: 20)).foregroundStyle(.white) }
                }
                Spacer(minLength: 10)
                Text(AnswerSettings.names[id] ?? id).font(.system(size: 15, weight: .semibold)).foregroundStyle(lit ? Color.white : Token.text).lineLimit(1)
                Text(line).font(.system(size: 12.5)).foregroundStyle(lit ? Color.white.opacity(0.85) : Token.quiet)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true).frame(minHeight: 32, alignment: .topLeading).padding(.top, 2)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 138, alignment: .topLeading)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Token.raised)
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(LinearGradient(colors: [tileTop, tileBottom], startPoint: .top, endPoint: .bottom)).opacity(lit ? 1 : 0)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(lit ? tileEdge : Token.border))
            .shadow(color: tileTop.opacity(ticked ? 0.3 : 0), radius: 12, y: 5)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!answers.enabled || (!there && !ticked))
        .opacity(off ? 0.45 : 1)
        .animation(.easeOut(duration: 0.18), value: lit)
        .onHover { if !PictureArgs.on { hover = $0 } }
        .testFrame("answers.choice.\(id)")
    }
}

/// One app that chats: its real icon, its name, and a pill menu with its own choice (green) or "Follows default".
private struct AppAnswerCard: View {
    let app: (id: String, name: String)
    @ObservedObject var answers: AnswersModel
    @State private var hover = false
    var body: some View {
        let own = !answers.followsDefault(app.id)
        let lock = answers.isPrivate(app.id)
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Group {
                    if let img = Bundle.main.image(forResource: "icon-\(app.id)") { Image(nsImage: img).resizable() } else { Color(NSColor.hex(0x1C6B2A)) }
                }
                .frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 10.6, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(Token.text).lineLimit(1)
                    if lock {
                        Label("Private by default", systemImage: "lock.fill").font(.system(size: 12)).foregroundStyle(Token.quiet).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            Menu {
                Button { Task { await answers.setApp(app.id, to: nil) } } label: {
                    if answers.followsDefault(app.id) { Label(answers.followLabel(app.id), systemImage: "checkmark") } else { Text(answers.followLabel(app.id)) }
                }
                Divider()
                ForEach(["auto"] + AnswerSettings.engineIds, id: \.self) { e in
                    Button { Task { await answers.setApp(app.id, to: e) } } label: {
                        if answers.appChoice(app.id) == e { Label(AnswerSettings.names[e] ?? e, systemImage: "checkmark") } else { Text(AnswerSettings.names[e] ?? e) }
                    }
                    .disabled(!answers.available(e))
                }
            } label: {
                HStack(spacing: 6) {
                    if lock { Image(systemName: "lock.fill").font(.system(size: 10.5)) }
                    Text(lock ? "Open model" : answers.appWords(app.id)).font(.system(size: 13, weight: .medium)).lineLimit(1)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(own || lock ? Token.tintText : Token.quiet)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .frame(maxWidth: .infinity)
                .background(Capsule().fill(own || lock ? Token.tint : Token.hairline))
                .overlay(Capsule().strokeBorder(own || lock ? Token.tintBorder : Token.border))
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
            .disabled(!answers.enabled)
            .testFrame("answers.app.\(app.id)")
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background {
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Token.raised)
                if let sym = Release.motifs[app.id] {
                    Image(systemName: sym).symbolRenderingMode(.hierarchical).font(.system(size: 90))
                        .foregroundStyle(Color.nativeGreen).opacity(0.06)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing).offset(x: 26, y: -30).allowsHitTesting(false)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(hover && answers.enabled ? tileEdge : Token.border))
        .opacity(answers.settings == nil ? 0.45 : 1)
        .onHover { if !PictureArgs.on { hover = $0 } }
    }
}
