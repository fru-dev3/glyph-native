import SwiftUI

/// The picture on each card. A marketplace card carries a wide product screenshot; these apps have no
/// screenshot worth looking at, so each card carries a drawing of what its app actually does, in the
/// family's green: Jot a voice, Time a day going round, Well a pulse, CRM people joined up, Omega rings
/// closing on a goal, Studio agents on a mesh. Drawn, never a file: it is sharp at any size, right in
/// both appearances, and the shapes follow the card's own live number rather than a frozen picture.
struct CardArt: View {
    let id: String
    var live: Double = 0.62      // 0 to 1, the app's own fill: hours of the day, goals done, and so on
    var white = false

    private var ink: Color { white ? .white : .nativeGreen }

    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            let strong = GraphicsContext.Shading.color(ink.opacity(white ? 0.9 : 0.75))
            let faint = GraphicsContext.Shading.color(ink.opacity(white ? 0.35 : 0.22))
            switch id {
            case "jot":
                // A voice: bars off a centre line, the loud ones solid.
                let n = 11, gap = w / Double(n)
                let tall: [Double] = [0.25, 0.5, 0.85, 0.45, 1, 0.7, 0.95, 0.35, 0.6, 0.3, 0.18]
                for i in 0..<n {
                    let bh = h * tall[i] * 0.9, x = gap * Double(i) + gap * 0.2
                    let r = Path(roundedRect: CGRect(x: x, y: (h - bh) / 2, width: gap * 0.5, height: bh), cornerRadius: gap * 0.25)
                    ctx.fill(r, with: tall[i] > 0.55 ? strong : faint)
                }
            case "time":
                // The day going round, filled as far as it has got.
                let r = min(w, h) / 2 - 3, c = CGPoint(x: w - r - 3, y: h / 2)
                ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: faint, lineWidth: 7)
                var arc = Path()
                arc.addArc(center: c, radius: r, startAngle: .degrees(-90), endAngle: .degrees(-90 + 360 * live), clockwise: false)
                ctx.stroke(arc, with: strong, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                // The hours behind it, as ticks.
                for i in 0..<12 {
                    let a = Double(i) / 12 * 2 * .pi - .pi / 2
                    let p = CGPoint(x: c.x + cos(a) * (r - 13), y: c.y + sin(a) * (r - 13))
                    ctx.fill(Path(ellipseIn: CGRect(x: p.x - 1.5, y: p.y - 1.5, width: 3, height: 3)), with: faint)
                }
            case "well":
                // A pulse, with today's beat picked out.
                var p = Path()
                let pts: [(Double, Double)] = [(0, 0.5), (0.18, 0.5), (0.26, 0.2), (0.36, 0.85), (0.46, 0.5), (0.62, 0.5), (0.7, 0.33), (0.78, 0.62), (0.86, 0.5), (1, 0.5)]
                for (i, q) in pts.enumerated() {
                    let pt = CGPoint(x: q.0 * w, y: q.1 * h)
                    i == 0 ? p.move(to: pt) : p.addLine(to: pt)
                }
                ctx.stroke(p, with: strong, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                let dot = CGPoint(x: 0.36 * w, y: 0.85 * h)
                ctx.fill(Path(ellipseIn: CGRect(x: dot.x - 4, y: dot.y - 4, width: 8, height: 8)), with: strong)
            case "crm":
                // People, joined up: the ones you have seen to solid, the rest waiting.
                let pts: [(Double, Double)] = [(0.1, 0.25), (0.42, 0.1), (0.78, 0.3), (0.2, 0.75), (0.55, 0.6), (0.9, 0.82)]
                var lines = Path()
                for (a, b) in [(0, 1), (1, 2), (0, 3), (3, 4), (4, 2), (4, 5)] {
                    lines.move(to: CGPoint(x: pts[a].0 * w, y: pts[a].1 * h))
                    lines.addLine(to: CGPoint(x: pts[b].0 * w, y: pts[b].1 * h))
                }
                ctx.stroke(lines, with: faint, lineWidth: 1.5)
                for (i, q) in pts.enumerated() {
                    let r: Double = i == 4 ? 7 : 5
                    let rect = CGRect(x: q.0 * w - r, y: q.1 * h - r, width: r * 2, height: r * 2)
                    ctx.fill(Path(ellipseIn: rect), with: i % 2 == 0 ? strong : faint)
                }
            case "omega":
                // Rings closing on one goal, open at the foot: the letter the app is named for.
                let c = CGPoint(x: w - min(w, h) / 2 - 3, y: h / 2)
                for (i, r) in [min(w, h) / 2 - 3, min(w, h) / 2 - 13, min(w, h) / 2 - 23].enumerated() where r > 4 {
                    var a = Path()
                    a.addArc(center: c, radius: r, startAngle: .degrees(118), endAngle: .degrees(62), clockwise: false)
                    ctx.stroke(a, with: i == 0 ? strong : faint, style: StrokeStyle(lineWidth: i == 0 ? 5 : 3, lineCap: .round))
                }
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - 4, y: c.y - 4, width: 8, height: 8)), with: strong)
            default:
                // Studio: agents on a mesh, one of them working.
                let cols = 4, rows = 3
                var lines = Path()
                var dots: [CGPoint] = []
                for r in 0..<rows {
                    for c in 0..<cols {
                        dots.append(CGPoint(x: (Double(c) + 0.5) / Double(cols) * w, y: (Double(r) + 0.5) / Double(rows) * h))
                    }
                }
                for i in dots.indices {
                    if i % cols != cols - 1 { lines.move(to: dots[i]); lines.addLine(to: dots[i + 1]) }
                    if i + cols < dots.count { lines.move(to: dots[i]); lines.addLine(to: dots[i + cols]) }
                }
                ctx.stroke(lines, with: faint, lineWidth: 1)
                for (i, d) in dots.enumerated() {
                    let on = [1, 4, 6, 9, 10].contains(i)
                    let r: Double = on ? 4.5 : 3
                    ctx.fill(Path(ellipseIn: CGRect(x: d.x - r, y: d.y - r, width: r * 2, height: r * 2)), with: on ? strong : faint)
                }
            }
        }
        .allowsHitTesting(false)
    }
}
