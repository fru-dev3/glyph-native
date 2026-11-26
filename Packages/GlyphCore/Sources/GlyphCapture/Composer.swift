import SwiftUI
#if os(iOS)
import UIKit
#endif
import UniformTypeIdentifiers

/// The family's one input row, at the foot of every Glyph phone screen (Fru, 2026-11-09:
/// "standardize on one of this, right? I like the one where you have the text input, because I
/// think it's cleaner, it's more compact"). It is Glyph Jot's composer, and it replaces
/// `CaptureTrio` everywhere, including the screens where capture is the job.
///
/// One capsule with its controls inside it, not three things in a row (Fru, the same day, showing
/// ChatGPT's and Gemini's: "see how the plus button is inside of the design model... on the left
/// side is a plus button. On the right side is the microphone. And the middle is the text"): a `+`
/// on the left for whatever the screen offers to attach, the field in the middle, and a mic on the
/// right that becomes a send arrow the moment there is something to send. Both ends are filled
/// discs in the app's green, so the two buttons Fru presses most are the prominent things in the
/// bar (2026-11-09, on the white glyphs they replaced: "make it a feel green so it really stands
/// out, because it's a prominent button that I will have to click off very often. Same thing on
/// the left, and then the plus button on the right. I'd rather have it feel and prominent green").
/// Red while recording, and red means nothing else.
///
/// **The trade, stated so nobody rediscovers it:** on a capture-first screen the big mic was the
/// point, and a 34pt disc is a smaller target than the trio's 80pt one. Fru chose consistency
/// anyway.
///
/// `onSend` gets the words and whether they were spoken, so a screen that records its source
/// (Glyph Wealth logs "voice" against "typed") still can.
///
/// **One definition, and an app only ever changes what is in it** (Fru, 2026-11-09: "I hope you
/// have just one model template that you use for all the different apps... you're not changing the
/// design, you're not changing the dimensions, you're not changing it over and over again. The only
/// thing you change is the content of it... the same design, the same layout, the same pixel, the
/// same placement that just repeats throughout every single page"). An app passes its tint, its
/// placeholder and its actions. It does not pass a size, a spacing, a corner radius or a placement:
/// a parameter that would change the geometry is the signal that the template is about to fork, and
/// the answer is content instead. The one thing an app declares is how much of its own furniture
/// sits below the row, and it declares that once where it draws that furniture, through
/// `glyphComposerRoom`, not at each composer.
///
/// Accessibility identifiers: chat-attach, chat-field, chat-mic (or `micIdentifier`), chat-send,
/// and with tags handed in (`glyphComposerTags`) chat-tags, chat-tag-chip, chat-tag-clear.
public struct GlyphComposer: View {
    let tint: Color
    let placeholder: String
    /// The `+`: what this screen offers to attach (CRM's card scanner, Time's camera). The plus is
    /// always drawn, whatever an app passes: it is part of what the bar is made of, not content
    /// (Fru, 2026-11-09, having caught it missing in two apps: "the left side needs the icon
    /// there"). nil only means this screen has named no action of its own, and the plus then opens
    /// the family's own photo-or-file choice.
    let attach: (() -> Void)?
    let attachLabel: String
    /// What the mic does, when this screen's mic is not dictation: Glyph Jot's opens the recording
    /// screen, because a jot keeps its audio. nil opens the family's talk screen over live
    /// dictation, and Stop puts the words in the field: the default, and what every other screen wants. The bar is the same bar either way: an app passes its action,
    /// never a size or a second drawing of the mic.
    let mic: (() -> Void)?
    /// What a check taps to talk. The family's name is "chat-mic"; an app whose suite already taps
    /// its own ("today.talk" in Glyph Wealth) passes that instead.
    let micIdentifier: String
    /// The colour the row's own ground blends into, so a grouped page does not show a lighter band
    /// behind it. `.clear` for a composer drawn inline, inside something that already has a ground.
    let page: Color
    /// Every change to the field, for a screen that answers while the words are still being
    /// typed: Glyph Native's Apps page filters the family under the bar (Fru, 2026-11-15: "it
    /// should be search. I can type in there and chat"). nil for every other screen, which reads
    /// the words only when they are sent.
    let onEdit: ((String) -> Void)?
    let onSend: (String, Bool) async -> Void
    /// The screen's own copy of the words, for a screen that has to put words in the box: Glyph
    /// Bot's phone chat hands back a message that never reached the Mac, and words said on its home
    /// screen wait in an agent's box. nil for every other screen; the bar keeps its own.
    let text: Binding<String>?
    /// Something besides words is waiting to go (Bot's attached files): the send arrow shows with
    /// the field empty, and sends an empty sentence for the screen to fill in.
    let ready: Bool

