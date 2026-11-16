import SwiftUI

/// Original artwork recovered from the user's approved 唐镜藏书 concept.
/// Inspired by a Tang grape-and-beast mirror; it is not a photograph of an antique.
enum BookshelfTangPalette {
    static let gold = Color(red: 0.78, green: 0.67, blue: 0.43)
    static let highlight = Color(red: 0.91, green: 0.82, blue: 0.59)
    static let bronze = Color(red: 0.40, green: 0.37, blue: 0.24)
    static let verdigris = Color(red: 0.16, green: 0.28, blue: 0.23)
    static func ink(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.91, green: 0.86, blue: 0.73) : Color(red: 0.21, green: 0.19, blue: 0.15)
    }
    static func paper(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.09, green: 0.14, blue: 0.12) : Color(red: 0.94, green: 0.91, blue: 0.85)
    }
}

struct BookshelfTangMirror: View {
    let diameter: CGFloat
    let rotation: CGFloat
    let count: Int
    let selectedSlot: Int
    var isSpinning = false
    var isDrawing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            Image("BookshelfTangMirror")
                .resizable().scaledToFit()
                .rotationEffect(.degrees(Double(rotation)))
                .shadow(color: .black.opacity(0.22), radius: diameter * 0.023, y: diameter * 0.018)
            TangMirrorSectorLines(count: count)
                .stroke(BookshelfTangPalette.highlight.opacity(0.18), lineWidth: 0.6)
                .rotationEffect(.degrees(Double(rotation)))
            if count > 0 {
                TangMirrorSelectedSector(slot: selectedSlot, count: count)
                    .fill(BookshelfTangPalette.highlight.opacity(reduceTransparency ? 0.11 : 0.055))
                    .rotationEffect(.degrees(Double(rotation)))
            }
            // Two miniatures orbit on the engraved rim, opposite each other.
            // Opacity animates inside the rotated layer so angle normalization at
            // settlement cannot produce a backwards full-circle animation.
            if !reduceMotion {
                TangMechanicalModule(
                    diameter: diameter, rotation: rotation,
                    isSpinning: isSpinning, isDrawing: isDrawing,
                    reduceTransparency: reduceTransparency
                )
                .opacity(isSpinning ? 1 : 0)
                .animation(.easeOut(duration: 0.28), value: isSpinning)
            }
        }
        .frame(width: diameter, height: diameter)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .accessibilityIdentifier("bookshelf.ring.tangMirror")
    }
}

/// The mini mirror has the same grape relief and copper patina as the full wheel.
/// The center button's hit target is separate from this decoration.
struct BookshelfTangMirrorBoss: View {
    let diameter: CGFloat
    var isDrawing = false
    var body: some View {
        Image("BookshelfTangMirror")
            .resizable().scaledToFit()
            .frame(width: diameter, height: diameter)
            .clipShape(Circle())
            .overlay {
                Circle().strokeBorder(BookshelfTangPalette.highlight.opacity(isDrawing ? 1 : 0.75), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.36), radius: 2, y: 2)
            .accessibilityHidden(true)
    }
}

/// The artwork has no baked-in slice count; seams always follow the real 1...9 books.
struct TangMirrorSectorLines: Shape {
    let count: Int
    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard count > 1, rect.size.width > 0, rect.size.height > 0,
              rect.width.isFinite, rect.height.isFinite,
              rect.origin.x.isFinite, rect.origin.y.isFinite else { return path }
        let n = min(count, BookshelfRingGeometry.maximumCount)
        let side = min(rect.width, rect.height)
        let step = CGFloat.pi * 2 / CGFloat(n)
        for index in 0..<n {
            let a = CGFloat(index) * step - .pi / 2 - step / 2
            path.move(to: CGPoint(x: rect.midX + cos(a) * side * 0.09, y: rect.midY + sin(a) * side * 0.09))
            path.addLine(to: CGPoint(x: rect.midX + cos(a) * side * 0.408, y: rect.midY + sin(a) * side * 0.408))
        }
        return path
    }
}

