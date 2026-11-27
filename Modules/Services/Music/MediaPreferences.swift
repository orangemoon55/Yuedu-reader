import CoreFoundation
import Foundation

/// User-facing preferences for the native music surfaces.
///
/// The computed properties intentionally read `UserDefaults.standard` on every access. This
/// keeps playback and home code in sync with a setting changed while the app is running. The
/// `in:` overloads make the same rules usable with isolated defaults in tests.
enum MediaPreferences {
    static let musicDefaultRateKey = "media.music.defaultRate"
    static let musicResumeEnabledKey = "media.music.resumeEnabled"
    static let musicLoopCurrentKey = "media.music.loopCurrent"
    static let homeShowsContinueKey = "media.home.showsContinue"
    static let homeShowsHeroKey = "media.home.showsHero"
    static let posterColumnsKey = "media.home.posterColumns"
    static let musicArtworkSquareKey = "media.music.artworkSquare"

    private static let defaultRate: Float = 1
    private static let defaultMusicResumeEnabled = true
    private static let defaultMusicLoopCurrent = false
    private static let defaultHomeShowsContinue = true
    private static let defaultHomeShowsHero = true
    private static let defaultPosterColumns = 3
    private static let defaultMusicArtworkSquare = true

    static var musicDefaultRate: Float {
        get { musicDefaultRate(in: .standard) }
        set { setMusicDefaultRate(newValue, in: .standard) }
    }

    static var musicResumeEnabled: Bool {
        get { musicResumeEnabled(in: .standard) }
        set { setMusicResumeEnabled(newValue, in: .standard) }
    }

    static var musicLoopCurrent: Bool {
        get { musicLoopCurrent(in: .standard) }
        set { setMusicLoopCurrent(newValue, in: .standard) }
    }

    static var homeShowsContinue: Bool {
        get { homeShowsContinue(in: .standard) }
        set { setHomeShowsContinue(newValue, in: .standard) }
    }

    static var homeShowsHero: Bool {
        get { homeShowsHero(in: .standard) }
        set { setHomeShowsHero(newValue, in: .standard) }
    }

    static var posterColumns: Int {
        get { posterColumns(in: .standard) }
        set { setPosterColumns(newValue, in: .standard) }
    }

    static var musicArtworkSquare: Bool {
        get { musicArtworkSquare(in: .standard) }
        set { setMusicArtworkSquare(newValue, in: .standard) }
    }

    static func musicDefaultRate(in defaults: UserDefaults) -> Float {
        clampedRate(number(forKey: musicDefaultRateKey, in: defaults))
    }

    static func setMusicDefaultRate(_ value: Float, in defaults: UserDefaults) {
        defaults.set(clampedRate(value), forKey: musicDefaultRateKey)
    }

    static func musicResumeEnabled(in defaults: UserDefaults) -> Bool {
        bool(forKey: musicResumeEnabledKey, in: defaults, default: defaultMusicResumeEnabled)
    }

    static func setMusicResumeEnabled(_ value: Bool, in defaults: UserDefaults) {
        defaults.set(value, forKey: musicResumeEnabledKey)
    }

    static func musicLoopCurrent(in defaults: UserDefaults) -> Bool {
        bool(forKey: musicLoopCurrentKey, in: defaults, default: defaultMusicLoopCurrent)
    }

    static func setMusicLoopCurrent(_ value: Bool, in defaults: UserDefaults) {
        defaults.set(value, forKey: musicLoopCurrentKey)
    }

    static func homeShowsContinue(in defaults: UserDefaults) -> Bool {
        bool(forKey: homeShowsContinueKey, in: defaults, default: defaultHomeShowsContinue)
    }

    static func setHomeShowsContinue(_ value: Bool, in defaults: UserDefaults) {
        defaults.set(value, forKey: homeShowsContinueKey)
    }

    static func homeShowsHero(in defaults: UserDefaults) -> Bool {
        bool(forKey: homeShowsHeroKey, in: defaults, default: defaultHomeShowsHero)
    }

    static func setHomeShowsHero(_ value: Bool, in defaults: UserDefaults) {
        defaults.set(value, forKey: homeShowsHeroKey)
    }

    static func posterColumns(in defaults: UserDefaults) -> Int {
        let value = number(forKey: posterColumnsKey, in: defaults)
        guard value.isFinite, value.rounded() == value else { return defaultPosterColumns }
        if value <= 2 { return 2 }
        if value >= 5 { return 5 }
        return Int(value)
    }

    static func setPosterColumns(_ value: Int, in defaults: UserDefaults) {
        defaults.set(min(max(value, 2), 5), forKey: posterColumnsKey)
    }

    static func musicArtworkSquare(in defaults: UserDefaults) -> Bool {
        bool(forKey: musicArtworkSquareKey, in: defaults, default: defaultMusicArtworkSquare)
    }

    static func setMusicArtworkSquare(_ value: Bool, in defaults: UserDefaults) {
        defaults.set(value, forKey: musicArtworkSquareKey)
    }

    private static func number(forKey key: String, in defaults: UserDefaults) -> Double {
        guard let raw = defaults.object(forKey: key) as? NSNumber,
              String(cString: raw.objCType) != "c" else { return .nan }
        return raw.doubleValue
    }

    private static func bool(forKey key: String, in defaults: UserDefaults, default fallback: Bool) -> Bool {
        guard let number = defaults.object(forKey: key) as? NSNumber,
              String(cString: number.objCType) == "c" else { return fallback }
        return number.boolValue
    }

    private static func clampedRate(_ value: Float) -> Float {
        guard value.isFinite else { return defaultRate }
        return min(max(value, 0.5), 3)
    }

    private static func clampedRate(_ value: Double) -> Float {
        guard value.isFinite else { return defaultRate }
        if value <= 0.5 { return 0.5 }
        if value >= 3 { return 3 }
        return Float(value)
    }
}
