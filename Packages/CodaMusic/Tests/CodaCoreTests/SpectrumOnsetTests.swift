import Foundation
import Testing
@testable import CodaCore

@Suite struct SpectrumOnsetTests {
    @Test func silenceAndRefractoryPeriodRejectFalseAttacks() {
        var detector = SpectrumOnsetDetector()
        #expect(detector.advance(flux: 0, audible: false, delta: 0.012) == 0)
        #expect(detector.advance(flux: 0.4, audible: true, delta: 0.012) > 0)
        #expect(detector.advance(flux: 1, audible: true, delta: 0.012) == 0)
        for _ in 0..<100 { _ = detector.advance(flux: 0, audible: true, delta: 0.012) }
        #expect(detector.advance(flux: 1, audible: false, delta: 0.012) == 0)
    }

    @Test func peaksSurviveDisplayGapsButExpireAndAreConsumedOnce() {
        let mailbox = SpectrumOnsetMailbox()
        #expect(mailbox.publish(bass: 0.9, melody: 0.2, now: 1))
        #expect(mailbox.publish(bass: 0.1, melody: 0.8, now: 1.01))
        let peaks = mailbox.take(now: 1.03)
        #expect(peaks.bass == 0.9 && peaks.melody == 0.8)
        #expect(mailbox.take(now: 1.04).bass == 0)
        #expect(mailbox.publish(bass: 1, melody: 1, now: 2))
        for i in 1...20 {
            #expect(mailbox.publish(bass: 0, melody: 0, now: 2 + Double(i) * 0.01))
        }
        #expect(mailbox.take(now: 2.21).bass == 0)
    }
}
