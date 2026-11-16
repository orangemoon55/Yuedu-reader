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

/// The miniature grape mirror remains upright and is the shelf draw control.
/// The identifier is retained so existing navigation/UI automation still finds it.
struct BookshelfRingCenterBadge: View {
    let diameter: CGFloat
    var isDrawing = false
    var onDraw: (() -> Void)? = nil

    var body: some View {
        Group {
            if let onDraw {
                Button(action: onDraw) {
                    badge
                        .frame(width: max(44, diameter), height: max(44, diameter))
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(isDrawing)
                .accessibilityLabel(localized(isDrawing ? "抽籤中" : "書架抽籤"))
                .accessibilityHint(localized(isDrawing ? "正在旋轉" : "隨機推薦一本書"))
            } else {
                badge
            }
        }
        .frame(width: diameter, height: diameter)
        .accessibilityIdentifier("bookshelf.ring.centerIcon")
    }

    private var badge: some View {
        BookshelfTangMirrorBoss(diameter: diameter, isDrawing: isDrawing)
    }
}
