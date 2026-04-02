# Traceability (Raw -> Iteration 5 Actions)

Raw source:
- `app-architecture.raw.txt`

Action in this iteration:
1. Tab index/state extraction (TabManager-first step):
- Added `src/apprt/winui3/tab_index.zig` for index policy.
- Moved `goto_tab` index calculation, close-time index clamping, and active-index validation from `App.zig` to `tab_index.zig`.

Why this action:
- Directly addresses review finding about distributed tab management logic.

Inference boundary:
- Full tab lifecycle extraction (`newTab`/`closeTab` object-level orchestration) remains pending.
