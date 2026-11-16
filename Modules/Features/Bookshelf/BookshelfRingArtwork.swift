import SwiftUI
import UIKit

/// The photo is fitted around the sector's centre and counter-rotated so its
/// cover stays upright while the rotor and the clipping sector turn together.
struct BookshelfRingSectorArtwork: View {
    let image: UIImage?
    let slot: Int
    let count: Int
    let diameter: CGFloat
    let rotation: CGFloat
    let isSelected: Bool
    let colorScheme: ColorScheme

    var body: some View {
        let shape = BookshelfRingSector(slot: slot, count: count)
        let step = BookshelfRingGeometry.step(count: count)
        let radians = (CGFloat(slot) * step - 90) * .pi / 180
        let radius = count == 1 ? 0 : diameter * 0.265
        ZStack {
            // Always an opaque backing: a themed illustration cannot leak into
            // the cover and change its colour, even before a bitmap arrives.
            Color(uiColor: colorScheme == .dark ? .secondarySystemBackground : .systemBackground)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: diameter * 1.12, height: diameter * 1.12)
                    .clipped()
                    .rotationEffect(.degrees(-Double(rotation)))
                    .position(x: diameter / 2 + cos(radians) * radius,
                              y: diameter / 2 + sin(radians) * radius)
                Color(uiColor: colorScheme == .dark ? .black : .white)
                    .opacity(colorScheme == .dark ? 0.36 : 0.32)
            }
        }
        .frame(width: diameter, height: diameter)
        .clipShape(shape)
        .overlay {
            shape.stroke(isSelected ? Color.white.opacity(0.8) : Color.primary.opacity(0.12),
                         lineWidth: isSelected ? 1.5 : 0.6)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The centre is an opaque brand badge, independent of rotor angle and book tint.
struct BookshelfRingCenterBadge: View {
    let diameter: CGFloat
    let isDrawing: Bool
    var onDraw: (() -> Void)? = nil

    var body: some View {
        Group {
            if let onDraw {
                Button(action: onDraw) {
                    ZStack {
                        badge
                        if isDrawing {
                            ProgressView()
                                .tint(.white)
                                .padding(8)
                                .background(.ultraThinMaterial, in: Circle())
                                .accessibilityHidden(true)
                        } else {
                            Image(systemName: "sparkles")
                                .font(.system(size: diameter * 0.18, weight: .bold))
                                .foregroundStyle(.white)
                                .shadow(color: .black.opacity(0.75), radius: 3, x: 0, y: 1)
                                .frame(width: diameter * 0.38, height: diameter * 0.38)
                                .background(Color.accentColor.opacity(0.78), in: Circle())
                                .offset(x: diameter * 0.28, y: diameter * 0.28)
                                .accessibilityHidden(true)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(isDrawing)
                .accessibilityLabel(localized(isDrawing ? "抽签中" : "书架抽签"))
                .accessibilityHint(localized(isDrawing ? "正在旋转" : "随机推荐一本书"))
            } else {
                badge
            }
        }
        .frame(width: diameter, height: diameter)
        .accessibilityIdentifier("bookshelf.ring.centerIcon")
    }

    private var badge: some View {
        Image("YueduAppIcon")
            .resizable()
            .scaledToFill()
            .frame(width: diameter, height: diameter)
            .background(Color(red: 0.09, green: 0.15, blue: 0.25))
            .clipShape(Circle())
            .overlay { Circle().stroke(Color.white.opacity(0.75), lineWidth: 1) }
            .shadow(color: .black.opacity(0.16), radius: 2, y: 1)
            .accessibilityHidden(true)
    }
}
