# Mugoat Nova N001

Base: pristine gta5-ios-port 1.4.4 archive, root commit 9f78685. New branch mugoat-nova; no changes to previous release branches.

Integrated: current vehicle replace/add-on importer, resource compatibility and large-resource support; skin aliases and Menyoo model list; custom audio REL54 conversion and per-model assignment; optional Menyoo; turbo/backfire; PAD with independent collision-checked layout; persistent Settings/Plugin shortcuts with external input; Sandbox map fog reveal.

Vietnamese: one direct-read NVP pack per text mode, no 1,200-file extraction. Both pack payloads verified byte-for-byte against prior ZIPs. Overlay table no longer truncates after 256 entries. Save data untouched. Vietnamese launcher catalog retained.

Graphics: original renderer plus five-line explicit-output extension of its existing MetalFX spatial upscaler. No V5 distance/streaming/memory/downmix/runtime policy imported. Native PCM function, DSP/Opus preparation and original memory guard sections protected by hash tests. Presets stay original; Nova SR is opt-in and changes apply at next game start.

Default touch camera: swipe. New generated icon and background; Mods on launcher home. Original authorship/license preserved. Upstream telemetry and update network calls disabled.

Camera plugin: user imports original DynamicVehicleFirstPerson ZIP; configuration page edits documented INI options and F7 menu binding with backups. ASI is not bundled; iOS plugin playback is unverified and may be incompatible with the PC memory scan. No per-frame forced FOV or body hiding.

Local tests: source/audio/memory invariants; complete pack bounds; all packed entries byte-identical to prior translations. macOS CI: whole-app iPhone SDK Swift type check, production PAD layout tests, scale math, native pack reader with sanitizers. Device FPS/audio/mission validation remains required on iPhone; no claim of verified FPS increase yet.

Public redistribution of bundled Menyoo, Vietnamese packs and turbo sounds explicitly approved by owner on 2026-10-31. No saves or 20 GB game assets uploaded. Only previously authorized minimal engine/manifest/shader build inputs reused.

Rollback: previous branches unchanged. Root commit 9f78685 is the pristine 1.4.4 source. Nova bundle ID vn.gta.newgen.nova allows side-by-side installation with the older app. Nova expects the original Mugoat game data, not PortData.
