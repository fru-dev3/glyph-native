import Charts
import GlyphAI
import MapKit
import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// One A2UI surface, drawn in the family's look: the composer's dark ground (it is dark under a light system
/// too, as the composer is), the app's tint on what you press, system sans. Drop it into a chat turn:
///
/// ```swift
/// A2UISurfaceView(surface: s) { action in Task { await model.act(action) } }
/// ```
///
/// A part the catalog does not have draws nothing (logged once when it arrives); a child that has not
/// arrived yet draws as a quiet placeholder. Accessibility identifiers: `a2ui-<surfaceId>` on the surface,
/// `a2ui-<componentId>` on each part.
public struct A2UISurfaceView: View {
    let surface: A2UISurface
    let tint: Color
    let onAction: (A2UIAction) -> Void

    public init(surface: A2UISurface, tint: Color = .officeGreen, onAction: @escaping (A2UIAction) -> Void) {
        self.surface = surface; self.tint = tint; self.onAction = onAction
    }

    public var body: some View {
        A2UINode(id: "root", scope: "", depth: 0, ctx: A2UIContext(surface: surface, tint: tint, onAction: onAction))
            .frame(maxWidth: .infinity, alignment: .leading)
            .tint(tint)
            .environment(\.colorScheme, .dark)
            // `.contain`, here and on every part that holds others: an identifier on a plain container is
            // handed down to its children and replaces theirs, so every button read as "a2ui-<surface>" and a
            // check could not find "a2ui-save" (found adopting it in Glyph X, 2026-11-22).
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("a2ui-\(surface.id)")
    }
}

struct A2UIContext {
    let surface: A2UISurface
    let tint: Color
    let onAction: (A2UIAction) -> Void
}

/// The family's dark tokens, as the composer and the tag chips draw them.
enum A2UIStyle {
    static let ground = Color(white: 0.11)       // the composer's bar, `glyphDisc`
    static let raised = Color(white: 0.17)       // the composer's field
    static let chip = Color(red: 0x1c / 255, green: 0x1c / 255, blue: 0x1e / 255)
    static let edge = Color(red: 0x2c / 255, green: 0x2c / 255, blue: 0x2e / 255)
    static let text = Color(red: 0xe6 / 255, green: 0xe6 / 255, blue: 0xea / 255)
    static let quiet = Color(red: 0x8e / 255, green: 0x8e / 255, blue: 0x93 / 255)
}

/// One component by id, in a scope (a template's item, for relative bindings).
struct A2UINode: View {
    let id: String
    let scope: String
    let depth: Int
    let ctx: A2UIContext
    @Environment(\.openURL) private var openURL

    private var s: A2UISurface { ctx.surface }
    /// The parts that hold other controls, so their identifier must not replace their children's.
    static let holders: Set<String> = ["Card", "Column", "Row", "List", "Place", "DayStrip", "ChoicePicker"]

    var body: some View {
        if depth > 40 {
            EmptyView()     // a cycle in the tree: stop rather than recurse forever
        } else if let c = s.components[id] {
            if A2UINode.holders.contains(c.type) {
                part(c).accessibilityElement(children: .contain).accessibilityIdentifier("a2ui-\(c.id)")
            } else {
                part(c).accessibilityIdentifier("a2ui-\(c.id)")
            }
        } else {
            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(A2UIStyle.raised)
                .frame(maxWidth: .infinity).frame(height: 18)
                .accessibilityLabel("Loading").accessibilityIdentifier("a2ui-pending")
        }
    }

    // MARK: Values

    private func v(_ c: A2UIComponent, _ k: String) -> JSONValue? { s.resolve(c[k], scope: scope) }
    private func str(_ c: A2UIComponent, _ k: String) -> String? {
        guard let x = v(c, k) else { return nil }
        if let t = x.string { return t }
        if let n = x.number { return n == n.rounded() ? String(Int(n)) : String(n) }
        return nil
    }
    private func num(_ c: A2UIComponent, _ k: String) -> Double? { v(c, k)?.number }
    private func flag(_ c: A2UIComponent, _ k: String) -> Bool { v(c, k)?.bool ?? false }

    private func child(_ cid: String?, _ sc: String? = nil) -> A2UINode? {
        cid.map { A2UINode(id: $0, scope: sc ?? scope, depth: depth + 1, ctx: ctx) }
    }

