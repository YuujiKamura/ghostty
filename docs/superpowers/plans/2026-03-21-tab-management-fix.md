# Tab Management Fix (Issues #127, #128, #129) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix tab management so adding/closing tabs does not clear existing tab content or cause index misalignment.

**Architecture:** Add a `tab_mutation_in_progress` guard flag to App that suppresses `onSelectionChanged` side effects during programmatic tab mutations. Ensure `rebindSwapChain()` is called on the newly-visible surface after every visibility switch. Fix `auditActiveTabBinding` to check the correct child.

**Tech Stack:** Zig, WinUI3 XAML Islands, COM interop

---

## File Structure

| File | Role | Change |
|---|---|---|
| `src/apprt/winui3/App.zig` | App state fields | Add `tab_mutation_in_progress: bool = false` field |
| `src/apprt/winui3/tab_manager.zig` | Tab create/close | Wrap mutations in guard flag; remove redundant `attachSurfaceToTabItem` calls |
| `src/apprt/winui3/event_handlers.zig` | XAML event handlers | Skip `attachSurfaceToTabItem` when guard flag is true |
| `src/apprt/winui3/surface_binding.zig` | Panel visibility | Add `rebindSwapChain` on Visible restore; fix `auditActiveTabBinding` |

---

### Task 1: Add `tab_mutation_in_progress` Guard Flag (Issue #127)

**Files:**
- Modify: `src/apprt/winui3/App.zig:145` (add field after `active_surface_idx`)
- Modify: `src/apprt/winui3/event_handlers.zig:55-91` (guard `onSelectionChanged`)

- [ ] **Step 1: Add field to App.zig**

In `src/apprt/winui3/App.zig`, after line 145 (`active_surface_idx: usize = 0,`), add:

```zig
/// Guard flag: true while newTab/closeTab are mutating tab state.
/// onSelectionChanged skips attachSurfaceToTabItem while this is true.
tab_mutation_in_progress: bool = false,
```

- [ ] **Step 2: Guard onSelectionChanged in event_handlers.zig**

In `src/apprt/winui3/event_handlers.zig`, at the top of `onSelectionChanged` (after line 62), add an early return when the guard is set:

```zig
pub fn onSelectionChanged(self: anytype, sender_obj: ?*anyopaque, args_obj: ?*anyopaque) void {
    const sender_ptr = if (sender_obj) |p| @intFromPtr(p) else @as(usize, 0);
    const args_ptr = if (args_obj) |p| @intFromPtr(p) else @as(usize, 0);
    log.info("handler enter: onSelectionChanged sender=0x{x} args=0x{x}", .{ sender_ptr, args_ptr });

    // Skip side effects during programmatic tab mutations (Issue #127).
    if (self.tab_mutation_in_progress) {
        log.info("onSelectionChanged: skipped (tab_mutation_in_progress)", .{});
        return;
    }

    if (!com.isValidComPtr(sender_ptr) or !com.isValidComPtr(args_ptr)) {
        log.err("handler guard: onSelectionChanged suspicious sender/args sender=0x{x} args=0x{x}", .{ sender_ptr, args_ptr });
        return;
    }
    // ... rest unchanged
```

- [ ] **Step 3: Build and verify**

Run: `cd . && ./build-winui3.sh`
Expected: Build succeeds with no errors.

- [ ] **Step 4: Commit**

```bash
git add src/apprt/winui3/App.zig src/apprt/winui3/event_handlers.zig
git commit -m "feat(tab): add tab_mutation_in_progress guard flag (Issue #127)

onSelectionChanged now skips attachSurfaceToTabItem when the flag is set,
preventing triple-fire during programmatic tab mutations."
```

---

### Task 2: Wrap `newTabWithProfile` in Guard Flag (Issue #127)

**Files:**
- Modify: `src/apprt/winui3/tab_manager.zig:29-101`

- [ ] **Step 1: Set guard at start, clear at end of newTabWithProfile**

Replace `newTabWithProfile` to wrap the mutation in the guard flag. The key changes:
1. Set `self.tab_mutation_in_progress = true` before `tab_items.append()`
2. Clear it at the end (after `attachSurfaceToTabItem`)
3. Remove the now-redundant `SetSelectedIndex` call (the explicit `attachSurfaceToTabItem` handles everything)

In `src/apprt/winui3/tab_manager.zig`, replace lines 77-100 (from `// Add to TabItems collection.` to end of function) with:

