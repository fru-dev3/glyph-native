import SwiftUI

/// The whole screen while you talk, the same in every Glyph app: Glyph Jot's recording screen,
/// drawn once (Fru, 2026-11-22, showing Jot's: "why isn't the composer for all the apps consistent
/// like this when talking with audio the way it's in jot. i'm really striving for consistency").
///
/// At the top a chevron that tucks it away, a red dot, the time and the word count; the words
/// large, the settled ones in full ink and the ones still being heard in grey; the live microphone
/// as a waveform in the app's colour; Pause and Stop with their names under them. The numbers are
/// Jot's (`Jot/Recording.swift`), so the two screens are the same screen; change them in both or
/// in neither. System sans, as Jot's own `.reading` is.
///
/// It drives the `LiveDictation` it is given and keeps no recorder of its own: the composer opens
/// it from its mic, and Stop puts the words in the composer's field, where nothing leaves until
/// send (Fru, 2026-11-09).
///
/// Identifiers: talk.screen, talk.minimize, talk.time, talk.count, talk.tag, talk.words,
/// talk.waveform, glyph.pause, talk.stop.
public struct GlyphTalkScreen: View {
    let dictation: LiveDictation
    let tint: Color
    /// The tag these words will be filed under, a slug, shown at the top as Jot shows its tags.
    let tag: String?
    let onMinimize: () -> Void
    let onStop: () -> Void
    @State private var levels: [Double] = Array(repeating: 0, count: 48)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(dictation: LiveDictation, tint: Color = .glyphGreen, tag: String? = nil,
                onMinimize: @escaping () -> Void, onStop: @escaping () -> Void) {
        self.dictation = dictation; self.tint = Self.lit(tint); self.tag = tag
        self.onMinimize = onMinimize; self.onStop = onStop
    }

    private var words: Int { dictation.text.split(whereSeparator: \.isWhitespace).count }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button(action: onMinimize) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(tint)
                        .frame(width: 40, height: 40)
                        .background(Self.fill, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Minimize")
                .accessibilityIdentifier("talk.minimize")
                GlyphTalkDot(paused: dictation.paused, size: 10)
                GlyphTalkTimer(dictation: dictation).accessibilityIdentifier("talk.time")
                Spacer()
                Text("\(words) words").foregroundStyle(.secondary).accessibilityIdentifier("talk.count")
            }
            .font(.title3.weight(.semibold))
            .padding(.horizontal, 20)
            .padding(.top, 12)

            // Jot's two chips: that the words are written as you talk, and where they are going.
            HStack(spacing: 8) {
                GlyphTalkChip(text: "Writing as you talk", lit: true)
                if let tag {
                    GlyphTalkChip(text: GlyphTags.display(tag), hash: GlyphTags.color(tag))
                        .accessibilityLabel("Logging to \(GlyphTags.display(tag))")
                        .accessibilityIdentifier("talk.tag")
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 8)

            ScrollView {
                Text("\(dictation.settled)\(Text(dictation.pending).foregroundStyle(.secondary))")
                    .font(.system(.title))
                    .lineSpacing(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 28)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: dictation.text)
                    .accessibilityIdentifier("talk.words")
            }
            .defaultScrollAnchor(.top, for: .alignment)
            .defaultScrollAnchor(.bottom, for: .sizeChanges)
            .overlay {
                if dictation.text.isEmpty {
                    Text(dictation.paused ? "Paused" : "Listening…").font(.system(.title)).foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center).padding(.horizontal, 32)
                }
            }

            if let problem = dictation.problem {
                Label(problem, systemImage: "exclamationmark.circle").font(.footnote.weight(.medium))
                    .foregroundStyle(.primary).padding(.horizontal)
            }

            GlyphTalkWave(levels: levels, tint: tint, still: reduceMotion)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Sound level")
                .accessibilityIdentifier("talk.waveform")
                .frame(height: 56)
                .opacity(dictation.paused ? 0.3 : 1)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)

            // Buttons centred on one line, their names on the next, so both line up (Jot's grid).
            Grid(horizontalSpacing: 36, verticalSpacing: 10) {
                GridRow(alignment: .center) {
                    Button { dictation.paused ? dictation.resume() : dictation.pause() } label: {
                        Image(systemName: dictation.paused ? "play.fill" : "pause.fill")
                            .font(.system(size: 24, weight: .semibold))
                            .frame(width: 64, height: 64)
                            .background(Self.fill, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(dictation.paused ? "Resume" : "Pause")
                    .accessibilityIdentifier("glyph.pause")
                    Button(action: onStop) {
                        ZStack {
                            Circle().fill(Color.red.opacity(0.14)).frame(width: 104, height: 104)
                            Circle().fill(Color.red).frame(width: 80, height: 80)
                            RoundedRectangle(cornerRadius: 7).fill(.white).frame(width: 28, height: 28)
                        }
                    }
                    .buttonStyle(.plain)
                    .sensoryFeedback(.impact(weight: .medium), trigger: dictation.on)
                    .accessibilityLabel("Stop")
                    .accessibilityIdentifier("talk.stop")
                    Color.clear.frame(width: 64, height: 64) // keeps Stop centred
                }
                GridRow {
                    Text(dictation.paused ? "Resume" : "Pause")
                    Text("Stop")
                    Color.clear.frame(width: 1, height: 1)
                }
                .font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                .accessibilityHidden(true)
            }
            .padding(.bottom, 8)
        }
        .tint(tint)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("talk.screen")
        .onChange(of: dictation.level) { _, l in
            levels.removeFirst()
            levels.append(max(0, min(1, l)))
        }
    }

    /// The brand green as a colour to draw lines in: #008000 is a ground for white type and goes
    /// dim as bars on black, so the family's default tint is drawn as Jot's own `glyphGreen`
    /// (#2eae2e on black, #008000 on white). Any other tint is the app's, as given.
    static func lit(_ tint: Color) -> Color { tint == .officeGreen ? .glyphGreen : tint }

    /// Jot's `secondarySystemFill`, on both platforms.
    static var fill: Color {
        #if os(iOS)
        Color(uiColor: .secondarySystemFill)
        #else
        Color.primary.opacity(0.1)
        #endif
    }
}

