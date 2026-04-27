# Lifecycle Cleanup Audit — issue #230

**Date**: 2026-04-27
**Branch**: `audit-230-lifecycle-cleanup` (off `main` @ `f4beed720`)
**Vendor**: `vendor/zig-control-plane` @ `a428e4ae8`
**Scope**: Audit-only — no code changes. Maps every resource that may
**not** be released when the process is `taskkill`'d, crashes, or the OS
reboots, and proposes a fix for each.
**Reference fix**: #195 (`fix(#195): clean up stale session files at
control plane init` — commit `34f5d11aa`). The audit re-uses that
*startup-sweep + liveness-probe* pattern as the recommended template.

> Cleanup paths considered "guaranteed at process death" in this
> document: only **OS-managed** ones (kernel handles closed when the
> process object is destroyed, window classes destroyed when the
> process token releases its `HMODULE`). Anything written by the
> process — files, named-pipe metadata in another peer, system-wide
> timer beat — is assumed **not** cleaned up unless explicitly proven
> otherwise.

---

## Executive summary — top 5 user-visible damages

| Rank | Resource | Failure surface | Severity |
|------|----------|-----------------|----------|
| 1 | `~/AppData/Local/ghostty/control-plane/winui3/logs/*.log` accumulates forever | Disk fills slowly. **Observed today: 162 stale `.log` files** in this repo's checkout, 227 KB total but unbounded. Each crashed/killed session leaves one. | **High** (silent, monotonic) |
| 2 | `~/.ghostty-win/crash/<unix>-watchdog.log` accumulates forever | Each watchdog fire (#139 H1/H2 hangs are common — 5h sessions hit it) writes a new file, never cleaned. | **High** (correlates with the "hang" cluster, so users hitting bugs accrue files fastest) |
| 3 | `win32` apprt session files are **never** swept | #195's sweep was added to WinUI3 only. The win32 apprt (`src/apprt/win32/control_plane.zig`) writes `*.session` files but has no `cleanupStaleSessions` call at init. Stale sessions → deckpilot picks them as "live". | **High** (re-introduces #195 for any user on win32 runtime — uncommon today, but wt-sidecar work uses it) |
| 4 | `timeBeginPeriod(1)` set in WinUI3 with **no `timeEndPeriod` pair** | System-wide timer interrupt rate stays at 1ms after every WinUI3 crash. Battery + scheduler effects across the whole OS until reboot. win32 apprt does pair them (`src/apprt/win32/App.zig:60` ↔ `:246`); WinUI3 only calls Begin (`src/apprt/winui3/App.zig:421`). | **Medium-High** (cross-process effect, includes laptop battery drain) |
| 5 | PTY child (`OpenConsole.exe` / `conhost.exe`) orphaned on hard kill | `Pty.deinit` in `src/pty.zig:443` calls `ClosePseudoConsole`, but only on graceful exit. Hard kill leaves the conhost child plus its child shell orphaned. No `JobObject` ties them to ghostty's lifetime. | **Medium-High** (zombie processes consume RAM and a console handle slot; user sees "ghostty closed but my shell is still there") |

**Issue-creation candidates** (Opus to file later, in suggested order):

1. `feat(#230): add log rotation/sweep for control-plane/winui3/logs/*.log`
2. `feat(#230): clean up watchdog crash dumps (~/.ghostty-win/crash/) on startup`
3. `fix(#230): apply #195 stale-session sweep to win32 apprt`
4. `fix(#230): pair timeBeginPeriod(1) with timeEndPeriod(1) in WinUI3`
5. `fix(#230): wrap PTY child in JobObject (KILL_ON_JOB_CLOSE)`
6. `chore(#230): document non-cleanup paths and add sweep-on-startup to bootstrap`

---

## Methodology

For each of the 7 categories in #230 §"Audit needed", I record:

- **Files & lines** where the resource is acquired and released.
- **Release path** (defer / errdefer / explicit deinit) and whether it is
  reachable when the process dies via:
  - `std.process.exit(2)` (the watchdog path — bypasses defer/cleanup).
  - `taskkill /F` or OS process termination (no Zig stack unwind).
  - Hard crash (segfault, stack overflow — same as taskkill).
  - OS reboot (everything below the kernel disappears, but on-disk state
    survives).
- **Residual harm** when the cleanup is skipped.
- **Suggested fix**, anchored on the #195 startup-sweep pattern.

The 7 categories are merged where appropriate (e.g. "log rotation" lives
under §1 file-system; "WinRT registration" under §3 registry).

---

## §1 File-system

### 1.1 Session files — `*.session` (WinUI3) — **#195 fixed**

- **Acquire**: `src/apprt/winui3/control_plane.zig:213` calls
  `ControlPlaneLib.start()` (in `vendor/zig-control-plane/src/session.zig:77
  SessionManager.writeFile`). Path:
  `%LOCALAPPDATA%\ghostty\control-plane\winui3\sessions\{safe}-{pid}.session`.
- **Release**: `src/apprt/winui3/control_plane.zig:332` `cp.stop()` → vendor
  `removeFile()` (best-effort, returns void).
- **Reachable on hard kill?** No. `cp.stop()` runs from `App.fullCleanup`
  (`App.zig:1508`), only reached on the graceful exit path through the
  XAML message loop. `taskkill /F` or watchdog `process.exit(2)` skip it.
- **Mitigation today**: `initControlPlane` calls
  `zcp.session.cleanupStaleSessions(allocator, "ghostty-winui3")` on the
  next launch (`control_plane.zig:189` after #195). PID liveness probed
  via `defaultIsAlive` (`vendor/.../session.zig:207`) using
  `OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION)` + `GetExitCodeProcess`
  / `STILL_ACTIVE`. Self-protect: current PID still alive when sweep
  runs.
- **Residual gap**: sweep only runs when a *new* WinUI3 ghostty starts.
  If user hard-kills and never re-launches WinUI3, files persist. With 9
  files visible right now in this dev box (`stall-probe-*.session`),
  the gap is real but bounded.
- **Suggested follow-up**: add an `--orphan-sweep` CLI subcommand /
  scheduled task (or a `tools/sweep` helper) so deckpilot can sweep
  without spawning a UI. Low priority — #195 covers the common case.

### 1.2 Session files — `*.session` (win32 apprt) — **NOT fixed**

- **Acquire**: `src/apprt/win32/control_plane.zig:99-129` writes
  `%LOCALAPPDATA%\ghostty\control-plane\win32\sessions\{safe}-{pid}.session`
  via `writeSessionFile()`.
- **Release**: `destroy()` at `:142` calls `std.fs.deleteFileAbsolute`,
  same hard-kill exposure as 1.1.
- **Reachable on hard kill?** No.
- **Mitigation today**: **none**. `cleanupStaleSessions` is **never
  called** for the win32 path (`grep` for `cleanupStaleSessions` in
  `src/` returns zero hits outside the WinUI3 module).
- **Residual harm**: same as #195 — deckpilot/wt-sidecar pick stale
  win32 sessions as live. Lower visibility because most users run
  WinUI3, but `wt-sidecar` and any user on `-Dapp-runtime=win32` paths
  are fully exposed.
- **Suggested fix**: in `ControlPlane.create` after `ensureDirectories()`
  (around `control_plane.zig:128`), call
  `zcp.session.cleanupStaleSessionsIn(self.allocator, self.sessions_dir,
  zcp.session.defaultIsAlive)`. Pattern is identical to #195 but with an
  explicit `dir_path` because the win32 apprt builds its own path
  (`{LOCALAPPDATA}\ghostty\control-plane\win32\sessions`) rather than
  the vendor's WinUI3-shaped path.

### 1.3 Per-session log files — `logs/{safe}-{pid}.log` — **NOT fixed**

- **Acquire**: `src/apprt/win32/control_plane.zig:184` opens (or creates
  with `.truncate=false`) the per-pid log file in `logs_dir`.
- **Release**: file is closed at end of `appendLog` each line. Path is
  **never deleted** by either apprt (`grep -n deleteFileAbsolute
  src/apprt/win*` returns only the `.session` deletion at win32
  `:142`).
- **Reachable on hard kill?** Cleanup wasn't there even on graceful
  exit, so kill-vs-graceful makes no difference: the file is intentionally
  preserved post-mortem for diagnostics.
- **Residual harm**: monotonic disk usage. Direct evidence — this dev
  box has **162 leftover `.log` files in `…/winui3/logs/`** totalling
  227 KB right now, mostly from `codex-*`, `autoscroll-debug-*`, and
  similar killed sessions. At ~1.5 KB each, even heavy users are years
  away from a real "out of disk" event, but: (a) it's monotonically
  unbounded, (b) `Defender` scans every new file, (c) the directory
  listing slows down deckpilot session enumeration.
- **Suggested fix**: at startup (next to the #195 sweep), iterate
  `logs_dir`, parse `{safe}-{pid}.log`, drop entries whose PID is dead
  AND whose mtime is > N days. Two knobs:
    1. PID-dead retention (default 24h — keeps post-mortem useful).
    2. Absolute cap (default 30 days regardless of liveness).
  Same liveness probe as `defaultIsAlive`. Could live in
  `vendor/zig-control-plane/src/session.zig` as `cleanupStaleLogs` and
  be called from both apprts.

### 1.4 Watchdog crash logs — `~/.ghostty-win/crash/<unix>-watchdog.log` — **NOT fixed**

- **Acquire**: `src/apprt/winui3/watchdog.zig:294-318` writes one file
  per watchdog fire.
- **Release**: never. The file is intentionally durable so a post-crash
  user/operator can read it.
- **Reachable on hard kill?** N/A — the file IS the crash record.
- **Residual harm**: each #139 H1/H2 hang (these are frequent on long
  WinUI3 runs per memory `project_ghostty_winui3_hang_28900.md`) writes
  one file. Three concurrent hung sessions = 3 files per incident. Over
  the lifetime of a heavy user, this directory grows without bound.
- **Suggested fix**: bootstrap-time sweep that keeps the most recent
  N files (default 50) AND deletes anything older than 30 days,
  whichever leaves more. Keep this *bootstrap-side* because watchdog
  cleanup must NOT race a watchdog fire.

### 1.5 IPC pipe metadata / lock files — N/A

- No lock files, no `.pid` files, no temp directories owned by the app.
- `ghostty_debug.log` (`src/apprt/winui3/os.zig:685`) uses
  `CREATE_ALWAYS` so it's truncated each launch — bounded by definition
  but **races** between concurrent ghostty processes (last writer wins,
  which is mostly OK for diagnostics).
- Suggested fix: rename per-pid (`ghostty_debug-{pid}.log`) so concurrent
  diagnostic captures don't overwrite each other. Same monotonic-growth
  concern as 1.3 if we do — fold into the same sweep.

### 1.6 PTY pipes — process-bounded

- `src/pty.zig:330` creates `\\.\pipe\LOCAL\ghostty-pty-{pid}-{n}` pipes.
  These are anonymous-equivalent (the `\pipe\LOCAL\` prefix scopes them
  to the session). Kernel destroys them when the last handle closes.
- **Reachable on hard kill?** Yes — kernel handle table teardown closes
  every handle owned by the dying process, which is sufficient. No
  external state to clean.
- **No fix needed.**

---

## §2 Named pipes (server-side)

### 2.1 Control-plane server pipe — `\\.\pipe\ghostty-winui3-{safe}-{pid}`

- **Acquire**: `vendor/zig-control-plane/src/pipe_server.zig:144`
  `CreateNamedPipeW`.
- **Release**: `pipe_server.zig` deinit closes the handle. Server thread
  loops `CreateNamedPipeW` per connection (vendor pattern).
- **Reachable on hard kill?** Pipes are kernel objects bound to the
  creating process's handle table. When the process dies the handle is
  closed and the **server-side** pipe instance is destroyed. Other
  processes that had the pipe open as clients see `ERROR_BROKEN_PIPE` on
  the next read/write — that is the correct behaviour, not a leak.
- **No new server-side leak**. The relevant orphan to consider here is
  the `.session` *file* that points at this pipe name (covered in §1.1).
  A peer process reading the file and trying to connect will get
  `ERROR_FILE_NOT_FOUND` — annoying but not a resource leak.

### 2.2 Single-instance IPC pipe — `\\.\pipe\ghostty-{instance_id}` or `ghostty-default`

- **Acquire**: `src/apprt/winui3/ipc.zig:149` `CreateNamedPipeW` per
  `listenerLoop` iteration.
- **Release**: `ipc.zig:184` `CloseHandle(pipe)` per connection;
  `deinit()` at `:107` joins the listener thread and closes the
  handle for the in-flight pipe (via `unblockListener` at `:123`).
- **Reachable on hard kill?** No. But same kernel argument as 2.1 — the
  handle dies with the process, no external metadata persists.
- **Residual harm**: minimal. Listening pipes do not leave anything
  on-disk.
- **No fix recommended.**

### 2.3 PTY pipes — covered in §1.6.

**Overall §2 verdict**: Windows named pipes are kernel objects with
proper auto-cleanup. The risks are entirely in the **on-disk metadata**
that points at pipe names (`.session` files), which is §1's problem.

---

## §3 Registry entries / WinRT registration / file association

### 3.1 Registry — none

- `grep -E "RegCreateKey|RegOpenKey|RegSetValue|HKEY_"` over `src/`
  returns **zero matches**. ghostty-win does not write to the registry.
- **No fix needed.**

### 3.2 WinRT activation factories

- Bootstrap: `src/apprt/winui3/bootstrap.zig:60` calls
  `MddBootstrapInitialize`. Shutdown: `bootstrap.zig:76 deinit()` calls
  the matching `MddBootstrapShutdown` and `FreeLibrary`.
- **Reachable on hard kill?** No. But MddBootstrap state is per-process
  (it manipulates the in-process activation context, not a global
  registry). Process death tears it down with the process — no system-
  wide residue.
- **No fix needed.**

### 3.3 Window classes (`RegisterClassExW`)

- WinUI3 registers three classes: `nonclient_island_window` drag-bar
  (`nonclient_island_window.zig:422`), `island_window` content
  (`island_window.zig:57`), `input_overlay`
  (`input_overlay.zig:32`).
- All gated by `static bool *_class_registered = false` — **never
  unregistered**. WinUI3's `fullCleanup` does NOT call
  `UnregisterClassW`. The win32 apprt does
  (`src/apprt/win32/App.zig:243`).
- **Reachable on hard kill?** Window classes are reference-counted by
  the OS per `HMODULE`. They auto-unregister when the executable's
  `HMODULE` is unloaded (i.e. when the process exits, gracefully or
  not). So the leak is *intra-process only* — when the same process
  re-creates a window after a partial cleanup, the class is still
  registered (which is why the code handles `ERROR_CLASS_ALREADY_EXISTS
  = 1410` at `nonclient_island_window.zig:425`).
- **Residual harm**: none cross-process. Intra-process re-creation is
  handled correctly.
- **No fix needed.**

### 3.4 File association / ProgID

- `grep -E "ProgID|file_association"` returns no matches. Not
  registered. **No fix needed.**

---

## §4 Shared memory / memory-mapped files

- `grep -E "CreateFileMapping|MapViewOfFile|OpenFileMapping"` returns
  **zero matches**. ghostty-win does not use named shared memory.
- The "shared-memory snapshots" mentioned in `control_plane.zig:55-57`
  are just in-process buffers, not OS shared memory.
- **No fix needed.**

---

## §5 Job objects / process groups / child processes

### 5.1 PTY child (`OpenConsole.exe` / `conhost.exe`)

- **Acquire**: `src/pty.zig:430` `CreatePseudoConsole(...)` spawns the
  console host as a child of ghostty.
- **Release**: `Pty.deinit` (`pty.zig:443`) calls `ClosePseudoConsole`,
  which in turn signals the console host to exit. `Command.zig` runs
  `CreateProcessW` for the user shell as a grandchild.
- **Reachable on hard kill?** **No.** Without a Job Object, when ghostty
  is `taskkill /F`'d Windows does NOT cascade-kill its descendants.
  `OpenConsole.exe` keeps running until it notices its master pipe is
  closed, then it exits — but the **shell** the user spawned is now an
  orphan reparented to the system process. Most shells (cmd, pwsh) exit
  when stdin closes; some (vim, less waiting on input, an SSH session,
  a `tail -f`) do not, and become true zombies.
- **Residual harm**: orphaned `pwsh.exe` / `bash.exe` / SSH client
  processes, each holding RAM and possibly network sockets. Visible in
  Task Manager as "no parent" processes. Repeated kills accrete them.
- **Suggested fix**: wrap each PTY in a `JobObject` with
  `JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE`. When ghostty dies for any
  reason — graceful, taskkill, segfault, watchdog `exit(2)` — the kernel
  closes the Job's handle, which cascade-terminates all members. The
  Job has to be created **before** `CreatePseudoConsole`, and the
  console process attached via `AssignProcessToJobObject` (or, simpler:
  use `STARTUPINFOEX` with `PROC_THREAD_ATTRIBUTE_JOB_LIST` so the
  child is in the job from creation, avoiding a race window).
- **Alternative**: rely on `EXTENDED_STARTUPINFO_PRESENT` +
  `PROCESS_BREAKAWAY_OK = false` — gives partial cascade but still
  doesn't survive `taskkill` because nothing ties the child to the
  parent's process object.
- **Cost**: small — JobObject is a single handle and the scaffolding is
  a few dozen lines in `pty.zig` / `Command.zig`. Already a known
  Windows-terminal pattern (Conhost itself uses one).

### 5.2 Other spawned processes

- `Command.zig:362` is the generic `CreateProcessW` (used by
  `--exec`, recovery actions, etc.). Same orphan risk as 5.1. Same fix
  applies — share the JobObject.

---

## §6 GPU resources (D3D11)

### 6.1 D3D11 device + context + factory

- **Acquire**: `src/renderer/D3D11.zig:106 init()` creates
  `ID3D11Device`, `ID3D11DeviceContext`, `IDXGIFactory2`.
- **Release**: `D3D11.zig:154 deinit()` walks the chain
  (swap chain → factory → context.flush + release → device → composition
  surface handle).
- **Reachable on hard kill?** No defer/deinit runs on hard kill. But:
  GPU resources are owned by the **DXGI/D3D kernel-mode object table**
  per process. When the process dies the kernel reclaims them. The
  composition surface handle (`composition_surface_handle`) is a
  kernel handle — same auto-close on process death.
- **Residual harm cross-process**: essentially zero. The driver may
  hold transient state (work queued in the command buffer) for a few
  ms, then reclaims. No system-wide leak.
- **One subtle gap**: in **Debug** builds (`D3D11_CREATE_DEVICE_DEBUG`,
  `D3D11.zig:115`) the D3D Debug Layer prints "Live Object" reports on
  the next debugger attach if the process didn't release everything.
  This is dev-only noise, not a production resource leak.
- **No production fix needed**. For Debug noise, keep current
  `deinit()` and rely on the graceful-exit path.

---

## §7 DWM compositor state

### 7.1 `DwmExtendFrameIntoClientArea` / glass titlebar

- **Acquire**: `src/apprt/winui3/nonclient_island_window.zig:184`
  extends the frame each resize.
- **Release**: not explicitly released. DWM compositor state is
  per-window; when the HWND is destroyed the compositor entries
  disappear with it.
- **Reachable on hard kill?** Window destruction is OS-driven on
  process death, so the DWM entry is reclaimed.
- **No fix needed.**

### 7.2 Transparent drag bar (`createDragBarWindow`)

- **Acquire**: `nonclient_island_window.zig:445` `CreateWindowExW` with
  `WS_EX_LAYERED | WS_EX_NOREDIRECTIONBITMAP`.
- **Release**: `App.fullCleanup` at `App.zig:1473` calls
  `nci.destroyDragBarWindow()`. Even when not called, the OS destroys
  child windows with their parent on process death.
- **Residual harm**: none cross-process. The compositor doesn't keep
  a "ghost" of a destroyed HWND.
- **No fix needed.**

### 7.3 Layered-window memory

- `WS_EX_LAYERED` allocates a redirection bitmap in DWM (per-window).
  Process-bound; auto-cleaned by the OS.

**Overall §7 verdict**: DWM state is HWND-bound, HWNDs die with the
process. No fix required.

---

## §8 Cross-cutting: system-wide timer beat — **NEW finding, not in #230 list**

- `src/apprt/winui3/App.zig:421` calls `os.timeBeginPeriod(1)` to raise
  the system multimedia-timer rate to 1 ms.
- **No matching `timeEndPeriod(1)`** anywhere in `src/apprt/winui3/`.
  Confirmed by `grep -n "timeEndPeriod\|timeBeginPeriod"
  src/apprt/winui3/App.zig` → only one match (line 421).
- The win32 apprt **does** pair them
  (`src/apprt/win32/App.zig:60` ↔ `:246`).
- **Reachable on hard kill?** Windows reference-counts
  `timeBeginPeriod` per process — the OS DOES decrement when the
  process exits, even on hard kill. So the *system-wide* leak is
  bounded to the lifetime of all currently-running ghostty processes.
- **Residual harm**: none cross-process *after* the process is gone.
  But the asymmetry vs the win32 apprt is still worth flagging — if
  ghostty's main loop ever re-enters or the process is suspended (e.g.
  PLM/UWP-style), the lack of an explicit `timeEndPeriod` will hold the
  beat artificially. Also, mismatched `Begin`/`End` count in tests can
  trip the OS reference counter into a "permanently elevated" state if
  refactoring ever moves the call.
- **Suggested fix (low effort)**: in `App.fullCleanup` (where it
  already pairs `BufferedPaintInit`/`BufferedPaintUnInit` at
  `App.zig:1598`), add `_ = os.timeEndPeriod(1);`. Also document the
  pairing convention so future code doesn't drift.

---

## §9 Cross-cutting: known issue links

- **#195** (closed): WinUI3 stale session sweep. Template for §1.1, §1.2,
  §1.3, §1.4 fixes.
- **#220**: BlockingQueue.shutdown() — added the producer/consumer
  shutdown contract that other lifecycle tear-down uses. Documented in
  `notes/2026-04-26_deadlock_lint_rules.md` and
  `notes/architecture/2026-04-27_phase2_bounded_mailbox_design.md`.
  Not a leak source itself, but the `shutdown()` semantics are required
  for any new "kill the consumer thread cleanly" path that lifecycle
  fixes might add.
- **#207**: CP read-lane `tryLock` (renderer mutex contention) — already
  drives `last_renderer_locked` in `control_plane.zig`. No lifecycle
  exposure.
- **#214**: Dispatcher watchdog log sink — feeds the watchdog crash log
  cluster in §1.4.
- **winshot-killed-WT incident** (issue body): example of a child
  killing its parent. Same JobObject fix in §5.1 applies — a JobObject
  with `JOB_OBJECT_LIMIT_BREAKAWAY_OK = false` for child PTY processes
  prevents *them* from killing the parent's job.

---

## §10 Recommended implementation order (for follow-up issues)

1. **Win32 apprt #195 parity** (§1.2). One-line addition, identical
   pattern to WinUI3. Highest risk-reduction per LOC.
2. **`timeEndPeriod` pair** (§8). One line. Easy win.
3. **Log sweep** (§1.3 + §1.4). One sweep helper in
   `vendor/zig-control-plane/src/session.zig`, called from both apprt
   bootstraps. Same liveness probe.
4. **JobObject for PTY** (§5.1). Bigger surface — introduces
   `STARTUPINFOEX` + `PROC_THREAD_ATTRIBUTE_JOB_LIST` machinery in
   `pty.zig` / `Command.zig`. Test plan: `taskkill /F` ghostty, observe
   Task Manager — pwsh / vim children should disappear.
5. **`ghostty_debug.log` per-pid + sweep** (§1.5). Diagnostic-only,
   bottom of priority but one-line rename.

---

## §11 Out of scope (intentionally not audited here)

- **Memory leaks** that don't survive the process — `defer` paths inside
  one process. Already covered by Zig's allocator + valgrind/asan in
  test runs.
- **Renderer thread shutdown deadlocks** — covered by #220 and the
  Phase 2 bounded mailbox work, not lifecycle leaks.
- **xcb/Wayland/macOS apprt cleanup** — Windows-only audit.
- **`vendor/zig-control-plane` internals** beyond its session/cleanup
  contract — that vendor is a separate repo; only its public API
  surface (`cleanupStaleSessions`, `cleanupStaleSessionsIn`,
  `defaultIsAlive`) is in scope.

---

## Appendix A — observed residual state on disk (reproducer)

```text
$ ls "$LOCALAPPDATA/ghostty/control-plane/winui3/sessions" | wc -l
9
$ ls "$LOCALAPPDATA/ghostty/control-plane/winui3/logs" | wc -l
162
$ du -sh "$LOCALAPPDATA/ghostty/control-plane/winui3/logs"
227K
```

(Captured 2026-04-27 on the audit dev box — not synthesised. The 9
session files include `stall-probe-*.session` from killed reproduction
runs, demonstrating the #195 sweep gap when a fresh launch never
happens.)

## Appendix B — files touched while reading (no edits)

- `src/apprt/winui3/control_plane.zig`
- `src/apprt/winui3/App.zig` (lines 1416-1612)
- `src/apprt/winui3/bootstrap.zig`
- `src/apprt/winui3/ipc.zig`
- `src/apprt/winui3/nonclient_island_window.zig` (lines 400-475)
- `src/apprt/winui3/island_window.zig`
- `src/apprt/winui3/input_overlay.zig`
- `src/apprt/winui3/watchdog.zig` (lines 270-369)
- `src/apprt/winui3/os.zig` (lines 670-702)
- `src/apprt/win32/control_plane.zig`
- `src/apprt/win32/App.zig`
- `src/pty.zig` (lines 330-450)
- `src/Command.zig` (lines 100-380)
- `src/renderer/D3D11.zig` (lines 100-170)
- `vendor/zig-control-plane/src/session.zig`
- `vendor/zig-control-plane/src/pipe_server.zig`
