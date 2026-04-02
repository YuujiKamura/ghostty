# H1 Fix Design: CP Read Callbacks → SendMessageW Dispatch

## Problem

Pipe server thread calls `controlPlaneCaptureState/CaptureTail/CaptureTabList`
which access `self.surfaces` (ArrayListUnmanaged) **without synchronization**.
UI thread mutates `self.surfaces` via `newTab/closeSurface`. This is UB and
causes hangs when the pipe thread reads stale/freed memory.

See `docs/hang-analysis.md` for full analysis.

## Design: SendMessageW-based UI Thread Dispatch

### New message constant

```zig
// os.zig
pub const WM_APP_CP_QUERY: UINT = WM_USER + 9;
```

### Query request struct

```zig
// control_plane.zig
const CpQueryType = enum(u8) {
    capture_state,
    capture_tail,
    capture_tab_list,
};

const CpQuery = struct {
    query_type: CpQueryType,
    allocator: Allocator,
    tab_index: ?usize,
    // Result (written by UI thread, read by pipe thread after SendMessageW returns)
    result_state: ?StateSnapshot = null,
    result_tail: ?[]u8 = null,
    result_tab_list: ?[]u8 = null,
};
```

### Provider callbacks (pipe thread) — BEFORE

```zig
fn provTabCount(ctx: *anyopaque) usize {
    const self: *ControlPlane = @ptrCast(@alignCast(ctx));
    const capture = self.capture_state_fn orelse return 0;
    const cb_ctx = self.callback_ctx orelse return 0;
    var snapshot = (capture(cb_ctx, self.allocator, null) catch return 0) orelse return 0;
    defer snapshot.deinit(self.allocator);
    return snapshot.tab_count;
}
```

### Provider callbacks (pipe thread) — AFTER

```zig
fn provTabCount(ctx: *anyopaque) usize {
    const self: *ControlPlane = @ptrCast(@alignCast(ctx));
    var query = CpQuery{
        .query_type = .capture_state,
        .allocator = self.allocator,
        .tab_index = null,
    };
    // Synchronous dispatch to UI thread. Blocks until WndProc processes it.
    _ = os.SendMessageW(self.hwnd, os.WM_APP_CP_QUERY, 0, @intFromPtr(&query));
    var snapshot = query.result_state orelse return 0;
    defer snapshot.deinit(self.allocator);
    return snapshot.tab_count;
}
```

Same pattern for `provActiveTab`, `provTabWorkingDir`, `provTabHasSelection`,
`provReadBuffer`, and the tab list callback.

### WndProc handler (UI thread) — NEW

```zig
// App.zig handleWndProcMessage
os.WM_APP_CP_QUERY => {
    const query: *ControlPlaneNative.CpQuery = @ptrFromInt(@as(usize, @bitCast(lparam)));
    switch (query.query_type) {
        .capture_state => {
            query.result_state = self.controlPlaneCaptureState(query.allocator, query.tab_index) catch null;
        },
        .capture_tail => {
            query.result_tail = self.controlPlaneCaptureTail(query.allocator, query.tab_index) catch null;
        },
        .capture_tab_list => {
            query.result_tab_list = self.controlPlaneCaptureTabList(query.allocator) catch null;
        },
    }
    return 0;
},
```

### Functions that change (now only called from UI thread)

- `controlPlaneCaptureState` — no change needed (already correct when single-threaded)
- `controlPlaneCaptureTail` — no change needed
- `controlPlaneCaptureTabList` — no change needed

### callback_ctx removal

After this change, `capture_state_fn`, `capture_tail_fn`, `capture_tab_list_fn`,
and `callback_ctx` are no longer called from control_plane.zig directly.
They are only called from WndProc (UI thread) via the query dispatch.

Options:
- **Keep the fn pointers**: WndProc calls them via ControlPlane fields (no change to App.zig)
- **Remove fn pointers**: WndProc calls App methods directly (cleaner but bigger diff)

Recommend: **Keep fn pointers** for minimal diff. Remove in a follow-up.

## Thread Safety Proof

```
Pipe server thread:                    UI thread:
  provTabCount()
    build CpQuery on stack
    SendMessageW(WM_APP_CP_QUERY) ──────► WndProc receives
    │ (blocked)                            handleCpQuery()
    │                                      controlPlaneCaptureState()
    │                                        surfaces.items.len  ← SAFE (UI thread)
    │                                        surface.pwd()       ← SAFE (UI thread)
    │                                      write result to CpQuery
    │ ◄────────────────────────────────── return 0
    read result from CpQuery
    return snapshot.tab_count
```

No concurrent access to `surfaces`. No lock ordering issues. No deadlock
(SendMessageW is a one-way block; UI thread never SendMessageW's to pipe thread).

## Deadlock Analysis

**Can UI thread block waiting for pipe thread?** No.
- `provSendInput` uses `PostMessageW` (async, non-blocking)
- `provNewTab/closeTab/switchTab/focus` use `PostMessageW` (async)
- UI thread never calls `SendMessageW` to the pipe thread

**Can pipe thread block waiting for UI thread?** Yes, by design.
- `SendMessageW` blocks until WndProc processes WM_APP_CP_QUERY
- This is the correct behavior: pipe queries wait for UI thread

**Can WndProc be blocked when SendMessageW arrives?** No.
- SendMessageW from another thread is dispatched when the target thread
  calls GetMessage/PeekMessage/MsgWaitForMultipleObjects
- Even if UI thread is in `tick()`, the next message pump iteration processes it
- tick() does NOT hold any lock that WM_APP_CP_QUERY handler needs

## Performance Impact

- STATE queries (tab_count, active_tab, pwd, selection): ~0.1ms additional latency
- TAIL queries: same as before (viewportString dominates), just runs on UI thread now
- UI thread overhead: negligible (one extra message per CP query)

## Files Changed

| File | Change |
|------|--------|
| `src/apprt/winui3/os.zig` | Add `WM_APP_CP_QUERY = WM_USER + 9` |
| `src/apprt/winui3/control_plane.zig` | Add CpQuery struct, change prov* callbacks to use SendMessageW |
| `src/apprt/winui3/App.zig` | Add WM_APP_CP_QUERY handler in handleWndProcMessage |

Estimated: ~80 lines changed, ~20 lines added.