    @State private var draft = ""
    /// This row's take, owned here rather than inside the mic, because sending has to end it and
    /// wait for the model's last words. See `send()`.
    @State private var dictation = LiveDictation()
    /// Send was pressed while the model was still writing the end of a take: the arrow waits
    /// rather than sending half a sentence.
    @State private var waiting = false
    /// The screen's own work on what was sent is still running: a hub round trip takes seconds,
    /// and without this the tap had nothing to show for itself (Fru, 2026-11-11, of Glyph Well:
    /// "when I type and hit submit it takes a long time to process and it's not obvious to me
    /// something is actually happening"). `onSend` is awaited, so the spinner lasts exactly as
    /// long as the work does and never guesses.
    @State private var working = false
    /// Waiting on the words, or on the work: either way the arrow is a spinner and does not take
    /// a second tap.
    private var busy: Bool { waiting || working }
    /// Any of what is in the field was spoken, so a screen that records its source ("voice"
    /// against "typed") is told the truth. It was always told "typed".
    @State private var spoke = false
    /// Listening: the mic stays a mic (a stop) even though the words it is writing would otherwise
    /// swap it for the send arrow.
    @State private var recording = false
    /// The family's photo-or-file choice, for a screen that named no attach action of its own.
    @State private var choosing = false
    @State private var taking = false
    /// Why the mic is not hearing anything, shown over the bar. Without it the mic is a control
    /// that can fail in silence: iOS refuses the microphone, or the speech model is still coming
    /// down, and all a tap does is nothing.
    @State private var micProblem: String?
    @FocusState private var field: Bool
    @Environment(\.glyphComposerRoom) private var room
    /// The tags this screen offers to log under, when the app handed some in. nil draws no `#`.
    @Environment(\.glyphComposerTags) private var tagging
    /// The tag sheet is up.
    @State private var picking = false
    /// What the last capture was, so a picked tag readies the same way in: the keyboard comes up
    /// after typing, and after talking it stays down so the mic is the thing in reach. The mic is
    /// never started for him: a tap on a tag is not consent to listen.
    @State private var lastSpoke = false
    @State private var focusAfterPick = false
    /// The talk screen is up (`GlyphTalkScreen`). Tucked away with the chevron, the take goes on
    /// and the bar shows it as a small live line and a red stop.
    @State private var talking = false
    /// What was in the field when this take began, and what the take last wrote there: the take's
    /// words go after the first, and a field changed since the second (sent and cleared) is left
    /// alone by the take's late words. See `DictateButton.fill`.
    @State private var before = ""
    @State private var wrote: String?

    /// The gap Fru wants above and below the composer: "All spacing must be even." It is the
    /// drawn gap, not the padding, so the paddings are set against it. Above, the scroll content
    /// already contributes about 3pt of its own, measured at 12.9pt when this padding was 10.
    nonisolated public static let air: CGFloat = 16

    /// What a finger needs, and what every control in this bar is tapped at, whatever size its
    /// disc is drawn. 44 is Apple's own minimum and the number Glyph Wealth's largest-text check
    /// has been asking for since the bar replaced the trio.
    nonisolated public static let touch: CGFloat = 44
    /// The disc as it is drawn. Smaller than the target on purpose: the bar stays compact.
    nonisolated static let disc: CGFloat = 34
    /// The `#` and the `+` inside the field: smaller and quieter than the one primary action.
    nonisolated static let small: CGFloat = 30
    /// The mic and the send arrow: the largest disc, the one thing the bar is for.
    nonisolated static let primary: CGFloat = 38

