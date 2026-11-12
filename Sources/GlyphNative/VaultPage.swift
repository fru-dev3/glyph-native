import SwiftUI
import AppKit
import NativeKit

/// Hidden launch arguments, honoured only together with --picture, so a real window never reads them.
enum PictureArgs {
    static var on: Bool { CommandLine.arguments.contains("--picture") }
    static func value(_ key: String) -> String? {
        guard on, let i = CommandLine.arguments.firstIndex(of: key), i + 1 < CommandLine.arguments.count else { return nil }
        return CommandLine.arguments[i + 1]
    }
}

/// The chosen vault folder, the proof it works, and this Mac's line among the devices.
@MainActor
final class VaultModel: ObservableObject {
    static let shared = VaultModel()
    @Published var path: String?
    @Published var outcome = ""
    @Published var failed = false
    @Published var entries: [VaultKit.Entry] = []
    @Published var now = Date()
    private var started = false

    static var macName: String { Host.current().localizedName ?? ProcessInfo.processInfo.hostName }
    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0" }
    var thisSlug: String { VaultKit.slug(Self.macName) }

    /// `--novault` with --picture: the empty state, whatever this Mac has chosen.
    private static var current: String? { PictureArgs.value("--novault") != nil ? nil : Setup.vaultPath }

    func start() {
        guard !started else { return }
        started = true
        path = Self.current
        Task {
            while !Task.isCancelled {
                // A picture never writes into a real vault.
                if !PictureArgs.on, let p = path { try? VaultKit.record(vault: p, name: Self.macName, version: Self.version) }
                reload()
                try? await Task.sleep(for: .seconds(300))
            }
        }
    }

    func reload() {
        now = .now
        entries = path.map { VaultKit.entries(vault: $0) } ?? []
    }

    /// Proves the folder, then makes it the vault.
    func accept(_ p: String) {
        do {
            outcome = try VaultKit.check(p); failed = false
            let full = (p as NSString).expandingTildeInPath
            if !Onboarding.isolated() { LocalVault.set(full) }   // also guarded inside set()
            path = full
            if !PictureArgs.on { try? VaultKit.record(vault: full, name: Self.macName, version: Self.version) }
        } catch { outcome = error.localizedDescription; failed = true }
        reload()
    }

    func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
        panel.prompt = "Use as Vault"
        if panel.runModal() == .OK, let u = panel.url { accept(u.path) }
    }

    func create(under home: String = NSHomeDirectory()) {
        let dir = (home as NSString).appendingPathComponent("Documents/Glyph Vault")
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        accept(dir)
    }

    /// The newest iPhone that is new since a screen opened: its file was not there then (`known`), or its time is
    /// later than the moment the screen opened. Never a phone that was there and unchanged.
    static func newPhone(_ entries: [VaultKit.Entry], known: Set<String>, since: Date) -> VaultKit.Device? {
        entries.compactMap { e -> VaultKit.Device? in
            guard case .device(let d, let file) = e, d.kind == "iPhone", !known.contains(file) || d.seen > since else { return nil }
            return d
        }.max { $0.seen < $1.seen }
    }

    static func phoneFiles(_ entries: [VaultKit.Entry]) -> Set<String> {
        Set(entries.compactMap { if case .device(let d, let f) = $0, d.kind == "iPhone" { f } else { nil } })
    }

    /// Re-reads the device files every 3 seconds until the calling task is cancelled (the screen went away).
    func watch() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled { reload() }
        }
    }

    func showInFinder() { if let p = path { NSWorkspace.shared.activateFileViewerSelecting([URL(filePath: p)]) } }
}

