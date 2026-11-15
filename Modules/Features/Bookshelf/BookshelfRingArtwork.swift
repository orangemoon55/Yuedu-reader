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

    var body: some View {
        Image("YueduAppIcon")
            .resizable()
            .scaledToFill()
            .frame(width: diameter, height: diameter)
            .background(Color(red: 0.09, green: 0.15, blue: 0.25))
            .clipShape(Circle())
            .overlay { Circle().stroke(Color.white.opacity(0.75), lineWidth: 1) }
            .shadow(color: .black.opacity(0.16), radius: 2, y: 1)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .accessibilityIdentifier("bookshelf.ring.centerIcon")
    }
}
