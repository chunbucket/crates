import SwiftUI

/// The record: grooved vinyl with the video art as its center label.
/// Progress renders as grooves being cut — the uncut remainder is a
/// lighter "raw acetate" wedge sweeping clockwise from 12 o'clock.
struct VinylView: View {
    var artPath: String?
    var progress: Double?      // nil = fully cut (finished record)
    var spinning: Bool

    @State private var angle: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            ZStack {
                // vinyl base
                Circle().fill(Color(white: 0.09))
                // grooves
                Canvas { ctx, sz in
                    let c = CGPoint(x: sz.width / 2, y: sz.height / 2)
                    let maxR = sz.width / 2 - 3
                    let labelR = sz.width * 0.30
                    var r = labelR + 4
                    while r < maxR {
                        let rect = CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)
                        ctx.stroke(Path(ellipseIn: rect),
                                   with: .color(Color(white: 0.16)),
                                   lineWidth: 0.8)
                        r += 3
                    }
                }
                // sheen
                Circle()
                    .fill(AngularGradient(
                        gradient: Gradient(colors: [
                            .clear, Color.white.opacity(0.05), .clear,
                            .clear, Color.white.opacity(0.04), .clear,
                        ]),
                        center: .center))

                // label = artwork
                labelView(size: size)
                    .frame(width: size * 0.60, height: size * 0.60)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.black, lineWidth: 2.5))
                    .overlay(Circle().fill(Color(white: 0.07)).frame(width: 7, height: 7))

                // uncut remainder
                if let p = progress, p < 1 {
                    UncutWedge(progress: p)
                        .fill(Color(white: 0.72).opacity(0.85))
                        .allowsHitTesting(false)
                }
            }
            .rotationEffect(.degrees(angle))
            .onAppear { if spinning { spin() } }
            .onChange(of: spinning) { _, now in
                if now { spin() } else { stopSpin() }
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    @ViewBuilder
    private func labelView(size: CGFloat) -> some View {
        if let path = artPath, let img = NSImage(contentsOfFile: path) {
            Image(nsImage: img)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            ZStack {
                Color(white: 0.20)
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.14, weight: .medium))
                    .foregroundStyle(Color(white: 0.45))
            }
        }
    }

    private func spin() {
        guard !reduceMotion else { return }
        angle = 0
        withAnimation(.linear(duration: 3.2).repeatForever(autoreverses: false)) {
            angle = 360
        }
    }

    private func stopSpin() {
        withAnimation(.easeOut(duration: 0.8)) {
            angle = angle.truncatingRemainder(dividingBy: 360)
        }
    }
}

/// Pie wedge covering the not-yet-cut part of the record (progress..1),
/// with the center label area punched out.
struct UncutWedge: Shape {
    var progress: Double

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let outerR = rect.width / 2
        let innerR = rect.width * 0.315
        let start = Angle(degrees: -90 + progress * 360)
        let end = Angle(degrees: 270)
        var p = Path()
        p.addArc(center: c, radius: outerR, startAngle: start, endAngle: end, clockwise: false)
        p.addArc(center: c, radius: innerR, startAngle: end, endAngle: start, clockwise: true)
        p.closeSubpath()
        return p
    }
}
