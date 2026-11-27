import Foundation
import Testing
@testable import yuedu_app

@Suite("Media preferences")
struct MediaPreferencesTests {
    @Test("isolated defaults expose the agreed values")
    func defaults() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(MediaPreferences.musicDefaultRate(in: defaults) == 1)
        #expect(MediaPreferences.musicResumeEnabled(in: defaults))
        #expect(MediaPreferences.musicLoopCurrent(in: defaults) == false)
        #expect(MediaPreferences.homeShowsContinue(in: defaults))
        #expect(MediaPreferences.homeShowsHero(in: defaults))
        #expect(MediaPreferences.posterColumns(in: defaults) == 3)
        #expect(MediaPreferences.musicArtworkSquare(in: defaults))
    }

    @Test("setters persist every preference without using standard defaults")
    func persistenceAndIsolation() throws {
        let (first, firstName) = try makeDefaults()
        let (second, secondName) = try makeDefaults()
        defer {
            first.removePersistentDomain(forName: firstName)
            second.removePersistentDomain(forName: secondName)
        }

        MediaPreferences.setMusicDefaultRate(0.75, in: first)
        MediaPreferences.setMusicResumeEnabled(false, in: first)
        MediaPreferences.setMusicLoopCurrent(true, in: first)
        MediaPreferences.setHomeShowsContinue(false, in: first)
        MediaPreferences.setHomeShowsHero(false, in: first)
        MediaPreferences.setPosterColumns(5, in: first)
        MediaPreferences.setMusicArtworkSquare(false, in: first)

        #expect(MediaPreferences.musicDefaultRate(in: first) == 0.75)
        #expect(MediaPreferences.musicResumeEnabled(in: first) == false)
        #expect(MediaPreferences.musicLoopCurrent(in: first))
        #expect(MediaPreferences.homeShowsContinue(in: first) == false)
        #expect(MediaPreferences.homeShowsHero(in: first) == false)
        #expect(MediaPreferences.posterColumns(in: first) == 5)
        #expect(MediaPreferences.musicArtworkSquare(in: first) == false)

        // A second suite remains at defaults, proving the helpers do not share state.
        #expect(MediaPreferences.posterColumns(in: second) == 3)
    }

    @Test("rates and poster columns clamp at their supported bounds")
    func clamping() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        MediaPreferences.setMusicDefaultRate(4, in: defaults)
        MediaPreferences.setPosterColumns(1, in: defaults)
        #expect(MediaPreferences.musicDefaultRate(in: defaults) == 3)
        #expect(MediaPreferences.posterColumns(in: defaults) == 2)

        MediaPreferences.setMusicDefaultRate(-2, in: defaults)
        MediaPreferences.setPosterColumns(9, in: defaults)
        #expect(MediaPreferences.musicDefaultRate(in: defaults) == 0.5)
        #expect(MediaPreferences.posterColumns(in: defaults) == 5)
    }

    @Test("invalid stored values fall back instead of leaking into the UI")
    func invalidValues() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(Float.nan, forKey: MediaPreferences.musicDefaultRateKey)
        defaults.set("three", forKey: MediaPreferences.posterColumnsKey)
        defaults.set(1, forKey: MediaPreferences.musicLoopCurrentKey)

        #expect(MediaPreferences.musicDefaultRate(in: defaults) == 1)
        #expect(MediaPreferences.posterColumns(in: defaults) == 3)
        #expect(MediaPreferences.musicLoopCurrent(in: defaults) == false)
    }

    private func makeDefaults() throws -> (UserDefaults, String) {
        let suiteName = "MediaPreferencesTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }
}