struct TangMirrorSelectedSector: Shape {
    let slot: Int
    let count: Int
    func path(in rect: CGRect) -> Path {
        guard count > 0, rect.size.width > 0, rect.size.height > 0,
              rect.width.isFinite, rect.height.isFinite,
              rect.origin.x.isFinite, rect.origin.y.isFinite else { return Path() }
        let n = min(count, BookshelfRingGeometry.maximumCount)
        let index = min(max(slot, 0), n - 1)
        let side = min(rect.width, rect.height)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let step = 360.0 / Double(n)
        let start = Double(index) * step - 90 - step / 2
        var path = Path()
        path.addArc(center: center, radius: side * 0.408,
                    startAngle: .degrees(start), endAngle: .degrees(start + step), clockwise: false)
        path.addArc(center: center, radius: side * 0.09,
                    startAngle: .degrees(start + step), endAngle: .degrees(start), clockwise: true)
        path.closeSubpath()
        return path
    }
}

struct TangTwinMirrorGeometry {
    static let orbitRatio: CGFloat = 0.447
    static let mirrorRatio: CGFloat = 0.064

    static func centers(diameter: CGFloat, rotation: CGFloat) -> [CGPoint] {
        guard diameter.isFinite, diameter > 0, rotation.isFinite else { return [] }
        return [CGFloat(0), 180].map { phase in
            let angle = (rotation + phase - 90) * .pi / 180
            return CGPoint(x: diameter * 0.5 + cos(angle) * diameter * orbitRatio,
                           y: diameter * 0.5 + sin(angle) * diameter * orbitRatio)
        }
    }
}

