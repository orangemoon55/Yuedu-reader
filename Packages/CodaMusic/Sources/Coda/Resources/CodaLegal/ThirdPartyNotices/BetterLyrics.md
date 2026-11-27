# BetterLyrics visual reference

Source: https://github.com/jayfunc/BetterLyrics
Reviewed commit: `0d3e6e26d9e6cb217ead7c6cf5ff1d85de1a3f2f`

BetterLyrics' `FluidBackgroundRenderer`, fluid shader, and lyric renderer were reviewed as visual references for artwork-colored flowing light, syllable highlighting and long-note glow. Kumone's `NowPlayingFluidBackground` is an independent native Core Animation gradient implementation for iPadOS 16 and macOS, using the existing artwork palette; no BetterLyrics source or shader is copied. Its motion clock stops on pause, inactive scenes, hidden windows, and Reduced Motion. Its gradient layers now advance with a native display link, independently of SwiftUI presentation scheduling. Real 60–250 Hz bass and 250–800 Hz lower-mid levels from Kumone’s existing AudioSpectrum feed a smoothed onset envelope, driving restrained gradient expansion and a beat vignette; no synthetic beat is used when samples are unavailable.
