import SwiftUI
import Testing
import UIKit
@testable import yuedu_app

@MainActor
struct VideoHeroActionLayoutTests {
    @Test("Stacked video actions do not consume the poster's height", arguments: [false, true])
    func stackedActions(hasEpisodes: Bool) {
        let screenWidth: CGFloat = 393
        let width = screenWidth - 2 * DSLayout.videoDetailMargin
        let posterHeight = screenWidth / DSLayout.videoPosterAspectRatio
        let expected = 2 * DSLayout.videoPlayButtonHeight + DSSpacing.md
        let measured = actionHeight(width: width, offeredHeight: posterHeight, hasEpisodes: hasEpisodes)
        #expect(abs(measured - expected) < 1)
    }

    @Test("Video actions stay on one row when there is room", arguments: [false, true])
    func sideBySideActions(hasEpisodes: Bool) {
        let measured = actionHeight(width: 600, offeredHeight: 600, hasEpisodes: hasEpisodes)
        #expect(abs(measured - DSLayout.videoPlayButtonHeight) < 1)
    }

    private func actionHeight(width: CGFloat, offeredHeight: CGFloat, hasEpisodes: Bool) -> CGFloat {
        let actions = VideoHeroActions {
            // A long episode title can make Play this wide and force the stacked layout.
            Color.clear.frame(width: DSLayout.videoPlayButtonMaxWidth, height: DSLayout.videoPlayButtonHeight)
        } buttons: {
            ForEach(0..<(hasEpisodes ? 3 : 2), id: \.self) { _ in
                Button {} label: {
                    Image(systemName: "plus").modifier(VideoHeroCapsuleIcon())
                }
            }
        }
        let host = UIHostingController(rootView: actions.environment(\.colorScheme, .dark))
        return host.sizeThatFits(in: CGSize(width: width, height: offeredHeight)).height
    }
}