    public init(tint: Color = .officeGreen,
                placeholder: String,
                attach: (() -> Void)? = nil,
                attachLabel: String = "Attach",
                micIdentifier: String = "chat-mic",
                page: Color = .talkPage,
                mic: (() -> Void)? = nil,
                onEdit: ((String) -> Void)? = nil,
                text: Binding<String>? = nil,
                ready: Bool = false,
                onSend: @escaping @MainActor (String, Bool) async -> Void) {
        self.tint = tint; self.placeholder = placeholder
        self.attach = attach; self.attachLabel = attachLabel; self.micIdentifier = micIdentifier
        self.page = page; self.mic = mic; self.onEdit = onEdit; self.onSend = onSend
        self.text = text; self.ready = ready
    }

    #if os(iOS)
    @Environment(\.glyphDrawerOpen) private var openDrawer
    #endif

    public var body: some View {
        VStack(spacing: 6) {
            if let micProblem {
                #if os(iOS)
                // A refused microphone is the one problem a tap can fix, and iOS never asks a
                // second time, so the sentence alone was a dead end: it named a screen and left
                // the person to find it. The button goes there (Fru, 2026-11-10: "I can't use the
                // button to record, like it says setting is off. You should be, it should enable
                // that"). The app cannot grant itself the microphone; this is the nearest thing.
                if micProblem == LiveDictation.micDenied {
                    Button {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        Text("Turn on the microphone")
                            .font(.footnote.weight(.semibold)).foregroundStyle(tint)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("chat-mic-settings")
                }
                #endif
                Text(micProblem).font(.footnote.weight(.medium)).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).padding(.horizontal, 24)
                    .accessibilityIdentifier("chat-mic-problem")
            }
            if dictation.on && !talking { liveLine }
            if let tagging, let slug = tagging.chosen.wrappedValue { tagRow(slug, tagging) }
            bar
        }
        .padding(.top, GlyphComposer.air - 3).padding(.bottom, 6 + room)
        .frame(maxWidth: .infinity)
        .background(page.opacity(0.96).ignoresSafeArea())
        .sheet(isPresented: $picking, onDismiss: {
            #if os(iOS)
            if focusAfterPick { field = true }
            #endif
            focusAfterPick = false
        }) {
            if let tagging {
                GlyphTagSheet(tagging.tags, counts: tagging.counts, tint: tint, app: tagging.app) { slug in pick(slug, tagging) }
            }
        }
        #if os(iOS)
        .fullScreenCover(isPresented: Binding(get: { talking }, set: { _ in })) { talkScreen }
        #else
        .sheet(isPresented: Binding(get: { talking }, set: { _ in })) { talkScreen.frame(minWidth: 420, minHeight: 640) }
        #endif
        // The take's words go into the field as they are heard, so Stop leaves them there to read,
        // edit and send, and a tucked-away take shows them growing in the bar.
        .onChange(of: dictation.text) { _, words in
            guard dictation.on || dictation.finishing || !words.isEmpty else { return }
            guard let now = DictateButton.fill(field: draft, wrote: wrote, before: before, take: words) else { return }
            wrote = now
            draft = now
        }
        .onChange(of: dictation.on) { _, on in
            recording = on
            if on { spoke = true } else { talking = false }   // a take that ends by itself closes the screen too
        }
        .onChange(of: dictation.problem) { _, p in micProblem = p }
        // A screen holding its own copy: the two stay one, whichever side changed.
        .onChange(of: draft) { _, w in if let text, text.wrappedValue != w { text.wrappedValue = w } }
        .onChange(of: text?.wrappedValue) { _, w in if let w, w != draft { draft = w } }
        .onAppear { if let w = text?.wrappedValue, !w.isEmpty { draft = w }; dictation.selfTestIfAsked() }
    }

    /// The family's talk screen over this bar's take. The binding ignores SwiftUI's write-back, as
    /// Jot's does: it writes false on every close, and only the chevron or Stop decide.
    private var talkScreen: some View {
        GlyphTalkScreen(dictation: dictation, tint: tint, tag: tagging?.chosen.wrappedValue,
                        onMinimize: { talking = false },
                        onStop: { dictation.stop(); talking = false })
    }

    /// The mic: the talk screen, over a take of this bar's own. An app's own `mic` (Jot's
    /// recorder, which keeps the audio) is called instead.
    private func talk() {
        if let mic { return mic() }
        if dictation.on { return dictation.stop() }
        micProblem = nil
        before = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        wrote = nil
        #if os(iOS)
        field = false
        #endif
        dictation.start()
        talking = true
    }