    /// `children`: a list of ids, or a template `{path, componentId}` repeated once per item of the array there.
    private func children(_ c: A2UIComponent) -> [(key: String, node: A2UINode)] {
        if let ids = c["children"]?.array {
            return ids.compactMap(\.string).enumerated().map { ("\($0.offset)-\($0.element)", child($0.element)!) }
        }
        if let t = c["children"]?.object, let path = t["path"]?.string, let tpl = t["componentId"]?.string {
            let base = A2UISurface.absolute(path, scope: scope)
            let n = s.value(at: base)?.array?.count ?? 0
            return (0..<n).map { i in ("\(base)/\(i)", child(tpl, base + "/\(i)")!) }
        }
        return []
    }

    private func fire(_ c: A2UIComponent, _ key: String = "action", userMessage: String? = nil) {
        let a = c[key]
        if let call = a?.object?["functionCall"]?.object, call["@call"]?.string == "openUrl",
           let u = s.resolve(call["args"]?.object?["url"], scope: scope)?.string, let url = URL(string: u) {
            openURL(url); return
        }
        // One send per surface at a time, and none twice from the same part once answered: a second tap is dropped
        // here, before it can write (A2UISurface.send).
        guard let act = s.action(a, source: c.id, scope: scope, userMessage: userMessage),
              s.send(from: A2UISurface.key(c.id, scope: scope)) else { return }
        ctx.onAction(act)
    }

    private func write(_ c: A2UIComponent, _ k: String, _ value: JSONValue) {
        if let p = s.binding(c[k], scope: scope) { s.set(value, at: p) }
    }

    // MARK: Parts

