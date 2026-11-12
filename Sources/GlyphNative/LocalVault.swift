import Foundation

/// The vault folder the person chose, kept in this app's own settings.
enum LocalVault {
    static var path: String? { UserDefaults.standard.string(forKey: "vaultPath") }
    static func set(_ path: String) { UserDefaults.standard.set(path, forKey: "vaultPath") }
}
