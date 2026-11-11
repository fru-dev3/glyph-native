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

    /// The vault: Glyph Studio's own config says where it is (LocalVault); GLYPH_NATIVE_VAULT in tests.
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
