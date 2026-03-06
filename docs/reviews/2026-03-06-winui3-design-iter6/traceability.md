# Traceability (Raw -> Iteration 6 Actions)

Raw source:
- `app-architecture.raw.txt`

Action in this iteration:
1. Tab lifecycle orchestration extraction:
- Added `src/apprt/winui3/tab_manager.zig`.
- Moved `newTab`, `closeTab`, and `closeActiveTab` implementations out of `App.zig`.
- Kept behavior unchanged while reducing `App.zig` responsibility concentration.

Why this action:
- Directly addresses recurring review feedback about tab logic concentration in `App.zig`.

Inference boundary:
- Further extraction (`WindowController`/`InputSystem`) is still pending.
