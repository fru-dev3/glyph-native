import SwiftUI
import AppKit
import CoreImage.CIFilterBuiltins
import Network
import NativeKit

/// Vault onboarding (M1 to M5): the state machine, the real checks, and the screens. Release window only.
@MainActor
final class SetupFlow: ObservableObject {
    enum Step: String { case welcome, `where`, other, ready, phone }
    struct Candidate: Identifiable { let id = UUID(); let name: String, address: String; var hasVault: Bool? }
    static let shared = SetupFlow()

    @Published var active: Bool
    @Published var step: Step = .welcome { didSet {
        if oldValue != step && !going { trail.append(oldValue) }
        if step == .phone && oldValue != .phone { newPairCode() }
    } }
    private var trail: [Step] = []      // screens in the order the person came
    private var going = false
    @Published var choice = 0                     // M2: 0 this Mac, 1 another computer, 2 a folder
    @Published var refusal: String?
    @Published var remoteName: String?            // M4: "On <name>" when the vault is on another computer
    @Published var proofAt: Date?
    @Published var candidates: [Candidate] = []
    @Published var picked: UUID?
    @Published var tailscale = "Looking for Tailscale."
    @Published var network = "Looking on this network."
    @Published var looking = false
    @Published var codeOpen = false
    @Published var code = ""
    @Published var codeNote: String?
    @Published var finishedOnce = false
    @Published var pairCode: String?       // the QR's one-time code; nil with an older service (the QR then works as before)
    @Published var pairExpires: Date?
    let model = VaultModel.shared

    init() {
        let want = PictureArgs.value("--setup")
        active = PictureArgs.on ? want != nil : Setup.vaultPath == nil
        if let want, let s = Step(rawValue: want) { step = s }
        // A picture of M4 has no accepted folder; GLYPH_NATIVE_VAULT (a temp folder) stands in for it.
        if PictureArgs.value("--setup") == "ready" { proofAt = .now; if let v = ProcessInfo.processInfo.environment["GLYPH_NATIVE_VAULT"] { model.path = v } }
        if active, step == .other { discover() }
        if active, step == .phone { newPairCode() }
        if let p = PictureArgs.value("--try") { useFolder(p) }
        // `--create-in <home>` (with --picture only): runs "On this Mac" against that folder and prints the outcome.
        if let h = PictureArgs.value("--create-in") { useHere(under: h); print("CREATE-IN \(step.rawValue): \(model.outcome)"); fflush(stdout) }
    }

    func restart() { step = .welcome; refusal = nil; remoteName = nil; active = true }
    func back() {
        refusal = nil; going = true; defer { going = false }
        if let p = trail.popLast() { step = p; return }
        switch step { case .phone: step = .ready; case .ready, .other: step = .where; default: step = .welcome }  // a picture opened mid-flow has no trail
    }
    func finish() { active = false; finishedOnce = true }

    /// Proves the folder (VaultKit.check inside accept); on success M4, otherwise the refusal on M2.
    private func ran(_: String) {
        if model.outcome.isEmpty { return }  // the panel was cancelled
        if model.failed { refusal = model.outcome; step = .where } else { refusal = nil; remoteName = nil; proofAt = .now; step = .ready }
    }
    func useFolder(_ p: String) { model.accept(p); ran("") }
    func useHere(under home: String = NSHomeDirectory()) { model.outcome = ""; model.create(under: home); ran("") }
    func pickFolder() { model.outcome = ""; model.choose(); ran("") }
    func cont() { switch choice { case 0: useHere(); case 1: openOther(); default: pickFolder() } }

    func openOther() { step = .other; refusal = nil; discover() }

    // MARK: M3 discovery (no new service: tailscale's own status, then each peer's /health)
    static var envFile: URL { Setup.envFile }
    static var storedAddress: String? {
        ((try? String(contentsOf: envFile, encoding: .utf8)) ?? "").split(separator: "\n")
            .first { $0.hasPrefix("GLYPH_VAULT_URL=") }.map { String($0.dropFirst(16)).trimmingCharacters(in: .whitespaces) }.flatMap { $0.isEmpty ? nil : $0 }
    }