    @ViewBuilder private func part(_ c: A2UIComponent) -> some View {
        switch c.type {
        case "Text": text(c)
        case "Image": image(c)
        case "Icon": Image(systemName: Self.symbol(str(c, "name") ?? "")).foregroundStyle(A2UIStyle.text)
        case "Row": row(c)
        case "Column": column(c)
        case "List": list(c)
        case "Card":
            VStack(alignment: .leading, spacing: 0) { child(c["child"]?.string) }
                .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .background(A2UIStyle.ground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color.white.opacity(0.06)) }
        case "Divider":
            if str(c, "axis") == "vertical" { Rectangle().fill(A2UIStyle.edge).frame(width: 1) }
            else { Rectangle().fill(A2UIStyle.edge).frame(height: 1).frame(maxWidth: .infinity) }
        case "Button": button(c)
        case "CheckBox": checkBox(c)
        case "TextField": textField(c)
        case "DateTimeInput": dateTime(c)
        case "ChoicePicker": choices(c)
        case "Slider": slider(c)
        case "Place": A2UIPlaceView(name: str(c, "name") ?? "", address: str(c, "address"), hours: str(c, "hours"),
                                    latitude: num(c, "latitude"), longitude: num(c, "longitude"), tint: ctx.tint)
        case "DayStrip": dayStrip(c)
        case "Chart": chart(c)
        case "TodoItem": todo(c)
        case "TagChip": tagChip(c)
        default: EmptyView()   // not in the catalog: logged when it arrived (A2UISurface.take)
        }
    }

    private func text(_ c: A2UIComponent) -> some View {
        let t = str(c, "text") ?? ""
        let md = (try? AttributedString(markdown: t, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(t)
        let variant = str(c, "variant") ?? "body"
        return Text(md)
            .font(variant == "title" ? .system(size: 19, weight: .semibold) : variant == "caption" ? .footnote : .body)
            .foregroundStyle(variant == "caption" ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private func image(_ c: A2UIComponent) -> some View {
        let variant = str(c, "variant") ?? "mediumFeature"
        let side: CGFloat? = ["icon": 24, "avatar": 40, "smallFeature": 72][variant]
        let height: CGFloat = ["mediumFeature": 140, "largeFeature": 220, "header": 160][variant] ?? side ?? 140
        let fit = str(c, "fit") ?? "fill"
        AsyncImage(url: str(c, "url").flatMap(URL.init(string:))) { img in
            img.resizable().aspectRatio(contentMode: fit == "contain" || fit == "scaleDown" ? .fit : .fill)
        } placeholder: { A2UIStyle.raised }
            .frame(width: side, height: height).frame(maxWidth: side == nil ? .infinity : nil)
            .clipShape(variant == "avatar" ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 14, style: .continuous)))
            .accessibilityLabel(str(c, "description") ?? "")
    }

    private func weighted(_ n: A2UINode, axis: Axis) -> some View {
        let w = s.components[n.id]?["weight"]?.number
        return n.frame(maxWidth: axis == .horizontal && w != nil ? .infinity : nil).layoutPriority(w ?? 0)
    }

    private func row(_ c: A2UIComponent) -> some View {
        let justify = str(c, "justify") ?? "start"
        let align: VerticalAlignment = ["start": .top, "end": .bottom, "center": .center][str(c, "align") ?? "center"] ?? .center
        let kids = children(c)
        return HStack(alignment: align, spacing: 10) {
            if ["end", "center", "spaceAround", "spaceEvenly"].contains(justify) { Spacer(minLength: 0) }
            ForEach(Array(kids.enumerated()), id: \.element.key) { i, k in
                if i > 0, ["spaceBetween", "spaceAround", "spaceEvenly"].contains(justify) { Spacer(minLength: 8) }
                if justify == "stretch" { k.node.frame(maxWidth: .infinity) } else { weighted(k.node, axis: .horizontal) }
            }
            if ["start", "center", "spaceAround", "spaceEvenly"].contains(justify) { Spacer(minLength: 0) }
        }
    }

    private func column(_ c: A2UIComponent) -> some View {
        let align = str(c, "align") ?? "stretch"
        let h: HorizontalAlignment = align == "center" ? .center : align == "end" ? .trailing : .leading
        let edge: Alignment = align == "center" ? .center : align == "end" ? .trailing : .leading
        // ponytail: `justify` has no room to act on in a column that hugs its content; it is read as start.
        return VStack(alignment: h, spacing: 14) {
            ForEach(children(c), id: \.key) { k in
                k.node.frame(maxWidth: align == "stretch" ? .infinity : nil, alignment: edge)
            }
        }
        .frame(maxWidth: .infinity, alignment: edge)
    }

    @ViewBuilder private func list(_ c: A2UIComponent) -> some View {
        let kids = children(c)
        if str(c, "direction") == "horizontal" {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) { ForEach(kids, id: \.key) { $0.node } }
            }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(kids.enumerated()), id: \.element.key) { i, k in
                    if i > 0 { Rectangle().fill(A2UIStyle.edge).frame(height: 1) }
                    k.node.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    @ViewBuilder private func button(_ c: A2UIComponent) -> some View {
        let variant = str(c, "variant") ?? "default"
        let label = child(c["child"]?.string)
        let said = c["child"]?.string.flatMap { s.components[$0] }.flatMap { $0.type == "Text" ? str($0, "text") : nil }
        let (sending, done, busy, note, bad) = sendState(c)
        VStack(alignment: .trailing, spacing: 6) {
        Button { fire(c, userMessage: said) } label: {
            HStack(spacing: 8) {
                if sending { ProgressView().controlSize(.small).tint(variant == "primary" ? .white : A2UIStyle.text) }
                if done { Image(systemName: "checkmark").font(.body.weight(.bold)) }
                label
            }
                .font(.body.weight(.semibold))
                .padding(.horizontal, variant == "borderless" ? 6 : 18).frame(minHeight: 44)
                .foregroundStyle(variant == "primary" ? Color.white : variant == "borderless" ? ctx.tint : A2UIStyle.text)
                .background {
                    if variant == "primary" { Capsule().fill(ctx.tint) }
                    else if variant != "borderless" { Capsule().fill(A2UIStyle.raised) }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(sending || done || busy)
        .opacity(busy ? 0.45 : 1)
        .accessibilityValue(sending ? "Sending" : done ? "Sent" : "")
            if let note {
                Label(note, systemImage: bad ? "exclamationmark.circle" : "checkmark.circle")
                    .font(.footnote).foregroundStyle(bad ? A2UIStyle.text : A2UIStyle.quiet).lineLimit(2)
                    .multilineTextAlignment(.trailing)
                    .accessibilityIdentifier(bad ? "a2ui-send-error" : "a2ui-send-answer")
            }
        }
    }

    /// A button's part in the surface's send: this one spins, then shows a check and the answer's line; the others
    /// wait (dimmed, untappable) until the hub answers; a failed send brings them all back with one line under it.
    private func sendState(_ c: A2UIComponent) -> (sending: Bool, done: Bool, busy: Bool, note: String?, bad: Bool) {
        let me = A2UISurface.key(c.id, scope: scope)
        let local = c["action"]?.object?["event"] == nil   // openUrl: nothing is sent, nothing to wait for
        switch s.sent {
        case .sending(let k): return (k == me, false, !local && k != me, nil, false)
        case .answered(let k, let line): return (false, k == me, false, k == me ? line : nil, false)
        case .failed(let k, let line): return (false, false, false, k == me ? line : nil, true)
        case nil: return (false, false, false, nil, false)
        }
    }

    private func checkBox(_ c: A2UIComponent) -> some View {
        let on = flag(c, "value")
        return Button { write(c, "value", .bool(!on)) } label: {
            HStack(spacing: 12) {
                Image(systemName: on ? "checkmark.square.fill" : "square").font(.system(size: 22))
                    .foregroundStyle(on ? ctx.tint : A2UIStyle.quiet)
                Text(str(c, "label") ?? "").foregroundStyle(A2UIStyle.text)
                Spacer(minLength: 0)
            }
            .frame(minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func fieldLabel(_ t: String?) -> some View {
        Text(t ?? "").font(.footnote.weight(.medium)).foregroundStyle(A2UIStyle.quiet)
    }

    private func textField(_ c: A2UIComponent) -> some View {
        let variant = str(c, "variant") ?? "shortText"
        let bound = Binding<String>(get: { str(c, "value") ?? "" }, set: { write(c, "value", .string($0)) })
        let prompt = str(c, "placeholder") ?? ""
        return VStack(alignment: .leading, spacing: 6) {
            fieldLabel(str(c, "label"))
            Group {
                if variant == "obscured" { SecureField(prompt, text: bound) }
                else if variant == "longText" { TextField(prompt, text: bound, axis: .vertical).lineLimit(3...6) }
                else {
                    TextField(prompt, text: bound)
                    #if os(iOS)
                        .keyboardType(variant == "number" ? .decimalPad : .default)
                    #endif
                }
            }
            .textFieldStyle(.plain).foregroundStyle(A2UIStyle.text)
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(A2UIStyle.raised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    /// The value's own form: "2026-11-24" (date), "15:30" (time) or a full ISO 8601 date-time (both).
    static func dateFormat(date: Bool, time: Bool) -> DateFormatter {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = date && time ? "yyyy-MM-dd'T'HH:mm" : date ? "yyyy-MM-dd" : "HH:mm"
        return f
    }

    static func parseDate(_ s: String, date: Bool, time: Bool) -> Date? {
        if let d = ISO8601DateFormatter().date(from: s) { return d }
        let f = dateFormat(date: date, time: time)
        if let d = f.date(from: String(s.prefix(date && time ? 16 : date ? 10 : 5))) {
            guard !date else { return d }
            // A time alone lands on today.
            let hm = Calendar.current.dateComponents([.hour, .minute], from: d)
            return Calendar.current.date(bySettingHour: hm.hour ?? 0, minute: hm.minute ?? 0, second: 0, of: .now)
        }
        return nil
    }

    private func dateTime(_ c: A2UIComponent) -> some View {
        var date = flag(c, "enableDate"), time = flag(c, "enableTime")
        if !date && !time { date = true; time = true }
        let bound = Binding<Date>(get: { Self.parseDate(str(c, "value") ?? "", date: date, time: time) ?? .now },
                                  set: { write(c, "value", .string(Self.dateFormat(date: date, time: time).string(from: $0))) })
        let lo = str(c, "min").flatMap { Self.parseDate($0, date: date, time: time) } ?? .distantPast
        let hi = str(c, "max").flatMap { Self.parseDate($0, date: date, time: time) } ?? .distantFuture
        let parts: DatePickerComponents = date && time ? [.date, .hourAndMinute] : date ? .date : .hourAndMinute
        return HStack {
            Text(str(c, "label") ?? "").foregroundStyle(A2UIStyle.text)
            Spacer(minLength: 8)
            DatePicker("", selection: bound, in: lo...max(lo, hi), displayedComponents: parts).labelsHidden()
        }
        .padding(.leading, 14).padding(.trailing, 8).padding(.vertical, 6)
        .background(A2UIStyle.raised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func choices(_ c: A2UIComponent) -> some View {
        let picked = (v(c, "value")?.array ?? []).compactMap(\.string)
        let one = (str(c, "variant") ?? "mutuallyExclusive") == "mutuallyExclusive"
        let opts: [(label: String, value: String)] = (c["options"]?.array ?? []).compactMap { o in
            guard let val = o.object?["value"]?.string else { return nil }
            return (s.resolve(o.object?["label"], scope: scope)?.string ?? val, val)
        }
        let toggle = { (val: String) in
            let next = one ? [val] : picked.contains(val) ? picked.filter { $0 != val } : picked + [val]
            write(c, "value", .array(next.map(JSONValue.string)))
        }
        return VStack(alignment: .leading, spacing: 8) {
            if let l = str(c, "label") { fieldLabel(l) }
            if str(c, "displayStyle") == "chips" {
                // Chips wrap onto a second row (the Tags place's FlowRow) rather than scroll off the card's
                // edge, where the last one was cut mid-word ("Eating o", Glyph Wealth, 2026-11-22).
                FlowRow(spacing: 8) {
                        ForEach(opts, id: \.value) { o in
                            let on = picked.contains(o.value)
                            Button { toggle(o.value) } label: {
                                Text(o.label).font(.system(size: 15, weight: .semibold)).monospacedDigit()
                                    .padding(.horizontal, 16).frame(height: 40)
                                    .foregroundStyle(on ? Color.white : A2UIStyle.text)
                                    .background(on ? ctx.tint : A2UIStyle.chip, in: Capsule())
                                    .overlay { Capsule().strokeBorder(on ? ctx.tint : A2UIStyle.edge) }
                            }
                            .buttonStyle(.plain).accessibilityAddTraits(on ? .isSelected : [])
                        }
                }
            } else {
                ForEach(opts, id: \.value) { o in
                    let on = picked.contains(o.value)
                    Button { toggle(o.value) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: one ? (on ? "largecircle.fill.circle" : "circle") : (on ? "checkmark.square.fill" : "square"))
                                .font(.system(size: 20)).foregroundStyle(on ? ctx.tint : A2UIStyle.quiet)
                            Text(o.label).foregroundStyle(A2UIStyle.text)
                            Spacer(minLength: 0)
                        }
                        .frame(minHeight: 40).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).accessibilityAddTraits(on ? .isSelected : [])
                }
            }
        }
    }

    private func slider(_ c: A2UIComponent) -> some View {
        let lo = num(c, "min") ?? 0, hi = max(num(c, "max") ?? 100, lo + 1)
        let steps = num(c, "steps").map { max(1, $0) }
        let bound = Binding<Double>(get: { min(max(num(c, "value") ?? lo, lo), hi) }, set: { write(c, "value", .number($0)) })
        let shown = bound.wrappedValue
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                fieldLabel(str(c, "label"))
                Spacer()
                Text(shown == shown.rounded() ? String(Int(shown)) : String(format: "%.1f", shown))
                    .font(.footnote.weight(.semibold)).monospacedDigit().foregroundStyle(A2UIStyle.text)
            }
            if let steps { Slider(value: bound, in: lo...hi, step: (hi - lo) / steps) } else { Slider(value: bound, in: lo...hi) }
        }
    }

    // MARK: Glyph parts

    private func dayStrip(_ c: A2UIComponent) -> some View {
        let f = Self.dateFormat(date: true, time: false)
        let cal = Calendar.current
        let start = cal.startOfDay(for: str(c, "start").flatMap(f.date(from:)) ?? .now)
        let n = min(max(Int(num(c, "days") ?? 7), 1), 14)
        let days = (0..<n).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
        let marks: [(date: String, label: String, detail: String?)] = (v(c, "marks")?.array ?? []).compactMap { m in
            guard let o = m.object, let d = o["date"]?.string, let l = o["label"]?.string else { return nil }
            return (String(d.prefix(10)), l, o["detail"]?.string)
        }
        let marked = Set(marks.map(\.date))
        let chosen = str(c, "value").map { String($0.prefix(10)) }
        let weekday = DateFormatter(); weekday.dateFormat = "EEEEE"
        let short = DateFormatter(); short.dateFormat = "EEE d"
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 4) {
                ForEach(days, id: \.self) { day in
                    let key = f.string(from: day)
                    let on = key == chosen
                    Button {
                        write(c, "value", .string(key))
                        if c["action"] != nil { fire(c) }
                    } label: {
                        VStack(spacing: 5) {
                            Text(weekday.string(from: day)).font(.caption2.weight(.semibold)).foregroundStyle(A2UIStyle.quiet)
                            Text("\(cal.component(.day, from: day))").font(.system(size: 17, weight: .semibold)).monospacedDigit()
                                .foregroundStyle(on ? Color.white : A2UIStyle.text)
                                .frame(width: 34, height: 34)
                                .background { if on { Circle().fill(ctx.tint) } }
                            Circle().fill(marked.contains(key) ? Color.glyphGreen : .clear).frame(width: 6, height: 6)
                        }
                        .frame(maxWidth: .infinity).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(short.string(from: day) + (marked.contains(key) ? ", something due" : ""))
                }
            }
            ForEach(marks.sorted { $0.date < $1.date }, id: \.label) { m in
                HStack(spacing: 12) {
                    Text(f.date(from: m.date).map(short.string(from:)) ?? m.date)
                        .font(.footnote.weight(.semibold)).monospacedDigit()
                        .foregroundStyle(m.date == chosen ? Color.glyphGreen : A2UIStyle.quiet)
                        .frame(width: 56, alignment: .leading)
                    Text(m.label).foregroundStyle(A2UIStyle.text).lineLimit(2)
                    Spacer(minLength: 4)
                    if let d = m.detail { Text(d).font(.subheadline.weight(.medium)).monospacedDigit().foregroundStyle(A2UIStyle.quiet) }
                }
            }
        }
    }

    private func chart(_ c: A2UIComponent) -> some View {
        let points: [(label: String, value: Double)] = (v(c, "points")?.array ?? []).compactMap { p in
            guard let o = p.object, let l = o["label"]?.string, let y = o["value"]?.number else { return nil }
            return (l, y)
        }
        let currency = str(c, "currency"), unit = str(c, "unit")
        let whole = points.allSatisfy { abs($0.value) >= 10 }
        let say = { (y: Double) -> String in
            if let currency { return y.formatted(.currency(code: currency).precision(.fractionLength(y >= 100 || whole ? 0 : 2))) }
            let n = y.formatted(.number.precision(.fractionLength(0...1)))
            return unit.map { "\(n) \($0)" } ?? n
        }
        let line = str(c, "kind") == "line"
        let last = points.last
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(str(c, "label") ?? "").font(.system(size: 17, weight: .semibold)).foregroundStyle(A2UIStyle.text)
                Spacer(minLength: 8)
                if let last { Text(say(last.value)).font(.system(size: 17, weight: .semibold)).monospacedDigit().foregroundStyle(Color.glyphGreen) }
            }
            Chart {
                ForEach(Array(points.enumerated()), id: \.offset) { i, p in
                    if line {
                        LineMark(x: .value("When", p.label), y: .value("Amount", p.value))
                            .foregroundStyle(Color.glyphGreen).interpolationMethod(.monotone)
                        PointMark(x: .value("When", p.label), y: .value("Amount", p.value)).foregroundStyle(Color.glyphGreen)
                    } else {
                        BarMark(x: .value("When", p.label), y: .value("Amount", p.value), width: .ratio(0.62))
                            .foregroundStyle(i == points.count - 1 ? Color.glyphGreen : Color.glyphGreen.opacity(0.45))
                            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine().foregroundStyle(A2UIStyle.edge)
                    AxisValueLabel { if let y = value.as(Double.self) { Text(say(y)).font(.caption2).foregroundStyle(A2UIStyle.quiet) } }
                }
            }
            .chartXAxis {
                AxisMarks { _ in AxisValueLabel().font(.caption2).foregroundStyle(A2UIStyle.quiet) }
            }
            .frame(height: 150)
            .accessibilityLabel((str(c, "label") ?? "Chart") + ": " + points.map { "\($0.label) \(say($0.value))" }.joined(separator: ", "))
        }
    }

    private func todo(_ c: A2UIComponent) -> some View {
        let done = flag(c, "done")
        let tags = (v(c, "tags")?.array ?? []).compactMap(\.string)
        return HStack(alignment: .top, spacing: 12) {
            Button {
                write(c, "done", .bool(!done))
                if c["action"] != nil { fire(c) }
            } label: {
                Image(systemName: done ? "checkmark.circle.fill" : "circle").font(.system(size: 24))
                    .foregroundStyle(done ? ctx.tint : A2UIStyle.quiet)
                    .frame(width: 28, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(done ? "Done" : "Not done")
            VStack(alignment: .leading, spacing: 3) {
                Text(str(c, "title") ?? "").font(.body.weight(.medium))
                    .strikethrough(done).foregroundStyle(done ? A2UIStyle.quiet : A2UIStyle.text)
                HStack(spacing: 8) {
                    if let t = str(c, "time"), !t.isEmpty { Text(t).foregroundStyle(A2UIStyle.quiet) }
                    ForEach(tags, id: \.self) { t in
                        (Text("#").foregroundStyle(GlyphTags.color(t)).fontWeight(.bold) + Text(GlyphTags.display(t)).foregroundStyle(A2UIStyle.quiet))
                    }
                }
                .font(.footnote).lineLimit(1)
            }
            .padding(.vertical, 10)
            Spacer(minLength: 0)
        }
    }

    private func tagChip(_ c: A2UIComponent) -> some View {
        let name = str(c, "name") ?? ""
        return Button { fire(c) } label: {
            HStack(spacing: 5) {
                Text("#").fontWeight(.bold).foregroundStyle(GlyphTags.color(name))
                Text(GlyphTags.display(name)).foregroundStyle(A2UIStyle.text)
            }
            .font(.system(size: 14, weight: .semibold))
            .padding(.horizontal, 12).frame(height: 32)
            .background(A2UIStyle.chip, in: Capsule())
            .overlay { Capsule().strokeBorder(A2UIStyle.edge) }
        }
        .buttonStyle(.plain).disabled(c["action"] == nil)
    }

    /// The Basic Catalog's icon names as SF Symbols.
    static func symbol(_ name: String) -> String {
        let map = ["accountCircle": "person.crop.circle", "add": "plus", "arrowBack": "chevron.left", "arrowForward": "chevron.right",
                   "attachFile": "paperclip", "calendarToday": "calendar", "call": "phone", "camera": "camera", "check": "checkmark",
                   "close": "xmark", "delete": "trash", "download": "arrow.down.circle", "edit": "pencil", "event": "calendar.badge.clock",
                   "error": "exclamationmark.circle", "fastForward": "forward", "favorite": "heart.fill", "favoriteOff": "heart",
                   "folder": "folder", "help": "questionmark.circle", "home": "house", "info": "info.circle", "locationOn": "mappin.and.ellipse",
                   "lock": "lock", "lockOpen": "lock.open", "mail": "envelope", "menu": "line.3.horizontal", "moreVert": "ellipsis",
                   "moreHoriz": "ellipsis", "notificationsOff": "bell.slash", "notifications": "bell", "pause": "pause", "payment": "creditcard",
                   "person": "person", "phone": "phone", "photo": "photo", "play": "play", "print": "printer", "refresh": "arrow.clockwise",
                   "rewind": "backward", "search": "magnifyingglass", "send": "paperplane", "settings": "gearshape", "share": "square.and.arrow.up",
                   "shoppingCart": "cart", "skipNext": "forward.end", "skipPrevious": "backward.end", "star": "star.fill", "starHalf": "star.leadinghalf.filled",
                   "starOff": "star", "stop": "stop", "upload": "arrow.up.circle", "visibility": "eye", "visibilityOff": "eye.slash",
                   "volumeDown": "speaker.wave.1", "volumeMute": "speaker", "volumeOff": "speaker.slash", "volumeUp": "speaker.wave.3",
                   "warning": "exclamationmark.triangle"]
        return map[name] ?? "questionmark.square.dashed"
    }
}

/// A place: a still map with its pin, the name, the address and the hours, and Open in Maps.
struct A2UIPlaceView: View {
    let name: String
    let address: String?
    let hours: String?
    let latitude: Double?
    let longitude: Double?
    let tint: Color
    @State private var map: Image?
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let latitude, let longitude {
                // The map as an overlay, never a child that sizes the box: filled into 150 points high it is
                // wider than a phone's column, and as a ZStack child it widened the card and with it every line
                // of the chat past the screen's edge (Glyph X, 2026-11-22).
                ZStack {
                    A2UIStyle.raised
                        .overlay { if let shot = map ?? A2UIMap.cached(latitude, longitude) { shot.resizable().scaledToFit() } }
                    Image(systemName: "mappin.circle.fill").font(.system(size: 30)).symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color.officeGreen).shadow(radius: 3).offset(y: -4)
                }
                // The box takes the snapshot's own shape, so the still is drawn whole: filled into a fixed 150 points
                // it was cropped at the sides, and MapKit's logo read "laps" (2026-11-22). Its attribution (logo and
                // Legal) must stay fully visible; the corner is small enough not to clip the logo either.
                .aspectRatio(A2UIMap.size.width / A2UIMap.size.height, contentMode: .fit).frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .task { if map == nil { map = await A2UIMap.snapshot(latitude, longitude) } }
                .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(name).font(.system(size: 19, weight: .semibold)).foregroundStyle(A2UIStyle.text)
                if let address { Text(address).font(.subheadline).foregroundStyle(A2UIStyle.quiet) }
                if let hours {
                    Label(hours, systemImage: "clock").font(.subheadline).foregroundStyle(A2UIStyle.quiet).labelStyle(.titleAndIcon)
                }
            }
            if latitude != nil || address != nil {
                Button {
                    var q = URLComponents(string: "https://maps.apple.com/")!
                    q.queryItems = [URLQueryItem(name: "q", value: name)]
                        + (latitude.flatMap { la in longitude.map { [URLQueryItem(name: "ll", value: "\(la),\($0)")] } } ?? [])
                        + (latitude == nil ? [URLQueryItem(name: "address", value: address)] : [])
                    if let u = q.url { openURL(u) }
                } label: {
                    Label("Open in Maps", systemImage: "map").font(.body.weight(.semibold)).foregroundStyle(tint)
                        .frame(minHeight: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain).accessibilityIdentifier("a2ui-open-in-maps")
            }
        }
    }
}

/// Still maps (MKMapSnapshotter, dark), kept for the session so a redraw does not ask again.
public enum A2UIMap {
    @MainActor static var shots: [String: Image] = [:]
    /// The still's size; the Place card draws it at this shape, never cropped (the logo and Legal sit at its edges).
    static let size = CGSize(width: 360, height: 180)
    static func key(_ la: Double, _ lo: Double) -> String { String(format: "%.5f,%.5f", la, lo) }
    @MainActor static func cached(_ la: Double, _ lo: Double) -> Image? { shots[key(la, lo)] }

    @MainActor static func snapshot(_ la: Double, _ lo: Double) async -> Image? {
        if let got = cached(la, lo) { return got }
        let o = MKMapSnapshotter.Options()
        o.region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: la, longitude: lo), latitudinalMeters: 700, longitudinalMeters: 700)
        o.size = size
        #if os(iOS)
        o.traitCollection = UITraitCollection(userInterfaceStyle: .dark)
        #elseif os(macOS)
        o.appearance = NSAppearance(named: .darkAqua)
        #endif
        guard let shot = try? await MKMapSnapshotter(options: o).start() else { return nil }
        #if os(iOS)
        let img = Image(uiImage: shot.image)
        #else
        let img = Image(nsImage: shot.image)
        #endif
        shots[key(la, lo)] = img
        return img
    }

    /// Fetches the maps a surface's places need, so it draws whole the first time (and in a still picture).
    @MainActor public static func prepare(_ surface: A2UISurface) async {
        for c in surface.components.values where c.type == "Place" {
            if let la = surface.resolve(c["latitude"])?.number, let lo = surface.resolve(c["longitude"])?.number { _ = await snapshot(la, lo) }
        }
    }
}
