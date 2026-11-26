import Testing
@testable import yuedu_app

struct MusicPlaybackCapsuleTests {
    @Test func loadedSessionRemainsReachableEvenWhenPaused() {
        // Visibility intentionally does not depend on isPlaying: dismissing a player or
        // pausing a song must leave the way back into that same queue on every root tab.
        #expect(MusicPlaybackCapsulePolicy.isPresented(hasTrack: true, musicOwnsSession: true,
                                                     tabBarHidden: false, keyboardVisible: false))
    }

    @Test func emptyStoppedOrAnotherAudioOwnerNeverShowsMusicCapsule() {
        #expect(!MusicPlaybackCapsulePolicy.isPresented(hasTrack: false, musicOwnsSession: true,
                                                      tabBarHidden: false, keyboardVisible: false))
        #expect(!MusicPlaybackCapsulePolicy.isPresented(hasTrack: true, musicOwnsSession: false,
                                                      tabBarHidden: false, keyboardVisible: false))
    }

    @Test func readerAndKeyboardRetainTheirFullInteractionArea() {
        #expect(!MusicPlaybackCapsulePolicy.isPresented(hasTrack: true, musicOwnsSession: true,
                                                      tabBarHidden: true, keyboardVisible: false))
        #expect(!MusicPlaybackCapsulePolicy.isPresented(hasTrack: true, musicOwnsSession: true,
                                                      tabBarHidden: false, keyboardVisible: true))
    }

    @Test func policyExhaustivelyRequiresAllFourConditions() {
        for track in [false, true] {
            for owner in [false, true] {
                for hidden in [false, true] {
                    for keyboard in [false, true] {
                        #expect(MusicPlaybackCapsulePolicy.isPresented(hasTrack: track, musicOwnsSession: owner,
                            tabBarHidden: hidden, keyboardVisible: keyboard) == (track && owner && !hidden && !keyboard))
                    }
                }
            }
        }
    }
}