    nonisolated static func ask(_ address: String, port: Int) async -> Bool {
        guard let url = Onboarding.healthURL(address: address, port: port) else { return false }
        var r = URLRequest(url: url); r.timeoutInterval = 2
        guard let (d, _) = try? await URLSession.shared.data(for: r) else { return false }
        return Onboarding.health(d) != nil
    }

    /// Computers advertising `_glyph-vault._tcp` on this network (Bonjour, no new package): name, first IPv4 address and port.
    nonisolated static func bonjourPeers(seconds: Double = 3) async -> [Onboarding.Peer] {
        await withCheckedContinuation { (cont: CheckedContinuation<[Onboarding.Peer], Never>) in
            let q = DispatchQueue(label: "glyph.bonjour")
            let browser = NWBrowser(for: .bonjour(type: "_glyph-vault._tcp", domain: nil), using: .tcp)
            nonisolated(unsafe) var results: [NWBrowser.Result] = []
            nonisolated(unsafe) var out: [Onboarding.Peer] = []
            browser.browseResultsChangedHandler = { r, _ in results = Array(r) }
            browser.start(queue: q)
            q.asyncAfter(deadline: .now() + seconds) {
                browser.cancel()
                let group = DispatchGroup()
                for r in results {
                    guard case let .service(name, _, _, _) = r.endpoint else { continue }
                    group.enter()
                    let params = NWParameters.tcp
                    (params.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options)?.version = .v4
                    let c = NWConnection(to: r.endpoint, using: params)
                    nonisolated(unsafe) var done = false
                    let finish: (Onboarding.Peer?) -> Void = { p in
                        guard !done else { return }; done = true; c.cancel()
                        if let p { out.append(p) }; group.leave()
                    }
                    c.stateUpdateHandler = { st in
                        switch st {
                        case .ready:
                            if case let .hostPort(h, port)? = c.currentPath?.remoteEndpoint {
                                let ip = "\(h)".split(separator: "%").first.map(String.init) ?? ""
                                finish(ip.isEmpty ? nil : Onboarding.Peer(name: name, address: "\(ip):\(port.rawValue)"))
                            } else { finish(nil) }
                        case .failed, .cancelled: finish(nil)
                        default: break
                        }
                    }
                    c.start(queue: q)
                    q.asyncAfter(deadline: .now() + 2) { finish(nil) }
                }
                group.notify(queue: q) { cont.resume(returning: out) }
            }
        }
    }

    func discover() {
        if PictureArgs.on, CommandLine.arguments.contains("--fake-peers") {
            candidates = [Candidate(name: "Home Mac mini", address: "100.64.0.2", hasVault: true), Candidate(name: "Studio iMac", address: "100.64.0.3", hasVault: false)]
            picked = candidates.first?.id; tailscale = "Tailscale is on, so this also works away from home."; network = "Found 2 computers on this network."; return
        }
        looking = true; network = "Looking on this network."
        let port = Onboarding.port(of: Self.storedAddress)
        Task {
            async let nearby = Self.bonjourPeers()
            let out: (Data?, Bool) = await Task.detached {
                guard let exe = Onboarding.tailscalePaths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { return (nil, false) }
                let p = Process(); p.executableURL = URL(filePath: exe); p.arguments = ["status", "--json"]
                let pipe = Pipe(); p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
                guard (try? p.run()) != nil else { return (nil, true) }
                let d = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
                return (d, true)
            }.value
            var tail: [Onboarding.Peer] = []
            if !out.1 { tailscale = "Tailscale is not installed on this Mac." }
            else if let d = out.0, let on = Onboarding.tailscaleOn(statusJSON: d) {
                tailscale = on ? "Tailscale is on, so this also works away from home." : "Tailscale is off on this Mac."
                tail = Onboarding.peers(statusJSON: d)
            } else { tailscale = "Tailscale is off on this Mac." }
            let near = await nearby
            network = near.isEmpty ? "No computer found on this network." : "Found \(near.count) computer\(near.count == 1 ? "" : "s") on this network."
            var found = Onboarding.merged([tail, near]).map { Candidate(name: $0.name, address: $0.address, hasVault: nil) }
            candidates = found
            await withTaskGroup(of: (String, Bool).self) { g in
                for c in found { g.addTask { (c.address, await Self.ask(c.address, port: port)) } }
                for await (a, ok) in g { if let i = candidates.firstIndex(where: { $0.address == a }) { candidates[i].hasVault = ok } }
            }
            found = candidates; picked = (found.first { $0.hasVault == true } ?? found.first)?.id
            looking = false
        }
    }

