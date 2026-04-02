# Traceability (Raw -> Iteration 4 Actions)

Raw source:
- `app-architecture.raw.txt`

Action in this iteration:
1. Responsibility split (first step):
- Extracted TabView runtime bootstrapping logic from `App.zig` into `tabview_runtime.zig`.
- `App.zig` now delegates TabView root creation and default TabView2 options to the new module.

Why this action:
- Direct response to recurring review finding: `App.zig` responsibility concentration.

Inference boundary:
- Full `TabManager` extraction is not complete in this iteration.
