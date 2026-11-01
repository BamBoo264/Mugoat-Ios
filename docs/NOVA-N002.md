# Nova N002 — log-driven changes

Both supplied logs are A16 / iPhone15,3, app limit 4096 MiB with increased-memory entitlement reported granted. These are not measurements from every tester model. Renderer sample medians: 42.8 and 42.1 FPS. Health samples show GPU 0.9–3.8 ms, thermal fair/serious and extensive streaming churn; CPU/streaming/thermal limitation is an inference, not proof of a single cause. No persistent GPU readback wait was observed. Log spam includes >2,100 instances each of two parser-warning families.

Changes: bounded filtering of five specific repetitive diagnostics (unknown errors preserved); unused upstream analytics no longer queue/write JSON; live resolution changes use the same SR internal/output math as startup. Standard retains N001 graphics/presets and memory guard. LowRAM uses original Lite path, low graphics at 540p, ambient density 0.30 and detail multiplier 0.55. No new forced RAM reclamation or cache/pipeline policy.

Camera: log confirms F7/0x76 read, but DynamicVehicleFirstPerson stops with a C++ exception during initialization after missing Windows filesystem calls. Added real UTF16 filesystem wrappers, LocalAppData known-folder result and matched free. Unsupported folder GUIDs return failure and null output rather than false S_OK. Tested wrappers separately; full PC plugin may still require additional Windows APIs or real GTA5.exe patterns. Do not claim camera works until a device test succeeds. Original camera ASI not bundled.

References: https://learn.microsoft.com/en-us/windows/win32/api/fileapi/nf-fileapi-getfileattributesexw and https://learn.microsoft.com/en-us/windows/win32/api/shlobj_core/nf-shlobj_core-shgetknownfolderpath

Two IPAs are signed with the same Full.entitlements (increased-memory-limit and extended-virtual-addressing). This requests eligibility; actual post-Esign grant and process limits depend on device, OS and certificate. Both variants share one compiled executable to avoid duplicate engine compilation. LowRAM uses its own bundle ID for rollback/side-by-side tests.

User clarification: LowRAM includes explicit movement cleanup settings (40/60/80/120/160 m), small reserve selection (64/128/192/256 MiB), default 80 m / 128 MiB. Only LowRAM opts in. Requests capped at 16 MiB, no more often than 500 ms, require movement permission or scene transition unless critical headroom. Engine lifetime rules and heap ceiling remain. Standard continues original guard.
