# Lifecycle cleanup audit (process exit / crash)

## Scope

Audits which `defer` / `errdefer` / explicit `close` paths inside the
WinUI3 apprt run only on **graceful exit** (`App.deinit`,
`ControlPlane.destroy`, etc.) and therefore leak resources or leave
observable residue when the ghostty process is killed by `taskkill /F`,
SIGKILL-equivalent, an unhandled exception, or a hard reboot.

Out of scope: `src/Surface.zig` top-level, `src/termio/`, `src/os/`, and
other upstream-shared core (per #238 apprt-contract; cleanup work belongs
under `src/apprt/winui3/`). PTY child-process lifecycle is owned by
`termio/Exec.zig` and tracked separately.

Source pin: `fork/main` @ `c7f338f1b`.

## Findings

### 1. CP session files (`*.session`)
- **Resource**: `%LOCALAPPDATA%\ghostty\control-plane\winui3\sessions\<safe_name>-<pid>.session`. Created by `vendor/zig-control-plane/src/session.zig::SessionManager.writeFile` from `ControlPlane.start()` (called inside `initControlPlane` at `src/apprt/winui3/control_plane.zig:317`).
- **Cleanup path**: `ControlPlane.stop()` → `SessionManager.removeFile()` → `deleteFileFromPath`. Wired through `ControlPlane.destroy` at `src/apprt/winui3/control_plane.zig:454-466` (graceful only).
- **Crash safety**: **leaks indefinitely.** The intended startup-sweep (`zcp.session.cleanupStaleSessions`) was authored on branch `fix-195-stale-session-cleanup` (commit `34f5d11aa`) but **was never merged into `fork/main`**. `git log --all -S "cleanupStaleSessions" -- src/apprt/winui3/control_plane.zig` shows the helper added there and nowhere else, and the present `initControlPlane` body (`control_plane.zig:282-334`) does not call it. The library export at `vendor/zig-control-plane/src/session.zig:297 cleanupStaleSessions` therefore has zero callers in `src/`.
- **Observable impact**: stale `.session` files accumulate; deckpilot / external observers that enumerate the sessions dir can mistake a dead PID's file for a live ghostty until the file is manually deleted. (This is the original #195 symptom.) Issue #230 body claims "(#195 fix済)" — **this is incorrect on `fork/main`**; the fix lives in an unmerged branch.

