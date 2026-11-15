import SwiftUI

/// Decorative only: the book annulus ends at 0.465d, the gear occupies its outer rim.
struct BookshelfCyberGear: View {
    let diameter: CGFloat
    let rotation: CGFloat
    let colorScheme: ColorScheme
    var isSpinning = false
    var selectedSlot = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var pulse: Double = 0

    private struct Event: Equatable {
        let slot: Int
        let spinning: Bool
    }

    private var cyan: Color { Color(red: 0.10, green: 0.84, blue: 0.96) }
    private var blue: Color { Color(red: 0.20, green: 0.38, blue: 1) }

    var body: some View {
        ZStack {
            CyberGearShape()
                .fill(LinearGradient(colors: colorScheme == .dark
                    ? [Color(white: 0.32), Color(white: 0.07), Color(white: 0.23)]
                    : [Color(white: 0.32), Color(white: 0.13), Color(white: 0.46)],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay {
                    CyberGearShape().stroke(Color.white.opacity(0.38), lineWidth: 0.6)
                }
                .rotationEffect(.degrees(Double(rotation)))
            Circle().stroke(Color.black.opacity(0.45), lineWidth: max(1, diameter * 0.005))
                .padding(diameter * 0.033)
            Circle().stroke(cyan.opacity(isSpinning ? 0.9 : 0.45), lineWidth: max(0.8, diameter * 0.0028))
                .padding(diameter * 0.03)
                .shadow(color: cyan.opacity(reduceTransparency ? 0 : (isSpinning ? 0.65 : 0.18)),
                        radius: isSpinning ? 3 : 1)
            CyberGearTicks()
                .stroke(cyan.opacity(0.55 + pulse * 0.4), lineWidth: max(0.7, diameter * 0.002))
                .rotationEffect(.degrees(Double(rotation)))
            Circle().trim(from: 0.02, to: 0.18)
                .stroke(AngularGradient(colors: [cyan.opacity(0.1), cyan, blue], center: .center),
                        style: StrokeStyle(lineWidth: max(1.3, diameter * 0.004), lineCap: .round))
                .padding(diameter * 0.019)
                .rotationEffect(.degrees(reduceMotion ? -90 : Double(rotation * 0.55) - 90))
                .opacity(isSpinning ? 1 : 0.32)
                .shadow(color: cyan.opacity(reduceTransparency ? 0 : 0.55), radius: 2)
            Circle().trim(from: 0.48, to: 0.57)
                .stroke(Color(red: 0.61, green: 0.36, blue: 0.94).opacity(0.75),
                        style: StrokeStyle(lineWidth: max(1, diameter * 0.003), lineCap: .round))
                .padding(diameter * 0.019)
                .rotationEffect(.degrees(reduceMotion ? 0 : Double(-rotation * 0.35)))
            Circle().stroke(cyan.opacity(pulse * 0.75), lineWidth: max(0.7, diameter * 0.003))
                .padding(diameter * (0.027 - pulse * 0.004))
        }
        .frame(width: diameter, height: diameter)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .accessibilityIdentifier("bookshelf.ring.cyberGear")
        .animation(.easeOut(duration: reduceMotion ? 0 : 0.18), value: isSpinning)
        .task(id: Event(slot: selectedSlot, spinning: isSpinning)) {
            guard !reduceMotion else { pulse = 0; return }
            // Finite detent/settlement flash, cancelled when another detent arrives.
            withAnimation(.easeOut(duration: 0.07)) { pulse = 1 }
            do { try await Task.sleep(for: .milliseconds(isSpinning ? 90 : 140)) }
            catch { return }
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.28)) { pulse = 0 }
        }
    }
}

struct CyberGearShape: Shape {
    static let toothCount = 32
    static let innerRadius: CGFloat = 0.464
    static let rootRadius: CGFloat = 0.482
    static let tipRadius: CGFloat = 0.496

    private static let unitPath: Path = {
        var path = Path()
        let step = 2 * CGFloat.pi / CGFloat(toothCount)
        let vertices: [(CGFloat, CGFloat)] = [
            (0, rootRadius), (0.19, rootRadius), (0.29, tipRadius),
            (0.69, tipRadius), (0.81, rootRadius)
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