private struct TangTwinMirrorOrbit: View {
    let diameter: CGFloat
    let isDrawing: Bool
    var body: some View {
        let centers = TangTwinMirrorGeometry.centers(diameter: diameter, rotation: 0)
        ZStack {
            ForEach(centers.indices, id: \.self) { index in
                let angle = CGFloat(index) * 180 - 90
                Circle().trim(from: 0.02, to: isDrawing ? 0.20 : 0.13)
                    .stroke(AngularGradient(colors: [.clear, BookshelfTangPalette.gold.opacity(0.25),
                                                     BookshelfTangPalette.highlight], center: .center,
                                            startAngle: .degrees(0), endAngle: .degrees(75)),
                            style: StrokeStyle(lineWidth: isDrawing ? 2 : 1.2, lineCap: .round))
                    .padding(diameter * (0.5 - TangTwinMirrorGeometry.orbitRatio))
                    .rotationEffect(.degrees(Double(angle) - 70))
                BookshelfTangMirrorBoss(diameter: diameter * TangTwinMirrorGeometry.mirrorRatio,
                                        isDrawing: isDrawing)
                    .position(centers[index])
            }
        }
        .frame(width: diameter, height: diameter)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Every component is driven by the actual rotor angle. There is no independent
/// timer or perpetual animation, and stopping the wheel stops its mechanism.
enum TangMechanicalKinematics {
    struct Rod: Equatable {
        let start: CGPoint
        let hinge: CGPoint
        let end: CGPoint
    }

    static func rods(diameter: CGFloat, rotation: CGFloat) -> [Rod] {
        guard diameter.isFinite, diameter > 0, rotation.isFinite else { return [] }
        let center = CGPoint(x: diameter / 2, y: diameter / 2)
        return (0..<6).map { index in
            let phase = CGFloat(index) * .pi / 3
            let drive = rotation.truncatingRemainder(dividingBy: 360) * .pi / 180
            let angle = phase - .pi / 2 + drive * 0.58
            let extensionAmount = (sin(drive * 3 + phase) + 1) / 2
            func point(_ radius: CGFloat, _ offset: CGFloat = 0) -> CGPoint {
                CGPoint(x: center.x + cos(angle + offset) * diameter * radius,
                        y: center.y + sin(angle + offset) * diameter * radius)
            }
            return Rod(start: point(0.115),
                       hinge: point(0.245 + extensionAmount * 0.025, sin(drive * 3 + phase) * 0.09),
                       end: point(0.365 + extensionAmount * 0.025))
        }
    }

    static func plateAngle(layer: Int, rotation: CGFloat) -> Double {
        guard rotation.isFinite else { return 0 }
        return Double(rotation) * ([1.0, -0.62, 0.38][min(max(layer, 0), 2)])
    }
}

private struct TangMechanicalModule: View {
    let diameter: CGFloat
    let rotation: CGFloat
    let isSpinning: Bool
    let isDrawing: Bool
    let reduceTransparency: Bool

    private var energy: Double { isDrawing ? 1 : 0.72 }

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { layer in
                let side = diameter * (0.70 + CGFloat(layer) * 0.07)
                ZStack {
                    Circle().stroke(BookshelfTangPalette.bronze.opacity(0.65),
                                    lineWidth: diameter * (layer == 2 ? 0.013 : 0.009))
                    Circle().trim(from: 0.015, to: 0.985)
                        .stroke(AngularGradient(colors: [BookshelfTangPalette.gold.opacity(0.2),
                            BookshelfTangPalette.highlight.opacity(energy),
                            BookshelfTangPalette.bronze.opacity(0.4), BookshelfTangPalette.gold.opacity(0.2)],
                            center: .center), lineWidth: max(1, diameter * 0.003))
                    // Physical registration plates make the counter-rotation visible.
                    ForEach(0..<12, id: \.self) { tooth in
                        RoundedRectangle(cornerRadius: diameter * 0.002)
                            .fill(tooth.isMultiple(of: 3) ? BookshelfTangPalette.highlight : BookshelfTangPalette.gold)
                            .frame(width: diameter * 0.009, height: diameter * 0.016)
                            .offset(y: -side / 2)
                            .rotationEffect(.degrees(Double(tooth) * 30))
                    }
                }
                .frame(width: side, height: side)
                .rotationEffect(.degrees(TangMechanicalKinematics.plateAngle(layer: layer, rotation: rotation)))
                .opacity(reduceTransparency ? 0.8 : 1)
            }
            TangLinkageRods(diameter: diameter, rotation: rotation, energy: energy)
            TangTwinMirrorOrbit(diameter: diameter, isDrawing: isDrawing)
                .rotationEffect(.degrees(Double(rotation) * -0.38))
            Circle()
                .stroke(BookshelfTangPalette.highlight.opacity(isDrawing ? 0.95 : 0.28),
                        style: StrokeStyle(lineWidth: max(1, diameter * 0.006), dash: [3, 5]))
                .frame(width: diameter * 0.19, height: diameter * 0.19)
                .scaleEffect(isDrawing ? 1.18 : 1)
                .opacity(isDrawing ? 1 : 0)
                .animation(.easeOut(duration: 0.32), value: isDrawing)
        }
        .frame(width: diameter, height: diameter)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct TangLinkageRods: View {
    let diameter: CGFloat
    let rotation: CGFloat
    let energy: Double

    var body: some View {
        Canvas { context, _ in
            for mechanism in TangMechanicalKinematics.rods(diameter: diameter, rotation: rotation) {
                var rod = Path()
                rod.move(to: mechanism.start)
                rod.addLine(to: mechanism.hinge)
                rod.addLine(to: mechanism.end)
                context.stroke(rod, with: .color(.black.opacity(0.48)),
                               style: StrokeStyle(lineWidth: max(2, diameter * 0.009), lineCap: .round, lineJoin: .round))
                context.stroke(rod, with: .color(BookshelfTangPalette.gold.opacity(0.26 + energy * 0.38)),
                               style: StrokeStyle(lineWidth: max(1, diameter * 0.004), lineCap: .round, lineJoin: .round))
                for joint in [mechanism.hinge, mechanism.end] {
                    let jointSize = diameter * 0.014
                    let circle = Path(ellipseIn: CGRect(x: joint.x - jointSize / 2, y: joint.y - jointSize / 2,
                                                       width: jointSize, height: jointSize))
                    context.fill(circle, with: .color(BookshelfTangPalette.highlight.opacity(0.8)))
                    context.stroke(circle, with: .color(BookshelfTangPalette.bronze), lineWidth: 1)
                }
            }
        }
        .frame(width: diameter, height: diameter)
        .allowsHitTesting(false)
    }
}
