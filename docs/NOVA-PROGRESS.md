# Mugoat Nova — integration status

Base: pristine source archive 1.4.4, commit 9f78685.

User requested retention: turbo/backfire and PAD.

PAD migrated: TouchControlsView.swift, ControlsLayout.swift, ManualPadLayout.swift;
NativePortViewController keeps Settings and Plugin visible with external input.
PAD toggles back to normal controls, and has an independent editable layout group.
Collision/out-of-bounds layout changes are rejected.

Production Swift layout tests copied to app/Tests/mission_controls.swift,
runner tools/test_manual_layout.py. NOT executed here: Windows lacks Swift/Xcode.
Must run these tests and iOS type checking on macOS before release.
EngineHost and MRRenderer confirmed byte-identical to the pristine baseline
at this PAD integration stage. No V5 memory/streaming policies migrated.

Other Nova features are still being integrated; no release IPA built yet.
