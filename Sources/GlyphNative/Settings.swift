import SwiftUI
import AppKit

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
                    row("Hub", setup.health?.ok == true ? "Reachable, \(setup.health?.domains?.count ?? 0) domains" : "Not answering", "settings.hub")
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

enum ShelfSubPage { case settings, about }

/// Settings as a page in the release window (the other window keeps SettingsSheet).
struct SettingsPage<Toggle: View>: View {
    @EnvironmentObject var shelf: Shelf
    let sidebarShown: Bool
    @Binding var sub: ShelfSubPage?
    @ViewBuilder let toggle: () -> Toggle

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if sub == .about { aboutBody } else { settingsBody }
            }
            .padding(.horizontal, 28).padding(.top, 22).padding(.bottom, 24)
        }
        .scrollEdgeEffectHidden(true, for: .all)
    }

    private func title(_ t: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            if !sidebarShown { toggle().padding(.leading, 48).alignmentGuide(.firstTextBaseline) { $0[.bottom] - 4 } }
            Text(t).font(.system(size: 30, weight: .bold)).tracking(-0.6).foregroundStyle(Token.text)
            Spacer(minLength: 8)
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
