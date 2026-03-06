# Traceability (Raw -> Iteration 9 Actions)

Raw sources:
- `app-architecture.raw.txt`
- `tab-manager-architecture.raw.txt`

Actions in this iteration:
1. COM scoped-release helper:
- Added `winrt.ComRef(T)` and applied it to selected runtime paths (`tab_manager`, `window_runtime`) to reduce manual `release()` burden.

2. Parallel validation run:
- Executed formatting+build and two architecture reviews in parallel (`App.zig`, `tab_manager.zig`).

Open follow-ups from raw:
- `tab_manager` still includes app-exit responsibility in `closeTab` (needs callback/delegation split).
- Further `App` state decomposition remains pending.
