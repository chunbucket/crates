import SwiftUI

/// The milk crate, as vector geometry: an isometric open box with the top
/// rim, a handle slot on each visible face, the diagonal lattice below the
/// band, corner posts and a bottom band. Drawn in two layers so records can
/// stand inside it: `CrateBack` (the far inner walls), then the records,
/// then `CrateFront` (rim and the two visible faces).
enum MilkCrate {
    /// Projection: the front vertical edge is at the origin, x goes up-right,
    /// y goes up-left, z goes up. Box is w × d × h in these units.
    static let w = 1.0, d = 1.0, h = 0.82
    static let rim = 0.09   // rim depth seen from above

    static func project(_ x: Double, _ y: Double, _ z: Double) -> CGPoint {
        CGPoint(x: 0.866 * (x - y), y: -0.5 * (x + y) - z)
    }

    /// Scale + translate that fits the box into `size`.
    static func fit(_ size: CGSize) -> CGAffineTransform {
        let minX = -0.866 * d, maxX = 0.866 * w
        let minY = -(w + d) / 2 - h - 0.12, maxY = 0.0   // headroom for the records
        let scale = min(size.width / (maxX - minX), size.height / (maxY - minY)) * 0.96
        let cx = (minX + maxX) / 2, cy = (minY + maxY) / 2
        return CGAffineTransform(translationX: size.width / 2, y: size.height / 2)
            .scaledBy(x: scale, y: scale)
            .translatedBy(x: -cx, y: -cy)
    }

    static func poly(_ pts: [CGPoint], _ t: CGAffineTransform) -> Path {
        var p = Path()
        p.addLines(pts.map { $0.applying(t) })
        p.closeSubpath()
        return p
    }

    /// Sleeves stand on edge, faces parallel to the front wall, packed from
    /// the back of the crate forward. Taller than the crate, so their tops
    /// show over the near rim.
    static let sleeveCount = 7
    static let sleeveX0 = 0.13, sleeveWidth = 0.74, sleeveHeight = 1.06 * h, sleeveThickness = 0.028
    static func sleeveDepth(_ i: Int) -> Double {   // i = 0 is the backmost
        let back = d - 0.16, front = 0.20
        return back - (back - front) * Double(i) / Double(max(1, sleeveCount - 1))
    }

    struct Palette {
        var face: Color        // right face
        var faceDark: Color    // left face
        var rimLight: Color
        var inside: Color
        var hole: Color

        static let yellow = Palette(
            face: Color(red: 0.90, green: 0.80, blue: 0.20),
            faceDark: Color(red: 0.74, green: 0.65, blue: 0.14),
            rimLight: Color(red: 0.97, green: 0.90, blue: 0.38),
            inside: Color(red: 0.55, green: 0.48, blue: 0.10),
            hole: Color.black.opacity(0.55))
        static let white = Palette(
            face: Color(white: 0.90), faceDark: Color(white: 0.74), rimLight: Color(white: 0.98),
            inside: Color(white: 0.30), hole: Color.black.opacity(0.5))
        static let mono = Palette(
            face: Color(white: 0.62), faceDark: Color(white: 0.46), rimLight: Color(white: 0.78),
            inside: Color(white: 0.28), hole: Color.black.opacity(0.55))
    }
}

/// The far inner walls, seen through the opening.
struct CrateBack: View {
    var palette: MilkCrate.Palette = .yellow
    var body: some View {
        Canvas { ctx, size in
            let t = MilkCrate.fit(size)
            let (w, d, h, r) = (MilkCrate.w, MilkCrate.d, MilkCrate.h, MilkCrate.rim)
            let P = MilkCrate.project
            // a soft shadow on the ground
            let base = MilkCrate.poly([P(-0.08, -0.08, -0.02), P(w + 0.1, -0.08, -0.02), P(w + 0.1, d + 0.1, -0.02), P(-0.08, d + 0.1, -0.02)], t)
            ctx.fill(base, with: .color(.black.opacity(0.35)))
            // opening floor + inner walls, one darker parallelogram
            ctx.fill(MilkCrate.poly([P(r, r, h), P(w - r, r, h), P(w - r, d - r, h), P(r, d - r, h)], t),
                     with: .color(palette.inside))
            // inner back walls catch a little light along their top
            ctx.fill(MilkCrate.poly([P(w - r, r, h), P(w - r, d - r, h), P(w - r, d - r, h - 0.35), P(w - r, r, h - 0.35)], t),
                     with: .color(palette.faceDark.opacity(0.9)))
            ctx.fill(MilkCrate.poly([P(r, d - r, h), P(w - r, d - r, h), P(w - r, d - r, h - 0.35), P(r, d - r, h - 0.35)], t),
                     with: .color(palette.face.opacity(0.9)))
        }
    }
}

