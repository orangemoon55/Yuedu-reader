#!/usr/bin/env python3
"""Offline source/syntax regressions, not an Apple SDK typecheck or UI test.
Run: python3 Packages/CodaMusic/Tests/PlayerRegression/test_now_playing_poster.py
Requires the tree_sitter and tree_sitter_swift Python packages; no networking.
"""
import json
from pathlib import Path
import subprocess
import sys
import unittest

from tree_sitter import Language, Parser
import tree_sitter_swift

ROOT = Path(__file__).resolve().parents[4]
PLAYER = Path("Packages/CodaMusic/Sources/Coda/Features/Player")
BASE = "50e7ac7"
SWIFT = ["NowPlayingView.swift", "NowPlayingFluidBackground.swift", "NowPlayingPortraitArtwork.swift",
         "NowPlayingSoftMistBackground.swift", "NowPlayingPosterControls.swift", "NowPlayingPosterLayout.swift"]
PARSER = Parser(Language(tree_sitter_swift.language()))


def read(path):
    return (ROOT / path).read_text()


def baseline(path):
    return subprocess.check_output(["git", "show", f"{BASE}:{path}"], cwd=ROOT).decode()


def functions(source):
    data = source.encode()
    result = {}

    def walk(node):
        if node.type == "function_declaration":
            name = node.child_by_field_name("name")
            if name:
                result.setdefault(data[name.start_byte:name.end_byte].decode(), []).append(
                    data[node.start_byte:node.end_byte].decode())
        for child in node.named_children:
            walk(child)
    walk(PARSER.parse(data).root_node)
    return result


