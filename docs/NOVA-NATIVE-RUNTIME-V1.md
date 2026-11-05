# Nova Native Runtime V1

Actual Nova source rebuilt with a modified ARM64 AOT backend. No 1.6 executable, launcher, shader library or app payload used. Not a full rewrite of GTA's engine. Input remains user-owned game.wasm compiled ahead of time through wasm2c to ARM64.

Cache stable heap base once per generated function; use it in scalar/ordinary SIMD access helpers. Preserve explicit atomic calls, wait/notify, vector bounds checks, original audio behavior and memory guard. Source/NativeThreads.c grows only size inside the existing mapping. Do not enable this transform with a relocatable memory allocator.

Keep Nova launcher, vehicle/skin/sound mods, Menyoo, PAD, turbo, localization and renderer source. The original Nova remains at e0b17c1 / nova-online. Separate worktree and installation identifier vn.gta.newgen.nova.runtime allow rollback. No claim that all these features were device-retested.

Preflight: idempotence/fail-closed codegen tests; protected audio/memory tests; whole UIKit Swift typecheck; original importer/layout/pack tests; hash-verified engine/shader inputs; generated ARM64 syntax checks; production shared-SIMD tests in cached and uncached mode with ASan/UBSan, out-of-bounds traps and 20000 release/acquire handoffs. Release packaging is gated after these checks. One gameplay app only, no keygen/demo app.

Device gates still outstanding: GTA world entry, input/audio, missions, saves, mod regression and long-session FPS/thermal/RAM measurement. Host tests and a successful IPA build cannot certify these. No FPS gain claimed without device comparison.

Design reference: MIT upstream commit 9357c182b5cddd58e16dee684ea07ebc18a97a5d, Scripts/prepare_memory_base.py. This variant deliberately does not import engine-wide non-atomic conversion or alter graphics to mask CPU cost.
