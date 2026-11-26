# Yingxia source reuse in the Readcc media-refactor candidate

Date: 2026-11-26 (+08:00). Upstream: jo32/tvbox-silicon, pinned commit `a6bcc00bbbdbd7c6af7b7223ca2fa6018d6d685c`. Upstream originals are unchanged. This document describes actual source changes, not a completed whole-application transplant or verified native playback.

## Directly reused implementation

| Upstream | Readcc adaptation and production call |
| --- | --- |
| `Sources/TVCore/PlaybackResolution.swift:3-33` | `YingxiaPlaybackChoices.swift`: original single/alternating/FongMi URL-object algorithm, adapted from JSONValue to Foundation values. `CatVodContentParser.playbackChoices` calls it in the real response path. Position and all valid alternatives are retained; the existing stream factory opens the first ordered choice through source-owned URL resolution. A player-side alternative-quality UI and upstream web sniffer are NOT implemented here. |
| `Sources/TVCore/Catalog.swift:154-156,495-506` | `CatVodContentParser.detail(_:fallbackID:fallbackTitle:)`: request-context identity/name recovery. The catalog supplies its actual requested ID; the movie page supplies its selected title. Recovery is restricted to film evidence or a matching explicit vod_id. Empty results, unrelated objects and business/auth failures do not become fabricated films. The strict overload and list filtering remain strict. |
| `Sources/TVCore/MusicQueue.swift` | `YingxiaMusicQueue<Track>` adapts the real clamped cursor, navigation, bounded-failure and restart policy to existing MediaHubLibraryItem. MusicPlayer now owns the complete ordered selection; AVQueuePlayer owns one current item. Previous/next/EOF no longer derive history from consumed native items. Two consecutive failures may advance; the third stops. |
| `Sources/TVCore/MusicLyrics.swift:3-99` (upstream file SHA-256 `6d631aa7a1f291c9f9807019c8c22f466fc5602ba3e6bcd71609c3f397a948bb`) | `Modules/Services/Music/YingxiaMusicLyrics.swift` adapts LRC timestamps, multiple stamps, offsets, translation pairing, unsynced text, credit cleanup and time-to-line lookup. `MusicPlayerView` imports a user-selected local `.lrc`, highlights/scrolls from `MusicPlayer.currentTime`, and seeks the shared player on a timed-line tap. No online lyric request is made. |

Adapted source notices retain `GPL-3.0-only` and the upstream copyright; the licence is preserved verbatim in `LICENSES/Yingxia-GPL-3.0-only.txt`. The existing project licence is not silently applied to copied GPL portions. NOTICE records actual provenance. This is not a legal clearance for a resulting binary or a representation that a NOTICE alone satisfies distribution obligations.

## Lifecycle and routing changes

- Long-press destinations are typed optional `@State` values in ContentView, not AppStorage/UserDefaults. Relaunch starts on reading roots; legacy saved menu values are ignored. Source installations, source configuration, credentials and bookmarks are NOT deleted or made transient.
- The root-owned deferred/coalesced action coordinator is retained. It still defers host replacement until after menu action return and drops superseded actions. A fixed dismissal delay is a mitigation, not proof against every OS race.
- Music item status work is now cancellable. Replacement/seek/stop/takeover invalidate event generations, unregister item/time observers and reject stale item callbacks. Terminal EOF/failure is consumed at most once per generation. Existing TTS/audiobook ownership and header-aware assets remain.
- New/updated native tests cover queue history, stale notifications, failure limits, repeated video/music menus on both roots, ignoring legacy values and resetting on relaunch. CI selection now uses an iPad for wide toolbar/sidebar tests and a separate iPhone for the crash path; missing/skip-only iPad coverage must not count as a pass.
- New native `YingxiaMusicLyricsTests` covers LRC timestamp/offset/translation/plain-text/no-lyric parsing, explicit local-file import, and rejecting stale picker results after track/selection changes. Add the exact selector `-only-testing:'yuedu appTests/YingxiaMusicLyricsTests'` to the media51 native test command; this task did not edit test scripts, and the suite could not run here (exit 69, missing Xcode/iOS SDK).
- Old CI 45718008853 failed before tests, on TMDBClientTests.swift's nested `#require`. The nested macro is split into separate assertions without changing the request or expected values.

## Explicitly incomplete full-port work

This candidate does NOT import all of TVCore, its QuickJS/JVM/Python/Node hosts, its AVQueuePlayer/remux session, upstream music catalogs/resolvers or online lyric providers (only the local LRC parser/timeline subset is integrated), custom DASH/CENC/cloud AVAsset schemes, subtitles or danmaku. It does not claim arbitrary TVBox/LX/MusicFree compatibility.

The archived upstream Package.swift requires FFmpeg.xcframework and LibASS.xcframework that are absent from that source checkout. Full package reuse also requires choosing a single Node owner, bundling resources, linking native runtime symbols, bridging app-wide audio ownership and migrating installed source/bookmark schemas. These remain tracked integration work, not invisible stubs. Existing Readcc runtime/player paths remain for functions not ported here; no upstream identity, account, credentials, executable or optional cloud endpoint is copied.

## Verification boundary

Local source-contract, syntax, patch-reconstruction and exact rollback checks can be repeated from the transaction artifacts. They do not execute Swift typechecking, XCTest, UI gestures or playback. The native script exits 69 when xcodebuild/iOS SDK is unavailable; that is a concrete blocker, not a skipped pass. No new IPA is generated or represented by the existing af75484 product.

The supplied screenshot only shows a parser error for a title; its raw response and source identity are unavailable. New synthetic contract fixtures prove neither that title's root cause nor real-source/physical-device recovery. The full refactor and the requirement to verify crash-free switching remain unaccepted until the new candidate passes native tests and device feedback.