class PlayerPosterRegression(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.view = read(PLAYER / "NowPlayingView.swift")
        cls.old = baseline(PLAYER / "NowPlayingView.swift")

    def test_swift_syntax(self):
        paths = [PLAYER / name for name in SWIFT]
        paths.append(Path("Packages/CodaMusic/Tests/CodaCoreTests/NowPlayingPosterLayoutTests.swift"))
        for path in paths:
            with self.subTest(path=str(path)):
                tree = PARSER.parse((ROOT / path).read_bytes())
                self.assertFalse(tree.root_node.has_error, str(path))

    def test_existing_seek_volume_lyrics_and_landscape_functions_unchanged(self):
        old, new = functions(self.old), functions(self.view)
        for name in ["volumeControl", "phoneRegularLayout", "iPadRegularLayout", "desktopRegularLayout",
                     "landscapeLyricsColumn", "togglePlaylistPanel", "cancelScrubbing", "scrubber",
                     "timeLabels", "loadArtwork", "applyArtwork"]:
            with self.subTest(function=name):
                self.assertIn(name, old)
                self.assertEqual(old[name], new[name])

        # The requested phone-only return-to-preview branch is verified below;
        # remove only that exact new branch before the original byte equality.
        name = "portraitUtilityBar"
        self.assertEqual(len(new[name]), len(old[name]))
        self.assertEqual(len(new[name]), 1, "No extra overload may escape the exact branch comparison")
        current = new[name][0]
        phone_branch = '''if allowsArtwork && UIDevice.current.userInterfaceIdiom == .phone {
                    // Returning from queue/comments restores only the preview;
                    // the old single-column lyric toggle is not an entry point.
                    iPadPanelButton("chevron.backward", label: "返回播放", selected: false) {
                        portraitFullLyricsPresented = false
                        playlistTrack = nil
                        iPadPanel = .lyrics
                        registerPortraitControlsActivity()
                    }
                } else {
                '''
        self.assertEqual(current.count(phone_branch), 1)
        self.assertEqual(current.count('\n                }\n            }\n            .fixedSize'), 1)
        restored = current.replace(phone_branch, '', 1).replace(
            '\n                }\n            }\n            .fixedSize', '\n            }\n            .fixedSize', 1)
        self.assertEqual(old[name], [restored], "All original non-phone branches and controls must remain exact")

    def test_phone_full_lyrics_are_swipe_only_and_read_only(self):
        phone = self.view.split('private func phonePortraitLyricsLayout', 1)[1].split(
            'private var portraitShowsArtwork', 1)[0]
        self.assertIn('== .phone && size.height > size.width', self.view)
        for forbidden in ['portraitLyricsToggle', 'AppleMusicLyricsColumn', 'onTapGesture', 'portraitControlsAutoHide']:
            self.assertNotIn(forbidden, phone)
        for token in ['PortraitLyricsSwipeObserver(expanded: false)', 'PortraitLyricsSwipeObserver(expanded: true)',
                      '向右滑动查看完整歌词', 'portraitFullLyricsPresented = false']:
            self.assertIn(token, phone)
        self.assertEqual(phone.count('portraitPlaybackControls('), 1)
        self.assertIn('phonePoster: true', phone)
        self.assertIn('.accessibilityAction(named: Text("显示完整歌词"))', phone)
        resident = self.view.split('private var hasLyricsColumn', 1)[0]
        reset = resident.split('.onChange(of: player.currentTrack?.id)', 1)[1]
        self.assertIn('portraitFullLyricsPresented = false', reset.split('#if os(macOS)', 1)[0])
        self.assertIn('.onChange(of: player.showNowPlaying)', resident)
        self.assertIn('phonePoster: Bool = false', self.view)
        self.assertIn('if phonePoster || portraitShowsArtwork', self.view)
        self.assertEqual(self.view.count('phonePoster: true'), 2)
        source = read(PLAYER / 'NowPlayingPortraitArtwork.swift')
        readonly = source.split('struct NowPlayingPortraitLyrics:', 1)[1].split('struct PortraitLyricsSwipeObserver:', 1)[0]
        for forbidden in ['onTapGesture', 'Button(', 'player.seek', 'cursor.seek']:
            self.assertNotIn(forbidden, readonly)
        self.assertIn('.task(id: expanded)', readonly)
        self.assertNotIn('.onChange(of: cursor', readonly)
        for token in ['pan.cancelsTouchesInView = false', 'bounds.contains(touch.location(in: self))',
                      'shouldRecognizeSimultaneouslyWith', 'view.detach()']:
            self.assertIn(token, source)

    def test_native_engine_and_shared_integrations_are_not_replaced(self):
        paths = [PLAYER / name for name in ["PlayerBar.swift", "AppleMusicLyricsColumn.swift",
                 "IOSPlaybackQueueView.swift", "IOSSystemVolumeSlider.swift", "PlaybackDeviceButton.swift",
                 "SongCommentsColumn.swift", "NowPlayingTrackDestinationLinks.swift"]]
        paths.append(Path("Packages/CodaMusic/Sources/Coda/Core/Player/PlayerService.swift"))
        for path in paths:
            with self.subTest(path=str(path)):
                self.assertEqual(read(path), baseline(path))

    def test_mac_renderer_implementation_retained(self):
        path = PLAYER / "NowPlayingFluidBackground.swift"
        old, new = baseline(path), read(path)
        marker = "private struct FluidBackgroundSurface"
        self.assertEqual(old.split(marker, 1)[1], new.split(marker, 1)[1])
        self.assertIn("#if os(iOS)\n        NowPlayingSoftMistBackground", new)
        self.assertIn("#else\n        FluidBackgroundSurface", new)

    def test_poster_transport_uses_real_player_state_and_actions(self):
        source = read(PLAYER / "NowPlayingPosterControls.swift")
        for token in ["@EnvironmentObject private var player: PlayerService", "player.previous", "player.next",
                      "player.togglePlayPause", "player.toggleShuffle()", "player.cycleRepeatMode",
                      "player.fmTrash()", "disabled: player.isFMMode", "player.showsPlaybackLoading"]:
            self.assertIn(token, source)
        self.assertIn("PlayerPlayPauseButton", source)
        self.assertIn("PlayerTransportButton", source)

    def test_poster_panels_favorites_downloads_airplay_and_playlist_are_live(self):
        for token in ["player.loadCurrentLyricsIfNeeded()", "iPadPanel = .queue", "showPortraitLyrics",
                      "SongCommentsStore(trackID: track.id)", "PlayerFavoriteButton(trackID: track.id",
                      "TrackDownloadActions(track: track, showsIcons: true)",
                      "CurrentPlaybackDeviceButton(showsName: false)",
                      "onAddToPlaylist: togglePlaylistPanel", "Button(action: onAddToPlaylist)",
                      "IOSSystemVolumeSlider", "player.seek(to: value * dragDuration)"]:
            self.assertIn(token, self.view)
        for token in ["NowPlayingAddToPlaylistColumn", "SongCommentsColumn", "IOSInlinePlaybackQueueView"]:
            self.assertIn(token, self.view)

    def test_actual_metadata_and_no_fabricated_reference_song(self):
        for token in ["player.currentTrack?.name", "NowPlayingTrackDestinationLinks", "posterMusicSource",
                      "player.unblockSource", "platformSong?.source.rawValue", "player.lyrics?.isInstrumental",
                      '"暂无歌词"', '"歌词加载中…"']:
            self.assertIn(token, self.view)
        source = "\n".join(read(PLAYER / name) for name in SWIFT)
        for fake in ["人生何处不相逢", "陈慧娴", "小芸音乐", "畅怡守", "URLSession", "https://"]:
            self.assertNotIn(fake, source)

    def test_accessibility_and_small_screen_fallbacks(self):
        source = read(PLAYER / "NowPlayingSoftMistBackground.swift")
        for token in ["accessibilityReduceMotion", "accessibilityReduceTransparency", "colorSchemeContrast",
                      "if !reduceTransparency", "reduceMotion ? nil", ".ignoresSafeArea()",
                      ".allowsHitTesting(false)", ".accessibilityHidden(true)"]:
            self.assertIn(token, source)
        self.assertIn("ScrollView(.vertical, showsIndicators: false)", self.view)
        self.assertIn("posterDynamicTypeSize.isAccessibilitySize", self.view)
        self.assertIn("layout.viewportHeight", self.view)
        self.assertIn(".accessibilityLabel(\"待播清单\")", self.view)
        self.assertIn("account.provider.supportsDownloads", self.view)
        self.assertIn('player.singleColumnLyricsVisible', self.view)

    def test_poster_is_stable_when_paused_and_does_not_invent_animation(self):
        source = read(PLAYER / "NowPlayingPortraitArtwork.swift")
        self.assertIn("isArtworkPage ? 1000 : 12", source)
        self.assertNotIn("animateBounce", source)
        self.assertNotIn("pausedInset", self.view)
        for name in ["NowPlayingSoftMistBackground.swift", "NowPlayingPortraitArtwork.swift"]:
            source = read(PLAYER / name)
            for token in ["CADisplayLink", "Timer(", "repeatForever", "rotationEffect", "Task.sleep"]:
                self.assertNotIn(token, source)


if __name__ == "__main__":
    output = None
    if "--json" in sys.argv:
        index = sys.argv.index("--json")
        output = Path(sys.argv[index + 1])
        del sys.argv[index:index + 2]
    result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(PlayerPosterRegression))
    if output:
        output.write_text(json.dumps({"kind": "offline-source-and-tree-sitter-only", "baseline": BASE,
                                     "tests_run": result.testsRun, "failures": len(result.failures),
                                     "errors": len(result.errors), "passed": result.wasSuccessful(),
                                     "native_typecheck": "unavailable", "native_tests": "not run"}, indent=2) + "\n")
    raise SystemExit(0 if result.wasSuccessful() else 1)
