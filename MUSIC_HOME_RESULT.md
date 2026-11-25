# Music home visual pass — Build51 candidate

## Scope

Updated only the existing candidate at `/var/minis/shared/readcc-build51/continuation-evidence/crash-music-home-4k/candidate`. Reference inspected: `/var/minis/attachments/uploads/photo_31B9D827.png`.

## Exact changed files

1. `Modules/Features/Music/MusicJSSourceView.swift`
2. `Modules/Features/Music/MusicCatalogComponents.swift`
3. `Modules/Services/Music/MusicHomePresentation.swift`
4. `Tests/iOS/yuedu appTests/MusicCatalogTests.swift`
5. `MUSIC_HOME_RESULT.md` — this report.

Changes above are this pass only; unrelated pre-existing candidate changes were left in place. No test runner, non-Music source, project file, or parent navigation file was edited.

## Applied layout

- Sampled the reference's light canvas as RGB 243/246/251 and continue-card surface as RGB 238/240/242; dark mode retains native system surfaces.
- Kept the parent's centered inline music title, navigation stack, close action, root media controls and tabs. Added no replacement title, nested home navigation stack or inner tabs.
- Matched the settings slider to a primary-color title-sized icon. Search uses 16-point outer margins, a compact grey rounded field, and no empty-query submit icon; submission remains available from the keyboard and after entering a query.
- Continue-playing card uses 16-point outer margins, 14-point inner spacing, 20-point rounding, 66-point artwork with 6-point rounding, title/artist/current-time hierarchy and a 30-point playback symbol. Existing resume/open-player and JS retry actions are preserved; the card is disabled during URL resolution.
- Both horizontal shelves use 148-point square artwork, 18-point corners, 14-point card gaps, 16-point outer margins, single-line titles, smaller secondary captions and tighter section headings.
- Heading chevrons are functional navigation links into the actual returned catalogue entries, not decorative dead controls. Collection links retain existing play/save callbacks.
- Chart captions identify the actual NetEase catalogue origin; recommended playlists retain the service-returned creator, with a catalogue-origin fallback for missing creators. No screenshot songs, QQ attribution, artwork, listening history or audio URLs were fabricated.

## Functional boundaries preserved

The search, provider selection, cancellation, resolver mapping, save and JS URL-resolution functions were compared with a pre-edit snapshot and are byte-for-byte unchanged. The existing continuation button action is also unchanged. Metadata search still does not obtain playback URLs; playback continues through the imported source's existing resolver and player sheet.

The continue card still appears only for `MusicPlayer.currentTrack` of music kind. An empty session remains empty instead of imitating the screenshot's listening history. Public-catalogue attribution, playback-rights notices, loading/error states and retry actions remain available.

## Tests and checks

- PASS: `tree_sitter_swift` parsed all 13 Swift files under the Music feature/service directories plus `MusicCatalogTests.swift`; zero syntax-error trees after the final edits.
- PASS: targeted `git diff --check` for Music feature/service files and `MusicCatalogTests.swift`.
- PASS: snapshot comparison of search/resolution/save/cancellation functions and continuation action.
- Added unit coverage for chart origin versus playlist creator captions, including blank-creator fallback; expanded continuation coverage for a music session and NaN/infinite/negative time values.
- LIMITATION: neither `swift` nor `xcodebuild` is installed in this environment. XCTest/Swift Testing, SwiftUI type-checking, simulator/device rendering and pixel-diff validation were not run. Syntax validation is not an iOS compile or a claim of verified pixel-perfect rendering.

No commit, publication or cloud build was performed.
