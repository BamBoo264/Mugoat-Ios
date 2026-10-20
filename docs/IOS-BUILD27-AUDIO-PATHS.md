# iOS 2.7 (27): native audio metadata filenames

The submitted build26 log identifies the failure unambiguously:

    Loading DLC audio chunk ta103ninjah2r .../audioconfig/ta103ninjah2r_game.dat
    Failed to find .../audioconfig/ta103ninjah2r_game.dat151
    Native trap 5
    Native boot stopped: Unreachable instruction executed

This occurs while mounting the sound DLC during startup, before the selected audio profile can be applied to SH150. Other REL-only sound packs share the same missing-name problem.

Build26 imported PC `.dat151.rel`, `.dat54.rel` and `.dat10.rel` files, but the native engine opens the corresponding names without `.rel`. This is also documented in the upstream gta5-ios-port v1.4.2 `pg_audio_rel_walk` fix. The local original game data contains both filename variants; the Verity `.dat151` and `.dat151.rel` bytes are identical. Some supplied `.dat54` plain/release files differ, so author-supplied plain files must take precedence.

## Fix

- New loose imports include both release and native filenames, with identical data for aliases generated from a release-only source.
- Existing installed sound packs are repaired in a runtime RPF overlay before engine startup. The original installed package is not modified and does not need reinstalling.
- Handle all three supported extensions, nested archives, and idempotent preparation. Preserve any existing author-supplied native/plain file rather than replacing it.
- Only packages containing audio metadata enter this compatibility pass. No gameplay polling, fake loaded return, guest memory hook, changes to audio ABI, or changes to the renderer are introduced.

Regression tests use the real H2R REL151 fixture, reproduce the exact missing `.dat151` path, check `.dat54`/`.dat10`, byte preservation, existing plain-file precedence, nested archives and runtime manifest routing of a build26 package without altering its original bytes.

The build26 tests verified PC-style mounting declarations and REL profile discovery, but did not check the native engine's exact filename lookup; this gap is now covered. Native audio playback and compatibility of other metadata/codec revisions still require iPhone testing after this startup failure is fixed.