struct VaultPage<Toggle: View>: View {
    @ObservedObject var model: VaultModel
    @StateObject private var setup = Setup()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let sidebarShown: Bool
    @ViewBuilder let toggle: () -> Toggle
    @State private var wide = false
    @State private var answeredAt: Date?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    if !sidebarShown { toggle().padding(.leading, 48).alignmentGuide(.firstTextBaseline) { $0[.bottom] - 4 } }
                    Text("Vault").font(.system(size: 30, weight: .bold)).tracking(-0.6).foregroundStyle(Token.text)
                    Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day())).font(.system(size: 13)).foregroundStyle(Token.quiet)
                    Spacer(minLength: 8)
                }
                if model.path != nil { strip }
                heading("Folder")
                if wide { HStack(alignment: .top, spacing: 14) { folderCard; if hasAddress { computerCard } } }
                else { VStack(alignment: .leading, spacing: 14) { folderCard; if hasAddress { computerCard } } }
                heading("Devices")
                devicesCard
                Button("Set up again") { SetupFlow.shared.restart() }.buttonStyle(.plain).font(.system(size: 12.5)).foregroundStyle(Token.quiet)
                    .padding(.top, 4).testFrame("vault.again")
            }
            .padding(.horizontal, 28).padding(.top, 22).padding(.bottom, 24)
        }
        .scrollEdgeEffectHidden(true, for: .all)
        .onGeometryChange(for: Bool.self) { $0.size.width >= 760 } action: { wide = $0 }
        .onAppear { model.reload() }
        .task { await check() }
        .task { await model.watch() }
    }

    private func heading(_ t: String) -> some View {
        Text(t).font(.system(size: 11.5, weight: .semibold)).tracking(0.6).textCase(.uppercase).foregroundStyle(Token.accentLight)
    }

    private func card<C: View>(@ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 0) { c() }
            .padding(16).frame(maxWidth: .infinity, maxHeight: wide ? .infinity : nil, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Token.raised))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Token.border))
    }

    private var address: String { setup.env["GLYPH_VAULT_URL"] ?? "" }
    private var hasAddress: Bool { model.path != nil && !address.isEmpty }
    private var answering: Bool { setup.health?.ok == true }

    private func check() async {
        await setup.load()
        if answering { answeredAt = .now }
    }

    /// "http://studio.example:7071" gives "Studio"; an IP address or nothing gives "Vault computer".
    private var computerName: String {
        let host = URL(string: address)?.host() ?? ""
        let first = host.split(separator: ".").first.map(String.init) ?? ""
        guard !first.isEmpty, first.contains(where: \.isLetter), !host.contains(":") else { return "Vault computer" }
        return first.prefix(1).uppercased() + first.dropFirst()
    }

    private func tile(_ symbol: String) -> some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Token.tint)
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Token.tintBorder))
            .overlay(Image(systemName: symbol).font(.system(size: 20)).foregroundStyle(Token.accentLight))
            .frame(width: 44, height: 44)
    }

    private var folderCard: some View {
        card {
            HStack(spacing: 12) {
                tile("folder.fill")
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.path.map { ($0 as NSString).abbreviatingWithTildeInPath } ?? "No vault folder chosen yet.")
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(Token.text)
                        .lineLimit(1).truncationMode(.middle).textSelection(.enabled).testFrame("vault.path")
                    if model.path != nil { Text("On this Mac").font(.system(size: 12.5)).foregroundStyle(Token.quiet) }
                }
                Spacer(minLength: 8)
                VStack(spacing: 6) {   // one width for all, the widest label's
                    if model.path == nil { button("Create Glyph Vault", primary: true, fill: true) { model.create() }.testFrame("vault.create") }
                    button("Choose…", primary: false, fill: true) { model.choose() }.testFrame("vault.choose")
                    if model.path != nil { button("Show in Finder", primary: false, fill: true) { model.showInFinder() }.testFrame("vault.reveal") }
                }
                .fixedSize(horizontal: true, vertical: false)
            }
            if !model.outcome.isEmpty {
                Text(model.outcome).font(.system(size: 12.5)).foregroundStyle(model.failed ? Token.text : Token.quiet)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 10).testFrame("vault.outcome")
            }
        }
    }

    private var computerCard: some View {
        let amber = Color(red: 0.898, green: 0.635, blue: 0.239)
        return card {
            HStack(spacing: 12) {
                tile("desktopcomputer")
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(computerName).font(.system(size: 15, weight: .semibold)).foregroundStyle(Token.text)
                            .lineLimit(1).truncationMode(.tail).layoutPriority(0)
                        HStack(spacing: 5) {
                            if answering { Circle().fill(Token.accentLight).frame(width: 6, height: 6) }
                            Text(answering ? "Answering" : "Not answering").font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(answering ? Token.accentLight : amber).lineLimit(1)
                        }
                        .padding(.horizontal, 9).frame(height: 22).fixedSize().layoutPriority(1)
                        .background(Capsule().fill(answering ? Token.tint : Color(red: 0.165, green: 0.133, blue: 0.078)))
                        .testFrame("vault.computer")
                    }
                    HStack(spacing: 6) {
                        Text(address).font(.system(size: 12.5)).foregroundStyle(Token.quiet)
                            .lineLimit(1).truncationMode(.middle).textSelection(.enabled).testFrame("vault.address")
                        Button {
                            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(address, forType: .string)
                        } label: { Image(systemName: "doc.on.doc").font(.system(size: 12)).foregroundStyle(Token.quiet) }
                            .buttonStyle(.plain).help("Copy address").testFrame("vault.copy")
                    }
                }
                Spacer(minLength: 8)
                if answering {
                    if let t = answeredAt {
                        Text("Answered at \(t.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)))")
                            .font(.system(size: 12.5)).foregroundStyle(Token.quiet).lineLimit(1).fixedSize()
                    }
                } else {
                    button("Try again", primary: false) { Task { await check() } }.testFrame("vault.retry")
                }
            }
        }
    }

    private func button(_ t: String, primary: Bool, fill: Bool = false, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Text(t).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(primary ? Token.tintText : Token.rowText)
                .frame(maxWidth: fill ? .infinity : nil)
                .padding(.horizontal, 14).frame(height: 30)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(primary ? Token.tint : Token.raisedLifted))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(primary ? .clear : Token.border))
        }
        .buttonStyle(.plain).fixedSize(horizontal: !fill, vertical: true)
    }

    private var devicesCard: some View {
        card {
            if model.path == nil {
                quiet("Devices appear here once a vault folder is chosen.")
            } else {
                ForEach(Array(model.entries.enumerated()), id: \.offset) { i, e in
                    if i > 0 { Rectangle().fill(Token.hairline).frame(height: 1).padding(.vertical, 10) }
                    row(e)
                }
                if !model.entries.contains(where: { if case .device(let d, _) = $0 { d.kind == "iPhone" } else { false } }) {
                    if !model.entries.isEmpty { Rectangle().fill(Token.hairline).frame(height: 1).padding(.vertical, 10) }
                    quiet("No phone has reached this vault yet.")
                }
                Rectangle().fill(Token.hairline).frame(height: 1).padding(.vertical, 10)
                Button("Add another device") { SetupFlow.shared.step = .phone; SetupFlow.shared.active = true }
                    .buttonStyle(.plain).font(.system(size: 13.5, weight: .semibold)).foregroundStyle(Token.accentLight).testFrame("vault.add")
            }
        }
    }

    private var devices: [VaultKit.Device] { model.entries.compactMap { if case .device(let d, _) = $0 { d } else { nil } } }
    private func stale(_ d: VaultKit.Device) -> Bool { model.now.timeIntervalSince(d.seen) > 86_400 }

    /// The vault at the centre in two soft rings, each device a tile on a wide ellipse around it, joined ring to tile.
    private var strip: some View {
        let ds = devices
        let green = Color(red: 0.498, green: 0.831, blue: 0.604), amber = Color(red: 0.95, green: 0.7, blue: 0.25)
        let ringR: CGFloat = 70, tileHalf: CGFloat = 22
        return ZStack {
            LinearGradient(colors: [Color(red: 0.055, green: 0.14, blue: 0.07), Color(red: 0.07, green: 0.227, blue: 0.1)], startPoint: .topLeading, endPoint: .bottomTrailing)
            GeometryReader { g in
                let c = CGPoint(x: g.size.width / 2, y: g.size.height / 2)
                let rx = g.size.width * 0.38, ry = g.size.height * 0.30
                ForEach(Array(ds.enumerated()), id: \.offset) { i, d in
                    let n = ds.count
                    // one: left; two: left and right; more: even steps from the left, going over the top.
                    let a = Double.pi - (n == 2 ? Double(i) * Double.pi : Double(i) * 2 * Double.pi / Double(max(n, 1)))
                    let ox0 = CGFloat(cos(a)) * rx, oy = min(-CGFloat(sin(a)) * ry, g.size.height / 2 - 66)
                    // never closer than 150pt to the centre: push sideways along x
                    let need = max(0, (150 * 150 - oy * oy).squareRoot())
                    let side: CGFloat = abs(ox0) > 1 ? (ox0 < 0 ? -1 : 1) : (oy < 0 ? 1 : -1)
                    let ox = side * max(abs(ox0), need)
                    let pos = CGPoint(x: c.x + ox, y: c.y + oy)
                    let len = (ox * ox + oy * oy).squareRoot()
                    let u = CGPoint(x: -ox / len, y: -oy / len)   // node toward centre
                    let t = tileHalf / max(abs(u.x), abs(u.y))
                    let from = CGPoint(x: pos.x + u.x * t, y: pos.y + u.y * t)
                    let to = CGPoint(x: c.x - u.x * ringR, y: c.y - u.y * ringR)
                    let col = stale(d) ? amber : green
                    Path { p in p.move(to: from); p.addLine(to: to) }
                        .stroke(col.opacity(stale(d) ? 0.8 : 0.6), style: StrokeStyle(lineWidth: 1.5, dash: stale(d) ? [5, 5] : []))
                    if !stale(d) && !reduceMotion {
                        TimelineView(.animation) { tl in
                            let f = CGFloat((tl.date.timeIntervalSinceReferenceDate / 5 + Double(i) * 0.3).truncatingRemainder(dividingBy: 1))
                            Circle().fill(green).frame(width: 6, height: 6)
                                .position(x: from.x + (to.x - from.x) * f, y: from.y + (to.y - from.y) * f)
                        }
                    }
                    VStack(spacing: 3) {
                        RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color.white.opacity(0.1))
                            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(col.opacity(0.5)))
                            .overlay(Image(systemName: glyph(d)).font(.system(size: 20)).foregroundStyle(col))
                            .frame(width: 44, height: 44)
                        Text(d.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white).lineLimit(1).truncationMode(.middle)
                        Text(VaultKit.ago(d.seen, now: model.now)).font(.system(size: 12)).foregroundStyle(stale(d) ? amber : Token.quiet).lineLimit(1).truncationMode(.middle)
                    }.frame(width: 160, height: 44 + 3 + 16 + 3 + 15, alignment: .top)
                        .position(x: pos.x, y: pos.y + (44 + 3 + 16 + 3 + 15) / 2 - 22)
                }
                ZStack {
                    Circle().strokeBorder(Color.white.opacity(0.14), lineWidth: 1).frame(width: ringR * 2, height: ringR * 2)
                    Circle().strokeBorder(Color.white.opacity(0.2), lineWidth: 1).frame(width: 104, height: 104)
                    Group {
                        if let i = Bundle.main.image(forResource: "icon-native") { Image(nsImage: i).resizable().scaledToFit() } else { Color.clear }
                    }.frame(width: 64, height: 64).clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                }.position(c)
                Text(model.path.map { URL(filePath: $0).lastPathComponent } ?? "Vault")
                    .font(.system(size: 12)).foregroundStyle(.white.opacity(0.7)).lineLimit(1).truncationMode(.middle).frame(width: 140)
                    .position(x: c.x, y: c.y + ringR + 12)
            }
        }
        .frame(minHeight: 200, idealHeight: 260, maxHeight: 260).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Token.tintBorder))
    }

    private func glyph(_ d: VaultKit.Device) -> String {
        if d.kind == "iPhone" { return "iphone" }
        return ["mini", "studio", "imac", "desktop"].contains { d.name.lowercased().contains($0) } ? "desktopcomputer" : "laptopcomputer"
    }

    private func quiet(_ t: String) -> some View {
        Text(t).font(.system(size: 12.5)).foregroundStyle(Token.quiet).fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private func row(_ e: VaultKit.Entry) -> some View {
        switch e {
        case .device(let d, let file):
            let role = Onboarding.role(device: d.name, kind: d.kind, thisMac: model.thisSlug == VaultKit.slug(d.name) ? d.name : VaultModel.macName,
                                       storedAddress: SetupFlow.storedAddress, peers: [])
            (Text(d.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(Token.text)
                + Text(" · \(role) · last seen \(VaultKit.ago(d.seen, now: model.now))").font(.system(size: 13).monospacedDigit()).foregroundStyle(stale(d) ? Color(red: 0.95, green: 0.7, blue: 0.25) : Token.quiet))
                .lineLimit(1).truncationMode(.tail).testFrame("vault.row.\(file)")
        case .unreadable(let file):
            Text("Unreadable entry: \(file)").font(.system(size: 12.5)).foregroundStyle(Token.quiet).fixedSize(horizontal: false, vertical: true)
        }
    }
}