```zig
    // Add to TabItems collection.
    const tab_items_raw = try tab_view.TabItems();
    const tab_items: *com.IVector = @ptrCast(@alignCast(tab_items_raw));
    defer tab_items.release();

    // Guard: suppress onSelectionChanged side effects during mutation (Issue #127).
    self.tab_mutation_in_progress = true;
    defer self.tab_mutation_in_progress = false;

    try tab_items.append(@ptrCast(tvi_inspectable));

    // Store the IInspectable reference on the surface for later title updates.
    surface.tab_view_item_inspectable = tvi_inspectable;

    // Select the new tab and swap panel visibility.
    const size = try tab_items.getSize();
    const prev_idx = self.active_surface_idx;
    const new_idx: usize = @intCast(size - 1);
    try tab_view.SetSelectedIndex(@intCast(new_idx));
    self.active_surface_idx = new_idx;

    // Single authoritative panel switch (no more triple-fire).
    self.attachSurfaceToTabItem(if (self.surfaces.items.len > 1) prev_idx else null, new_idx) catch |err| {
        log.warn("newTabWithProfile: attachSurfaceToTabItem({}) failed: {}", .{ new_idx, err });
    };

    // Rebind swap chain on the new surface (may be no-op if renderer hasn't started yet).
    surface.rebindSwapChain();

    // Keep normal keyboard focus on the XAML surface after tab creation.
    input_runtime.focusKeyboardTarget(self);

    log.info("newTabWithProfile completed: idx={} total={}", .{ self.active_surface_idx, self.surfaces.items.len });
```

- [ ] **Step 2: Build and verify**

Run: `cd . && ./build-winui3.sh`
Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
git add src/apprt/winui3/tab_manager.zig
git commit -m "feat(tab): wrap newTabWithProfile in guard flag (Issue #127)

Single authoritative attachSurfaceToTabItem call instead of triple-fire.
Also calls rebindSwapChain on new surface explicitly."
```

---

### Task 3: Wrap `closeTab` in Guard Flag (Issue #129)

**Files:**
- Modify: `src/apprt/winui3/tab_manager.zig:103-188`

- [ ] **Step 1: Add guard flag to closeTab**

In `closeTab`, set the guard before XAML mutations. Replace lines 161-178 (from `// 3. Remove from TabView` to `focusKeyboardTarget`) with:

```zig
    // 3. Remove from TabView — guard SelectionChanged side effects (Issue #129).
    self.tab_mutation_in_progress = true;
    defer self.tab_mutation_in_progress = false;

    if (self.tab_view) |tv| {
        const tab_items_raw2 = tv.TabItems() catch {
            self.core_app.alloc.destroy(surface);
            return false;
        };
        const tab_items: *com.IVector = @ptrCast(@alignCast(tab_items_raw2));
        defer tab_items.release();
        tab_items.removeAt(@intCast(idx)) catch |err| {
            log.warn("closeTab: removeAt({}) failed: {}", .{ idx, err });
        };

        // 4. Force-select the correct tab and swap SwapChainPanel.
        tv.SetSelectedIndex(@intCast(self.active_surface_idx)) catch {};
        surface_binding.attachSurfaceToTabItem(self, null, self.active_surface_idx) catch |err| {
            log.warn("closeTab: attachSurfaceToTabItem({}) failed: {}", .{ self.active_surface_idx, err });
        };

        // Rebind swap chain on the newly active surface (Issue #128).
        if (self.active_surface_idx < self.surfaces.items.len) {
            self.surfaces.items[self.active_surface_idx].rebindSwapChain();
        }

        input_runtime.focusKeyboardTarget(self);
    }
```

Also set the guard for the early-return path (lines 138-152, the `surfaces.items.len == 0` branch). Add before line 140:

```zig
    if (self.surfaces.items.len == 0) {
        self.tab_mutation_in_progress = true;
        defer self.tab_mutation_in_progress = false;

        // Remove from TabView last (triggers SelectionChanged with -1).
        if (self.tab_view) |tv| {
            // ... existing code unchanged
```

- [ ] **Step 2: Build and verify**

Run: `cd . && ./build-winui3.sh`
Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
git add src/apprt/winui3/tab_manager.zig
git commit -m "feat(tab): wrap closeTab in guard flag (Issue #129)

Prevents SelectionChanged index mismatch during orderedRemove→removeAt gap.
Also calls rebindSwapChain on newly active surface after close."
```

---

### Task 4: Ensure `rebindSwapChain` on Visibility Restore (Issue #128)

**Files:**
- Modify: `src/apprt/winui3/surface_binding.zig:37-71`

- [ ] **Step 1: Fix indexOf usage and add rebindSwapChain call in attachSurfaceToTabItem**

Fix the `indexOf` return type bug (it returns `struct { index, value }`, not `?u32`). After making the active panel visible, call `rebindSwapChain` on the target surface. Replace lines 56-71 (from `// Ensure the active panel` to end of function body):

```zig
    // Ensure the active panel is in the grid (add if not already present).
    // indexOf returns struct { index: u32, value: bool } — value=true means found.
    const in_grid = if (children.indexOf(@ptrCast(panel)) catch null) |r| r.value else false;
    if (!in_grid) {
        try children.append(@ptrCast(panel));
    }

    // Collapse all panels, then make the active one visible.
    // Visibility values: 0 = Visible, 1 = Collapsed.
    for (self.surfaces.items) |s| {
        const p: *winrt.IInspectable = s.surface_grid orelse s.swap_chain_panel orelse continue;
        setPanelVisibility(p, 1); // Collapsed
    }
    setPanelVisibility(panel, 0); // Visible

    // Re-bind swap chain after Visible restore — Collapsed may have detached
    // the panel from the compositor, invalidating the DXGI surface (Issue #128).
    surface.rebindSwapChain();

    log.info("attachSurfaceToTabItem: idx={} panel=0x{x} made Visible + rebind in tab_content_grid", .{ idx, @intFromPtr(panel) });
```