### 2. CP named pipe (`\\.\pipe\ghostty-winui3-<safe_name>-<pid>`)
- **Resource**: server-side handle for the control-plane pipe, created by `vendor/zig-control-plane`'s `PipeServer` (started from `control_plane.zig:330-331`). The pipe **name** embeds the PID, so collisions across reboots are impossible.
- **Cleanup path**: `ControlPlane.destroy → pipe_server.deinit` (`control_plane.zig:455-459`). Server thread is stopped, handle released.
- **Crash safety**: handle is reclaimed by the kernel when the process dies. Pipe name disappears with the last open handle. The next ghostty launches under a new PID and binds a new pipe name, so re-bind never blocks.
- **Observable impact**: none for the pipe itself. (The associated session file is the leak — see #1.)

### 3. Legacy IPC pipe (`\\.\pipe\<configured-name>`)
- **Resource**: per-connection `CreateNamedPipeW` instance in `src/apprt/winui3/ipc.zig:149` (legacy `IpcServer`, separate from the CP pipe).
- **Cleanup path**: `IpcServer.deinit` (`ipc.zig:107-121`) — flips `running=false`, calls `unblockListener` to break the blocked `ConnectNamedPipe`, joins the listener thread, frees `pipe_name`. Per-connection pipes are closed inside `listenerLoop` at `ipc.zig:171/178/184`.
- **Crash safety**: kernel-reclaimed. Connected clients see `ERROR_BROKEN_PIPE` on next read; their cleanup is their problem.
- **Observable impact**: none.

### 4. Background threads (winui3-apprt-owned)
- **Resources / spawn sites**:
  - `App.watchdog_thread` — `src/apprt/winui3/App.zig:846`, joined at `App.zig:1662-1664`.
  - `IpcServer.listener_thread` — `src/apprt/winui3/ipc.zig:96`, joined at `ipc.zig:114-117`.
  - `cascade_detector.zig:442` — joined inside `cascade_detector.deinit`.
  - `tab_manager.zig:185 cleanup_thread = ...; cleanup_thread.detach()` (`DeferredSurfaceClose`) — **detached, never joined**.
  - `App.zig:473 reloadConfigThreadMain` — short-lived spawn, not joined; runs to completion.
  - `App.zig:2116 (open-URL helper) std.Thread.spawn` — short-lived, not joined.
- **Crash safety**: every thread terminates with the process. Detached `DeferredSurfaceClose` is the only one that releases real WinRT/COM state in its body; if it dies mid-run on hard kill the COM refs are torn down by the kernel. No handle leak on the OS side.
- **Observable impact**: none after process death. The risk is **mid-shutdown deadlock** (e.g. graceful `App.deinit` waiting on a thread whose detach never landed) — that's a different issue from the process-kill audit.

### 5. Debug log file (`%TEMP%\ghostty_debug.log`)
- **Resource**: `CreateFileW(..., CREATE_ALWAYS, GENERIC_WRITE, FILE_SHARE_READ)` and `SetStdHandle(STD_ERROR_HANDLE, h)` in `src/apprt/winui3/os.zig:691-718 attachDebugConsole`. Called once from `App.zig:527` at startup.
- **Cleanup path**: **none.** The handle is intentionally leaked — there is no `CloseHandle`, no `defer`, no companion `detachDebugConsole`. The expectation is that the OS reclaims the handle at process exit.
- **Crash safety**: handle reclaimed by the kernel; the on-disk file persists but has no log-rotation policy. Each run truncates it (CREATE_ALWAYS).
- **Observable impact**: prior-run debug output is overwritten on the next launch. The file itself stays around indefinitely (a few MB at most). Not a real leak; called out for completeness because the issue body listed "log rotation 無し蓄積" as a candidate.

### 6. WinRT / COM activations (HSTRING, IInspectable refcounts)
- **Resources**: many `winrt.hstring`, `winrt.activateInstance`, `getActivationFactory`, and `ComRef` guards across `App.zig`, `caption_buttons.zig`, `event_handlers.zig`, `tab_manager.zig`, `nonclient_island_window.zig`, etc. Almost every site uses `defer guard.deinit()` / `defer hs.deinit()` / `defer factory.release()`.
- **Cleanup path**: scoped guards on the graceful path. Apartment/runtime is cleaned by `RoUninitialize` only on graceful shutdown.
- **Crash safety**: kernel-reclaimed — COM apartments, factory caches, and HSTRING pool all live in process memory. No cross-process leak.
- **Observable impact**: none.

### 7. GPU resources (D3D11 device, DXGI swap chain, SwapChainPanel)
- **Resources**: `ID3D11Device`, `IDXGISwapChain1`, `ID3D11DeviceContext`, render-target views, vertex/index buffers, shaders. Bound to `SwapChainPanel` via `ISwapChainPanelNative` (`App.zig:2515-2529`). Lifetime is tied to the per-Surface renderer in `src/renderer/d3d11/`.
- **Cleanup path**: per-renderer `deinit` (upstream-shared) and `App.deinit → Surface.deinit` chain.
- **Crash safety**: GPU driver reclaims **all** process-owned resources on process death (DXGI/D3D11 are process-scoped). DWM may briefly hold the last-presented swap-chain frame for compositing, but releases it within one frame.
- **Observable impact**: none. (The "GPU resources leaked across crash" item from the issue body is — per the audit — not actually a leak vector on Windows; the kernel/driver always reclaims process-scoped GPU state.)

### 8. DWM compositor state (custom titlebar)
- **Resource**: `DwmExtendFrameIntoClientArea(hwnd, &margins)` at `nonclient_island_window.zig:184`, and `DwmSetWindowAttribute` for dark mode + caption color at `nonclient_island_window.zig:155-159`. Plus the transparent drag-bar child HWND (registered class `GhosttyDragBar`).
- **Cleanup path**: `NonClientIslandWindow.close` (`nonclient_island_window.zig:115-120`) calls `destroyDragBarWindow` and chains into `IslandWindow.close → DestroyWindow(hwnd)`.
- **Crash safety**: DWM tracks compositor state per-HWND; the kernel destroys the HWND on process death and DWM cleans up its side-band state synchronously. Window class registration (`GhosttyDragBar`, `GhosttyWindow`, `GhosttyInputOverlay`) survives within the **session** until the last instance unregisters, but the process-private hInstance dies with the process so the class is automatically unregistered.
- **Observable impact**: none.

### 9. Window handles + subclasses
- **Resource**: top-level HWND (`GhosttyWindow`), drag-bar child HWND, input-overlay child HWND. Subclasses installed via `comctl32!SetWindowSubclass` (no live caller in winui3; pattern declared in `os.zig`).
- **Cleanup path**: `IslandWindow.close → DestroyWindow` (`island_window.zig:191-212`).
- **Crash safety**: kernel-reclaimed. HWNDs cannot outlive their owning thread/process.
- **Observable impact**: none.

### 10. CP pending-input + IME-inject queues + response cache
- **Resource**: heap-allocated entries owned by `ControlPlane.pending_inputs`, `pending_ime_injects`, `response_cache` (mutex-protected vectors / structs in `control_plane.zig`).
- **Cleanup path**: `ControlPlane.destroy → clearPendingInputs → clearResponseCache` (`control_plane.zig:468-469, 478-496`).
- **Crash safety**: process heap reclaimed by OS.
- **Observable impact**: none.

### 11. Debug-console replacement and stderr redirection
- **Resource**: replaced `STD_ERROR_HANDLE` → log-file handle. The original handle is leaked (we don't store it).
- **Cleanup path**: none (matches #5).
- **Crash safety**: kernel reclaim.
- **Observable impact**: none — but if a crash hits before `attachDebugConsole`'s `SetStdHandle` returns, stderr-bound diagnostics from very early bootstrap are lost.

## Sweep recommendations

| # | Resource | Sweep mechanism | Priority | Effort |
|---|---|---|---|---|
| 1 | CP session files | **Re-land `fix-195-stale-session-cleanup`'s startup sweep** (cherry-pick `34f5d11aa` into `src/apprt/winui3/control_plane.zig::initControlPlane`). Bumps `vendor/zig-control-plane` if not already current. | **P0** | 30 min — pure relocate of an existing tested patch |
| 2 | CP named pipe | OS-handles-it (kernel reclaims handle; pipe name has PID baked in so collisions are impossible) | done | n/a |
| 3 | Legacy IPC pipe (`ipc.zig`) | OS-handles-it | done | n/a |
| 4 | `ghostty_debug.log` | OS-handles-it for handle. Optional: add weekly rotation via filename suffix (low value — file caps at a few MB, CREATE_ALWAYS truncates each run) | P2 | 1 h if pursued |
| 5 | Detached `DeferredSurfaceClose` thread | OS-handles-it on hard kill. Mid-graceful-shutdown is a separate concern (see #239 retrospective) | P1 | tracked separately |
| 6 | WinRT / COM, GPU, DWM, HWND | OS-handles-it (process-scoped, kernel reclaim) | done | n/a |
| 7 | New `apprt/winui3/lifecycle.zig` module | per #230 addendum + `docs/apprt-contract.md`: future home for additional sweep / vacuum logic that doesn't fit in `control_plane.zig` (registry, shared-mem, job objects, etc. — none are leaked today, but the location is reserved) | P2 | only when a real second sweep emerges |

## Cross-references
- #195 — session-file sweep precedent. **Open finding: the fix is unmerged on `fix-195-stale-session-cleanup` (`34f5d11aa`).** Closing #230 should be paired with re-landing #195.
- #238 / `docs/apprt-contract.md` — cleanup belongs under `src/apprt/winui3/`, not in upstream-shared core.
- #239 — Phase 2 retrospective; the Tier 2 work (`apprt/winui3/lifecycle.zig` module, additional sweepers) follows the same contract.
- winshot WT crash incident (issue #230 body) — child-process lifecycle is owned by `termio/Exec.zig` (upstream-shared) and is out of scope here. The audit-relevant takeaway is that ghostty-side CP / pipe / session resources do not contribute to that incident.
