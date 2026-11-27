#if os(macOS)
import AVFoundation
import CodaObjC
import Testing

/// The engine leans on `CodaCatchException` to survive AVFAudio's
/// NSExceptions; prove it really catches one rather than trusting the shim.
@Suite struct CodaObjCTests {
    @Test func catchesAnAVFAudioException() {
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        // Never attached: AVFAudio's "required condition is false" raise.
        let exception = CodaCatchException {
            engine.connect(player, to: engine.mainMixerNode, format: nil)
        }
        #expect(exception?.name.rawValue == "com.apple.coreaudio.avfaudio")
    }

    @Test func returnsNilWhenNothingIsRaised() {
        var ran = false
        #expect(CodaCatchException { ran = true } == nil)
        #expect(ran)
    }
}
#endif