Note: `surface` is already `self.surfaces.items[idx]` from line 46. The `rebindSwapChain` method checks `last_swap_chain` and is a no-op if null (new surface case).

- [ ] **Step 2: Build and verify**

Run: `cd . && ./build-winui3.sh`
Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
git add src/apprt/winui3/surface_binding.zig
git commit -m "feat(tab): rebindSwapChain after Visibility restore (Issue #128)

Collapsed may disconnect SwapChainPanel from compositor.
Always rebind after making panel Visible again."
```

---

### Task 5: Fix `auditActiveTabBinding` to Check Correct Child

**Files:**
- Modify: `src/apprt/winui3/surface_binding.zig:85-110`

- [ ] **Step 1: Fix audit to check indexOf instead of getAt(0)**

Replace `auditActiveTabBinding` (lines 85-110):

```zig
pub fn auditActiveTabBinding(self: anytype) void {
    if (self.active_surface_idx >= self.surfaces.items.len) return;
    const s = self.surfaces.items[self.active_surface_idx];
    const panel: *winrt.IInspectable = s.surface_grid orelse s.swap_chain_panel orelse return;
    const tab_content = self.tab_content_grid orelse return;

    const content_panel = tab_content.queryInterface(com.IPanel) catch return;
    defer content_panel.release();
    const children_raw = content_panel.Children() catch return;
    const children: *com.IVector = @ptrCast(@alignCast(children_raw));
    defer children.release();

    // Check that active surface's panel is present in the grid and Visible.
    // indexOf returns struct { index: u32, value: bool } — value=true means found.
    const in_grid = if (children.indexOf(@ptrCast(panel)) catch null) |r| r.value else false;
    const ue = panel.queryInterface(com.IUIElement) catch null;
    const vis: i32 = if (ue) |u| blk: {
        defer u.release();
        break :blk u.Visibility() catch -1;
    } else -1;
    const size = children.getSize() catch 0;

    log.info(
        "auditActiveTabBinding: active_idx={} panel=0x{x} in_grid={} visibility={} total_children={}",
        .{ self.active_surface_idx, @intFromPtr(panel), in_grid, vis, size },
    );
}
```

- [ ] **Step 2: Build and verify**

Run: `cd . && ./build-winui3.sh`
Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
git add src/apprt/winui3/surface_binding.zig
git commit -m "fix(tab): auditActiveTabBinding checks indexOf instead of getAt(0)

Old logic only checked first child, always mismatched for non-first tabs."
```

---

### Task 6: Remove Redundant rebindSwapChain in onSelectionChanged

**Files:**
- Modify: `src/apprt/winui3/event_handlers.zig:55-91`

- [ ] **Step 1: Remove rebindSwapChain from onSelectionChanged**

Since `attachSurfaceToTabItem` now calls `rebindSwapChain` internally (Task 4), the explicit call in `onSelectionChanged` is redundant. Remove line 84:

```zig
            // rebindSwapChain is now called inside attachSurfaceToTabItem (Issue #128).
            // self.surfaces.items[new_idx].rebindSwapChain();  // Removed: handled by attachSurfaceToTabItem
```

Keep the `focusCallback(true)` and `focusKeyboardTarget` calls — those are still needed.

- [ ] **Step 2: Build and verify**

Run: `cd . && ./build-winui3.sh`
Expected: Build succeeds.

- [ ] **Step 3: Commit**

```bash
git add src/apprt/winui3/event_handlers.zig
git commit -m "refactor(tab): remove redundant rebindSwapChain from onSelectionChanged

Now handled inside attachSurfaceToTabItem (Issue #128)."
```

---

### Task 7: Smoke Test — Build + Launch + Multi-Tab

- [ ] **Step 1: Build ReleaseFast**

Run: `cd . && ./build-winui3.sh`

- [ ] **Step 2: Launch and test tab operations**

Run: `./zig-out-winui3/bin/ghostty.exe`

Test checklist:
1. App launches with 1 tab, terminal renders correctly
2. Click "+" to add tab 2 — tab 2 shows terminal, switch back to tab 1 — content still visible
3. Add tab 3, switch between all 3 tabs — all content preserved
4. Close tab 2 (middle tab) — tab 1 and 3 still work, correct tab selected
5. Close remaining tabs until only 1 left — still works
6. Check logs for "tab_mutation_in_progress" messages confirming guard is working

- [ ] **Step 3: Check logs**

Run: Review ghostty log output for:
- `onSelectionChanged: skipped (tab_mutation_in_progress)` — confirms guard is suppressing triple-fire
- `attachSurfaceToTabItem: ... made Visible + rebind` — confirms rebind on every switch
- `auditActiveTabBinding: ... in_grid=true visibility=0` — confirms correct audit
