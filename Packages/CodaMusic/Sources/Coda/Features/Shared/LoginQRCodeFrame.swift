import SwiftUI

/// The original NetEase login QR frame, shared by every account provider.
struct LoginQRCodeFrame<Overlay: View>: View {
    let image: PlatformImage?
    var obscuresImage = false
    @ViewBuilder var overlay: () -> Overlay

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.white)
                .frame(width: 208, height: 208)
                .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
            if let image {
                Image(platformImage: image)
                    .resizable()
                    .interpolation(.none)
                    .frame(width: 180, height: 180)
                    .blur(radius: obscuresImage ? 3 : 0)
            } else {
                ProgressView()
            }
            overlay()
        }
    }
}
