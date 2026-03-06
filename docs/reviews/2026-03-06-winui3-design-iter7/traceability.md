# Traceability (Raw -> Iteration 7 Actions)

Raw source:
- `app-architecture.raw.txt`

Action in this iteration:
1. Input runtime extraction:
- Added `src/apprt/winui3/input_runtime.zig`.
- Moved native input window setup and input-overlay focus restoration out of `App.zig`.
- Updated `App.zig` and `tab_manager.zig` to delegate to `input_runtime`.

Why this action:
- Directly targets review feedback about concentrated responsibilities in `App.zig`.

Inference boundary:
- Full `WindowController` extraction is still pending.
