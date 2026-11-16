import SwiftUI

/// Decorative only: the book annulus ends at 0.465d, the gear occupies its outer rim.
struct BookshelfCyberGear: View {
    let diameter: CGFloat
    let rotation: CGFloat
    let colorScheme: ColorScheme
    var isSpinning = false
    var selectedSlot = 0
    var isDrawing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var pulse: Double = 0

    private struct Event: Equatable {
        let slot: Int
        let spinning: Bool
        let drawing: Bool
    }

    private var crimson: Color { Color(red: 0.88, green: 0.075, blue: 0.16) }
    private var magenta: Color { Color(red: 0.92, green: 0.16, blue: 0.68) }
    private var violet: Color { Color(red: 0.48, green: 0.18, blue: 0.77) }
    private var mutedGold: Color { Color(red: 0.72, green: 0.57, blue: 0.30) }

    var body: some View {
        let direction = rotation < 0 ? -1.0 : 1.0
        let trailAngle = Double(rotation * 0.72) - direction * 34
        ZStack {
            CyberGearShape()
                .fill(LinearGradient(colors: colorScheme == .dark
                    ? [Color(red: 0.22, green: 0.20, blue: 0.23), Color(red: 0.035, green: 0.025, blue: 0.04), Color(red: 0.16, green: 0.055, blue: 0.075)]
                    : [Color(red: 0.34, green: 0.29, blue: 0.29), Color(red: 0.11, green: 0.075, blue: 0.09), Color(red: 0.29, green: 0.10, blue: 0.13)],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay { CyberGearShape().fill(DSColor.surface.opacity(colorScheme == .dark ? 0.045 : 0.10)) }
                .overlay {
                    CyberGearShape().stroke(mutedGold.opacity(0.72), lineWidth: max(0.45, diameter * 0.001))
                }
                .rotationEffect(.degrees(Double(rotation)))
            CyberGearFacets()
                .fill(LinearGradient(colors: [crimson.opacity(0.88), magenta.opacity(0.46), Color.black.opacity(0.3)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay { CyberGearFacets().stroke(Color(red: 1, green: 0.34, blue: 0.31).opacity(0.62), lineWidth: max(0.5, diameter * 0.0013)) }
                .rotationEffect(.degrees(Double(rotation)))
            Circle().stroke(Color.black.opacity(0.74), lineWidth: max(1, diameter * 0.005))
                .padding(diameter * 0.034)
            Circle().stroke(mutedGold.opacity(0.88), lineWidth: max(0.7, diameter * 0.0018))
                .padding(diameter * 0.029)
            Circle().stroke(crimson.opacity(isDrawing ? 0.95 : 0.72), lineWidth: max(0.8, diameter * 0.0026))
                .padding(diameter * 0.026)
            Circle().stroke(violet.opacity(isDrawing ? 0.88 : 0.56), lineWidth: max(0.7, diameter * 0.0018))
                .padding(diameter * 0.022)
            CyberGearTicks()
                .stroke(LinearGradient(colors: [mutedGold, crimson.opacity(0.84)], startPoint: .top, endPoint: .bottom),
                        lineWidth: max(0.7, diameter * 0.0018))
                .opacity(0.62 + pulse * 0.34)
                .rotationEffect(.degrees(Double(rotation)))
            Circle().trim(from: 0.04, to: 0.21)
                .stroke(AngularGradient(colors: [crimson.opacity(0.18), crimson, magenta, violet.opacity(0.8)], center: .center),
                        style: StrokeStyle(lineWidth: max(1.4, diameter * 0.006), lineCap: .round))
                .padding(diameter * 0.019)
                .rotationEffect(.degrees(trailAngle))
                .opacity(isSpinning && !reduceMotion ? 0.98 : (isDrawing ? 0.72 : 0.22))
                .shadow(color: reduceTransparency || reduceMotion ? .clear : magenta.opacity(isSpinning ? 0.76 : (isDrawing ? 0.38 : 0.12)),
                        radius: isSpinning ? 4 : 1.2)
            Circle().trim(from: 0.10, to: 0.205)
                .stroke(LinearGradient(colors: [crimson.opacity(0.08), magenta, Color.white.opacity(0.76)],
                                       startPoint: .leading, endPoint: .trailing),
                        style: StrokeStyle(lineWidth: max(1.2, diameter * 0.004), lineCap: .round))
                .padding(diameter * 0.014)
                .rotationEffect(.degrees(trailAngle - direction * 20))
                .opacity(isSpinning && !reduceMotion ? 0.86 : 0)
                .shadow(color: reduceTransparency || reduceMotion ? .clear : crimson.opacity(0.7), radius: 3)
            Circle().trim(from: 0.47, to: 0.56)
                .stroke(AngularGradient(colors: [mutedGold.opacity(0.12), mutedGold, magenta.opacity(0.88)], center: .center),
                        style: StrokeStyle(lineWidth: max(1, diameter * 0.003), lineCap: .round))
                .padding(diameter * 0.019)
                .rotationEffect(.degrees(Double(-rotation * 0.35)))
                .opacity(isDrawing ? 0.95 : 0.54)
            Circle().stroke(magenta.opacity(pulse * 0.78), lineWidth: max(0.7, diameter * 0.003))
                .padding(diameter * (0.027 - pulse * 0.004))
                .shadow(color: reduceTransparency || reduceMotion ? .clear : magenta.opacity(pulse * 0.6), radius: 2)
        }
        .frame(width: diameter, height: diameter)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .accessibilityIdentifier("bookshelf.ring.cyberGear")
        .animation(.easeOut(duration: reduceMotion ? 0 : 0.3), value: isSpinning)
        .task(id: Event(slot: selectedSlot, spinning: isSpinning, drawing: isDrawing)) {
            guard !reduceMotion else { pulse = 0; return }
            withAnimation(.easeOut(duration: 0.07)) { pulse = 1 }
            do { try await Task.sleep(for: .milliseconds(isSpinning ? 90 : 140)) }
            catch { return }
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.28)) { pulse = 0 }
        }
    }
}

struct CyberGearShape: Shape {
    static let toothCount = 28
    static let innerRadius: CGFloat = 0.466
    static let rootRadius: CGFloat = 0.468
    static let tipRadius: CGFloat = 0.497

    private static let unitPath: Path = {
        var path = Path()
        let step = 2 * CGFloat.pi / CGFloat(toothCount)
        let vertices: [(CGFloat, CGFloat)] = [
            (0, rootRadius), (0.18, rootRadius), (0.29, 0.477),
            (0.36, tipRadius), (0.65, tipRadius), (0.73, 0.477), (0.82, rootRadius)
        ]
        for tooth in 0..<toothCount {
            for (fraction, radius) in vertices {
                let angle = (CGFloat(tooth) + fraction) * step - .pi / 2
                let point = CGPoint(x: 0.5 + cos(angle) * radius, y: 0.5 + sin(angle) * radius)
                if tooth == 0 && fraction == 0 { path.move(to: point) }
                else { path.addLine(to: point) }
            }
        }
        path.closeSubpath()
        path.move(to: CGPoint(x: 0.5 + innerRadius, y: 0.5))
        path.addArc(center: CGPoint(x: 0.5, y: 0.5), radius: innerRadius,
                    startAngle: .degrees(360), endAngle: .degrees(180), clockwise: true)
        path.addArc(center: CGPoint(x: 0.5, y: 0.5), radius: innerRadius,
                    startAngle: .degrees(180), endAngle: .degrees(0), clockwise: true)
        path.closeSubpath()
        return path
    }()

    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        guard rect.size.width > 0, rect.size.height > 0,
              rect.origin.x.isFinite, rect.origin.y.isFinite,
              rect.size.width.isFinite, rect.size.height.isFinite,
              side.isFinite, side > 0 else { return Path() }
        return Self.unitPath.applying(CGAffineTransform(a: side, b: 0, c: 0, d: side,
                                                      tx: rect.midX - side / 2, ty: rect.midY - side / 2))
    }
}

private struct CyberGearFacets: Shape {
    private static let unitPath: Path = {
        var path = Path()
        let step = 2 * CGFloat.pi / CGFloat(CyberGearShape.toothCount)
        let vertices: [(CGFloat, CGFloat)] = [
            (0.18, CyberGearShape.rootRadius), (0.36, CyberGearShape.tipRadius),
            (0.50, CyberGearShape.tipRadius), (0.50, CyberGearShape.rootRadius + 0.004)
        ]
        for tooth in 0..<CyberGearShape.toothCount {
            for (fraction, radius) in vertices {
                let angle = (CGFloat(tooth) + fraction) * step - .pi / 2
                let point = CGPoint(x: 0.5 + cos(angle) * radius, y: 0.5 + sin(angle) * radius)
                if fraction == 0.18 { path.move(to: point) } else { path.addLine(to: point) }
            }
            path.closeSubpath()
        }
        return path
    }()

    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        guard rect.size.width > 0, rect.size.height > 0,
              rect.origin.x.isFinite, rect.origin.y.isFinite,
              rect.size.width.isFinite, rect.size.height.isFinite,
              side.isFinite, side > 0 else { return Path() }
        return Self.unitPath.applying(CGAffineTransform(a: side, b: 0, c: 0, d: side,
                                                      tx: rect.midX - side / 2, ty: rect.midY - side / 2))
    }
}

private struct CyberGearTicks: Shape {
    private static let unitPath: Path = {
        var path = Path()
        for index in 0..<64 {
            let angle = CGFloat(index) * .pi / 32
            let inner: CGFloat = index.isMultiple(of: 4) ? 0.472 : 0.476
            path.move(to: CGPoint(x: 0.5 + cos(angle) * inner, y: 0.5 + sin(angle) * inner))
            path.addLine(to: CGPoint(x: 0.5 + cos(angle) * 0.48, y: 0.5 + sin(angle) * 0.48))
        }
        return path
    }()

    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        guard rect.size.width > 0, rect.size.height > 0,
              rect.origin.x.isFinite, rect.origin.y.isFinite,
              rect.size.width.isFinite, rect.size.height.isFinite,
              side.isFinite, side > 0 else { return Path() }
        return Self.unitPath.applying(CGAffineTransform(a: side, b: 0, c: 0, d: side,
                                                      tx: rect.midX - side / 2, ty: rect.midY - side / 2))
    }
}