    /// A tucked-away take, just above the bar, the way Jot's minimised recording shows: the dot,
    /// the time, the tag and the sound. A tap brings the talk screen back; the stop is the bar's
    /// own mic, red, so there is one stop on screen.
    private var liveLine: some View {
        Button { talking = true } label: {
            HStack(spacing: 10) {
                GlyphTalkDot(paused: dictation.paused, size: 9)
                GlyphTalkTimer(dictation: dictation).font(.headline)
                if dictation.paused {
                    Text("Paused").font(.subheadline).foregroundStyle(.secondary)
                } else if let slug = tagging?.chosen.wrappedValue {
                    HStack(spacing: 3) {
                        Text("#").font(.subheadline.weight(.bold)).foregroundStyle(GlyphTags.color(slug))
                        Text(GlyphTags.display(slug)).font(.subheadline).foregroundStyle(.secondary)
                    }
                    .lineLimit(1)
                }
                Spacer(minLength: 0)
                GlyphTalkLive(dictation: dictation, tint: GlyphTalkScreen.lit(tint))
                    .frame(width: 54, height: 18)
                    .opacity(dictation.paused ? 0.3 : 1)
            }
            .padding(.leading, 16).padding(.trailing, 16).padding(.vertical, 8)
            .background(.regularMaterial, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Open the talk screen")
        .accessibilityIdentifier("chat-talk-live")
        .padding(.horizontal, 16)
    }

    /// One tap on a tag in the sheet. A tag with a form of its own in the app (Glyph Well's stool
    /// scale) opens that instead; any other becomes the chip in the bar, and the next words are
    /// filed under it.
    private func pick(_ slug: String, _ tagging: GlyphComposerTags) {
        picking = false
        if tagging.form?(slug) == true { return }
        tagging.chosen.wrappedValue = slug
        focusAfterPick = !lastSpoke
    }

    /// The `#` in the bar, drawn while no tag is picked and nothing is typed yet. Once words are
    /// in the field it steps aside, so they get the room (a tag is picked before the words, and
    /// the x on the chip brings the `#` back).
    private func tagButton() -> some View {
        Button { picking = true } label: {
            // Bold and in the app's colour, on a disc the plus's size (Fru, 2026-11-22: "make the #
            // bolder with color"): it was a grey glyph that read as decoration, not as the way in.
            // Office green as the glyph's own colour was too dim on the dark bar: the glyph is white
            // and the colour is the disc and its ring, kept apart from the plus's solid disc.
            Text("#").font(.system(size: 17, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: Self.small, height: Self.small)
                .background(tint.opacity(0.42), in: Circle())
                .overlay(Circle().strokeBorder(tint, lineWidth: 1.5))
                .frame(width: Self.touch, height: Self.touch)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Log to a tag")
        .accessibilityIdentifier("chat-tags")
    }

    /// The picked tag, on its own slim row just above the bar: "Logging to #Book x". It sat in
    /// the bar until 2026-11-22, and beside the keyboard key, the plus and the send arrow it left
    /// the words a column about 90 points wide, four lines for a short sentence (pictured on Jot
    /// and Well). Above the bar, the way the best messaging apps show a reply, the field keeps the
    /// bar's whole width. Tapping the tag opens the sheet again; the x clears it.
    private func tagRow(_ slug: String, _ tagging: GlyphComposerTags) -> some View {
        HStack(spacing: 6) {
            Text("Logging to").font(.footnote).foregroundStyle(.secondary)
            Button { picking = true } label: {
                HStack(spacing: 2) {
                    Text("#").fontWeight(.bold).foregroundStyle(GlyphTags.color(slug))
                    Text(GlyphTags.display(slug)).lineLimit(1)
                }
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, 10).frame(height: 24)
                .background(Color(white: 0.22), in: Capsule())
                .frame(height: Self.touch)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Logging to \(GlyphTags.display(slug)), change the tag")
            .accessibilityIdentifier("chat-tag-chip")
            Button { tagging.chosen.wrappedValue = nil } label: {
                Image(systemName: "xmark").font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: Self.touch)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Clear the tag")
            .accessibilityIdentifier("chat-tag-clear")
        }
        // Its own small dark pill, the bar's ground, so it reads over whatever list scrolls
        // behind a composer drawn without a ground (Jot's home). Slim: the 44-point targets reach
        // past the pill's 32 points rather than adding their height to it.
        .padding(.vertical, -6)
        .padding(.leading, 14)
        .background(Color(white: 0.11), in: Capsule())
        .environment(\.colorScheme, .dark)
        .fixedSize()
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
    }

    /// The way into the drawer, at the bottom left where a thumb already is (Fru, 2026-11-14).
    ///
    /// Here and nowhere else. The tab bar carried it for a day, which put it in the bar in the
    /// apps that have one and in this row in the apps that do not -- the inconsistency Fru named:
    /// "in some cases like wealth, you have it below and then in some other ones, you don't have
    /// it there". Every app draws this composer, including the ones that reach it through
    /// `talkButton`, so this row is the one place that exists everywhere.
    ///
    /// Drawn whenever the screen has a drawer to open, and nothing otherwise. Quiet and hollow
    /// beside the filled green plus, so the two do not read alike.
    @ViewBuilder private var drawerWay: some View {
        #if os(iOS)
        if let openDrawer {
            Button(action: openDrawer) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: Self.touch, height: Self.touch)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open the drawer")
            .accessibilityIdentifier("chrome.drawer.bar")
        }
        #endif
    }

    /// A way out of the keyboard, drawn once for the family. Send is the only other key that
    /// dismisses it, and send is not what someone who typed nothing wants, so the only way out was
    /// to find a scroll view that happened to dismiss on a drag (Fru, 2026-11-11: "I struggle to
    /// make the keyboard disappear").
    ///
    /// In the bar, at its left end, where the drawer's button stands while the keyboard is down.
    /// It was a Done key in the keyboard's own toolbar until 2026-11-20: on iOS 26 that key
    /// floats over whatever is above the keys, and with the field empty it sat on the mic at the
    /// bar's right end (pictured on Glyph Well's Meds and on Glyph Jot). A control inside the bar
    /// cannot land on another one. Same identifier, so the apps' tests still find it.
    #if os(iOS)
    private var keyboardAway: some View {
        Button { field = false } label: {
            Image(systemName: "keyboard.chevron.compact.down")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: Self.touch, height: Self.touch)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Done")
        .accessibilityIdentifier("chat-keyboard-done")
    }
    #endif

    /// The plus. A screen with its own action gets a plain button; otherwise a menu: take a photo
    /// (only where there is a camera) or choose a file or photo.
    @ViewBuilder private var plus: some View {
        let disc = plusDisc
        if let attach {
            Button { attach() } label: { disc }
                .buttonStyle(.plain).accessibilityLabel(attachLabel).accessibilityIdentifier("chat-attach")
        } else {
            #if os(iOS)
            Menu {
                if CameraPicker.isAvailable { Button("Take a photo", systemImage: "camera") { taking = true } }
                Button("Choose a photo", systemImage: "photo") { choosing = true }
            } label: { disc }
                .buttonStyle(.plain).accessibilityLabel("Attach a photo or a file").accessibilityIdentifier("chat-attach")
            #else
            Button { choosing = true } label: { disc }
                .buttonStyle(.plain).accessibilityLabel("Attach a photo or a file").accessibilityIdentifier("chat-attach")
            #endif
        }
    }

    private var plusDisc: some View {
        // The `#`'s disc, so the two that qualify the capture read as one pair inside the field.
        Image(systemName: "plus").font(.system(size: 15, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: Self.small, height: Self.small)
            .background(tint.opacity(0.42), in: Circle())
            .overlay(Circle().strokeBorder(tint, lineWidth: 1.5))
            .frame(width: Self.touch, height: Self.touch)
            .contentShape(Circle())
    }

    /// The bar itself, in three groups (Fru, 2026-11-22: "I want the # to the right. And really think
    /// hard of spacing and alignment or grouping", then "Move the plus to the left side. Only
    /// microphone and # to the right"): the way to the app's places at the left; the field, with
    /// the `+` at its left end and the `#` at its right end, both on the same smaller disc because
    /// they qualify what is captured; and the one primary action at the right, the mic or the send
    /// arrow, the largest disc in the bar. The `#` steps aside once words are typed, so they get
    /// the room. Everything sits on the bottom line, so a field grown
    /// to five lines keeps the controls where the thumb left them.
    private var bar: some View {
        let empty = draft.trimmingCharacters(in: .whitespaces).isEmpty
        return HStack(alignment: .bottom, spacing: 6) {
            // With the keyboard up the drawer's place is the way out of the keyboard; see `keyboardAway`.
            #if os(iOS)
            if field { keyboardAway } else if !recording { drawerWay }
            #else
            if !recording { drawerWay }
            #endif
            HStack(alignment: .bottom, spacing: 0) {
                // The plus at the field's left end, the way into it from the side the words start on
                // (Fru, 2026-11-22: "Move the plus to the left side. Only microphone and # to the right").
                // It stays while words are typed, so starting to type never moves the words.
                if !recording { plus }
                TextField("", text: $draft, prompt: Text(tagging == nil ? placeholder : "Say it").foregroundStyle(.secondary), axis: .vertical)
                    .font(.system(size: 16))
                    .lineLimit(1...5)
                    .textFieldStyle(.plain)
                    .focused($field).submitLabel(.send)
                    .onSubmit { send() }
                    .onChange(of: draft) { _, words in onEdit?(words) }
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("chat-field")
                if !recording, empty, tagging != nil, tagging?.chosen.wrappedValue == nil { tagButton() }
            }
            .padding(.leading, recording ? 16 : 2).padding(.trailing, 2)
            .background(Color(white: 0.17), in: RoundedRectangle(cornerRadius: Self.touch / 2, style: .continuous))
            if (empty && !ready) || recording {
                // The mic sits in the bar, not on a disc beside it. No second, round voice button:
                // Fru has no realtime mode, so there is nothing for it to open.
                //
                // It writes into the field as it hears, rather than sending what it heard (Fru,
                // 2026-11-09: "a transcription of the text I'm recording being put into the text
                // input form... And then when I stop, you put it into the text box. And then I can
                // record and add some more, maybe make some changes before submitting"). So the
                // words stay, and nothing leaves until the send arrow is pressed. Since 2026-11-22
                // the mic opens the family's talk screen (`GlyphTalkScreen`, Jot's recording
                // screen) and Stop leaves the words here; the pause and the waveform that sat in
                // the bar are on that screen. Tucked away, the take shows above the bar and this
                // mic is its red stop, with the `+` stepped aside.
                micButton
            } else {
                Button { send() } label: {
                    ZStack {
                        Circle().fill(tint).frame(width: Self.primary, height: Self.primary)
                        // Waiting on the last words of a take. The tap has to show that it landed,
                        // or the wait reads as the dead button it is meant to fix.
                        if busy {
                            ProgressView().controlSize(.small).tint(.white)
                        } else {
                            Image(systemName: "arrow.up").font(.system(size: 17, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(width: Self.touch, height: Self.touch)
                    .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(busy)
                .accessibilityLabel("Send")
                .accessibilityIdentifier("chat-send")
            }
        }
        .padding(6)
        .background(Color(white: 0.11), in: RoundedRectangle(cornerRadius: Self.touch / 2 + 6, style: .continuous))
        // The bar is dark in both themes, but everything in it asks for a semantic colour, and in
        // light mode `.secondary` is a dark grey: the placeholder and the hamburger came out at
        // about 3:1 on near-black (Fru, 2026-11-18, of the family's phone screens). Saying the bar
        // is dark makes every one of them resolve light-on-dark, with no colour written by hand.
        .environment(\.colorScheme, .dark)
        .padding(.horizontal, 16)
        // One choice, defined here and nowhere else, for every screen that named no action of its
        // own. What comes back is the file's path, sent the way a typed sentence is sent: these
        // screens all hand `onSend` to an agent that reads the vault by path.
        // ponytail: a path as the sentence is the smallest honest wiring. A screen that wants a
        // photo understood rather than referenced passes its own `attach` (CRM's scanner, Time's
        // camera) and never reaches this.
        #if os(iOS)
        // A photo taken is saved as a file and its path sent, exactly as a chosen file is.
        .fullScreenCover(isPresented: $taking) {
            CameraPicker { image, _ in
                taking = false
                guard let data = image?.jpegData(compressionQuality: 0.9) else { return }
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("photo-\(UUID().uuidString.prefix(8)).jpg")
                guard (try? data.write(to: url)) != nil else { return }
                Task { @MainActor in working = true; await onSend(url.path, false); working = false }
            }.ignoresSafeArea()
        }
        #endif
        .fileImporter(isPresented: $choosing, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result, !urls.isEmpty else { return }
            let words = urls.map(\.path).joined(separator: "\n")
            Task { @MainActor in working = true; await onSend(words, false); working = false }
        }
    }

    /// The mic disc, a red stop while a take runs (tucked away, since the talk screen covers the
    /// bar otherwise). Drawn at 38 and tapped at 44. The waveform and the pause it used to carry in
    /// the bar are the talk screen's now: one way to talk, in every app (Fru, 2026-11-22).
    private var micButton: some View {
        let on = dictation.on
        return Button { talk() } label: {
            Image(systemName: on ? "stop.fill" : "mic.fill")
                .font(.system(size: Self.primary * 0.47, weight: .semibold)).foregroundStyle(.white)
                .frame(width: Self.primary, height: Self.primary)
                // Red is a running recording and nothing else, which is what this is.
                .background(on ? Color(red: 0.898, green: 0.282, blue: 0.302) : tint, in: Circle())
                .frame(width: Self.touch, height: Self.touch)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(on ? "Stop talking" : mic != nil ? "Record" : "Talk instead of typing")
        .accessibilityIdentifier(micIdentifier)
    }

    /// Sending ends the take and waits for the words that have not arrived yet.
    ///
    /// Stopping the microphone does not stop the model: it goes on turning the last seconds into
    /// text for a moment afterwards (`finishing`), and those words land in the field when they
    /// come. Sending into that gap did two wrong things at once: it sent without the tail, and the
    /// arriving words then refilled the field, so the submit looked as though it had not happened
    /// and the next tap logged the same thing a second time (Fru, 2026-11-10: "When I record here
    /// and I hit submit, it's not actually submitting correctly. I have to do it 2 or 3 times...
    /// we have to make sure it submits so I'm not losing my content"). One tap, the whole
    /// sentence, once.
    private func send() {
        if dictation.on { dictation.stop() }
        guard dictation.finishing else { return deliver() }
        waiting = true
        Task { @MainActor in
            // Bounded: a model that never finishes must not keep his words.
            let deadline = ContinuousClock.now + .seconds(3)
            while dictation.finishing, ContinuousClock.now < deadline {
                try? await Task.sleep(for: .milliseconds(40))
            }
            guard waiting else { return }
            waiting = false
            deliver()
        }
    }

    /// The field empties the moment the words leave it, so nothing is typed twice, and the arrow
    /// stays a spinner until the screen's own work on them is done.
    private func deliver() {
        let w = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let said = spoke
        draft = ""
        spoke = false
        guard !w.isEmpty || ready else { return }
        lastSpoke = said
        working = true
        let tag = tagging?.chosen
        let was = tag?.wrappedValue
        Task { @MainActor in
            await onSend(w, said)
            working = false
            // A pick is for one capture: the chip goes once its words are filed, so the next
            // thing said is not quietly filed under a tag he chose for something else.
            if let tag, was != nil, tag.wrappedValue == was { tag.wrappedValue = nil }
        }
    }
}

public extension Color {
    /// #008000, the brand's office green, in both appearances. The artboards draw it on black.
    static let officeGreen = Color(red: 0, green: 128 / 255, blue: 0)

    /// #2eae2e: the office green lifted enough to read as green type on black.
    ///
    /// One value, because it was seven. The same brand green was being brightened by hand in each
    /// app and arrived at (0.16, 0.66, 0.16), (0.18, 0.68, 0.18), (0.2, 0.72, 0.2),
    /// (0.3, 0.8, 0.3), (0.1, 0.68, 0.14), (0.2, 0.85, 0.4) and #3FA34D -- seven greens for one
    /// colour, which is exactly what a person notices moving between two of the apps. The shared
    /// token was the #3FA34D one and it sat inside a macOS-only file, so no iPhone screen could
    /// reach it. #2eae2e wins because it keeps the brand's hue: #008000 is a pure green, and
    /// #3FA34D is a desaturated one.
    ///
    /// It is a lift for TYPE, not a ground: white on #2eae2e falls to about 3:1 where white on
    /// #008000 holds about 5.2:1, so anything with white on it uses `officeGreen` at both
    /// appearances (see `omegaPicked`).
    static let officeGreenLit = Color(red: 0.18, green: 0.68, blue: 0.18)

    /// The brand green that reads at both appearances: #008000 on white, #2eae2e on black. The one
    /// the apps should ask for when they want "our green" as type or as a line.
    static let glyphGreen: Color = {
        #if os(iOS)
        return Color(UIColor { $0.userInterfaceStyle == .dark
            ? UIColor(red: 0.18, green: 0.68, blue: 0.18, alpha: 1)
            : UIColor(red: 0, green: 128 / 255, blue: 0, alpha: 1) })
        #elseif os(macOS)
        return Color(NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(red: 0.18, green: 0.68, blue: 0.18, alpha: 1)
            : NSColor(red: 0, green: 128 / 255, blue: 0, alpha: 1) })
        #else
        return .officeGreen
        #endif
    }()

    /// The family's warm colour: the one thing on a screen that means "not safe yet", such as
    /// entries that have not reached the vault. Each app had its own amber for this; this is the
    /// one the shared furniture uses.
    static let glyphWarm = Color(red: 0.85, green: 0.58, blue: 0.16)
}

/// How much of an app's own furniture sits below the composer, such as Glyph CRM's footer bar. An
/// app sets this once, where it draws that furniture, and every composer under it leaves the room.
/// It is here rather than on `GlyphComposer` so no screen passes the template a dimension.
///
/// Two safe-area insets on views a NavigationStack apart do not compose: an inset set out at the
/// root never reaches the list, which is how the footer came to draw over the composer. The
/// composer reserves the room, and the app's bar is laid into what it left.
/// The tags a screen's composer offers, handed in once where the screen draws its composer, as
/// the room below it is (Fru, 2026-11-21: "As soon as I'm on the app, one button, see the tags,
/// pick my tag, and begin logging"). With these the bar carries a `#` beside the field; without
/// them it is the bar it always was, so no app that says nothing changes.
///
/// ```swift
/// NavigationStack { Home() }
///     .talkButton { words in await save(words, tag: chosen) }   // reads `chosen` as it sends
///     .glyphComposerTags(GlyphComposerTags(tags, counts: counts, chosen: $chosen))
/// ```
///
/// The app keeps the chosen tag (a slug) and reads it in its own `onSend`, so what is said goes
/// through the app's own save path with the tag on it. The composer clears it once those words
/// are sent. `form` is a tag the app has a form for: return true when it opened one, and no chip
/// is drawn.
public struct GlyphComposerTags {
    /// The app's tags, by slug or by name. The sheet puts the most used first.
    public let tags: [String]
    /// How many things carry each, keyed as `tags` is.
    public let counts: [String: Int]
    public let chosen: Binding<String?>
    public let form: ((String) -> Bool)?
    /// The family id a tag made from the sheet is shown in; read off the bundle when nil.
    public let app: String?
    public init(_ tags: [String], counts: [String: Int] = [:], chosen: Binding<String?>, app: String? = nil,
                form: ((String) -> Bool)? = nil) {
        self.tags = tags; self.counts = counts; self.chosen = chosen; self.app = app; self.form = form
    }
}

public struct GlyphComposerTagsKey: EnvironmentKey {
    // Made and read on the main actor, as every view body is; see GlyphDrawerOpenKey.
    nonisolated(unsafe) public static let defaultValue: GlyphComposerTags? = nil
}

public extension View {
    /// The tags every composer under this view offers. See `GlyphComposerTags`.
    func glyphComposerTags(_ tags: GlyphComposerTags?) -> some View { environment(\.glyphComposerTags, tags) }
}

public struct GlyphComposerRoom: EnvironmentKey {
    public static let defaultValue: CGFloat = 0
}

public extension EnvironmentValues {
    var glyphComposerRoom: CGFloat {
        get { self[GlyphComposerRoom.self] }
        set { self[GlyphComposerRoom.self] = newValue }
    }
    var glyphComposerTags: GlyphComposerTags? {
        get { self[GlyphComposerTagsKey.self] }
        set { self[GlyphComposerTagsKey.self] = newValue }
    }
}
