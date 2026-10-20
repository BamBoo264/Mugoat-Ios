# iOS 2.6 (26): audio import and conservative frame pacing

## Evidence and limits

The submitted v25 log binds SH150 (5250c0a1) to the car profile `turismor` twice after spawning. It ends during guest ResizeBuffers, immediately after an adaptive 432p -> 378p change. It does not contain a fault backtrace. The screenshot reports native trap 6 but shows a different vehicle, so it cannot identify the exact crashing instruction in this log.

The appended performance history includes low-FPS windows with ~0.1–0.2ms pipeline work/frame, high idle time and thermal state 2. These are not matched build22/23 benchmarks. No measured FPS improvement is claimed before device testing.

## Changes

- Remove input-polling audio rebinding (including the duplicate binding immediately after spawn). Manual selection is persisted for a full app restart; it never changes a running audio graph.
- Filter manual donor choices by motorcycle/car family and ignore stale cross-family overrides at startup.
- Preserve a mod's declared profile when it exists in the real audio manager. Verified profiles are bound once at spawn, preserving the working build23 behavior; missing profiles use the verified stock fallback. There is no live rebind.
- Retain REL/AWC, directory structure, nested archives, content.xml and setup2.xml when adapting a DLC containing audio. The old flattening path discarded these files.
- Loose vehicle packages can include `.dat151.rel`, `.dat54.rel`, `.dat10.rel` and PC ADAT `.awc` files. Keep AWC under the author's `sfx/dlc_NAME` directory. Generate native audio mount entries; no Lua scripts are executed.
- Disable automatic gameplay resizing. Keep low graphics presets, texture LOD reduction, fixed boot resolution, and cache v3 compatibility identity.
- Use the existing engine frame cap without the additional Metal `afterMinimumDuration` limiter introduced in v25. This is a conservative rollback to the build22/23 presentation path; the contribution to FPS requires a matched device test.

## Compatibility

SH150 has empty audioNameHash and no private sound banks. 27rev requests `tyrus` but has no private sound banks. Their vehicle model files cannot provide new engine recordings by themselves. Custom audio requires matching REL metadata, wave banks, and audioNameHash. Native import support does not prove that every newer GTA/FiveM codec or metadata revision works in this older port.

Re-import original packages after updating: already converted packages cannot recover audio files discarded by an earlier importer. Choose automatic/the-mod audio and fully close/reopen the app. Do not delete saves or original data.

## Validation

Regression tests cover hierarchical RPF round trips, byte preservation of audio and original mount declarations, loose audio mount generation, path collisions and standalone sound DLCs, real H2R/Aquaphobic/W211 REL151 indices, audio-only extraction and truncated REL rejection. macOS CI builds the Release paid-certificate IPA. Actual sound quality, trap resolution and sustained FPS still require iPhone testing.

## Standalone sound packs supplied during this task

The Mod Manager now has **Nhập bộ âm thanh riêng** for ZIP/RAR/OIV/RPF/folders. OIV is treated only as an archive: assembly directives and Lua scripts are never executed. Select the installed vehicle's detail button, select an imported sound profile, fully close/reopen and spawn a new vehicle. The profile is also verified against the actual loaded guest audio manager before binding.

REL151 profile names are inferred from game REL filenames only when the corresponding Jenkins hash is actually present as a type-3 vehicle settings record. Unknown naming conventions are not guessed. Conflicting profile names are rejected. Sound-only packages are mounted through the same real DLC mechanism, with no model replacement.

- Kawasaki H2R: `ta103ninjah2r`, REL151 + REL54 + player/NPC ADAT banks. Import the ZIP or FiveM resource folder; Lua is ignored.
- Aquaphobic: 13 verified profiles and 25 AWC banks in the supplied RPF. `lambov10`, `rb26dett`, `k20a`, `gt3flat6` etc. Import the manual RPF, extracted folder or RAR. Native mount entries are regenerated for the audio-only import path.
- Benz: `w211` audio can be extracted independently. The vehicle models have incompatible resource versions 171/5, and its tuning RPF is encrypted. The audio-only path skips unrelated encrypted vehicle archives and does not import those models.
- Ducati1199 `d99`: no own banks; declares `PCJ`. For a practical test, install H2R audio and assign `ta103ninjah2r` to `d99`. This tests custom audio playback, not an authentic Ducati recording.

No iPhone is attached to this Windows environment: neither actual engine sound playback nor the absence of device crashes is claimed from importer/CI tests alone.
