# Traceability (Raw -> Iteration 8 Actions)

Raw source:
- `app-architecture.raw.txt`

Action in this iteration:
1. Window runtime extraction:
- Added `src/apprt/winui3/window_runtime.zig`.
- Moved window activation + resource bootstrap and visual diagnostic logic out of `App.zig`.
- `App.zig` now delegates those functions to `window_runtime`.

Why this action:
- Directly addresses review feedback about mixed responsibilities in `App.zig`.

Inference boundary:
- COM pointer lifecycle abstraction (`ComPtr`-style helper) remains pending.