    /// Asks the vault service for a pairing code. An older service answers 404 (or nothing): no code, the QR as before.
    func newPairCode() {
        pairCode = nil; pairExpires = nil
        if PictureArgs.on, let f = PictureArgs.value("--fake-code") {   // a picture: no service asked
            pairCode = "K7M2PQ9X"; pairExpires = Date().addingTimeInterval(f == "expired" ? -5 : 9 * 60 + 30); return
        }
        guard let addr = Self.storedAddress, let url = Onboarding.url(address: addr, port: Onboarding.port(of: addr), path: "/native/pair-codes") else { return }
        Task {
            var r = URLRequest(url: url); r.httpMethod = "POST"; r.timeoutInterval = 3
            guard let (d, resp) = try? await URLSession.shared.data(for: r), (resp as? HTTPURLResponse)?.statusCode == 200,
                  let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                  let c = j["code"] as? String, let e = j["expires"] as? Double else { return }
            pairCode = c; pairExpires = Date(timeIntervalSince1970: e)
        }
    }

    func connect(name: String, address: String) {
        do { try Onboarding.writeEnv(file: Self.envFile, key: "GLYPH_VAULT_URL", value: address) }
        catch { codeNote = error.localizedDescription; return }
        remoteName = name; refusal = nil; proofAt = .now; step = .ready
    }
    func connectPicked() { if let c = candidates.first(where: { $0.id == picked }) { connect(name: c.name, address: c.address) } }
    func useCode() {
        let a = code.trimmingCharacters(in: .whitespaces); codeNote = nil
        Task {
            if await Self.ask(a, port: Onboarding.port(of: a.contains(":") ? a : Self.storedAddress)) { connect(name: a, address: a) }
            else { codeNote = "Nothing reachable at that address." }
        }
    }
}

// MARK: root

struct RootView: View {
    @ObservedObject private var flow = SetupFlow.shared
    var body: some View {
        if flow.active { SetupView(flow: flow) }
        else { ReleaseShelfView() }
    }
}

// MARK: screens

private let panelGreen = Color(red: 0, green: 0.5, blue: 0)
private let mint = Color(red: 0.498, green: 0.831, blue: 0.604)

struct SetupView: View {
    @ObservedObject var flow: SetupFlow
    @Environment(\.accessibilityReduceMotion) private var still
    @State private var t = false
    @State private var opened = Date()
    @State private var known = Set<String>()
    @State private var arrived: VaultKit.Device?

