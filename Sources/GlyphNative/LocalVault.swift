import Foundation

/// This Mac's vault when none is chosen in Settings: the Glyph Bot vault, read from Studio's
/// own config (never assumed). The path keeps the `prevail` name on purpose, so an existing
/// install keeps working. It goes into the public copy as it is: it holds a product path and
/// nothing personal, and a stand-in there is what shipped a launcher that knew the vault while no
/// other app could see it (Fru, 2026-11-15).
enum LocalVault {
    private static var config: URL { URL.homeDirectory.appending(path: ".prevail/config.json") }

    /// Chooses the vault: writes `vaultPath` into the same config `path` reads, keeping every other key.
    static func set(_ path: String) {
        // Pictures and tests must never write the owner's real setting.
        let a = CommandLine.arguments, e = ProcessInfo.processInfo.environment
        if a.contains("--picture") || e["GLYPH_NATIVE_VAULT"] != nil || e["GLYPH_NATIVE_ENV"] != nil { return }
        var json = (try? Data(contentsOf: config)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        json["vaultPath"] = path
        try? FileManager.default.createDirectory(at: config.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]) { try? data.write(to: config, options: .atomic) }
    }

    static var path: String? {
        guard let data = try? Data(contentsOf: config),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return (json["vaultPath"] as? String).map { ($0 as NSString).expandingTildeInPath }
    }
}
