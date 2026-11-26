import GlyphCapture
import SwiftUI
#if os(macOS)
import AppKit
#endif

/// The renderer's demo: A2UI_FIXTURE=<name> picks one of the five (A2UIFixtures.all), else all of them.
/// On the Mac, A2UI_SHOTS=<dir> pictures each in turn and quits.
@main
struct A2UIDemoApp: App {
    var body: some Scene {
        WindowGroup { Demo() }
        #if os(macOS)
            .windowResizability(.contentSize)
        #endif
    }
}

/// What was said before each screen, invented, so the iPhone shows the screen in a chat turn as an app would.
let turns: [String: (said: String, reply: String, ask: Bool)] = [
    "time-picker": ("Remind me to call Ken this afternoon", "When this afternoon?", true),
    "place": ("Where was that coffee place by the lake?", "Lakeside Coffee, on Harbor Street. Open until 6 today.", false),
    "renewals": ("What renews this week?", "Three things renew this week, $469 in all.", false),
    "spending": ("How is grocery spending going?", "$110 last week, the most in six weeks, still under your $120.", false),
    "todos": ("Pick up rice, call the dentist tomorrow at nine and renew the car tabs by Friday", "Add these three?", true),
]

@MainActor
struct Demo: View {
    let env = ProcessInfo.processInfo.environment
    var names: [String] { env["A2UI_FIXTURE"].map { [$0] } ?? A2UIFixtures.all.map(\.name) }
    @State private var shown: String?

    #if os(iOS)
    @State private var model = ChatModel(app: "demo") { said, _ in [.answer("You said: \(said)")] }

    var body: some View {
        GlyphChat(model: model, face: nil, tint: .officeGreen, agent: "demo", name: "Demo", title: "A2UI", placeholder: "Ask anything")
            .preferredColorScheme(.dark)
            .task {
                model.onAction = { a, _ in
                    let ctx = a.context.keys.sorted().joined(separator: ", ")
                    return [ChatEntry(text: "Sent \(a.name)" + (ctx.isEmpty ? "" : " with \(ctx)"), done: true)]
                }
                guard model.entries.isEmpty else { return }
                for n in names {
                    guard let f = A2UIFixtures.all.first(where: { $0.name == n }), let t = turns[n] else { continue }
                    let stream = A2UIStream(jsonl: f.jsonl)
                    for s in stream.surfaces { await A2UIMap.prepare(s) }
                    var line = t.ask ? ChatEntry.ask(t.reply) : ChatEntry.answer(t.reply, who: "claude")
                    line.surfaces = stream.surfaces
                    model.entries += [ChatEntry(mine: true, text: t.said), line]
                    for s in stream.surfaces { sent(s) }
                }
            }
    }
    #endif

    /// A2UI_SENT=sending|answered|failed: the screen's primary button as if tapped, for a picture of its sent state.
    func sent(_ s: A2UISurface) {
        guard let how = env["A2UI_SENT"],
              let b = s.components.values.first(where: { $0.type == "Button" && $0["variant"]?.string == "primary" }),
              s.send(from: A2UISurface.key(b.id)) else { return }
        if how == "answered" { s.answered("Added in Travel: Lakeside Coffee") } else if how == "failed" { s.answered(nil, failed: true) }
    }

    #if os(macOS)
    @State private var streams: [(String, A2UIStream)] = []
    @State private var last = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(streams.filter { shown == nil || $0.0 == shown }, id: \.0) { _, stream in
                ForEach(stream.surfaces) { s in A2UISurfaceView(surface: s) { last = "Sent \($0.name)"; s.answered(last) } }
            }
            if !last.isEmpty { Text(last).font(.footnote).foregroundStyle(.secondary) }
        }
        .padding(20)
        .frame(width: 440, height: 640, alignment: .top)   // tall enough for the tallest fixture; the window does not follow content
        .background(Color.black)
        .preferredColorScheme(.dark)
        .task {
            streams = A2UIFixtures.all.filter { names.contains($0.name) }.map { ($0.name, A2UIStream(jsonl: $0.jsonl)) }
            for (_, st) in streams { for s in st.surfaces { await A2UIMap.prepare(s); sent(s) } }
            guard let dir = env["A2UI_SHOTS"] else { return }
            for n in names {
                shown = n
                try? await Task.sleep(for: .seconds(0.6))
                if let w = NSApp.windows.first(where: \.isVisible), let v = w.contentView { w.setContentSize(v.fittingSize) }
                try? await Task.sleep(for: .seconds(0.8))
                shot(URL(fileURLWithPath: dir).appending(path: "mac-\(n).png"))
            }
            NSApp.terminate(nil)
        }
    }

    /// The window as the window server draws it (as Glyph Life's check does), else the content view into a bitmap.
    func shot(_ url: URL) {
        guard let w = NSApp.windows.first(where: \.isVisible) else { return }
        if let v = w.contentView { w.setContentSize(v.fittingSize); v.layoutSubtreeIfNeeded() }   // the window fits this screen
        typealias Grab = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
        if let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage"),
           let image = unsafeBitCast(sym, to: Grab.self)(.null, 1 << 3, UInt32(w.windowNumber), 1 << 0 | 1 << 3)?.takeRetainedValue() {
            try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: url)
            return
        }
        guard let v = w.contentView, let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { return }
        v.cacheDisplay(in: v.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
    #endif
}