/// The recording dot: red while listening (pulsing, unless Reduce Motion), orange while paused.
struct GlyphTalkDot: View {
    let paused: Bool
    let size: CGFloat
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        Circle().fill(paused ? .orange : .red).frame(width: size, height: size)
            .opacity(pulse && !paused && !reduceMotion ? 0.25 : 1)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.8).repeatForever(), value: pulse)
            .onAppear { pulse = true }
            .accessibilityHidden(true)
    }
}

/// The listening time, standing still while paused (Jot's `RecorderTimer`).
struct GlyphTalkTimer: View {
    let dictation: LiveDictation
    var body: some View {
        if let start = dictation.startedAt {
            Text(timerInterval: start...Date.distantFuture, pauseTime: dictation.pausedAt, countsDown: false)
                .monospacedDigit()
        } else {
            Text("0:00").monospacedDigit()
        }
    }
}

/// Jot's waveform: 48 bars, the newest at the right and the strongest colour.
struct GlyphTalkWave: View {
    let levels: [Double]
    let tint: Color
    var still = false
    /// The height of a bar at full level: 56 on the screen, as Jot's.
    var scale: CGFloat = 56
    var body: some View {
        HStack(alignment: .center, spacing: scale < 30 ? 2 : 3) {
            ForEach(levels.indices, id: \.self) { i in
                Capsule()
                    .fill(tint.opacity(0.35 + 0.65 * Double(i) / Double(levels.count)))
                    .frame(maxWidth: .infinity)
                    .frame(height: max(scale < 30 ? 2 : 4, levels[i] * scale))
            }
        }
        .frame(maxHeight: .infinity)
        .animation(still ? nil : .linear(duration: 0.08), value: levels)
    }
}

/// Jot's state chip: 42 tall, #1c1c1e with a #2c2c2e hairline, and #10240f on #27512f when lit.
/// It states something true right now, which is why it is not a button.
struct GlyphTalkChip: View {
    let text: String
    var lit = false
    var hash: Color? = nil
    var body: some View {
        HStack(spacing: 7) {
            if let hash { Text("#").font(.system(size: 15.5, weight: .bold)).foregroundStyle(hash) }
            Text(text).font(.system(size: 14.5)).lineLimit(1)
        }
        .foregroundStyle(lit ? Color(red: 0x7f / 255, green: 0xd4 / 255, blue: 0x9a / 255)
                             : Color(red: 0xe6 / 255, green: 0xe6 / 255, blue: 0xea / 255))
        .padding(.horizontal, 16)
        .frame(height: 42)
        .background(lit ? Color(red: 0x10 / 255, green: 0x24 / 255, blue: 0x0f / 255)
                        : Color(red: 0x1c / 255, green: 0x1c / 255, blue: 0x1e / 255),
                    in: RoundedRectangle(cornerRadius: 21, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 21, style: .continuous)
                .strokeBorder(lit ? Color(red: 0x27 / 255, green: 0x51 / 255, blue: 0x2f / 255)
                                  : Color(red: 0x2c / 255, green: 0x2c / 255, blue: 0x2e / 255), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The small waveform of a tucked-away take, from the live microphone level.
struct GlyphTalkLive: View {
    let dictation: LiveDictation
    let tint: Color
    @State private var levels: [Double] = Array(repeating: 0, count: 14)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        GlyphTalkWave(levels: levels, tint: tint, still: reduceMotion, scale: 18)
            .accessibilityHidden(true)
            .onChange(of: dictation.level) { _, l in
                levels.removeFirst()
                levels.append(max(0, min(1, l)))
            }
    }
}
