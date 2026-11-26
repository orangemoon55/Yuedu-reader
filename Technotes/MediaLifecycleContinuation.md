# Music player lifecycle continuation

This phase continues from `8b32a4b7ccee2fcab225b60d46448ba727b162c4`. It changes application behavior; it is not another type-annotation-only test fix.

## Changed ownership boundaries

- `MusicPlayer.installItemObservers` installs a KVO-backed `AnyCancellable` for the current item's full lifetime. Observation remains installed after `.readyToPlay`; a later status-only `.failed` enters the same bounded failure policy as a failed-to-end notification.
- Replacement, seek (including the same AVPlayerItem), stop and takeover cancel the observation. Enqueued callbacks must still pass both the item identity and generation checks, then terminal-event de-duplication. Cancellation alone is not treated as a cross-thread completion barrier.
- KVO copies only the status raw integer before hopping to MainActor. It does not transfer an `NSKeyValueObservedChange` or Notification across actor boundaries.
- `isolated deinit` unregisters only this instance's stored remote-command/token pairs and cancels the current observation. It does not disable the shared command center, clear another owner's lock-screen metadata, detach another owner, or deactivate the shared audio session.

## Deterministic native regression coverage

`MusicPlayerLifecycleTests.swift` extends the existing selected `MusicPlayerPlaybackTests` class. Its status installer seam drives the real production queue/failure methods with app-owned local PCM assets, including ready-then-failed, stale events after seek, takeover, the bounded third failure, and duplicate/stale events. It is an event-order regression seam, not proof of a particular remote provider's AVFoundation failure timing.

Remote-command tests delegate to real `removeTarget(token)` while recording the per-instance command sequence and checking another owner's metadata/flags. They prove six removal-hook calls and no global-state clearing, not execution of the newer owner's target or independent introspection of opaque token identity. Production source retains each exact command/token pair; that part is a static ownership check.

The default production installer is real AVPlayerItem KVO, not the test seam. A separate new smoke test calls this exact installer on a real invalid local AVPlayerItem, without a failed-notification listener, and waits with a bounded condition for the real `.failed` status to cross the KVO/MainActor bridge. It is written for native execution; no pass is claimed from Linux. Existing native AVFoundation/queue tests continue to exercise actual local-media playback.

## Evidence boundary

Linux source contracts report the previous finite polling and missing destruction cleanup as false, and the changed mechanisms as true. This is not native typechecking or a crash-free verdict. Local `verify_media51_native.sh` returns 69 because this Linux environment has no Xcode/iOS SDK. The new exact app commit must be tested and built on the authorized native runner before a new IPA is represented as available.

Full upstream TVCore/runtime/session and music catalog/resolver integration remains separate unfinished work. Do not claim the complete original media-refactor request is satisfied by these lifecycle changes or by a successful IPA build alone.