/// Rim and the two visible faces with their details.
struct CrateFront: View {
    var palette: MilkCrate.Palette = .yellow
    var lattice = true

    var body: some View {
        Canvas { ctx, size in
            let t = MilkCrate.fit(size)
            let (w, d, h, r) = (MilkCrate.w, MilkCrate.d, MilkCrate.h, MilkCrate.rim)
            let P = MilkCrate.project

            // Faces: local (u across, v down from the top edge) → 2D.
            let right = CGAffineTransform(a: 0.866 * w, b: -0.5 * w, c: 0, d: h, tx: 0, ty: -h).concatenating(t)
            let left  = CGAffineTransform(a: -0.866 * d, b: -0.5 * d, c: 0, d: h, tx: 0, ty: -h).concatenating(t)
            drawFace(&ctx, right, fill: palette.face)
            drawFace(&ctx, left, fill: palette.faceDark)

            // Rim: outer top parallelogram minus the opening.
            var rimPath = MilkCrate.poly([P(0, 0, h), P(w, 0, h), P(w, d, h), P(0, d, h)], t)
            rimPath.addPath(MilkCrate.poly([P(r, r, h), P(w - r, r, h), P(w - r, d - r, h), P(r, d - r, h)], t))
            ctx.fill(rimPath, with: .color(palette.rimLight), style: FillStyle(eoFill: true))
            // a hairline along the front top edges
            var edge = Path()
            edge.move(to: P(0, d, h).applying(t)); edge.addLine(to: P(0, 0, h).applying(t)); edge.addLine(to: P(w, 0, h).applying(t))
            ctx.stroke(edge, with: .color(.white.opacity(0.35)), lineWidth: max(0.6, size.width * 0.006))
        }
    }

    private func drawFace(_ ctx: inout GraphicsContext, _ m: CGAffineTransform, fill: Color) {
        func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> Path {
            Path(CGRect(x: x, y: y, width: w, height: h)).applying(m)
        }
        // solid face
        ctx.fill(rect(0, 0, 1, 1), with: .color(fill))
        // ribs in the top band
        for v in [0.055, 0.105] { ctx.fill(rect(0.03, v, 0.94, 0.012), with: .color(.black.opacity(0.18))) }
        // handle slot
        ctx.fill(Path(roundedRect: CGRect(x: 0.33, y: 0.145, width: 0.34, height: 0.085), cornerRadius: 0.04).applying(m),
                 with: .color(palette.hole))
        guard lattice else { return }
        // lattice zone: holes first, then the bars over them
        let zone = CGRect(x: 0.07, y: 0.30, width: 0.86, height: 0.58)
        ctx.fill(Path(zone).applying(m), with: .color(palette.hole))
        var bars = Path()
        let bar = 0.06, step = 0.24   // coarse enough to read as holes at 84pt
        var k = -1.0
        while k < 2.0 {
            // "/" and "\" diagonals as thin parallelograms
            bars.addLines([CGPoint(x: k, y: zone.maxY), CGPoint(x: k + bar, y: zone.maxY),
                           CGPoint(x: k + bar + zone.height, y: zone.minY), CGPoint(x: k + zone.height, y: zone.minY)])
            bars.closeSubpath()
            bars.addLines([CGPoint(x: k, y: zone.minY), CGPoint(x: k + bar, y: zone.minY),
                           CGPoint(x: k + bar + zone.height, y: zone.maxY), CGPoint(x: k + zone.height, y: zone.maxY)])
            bars.closeSubpath()
            k += step
        }
        var zoneClip = ctx
        zoneClip.clip(to: Path(zone).applying(m))
        zoneClip.fill(bars.applying(m), with: .color(fill))
        // corner posts and the bands above/below the lattice
        ctx.fill(rect(0, 0.28, 0.07, 0.62), with: .color(fill))
        ctx.fill(rect(0.93, 0.28, 0.07, 0.62), with: .color(fill))
        ctx.fill(rect(0, 0.28, 1, 0.03), with: .color(fill))
        ctx.fill(rect(0, 0.88, 1, 0.12), with: .color(fill))
        ctx.fill(rect(0.03, 0.905, 0.94, 0.012), with: .color(.black.opacity(0.18)))
    }
}

