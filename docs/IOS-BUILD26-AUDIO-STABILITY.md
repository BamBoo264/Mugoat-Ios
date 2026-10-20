# iOS 2.6 (26): audio import and conservative frame pacing

## Evidence and limits

The submitted v25 log binds SH150 (5250c0a1) to the car profile `turismor` twice after spawning. It ends during guest ResizeBuffers, immediately after an adaptive 432p -> 378p change. It does not contain a fault backtrace. The screenshot reports native trap 6 but shows a different vehicle, so it cannot identify the exact crashing instruction in this log.

The appended performance history includes low-FPS windows with ~0.1–0.2ms pipeline work/frame, high idle time and thermal state 2. These are not matched build22/23 benchmarks. No measured FPS improvement is claimed before device testing.

## Changes

- Remove input-polling audio rebinding (including the duplicate binding immediately after spawn). Manual selection is persisted for a full app restart; it never changes a running audio graph.
- Filter manual donor choices by motorcycle/car family and ignore stale cross-family overrides at startup.
- Preserve a mod's declared profile when it exists in the real audio manager. Only missing profiles need the verified stock fallback; explicit compatible overrides apply once to a newly spawned vehicle.
- Retain REL/AWC, directory structure, nested archives, content.xml and setup2.xml when adapting a DLC containing audio. The old flattening path discarded these files.
- Loose vehicle packages can include `.dat151.rel`, `.dat54.rel`, `.dat10.rel` and PC ADAT `.awc` files. Keep AWC under the author's `sfx/dlc_NAME` directory. Generate native audio mount entries; no Lua scripts are executed.
- Disable automatic gameplay resizing. Keep low graphics presets, texture LOD reduction, fixed boot resolution, and cache v3 compatibility identity.
- Use the existing engine frame cap without the additional Metal `afterMinimumDuration` limiter introduced in v25. This is a conservative rollback to the build22/23 presentation path; the contribution to FPS requires a matched device test.

## Compatibility

SH150 has empty audioNameHash and no private sound banks. 27rev requests `tyrus` but has no private sound banks. Their vehicle model files cannot provide new engine recordings by themselves. Custom audio requires matching REL metadata, wave banks, and audioNameHash. Native import support does not prove that every newer GTA/FiveM codec or metadata revision works in this older port.

Re-import original packages after updating: already converted packages cannot recover audio files discarded by an earlier importer. Choose automatic/the-mod audio and fully close/reopen the app. Do not delete saves or original data.

## Validation

Regression tests cover hierarchical RPF round trips, byte preservation of audio and original mount declarations, loose audio mount generation, path collisions and explicit-versus-native audio policy state. macOS CI builds the Release paid-certificate IPA. Actual sound quality, trap resolution and sustained FPS still require iPhone testing.