    var body: some View {
        HStack(spacing: 0) {
            GeometryReader { g in left(g.size.height) }.frame(width: 560)
            stage.padding(.vertical, 16).padding(.trailing, 16)
        }
        .background(Token.ground).foregroundStyle(Token.text)
        .task(id: flow.step) {
            guard flow.step == .phone else { return }
            // What is on the Mac now is not news; only a phone newer than this moment is.
            flow.model.reload(); known = VaultModel.phoneFiles(flow.model.entries); opened = .now; arrived = nil
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                if Task.isCancelled { break }
                flow.model.reload()
                if arrived == nil { arrived = VaultModel.newPhone(flow.model.entries, known: known, since: opened) }
            }
        }
        .onAppear { if !still { withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) { t = true } } }
    }

    // left pane: label fixed at the top, main block centred, footer fixed at the bottom
    private func left(_ h: CGFloat) -> some View {
        let gap: CGFloat = h < 760 ? 20 : 32
        return VStack(alignment: .leading, spacing: 0) {
            topRow.padding(.top, 48)
            Spacer(minLength: 16)
            VStack(alignment: .leading, spacing: gap) { content(gap) }
            Spacer(minLength: 16)
            LabsLink().testFrame("setup.labs").padding(.bottom, 40)
        }
        .padding(.leading, 64).padding(.trailing, 36)
        .frame(width: 560, height: h, alignment: .topLeading)
    }

    private var hasVault: Bool { Setup.vaultPath != nil }
    private var topRow: some View {
        HStack(spacing: 0) {
            Group { if flow.step != .welcome { QuietButton(label: "Back", symbol: "chevron.left", help: nil) { flow.back() }.testFrame("setup.back") } }
                .frame(width: 76, height: 32, alignment: .leading)
            dots
            Spacer(minLength: 0)
            if hasVault {
                QuietButton(label: nil, symbol: "xmark", help: "Leave setup") { flow.finish() }.frame(width: 28, height: 28).testFrame("setup.close")
                    .background(Button("") { flow.finish() }.keyboardShortcut(.cancelAction).opacity(0).allowsHitTesting(false))
            }
        }.frame(height: 32)
    }

    private var stepNo: Int { switch flow.step { case .welcome, .where: 1; case .other: 2; default: 3 } }
    private var dots: some View {
        HStack(spacing: 8) {
            if flow.step == .phone { Text("Optional").font(.system(size: 13, weight: .semibold)).tracking(0.4).foregroundStyle(Token.quiet) }
            else {
                ForEach(1...3, id: \.self) { i in
                    Capsule().fill(i == stepNo ? panelGreen : Color(white: 0.23)).frame(width: i == stepNo ? 28 : 10, height: 10)
                        .shadow(color: i == stepNo ? mint.opacity(0.5) : .clear, radius: 6)
                }
                Text("Step \(stepNo) of 3").font(.system(size: 13, weight: .semibold)).tracking(0.4).foregroundStyle(Token.quiet).padding(.leading, 2)
            }
        }
    }

    @ViewBuilder private func content(_ gap: CGFloat) -> some View {
        let err = Color(red: 1, green: 0.62, blue: 0.55)
        switch flow.step {
        case .welcome:
            title("One life. One vault.")
            body("A vault is one folder on a computer you own.\nEverything you save sits there as plain files.")
            HStack(spacing: 16) {
                big("Set up my vault") { flow.step = .where }.testFrame("setup.begin")
                quiet("I already have a vault") { flow.pickFolder() }.testFrame("setup.have")
            }
        case .where:
            title("Where will it live?")
            VStack(alignment: .leading, spacing: 14) {
                option(0, "On this Mac", "A folder in Documents, ready now.", badge: "Recommended")
                option(1, "On another computer I own", "Stays on at home for your phone.")
                option(2, "I have a vault folder", "Pick it and we will check it.")
                if let r = flow.refusal { Text(r).font(.system(size: 14)).foregroundStyle(err).fixedSize(horizontal: false, vertical: true).testFrame("setup.refusal") }
            }
            big("Continue") { flow.cont() }.testFrame("setup.continue")
        case .other:
            title("Find your other Mac")
            VStack(alignment: .leading, spacing: 14) {
                Text(flow.looking ? "Looking on your network." : flow.candidates.isEmpty ? "No computer with Tailscale was found." : "Found near you").font(.system(size: 16, weight: .semibold)).foregroundStyle(Token.quiet)
                ForEach(flow.candidates) { c in candidate(c) }
                Text("Not listed? On that computer, open Glyph Native, choose Vault, then Share with my devices.").font(.system(size: 15)).foregroundStyle(Token.quiet).fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 16) {
                    if let c = flow.candidates.first(where: { $0.id == flow.picked }) { big("Connect to \(c.name)") { flow.connectPicked() }.testFrame("setup.connect") }
                    quiet("Use a code") { flow.codeOpen.toggle() }.testFrame("setup.code")
                }
                if flow.codeOpen {
                    HStack {
                        TextField("Address, like 100.64.0.2", text: $flow.code).textFieldStyle(.roundedBorder).frame(width: 240).onSubmit { flow.useCode() }
                        Button("Check") { flow.useCode() }
                    }
                }
                if let n = flow.codeNote { Text(n).font(.system(size: 14)).foregroundStyle(err) }
                VStack(alignment: .leading, spacing: 4) {
                    Text(flow.network).font(.system(size: 14)).foregroundStyle(Token.quiet).lineLimit(1)
                    Text(flow.tailscale).font(.system(size: 14)).foregroundStyle(Token.quiet).lineLimit(1)
                }
            }
        case .ready:
            title("Your vault is ready.")
            VStack(alignment: .leading, spacing: 10) {
                Text(flow.remoteName.map { "On \($0)" } ?? (flow.model.path.map { ($0 as NSString).abbreviatingWithTildeInPath } ?? "")).font(.system(size: 18, weight: .semibold)).foregroundStyle(Token.accentLight).lineLimit(1).truncationMode(.middle).testFrame("setup.where")
                body(proof)
            }
            HStack(spacing: 16) {
                big("Add my iPhone") { flow.step = .phone }.testFrame("setup.phone")
                quiet("Not now") { flow.finish() }.testFrame("setup.skip")
            }
        case .phone:
            title("Add my iPhone")
            if let d = arrived {
                Text("\(d.name) is connected.").font(.system(size: 22, weight: .semibold)).foregroundStyle(Token.accentLight).testFrame("setup.connected")
                Text(VaultKit.ago(d.seen, now: .now)).font(.system(size: 16)).foregroundStyle(Token.quiet)
                Button { flow.finish() } label: {
                    Text("Done").font(.system(size: 16, weight: .semibold)).foregroundStyle(Token.tintText).padding(.horizontal, 30).frame(height: 44)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Token.tint))
                }.buttonStyle(.plain).fixedSize().testFrame("setup.done")
            } else {
                VStack(alignment: .leading, spacing: gap < 32 ? 14 : 22) {
                    ForEach(Array(["Open Glyph Native on iPhone", "Tap Scan a code", "Point it at this square"].enumerated()), id: \.offset) { i, s in
                        HStack(spacing: 18) {
                            Text("\(i + 1)").font(.system(size: 20, weight: .bold)).foregroundStyle(Token.accentLight).frame(width: 44, height: 44).background(Circle().fill(Token.tint)).overlay(Circle().strokeBorder(Token.tintBorder))
                            Text(s).font(.system(size: 22, weight: .medium)).lineLimit(1)
                        }
                    }
                }
                Text("No Glyph Native on your iPhone yet? Scan anyway.").font(.system(size: 14)).foregroundStyle(Token.quiet).lineLimit(1).fixedSize()
                Rectangle().fill(Token.border).frame(height: 1)
                VStack(alignment: .leading, spacing: 14) {
                    note("house", "At home: same Wi-Fi on both.")
                    note("globe", "Away from home: turn on Tailscale on both.")
                }
                Button { flow.finish() } label: {
                    Text("Done").font(.system(size: 16, weight: .semibold)).foregroundStyle(Token.text).padding(.horizontal, 30).frame(height: 44)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Token.raised))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Token.border))
                }.buttonStyle(.plain).fixedSize().testFrame("setup.done")
            }
        }
    }

    private func body(_ s: String) -> some View {
        Text(s).font(.system(size: 18)).lineSpacing(5).foregroundStyle(Token.rowText).fixedSize(horizontal: false, vertical: true)
    }
    private func quiet(_ s: String, _ run: @escaping () -> Void) -> some View {
        Button(s, action: run).buttonStyle(.plain).font(.system(size: 16, weight: .medium)).foregroundStyle(Token.accentLight)
    }
    private func note(_ glyph: String, _ s: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: glyph).font(.system(size: 17)).foregroundStyle(Token.quiet).frame(width: 24)
            Text(s).font(.system(size: 16)).foregroundStyle(Token.quiet).lineLimit(1)
        }
    }

    private var proof: String {
        let f = DateFormatter(); f.dateFormat = "HH:mm"
        guard let at = flow.proofAt else { return "" }   // no proof ran, no sentence
        return flow.remoteName != nil ? "Connected at \(f.string(from: at))." : "We saved a test note here and read it back at \(f.string(from: at))."
    }

    private func title(_ s: String) -> some View { Text(s).font(.system(size: 44, weight: .bold)).tracking(-1.3).lineLimit(1).minimumScaleFactor(38.0 / 44.0).frame(maxWidth: .infinity, alignment: .leading) }

    private func big(_ s: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Text(s).font(.system(size: 16, weight: .semibold)).foregroundStyle(.white).padding(.horizontal, 32).frame(height: 52)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(panelGreen))
                .shadow(color: panelGreen.opacity(0.35), radius: 11, y: 8)
        }.buttonStyle(.plain).fixedSize()
    }

    private func option(_ i: Int, _ head: String, _ sub: String, badge: String? = nil) -> some View {
        let on = flow.choice == i
        return Button { flow.choice = i } label: {
            HStack(spacing: 16) {
                RoundedRectangle(cornerRadius: 12).fill(Token.ground).frame(width: 64, height: 52).overlay(optionArt(i))
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 10) {
                        Text(head).font(.system(size: 17, weight: .semibold)).lineLimit(1)
                        if let badge { Text(badge).font(.system(size: 12, weight: .semibold)).foregroundStyle(mint).padding(.horizontal, 8).padding(.vertical, 2)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color(red: 0.04, green: 0.1, blue: 0.04))).overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Token.tintBorder)) }
                    }
                    Text(sub).font(.system(size: 14.5)).foregroundStyle(Token.rowText).lineLimit(1)
                }
                Spacer(minLength: 0)
                Circle().strokeBorder(on ? Token.accentLight : Color(white: 0.23), lineWidth: 2).frame(width: 22, height: 22).overlay(Circle().fill(on ? Token.accentLight : .clear).frame(width: 8, height: 8))
            }
            .padding(.horizontal, 18).frame(minHeight: 76)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(on ? Token.tint : Token.raised))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(on ? Token.tintBorder : Token.border))
        }.buttonStyle(.plain).testFrame("setup.option\(i)")
    }

    @ViewBuilder private func optionArt(_ i: Int) -> some View {
        switch i {
        case 0: ZStack { RoundedRectangle(cornerRadius: 3).stroke(mint, lineWidth: 1.5).frame(width: 36, height: 24).offset(y: -4)
                Image(systemName: "folder.fill").font(.system(size: 13)).foregroundStyle(Color(red: 0.29, green: 0.66, blue: 0.42)).offset(y: -4) }
        case 1: ZStack { Image(systemName: "house").font(.system(size: 28)).foregroundStyle(Token.accentLight)
                Image(systemName: "wifi").font(.system(size: 11, weight: .bold)).foregroundStyle(Token.accentLight).offset(y: -18).opacity(t ? 1 : 0.35) }
        default: ZStack { Image(systemName: "folder.fill").font(.system(size: 28)).foregroundStyle(Color(red: 0.15, green: 0.32, blue: 0.18)); Image(systemName: "magnifyingglass").font(.system(size: 18, weight: .bold)).foregroundStyle(mint).offset(x: 8, y: 6) }
        }
    }

    private func candidate(_ c: SetupFlow.Candidate) -> some View {
        let on = flow.picked == c.id
        return Button { flow.picked = c.id } label: {
            HStack(spacing: 14) {
                Image(systemName: "macmini").font(.system(size: 24)).foregroundStyle(Token.accentLight).frame(width: 40)
                VStack(alignment: .leading, spacing: 3) {
                    Text(c.name).font(.system(size: 17, weight: .semibold))
                    Text(c.hasVault == nil ? "Checking" : c.hasVault == true ? "Has a vault" : "No vault yet").font(.system(size: 14)).foregroundStyle(Token.rowText)
                }
                Spacer()
                Circle().strokeBorder(on ? Token.accentLight : Color(white: 0.23), lineWidth: 2).frame(width: 22, height: 22).overlay(Circle().fill(on ? Token.accentLight : .clear).frame(width: 8, height: 8))
            }
            .padding(.horizontal, 18).frame(minHeight: 76)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(on ? Token.tint : Token.raised))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(on ? Token.tintBorder : Token.border))
        }.buttonStyle(.plain)
    }

    // right pane: the green stage and its illustration
    private var stage: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.055, green: 0.14, blue: 0.07), Color(red: 0.07, green: 0.227, blue: 0.1), Color(red: 0.047, green: 0.118, blue: 0.063)], startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [Color(red: 0.157, green: 0.59, blue: 0.275).opacity(0.42), .clear], center: .center, startRadius: 0, endRadius: 300)
            GeometryReader { g in
                let c = CGPoint(x: g.size.width / 2, y: g.size.height / 2)
                ZStack {
                    ForEach(0..<3, id: \.self) { i in
                        Circle().strokeBorder(mint.opacity(0.3 - Double(i) * 0.08), lineWidth: 1).frame(width: 300 + CGFloat(i) * 160)
                            .scaleEffect(t ? 1.03 : 0.97).opacity(t ? 0.95 : 0.3)
                    }
                    art.position(c)
                }.position(c)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Token.tintBorder))
        .accessibilityHidden(true)
    }

    private func icon(_ id: String, _ s: CGFloat) -> some View {
        Group { if let i = Bundle.main.image(forResource: "icon-\(id)") { Image(nsImage: i).resizable().scaledToFit() } else { Color.clear } }
            .frame(width: s, height: s).clipShape(RoundedRectangle(cornerRadius: s * 0.24, style: .continuous))
            .shadow(color: .black.opacity(0.4), radius: 10, y: 6).overlay(RoundedRectangle(cornerRadius: s * 0.24).strokeBorder(.white.opacity(0.08)))
    }

    private var folder: some View {
        ZStack {
            Image(systemName: "folder.fill").resizable().scaledToFit().frame(width: 250).foregroundStyle(LinearGradient(colors: [Color(red: 0.27, green: 0.69, blue: 0.38), Color(red: 0.09, green: 0.4, blue: 0.17)], startPoint: .top, endPoint: .bottom))
                .shadow(color: Color(red: 0.31, green: 0.82, blue: 0.47).opacity(0.45), radius: 24)
            icon("native", 68).offset(y: 14)
        }.offset(y: t ? -6 : 0)
    }

    @ViewBuilder private var art: some View {
        switch flow.step {
        case .welcome:
            ZStack {
                folder
                ForEach(Array(["studio", "jot", "ibis", "rig", "arena", "time", "cast"].enumerated()), id: \.offset) { i, id in
                    let a = Double(i) / 7 * 2 * .pi - .pi / 2 + (t ? 0.25 : 0)
                    icon(id, 62).offset(x: cos(a) * 250, y: sin(a) * 250)
                }
            }
        case .where:
            ZStack { folder; if flow.choice == 1 { icon("native", 44).offset(x: 150, y: -120) } }
        case .other:
            ZStack {
                ForEach(Array(flow.candidates.enumerated()), id: \.offset) { i, c in
                    let x: CGFloat = CGFloat(i) * 220 - CGFloat(flow.candidates.count - 1) * 110
                    // Path is drawn from its own corner, so it gets a frame whose middle is the stage's middle.
                    Path { p in p.move(to: CGPoint(x: 300, y: 350)); p.addLine(to: CGPoint(x: 300 + x, y: 240)) }
                        .stroke(mint.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [6, 6], dashPhase: t ? -28 : 0)).frame(width: 600, height: 600)
                    VStack(spacing: 6) { Image(systemName: "macmini").font(.system(size: 50)).foregroundStyle(mint); Text(c.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white) }.offset(x: x, y: -110)
                }
                VStack(spacing: 6) { Image(systemName: "laptopcomputer").font(.system(size: 80)).foregroundStyle(mint); Text("This Mac").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white) }.offset(y: 120)
                if flow.tailscale.contains("is on") {
                    Text("Tailscale: reachable away from home").font(.system(size: 13, weight: .semibold)).foregroundStyle(mint).padding(.horizontal, 14).padding(.vertical, 6)
                        .background(Capsule().fill(Color(red: 0.04, green: 0.1, blue: 0.04))).overlay(Capsule().strokeBorder(Token.tintBorder)).offset(y: 230)
                }
            }
        case .ready:
            ZStack { folder; Image(systemName: "checkmark.circle.fill").font(.system(size: 54)).foregroundStyle(mint).background(Circle().fill(Token.ground)).offset(x: 100, y: 70) }
        case .phone: qr
        }
    }

    private var qr: some View {
        let addr = SetupFlow.storedAddress
        let link = Onboarding.pairingLink(address: addr, name: VaultModel.macName, code: flow.pairCode)
        return VStack(spacing: 16) {
            if let link, let img = Self.qrImage(link) {
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    let gone = flow.pairExpires.map { $0 <= ctx.date } ?? false
                    VStack(spacing: 16) {
                        Image(nsImage: img).interpolation(.none).resizable().frame(width: 240, height: 240).padding(18)
                            .background(RoundedRectangle(cornerRadius: 20).fill(.white)).shadow(color: mint.opacity(0.4), radius: 28)
                            .opacity(gone ? 0.25 : 1).testFrame("setup.qr")
                        if let e = flow.pairExpires {
                            Text(Onboarding.codeLine(expires: e, now: ctx.date)).font(.system(size: 15, weight: .medium)).foregroundStyle(.white.opacity(0.9)).lineLimit(1).testFrame("setup.codeline")
                            Button { flow.newPairCode() } label: {
                                Text("Make a new code").font(.system(size: 15, weight: .semibold)).foregroundStyle(gone ? .white : mint).lineLimit(1)
                                    .padding(.horizontal, 22).frame(height: gone ? 44 : 36)
                                    .background(Capsule().fill(gone ? panelGreen : .clear)).overlay(Capsule().strokeBorder(gone ? .clear : Token.tintBorder))
                            }.buttonStyle(.plain).fixedSize().testFrame("setup.newcode")
                        }
                    }
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "iphone").font(.system(size: 54)).foregroundStyle(mint)
                    Text("This Mac is not sharing its vault with phones yet.").font(.system(size: 17, weight: .semibold)).foregroundStyle(.white).multilineTextAlignment(.center)
                    Text("Phone pairing needs a computer that serves the vault.").font(.system(size: 14)).foregroundStyle(.white.opacity(0.85)).multilineTextAlignment(.center)
                }.frame(width: 320).testFrame("setup.nocode")
            }
        }
    }

    static func qrImage(_ s: String) -> NSImage? {
        let f = CIFilter.qrCodeGenerator(); f.message = Data(s.utf8); f.correctionLevel = "M"
        guard let out = f.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)) else { return nil }
        let rep = NSCIImageRep(ciImage: out); let img = NSImage(size: rep.size); img.addRepresentation(rep); return img
    }
}