/// One sleeve standing in the crate: its face (cover art or plain card)
/// skewed into the crate's projection, and its top edge.
struct SleeveView: View {
    let index: Int
    let record: Record?
    let size: CGFloat
    /// The unit-square view is drawn at this many points, then skewed.
    private let px: CGFloat = 100

    private var faceTransform: CGAffineTransform {
        let y0 = MilkCrate.sleeveDepth(index)
        let x0 = MilkCrate.sleeveX0, sw = MilkCrate.sleeveWidth, sh = MilkCrate.sleeveHeight
        // local (u, v) in [0,1] → 3D (x0 + u·sw, y0, sh − v·sh) → 2D
        let face = CGAffineTransform(a: 0.866 * sw, b: -0.5 * sw, c: 0, d: sh,
                                     tx: 0.866 * (x0 - y0), ty: -0.5 * (x0 + y0) - sh)
        return CGAffineTransform(scaleX: 1 / px, y: 1 / px)
            .concatenating(face)
            .concatenating(MilkCrate.fit(CGSize(width: size, height: size)))
    }

    private var topEdge: Path {
        let t = MilkCrate.fit(CGSize(width: size, height: size))
        let y0 = MilkCrate.sleeveDepth(index), x0 = MilkCrate.sleeveX0
        let sw = MilkCrate.sleeveWidth, sh = MilkCrate.sleeveHeight, th = MilkCrate.sleeveThickness
        let P = MilkCrate.project
        return MilkCrate.poly([P(x0, y0, sh), P(x0 + sw, y0, sh), P(x0 + sw, y0 + th, sh), P(x0, y0 + th, sh)], t)
    }

    /// Plain sleeves behind the covers: cream, black, grey — the usual crate.
    private var blank: Color {
        [Color(red: 0.90, green: 0.87, blue: 0.78), Color(white: 0.12), Color(white: 0.55),
         Color(red: 0.86, green: 0.82, blue: 0.70)][index % 4]
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Group {
                if let p = record?.artPath, let img = NSImage(contentsOfFile: p) {
                    Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                } else {
                    blank
                }
            }
            .frame(width: px, height: px)
            .clipped()
            .overlay(Rectangle().strokeBorder(Color.black.opacity(0.35), lineWidth: 2))
            .transformEffect(faceTransform)
            topEdge.fill(Color.white.opacity(0.85))
            topEdge.stroke(Color.black.opacity(0.25), lineWidth: 0.5)
        }
        .frame(width: size, height: size, alignment: .topLeading)
    }
}

/// The crate with a crate's records standing in it: cover art on the
/// front sleeves, plain sleeves behind.
struct MilkCrateIcon: View {
    var sleeves: [Record]
    var size: CGFloat = 78
    var palette: MilkCrate.Palette = .white
    var lattice = true

    var body: some View {
        let n = sleeves.isEmpty ? 0 : MilkCrate.sleeveCount
        ZStack(alignment: .topLeading) {
            CrateBack(palette: palette)
            // back to front; the newest records take the front slots
            ForEach(0..<n, id: \.self) { i in
                let fromFront = n - 1 - i
                SleeveView(index: i, record: fromFront < sleeves.count ? sleeves[fromFront] : nil, size: size)
            }
            CrateFront(palette: palette, lattice: lattice)
        }
        .frame(width: size, height: size)
    }
}