/// Borderless quiet control: grey, green on hover.
struct QuietButton: View {
    let label: String?, symbol: String, help: String?, run: () -> Void
    @State private var over = false
    var body: some View {
        Button(action: run) {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: label == nil ? 13 : 12, weight: .semibold))
                if let label { Text(label).font(.system(size: 14, weight: .medium)) }
            }
            .foregroundStyle(over ? panelGreen : Token.quiet)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: label == nil ? .center : .leading).contentShape(Rectangle())
        }
        .buttonStyle(.plain).onHover { over = $0 }.help(help ?? "")
    }
}

/// The family footer: mark, "Built by Glyph Labs", a link to the site. Used by every setup screen and About.
struct LabsLink: View {
    @State private var over = false
    var body: some View {
        Button { if let u = URL(string: "https://glyph.fru.dev") { NSWorkspace.shared.open(u) } } label: {
            HStack(spacing: 8) {
                if let i = Bundle.main.image(forResource: "icon-native") {
                    Image(nsImage: i).resizable().frame(width: 18, height: 18).clipShape(RoundedRectangle(cornerRadius: 4.3, style: .continuous))
                }
                Text("Built by Glyph Labs").font(.system(size: 12.5)).foregroundStyle(over ? panelGreen : Token.quiet)
            }
        }
        .buttonStyle(.plain).onHover { over = $0 }
    }
}
