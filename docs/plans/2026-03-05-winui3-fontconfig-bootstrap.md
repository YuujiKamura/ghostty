# WinUI3 Fontconfig Bootstrap Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Eliminate `Fontconfig error: Cannot load default config file` on Windows/WinUI3 by shipping a default Fontconfig config and setting `FONTCONFIG_FILE`/`FONTCONFIG_PATH` at startup.

**Architecture:** Keep `fontconfig_freetype` backend unchanged. Add a small Windows-safe bootstrap that derives paths from `resources_dir` and exports environment variables before font discovery initializes. Install a bundled `fonts.conf` (+ optional `conf.d`) into `share/ghostty/fontconfig`.

**Tech Stack:** Zig, Ghostty build system (`GhosttyResources.zig`), WinUI3 runtime, Fontconfig.

---

### Task 1: Add deterministic path builder for Fontconfig env

**Files:**
- Create: `src/os/fontconfig_env.zig`
- Modify: `src/os/main.zig`
- Test: `src/os/fontconfig_env.zig`

**Step 1: Write the failing test**

Add tests in `src/os/fontconfig_env.zig` for:
- `resources_dir = "C:/x/share/ghostty"` -> file path `.../fontconfig/fonts.conf`
- path env `.../fontconfig`
- null/empty resources -> returns nulls

**Step 2: Run test to verify it fails**

Run: `zig test src/os/fontconfig_env.zig`  
Expected: FAIL (module/function missing).

**Step 3: Write minimal implementation**

Implement a pure helper:
- Input: optional resources dir string
- Output: `{ file: ?[]const u8, path: ?[]const u8 }`
- No Windows API calls, only string join/validation

**Step 4: Run test to verify it passes**

Run: `zig test src/os/fontconfig_env.zig`  
Expected: PASS.

**Step 5: Commit**

```bash
git add src/os/fontconfig_env.zig src/os/main.zig
git commit -m "win: add fontconfig env path resolver"
```

### Task 2: Wire startup env export in global init

**Files:**
- Modify: `src/global.zig`
- Modify: `src/os/env.zig` (only if helper overloads are needed)
- Test: `src/os/fontconfig_env.zig` (extend tests for integration helper inputs)

**Step 1: Write the failing test**

Add a test for helper behavior used by global init:
- given a valid resources dir, exported key/value pairs should be:
  - `FONTCONFIG_FILE=<resources>/fontconfig/fonts.conf`
  - `FONTCONFIG_PATH=<resources>/fontconfig`

**Step 2: Run test to verify it fails**

Run: `zig test src/os/fontconfig_env.zig`  
Expected: FAIL for missing integration-oriented helper.

**Step 3: Write minimal implementation**

In `src/global.zig`, after `self.resources_dir` resolution:
- If `build_config.font_backend.hasFontconfig() == true`
- If `resources_dir.app()` exists
- Build paths via `os.fontconfig_env` helper
- Call `internal_os.setenv("FONTCONFIG_FILE", ...)`
- Call `internal_os.setenv("FONTCONFIG_PATH", ...)`
- Log one info line with resolved paths (or one warn on failure)

**Step 4: Run test to verify it passes**

Run:
- `zig test src/os/fontconfig_env.zig`
- `zig build -Dapp-runtime=winui3 -Drenderer=d3d11`

Expected: PASS; build succeeds.

**Step 5: Commit**

```bash
git add src/global.zig src/os/fontconfig_env.zig src/os/env.zig
git commit -m "win: set FONTCONFIG_FILE and FONTCONFIG_PATH from resources dir"
```

### Task 3: Ship bundled fontconfig resources

**Files:**
- Create: `src/fontconfig/windows/fonts.conf`
- Create: `src/fontconfig/windows/conf.d/README` (or actual conf snippets if needed)
- Modify: `src/build/GhosttyResources.zig`

**Step 1: Write the failing test**

Define verification command first (acts as failing acceptance check):
- Build/install artifacts should contain `zig-out/share/ghostty/fontconfig/fonts.conf`

**Step 2: Run test to verify it fails**

Run:
- `zig build -Dapp-runtime=winui3 -Drenderer=d3d11`
- `Test-Path zig-out/share/ghostty/fontconfig/fonts.conf`

Expected: `False` before installation logic is added.

**Step 3: Write minimal implementation**

In `GhosttyResources.init`:
- Add install step copying `src/fontconfig/windows` to `share/ghostty/fontconfig`
- Keep it enabled on Windows builds (safe to gate by target OS).

Add `fonts.conf` minimal content:
- include default config include chain
- include Windows font dir (e.g. `C:/Windows/Fonts`)
- keep it small and deterministic

**Step 4: Run test to verify it passes**

Run:
- `zig build -Dapp-runtime=winui3 -Drenderer=d3d11`
- `Test-Path zig-out/share/ghostty/fontconfig/fonts.conf`

Expected: `True`.

**Step 5: Commit**

```bash
git add src/build/GhosttyResources.zig src/fontconfig/windows
git commit -m "build: install bundled fontconfig config for windows"
```

### Task 4: Runtime verification (tab on/off)

**Files:**
- No code changes expected
- Verify logs: `C:/Users/yuuji/ghostty-win/debug.log`

**Step 1: Write the failing test**

Define acceptance criteria:
- `Fontconfig error: Cannot load default config file` must not appear.

**Step 2: Run test to verify it fails (current baseline)**

Run:
- `timeout 10 ./zig-out/bin/ghostty.exe`
- `GHOSTTY_WINUI3_ENABLE_TABVIEW=false timeout 10 ./zig-out/bin/ghostty.exe`
- grep `debug.log` for Fontconfig error

Expected: FAIL before fixes.

**Step 3: Execute verification after implementation**

Run same commands after Tasks 1-3.

**Step 4: Confirm pass conditions**

Expected:
- no Fontconfig config-load error in both tab modes
- existing render signals still present:
  - `D3D11 swap chain created`
  - `Swap chain bound to SwapChainPanel`
  - `Present OK frame=...`

**Step 5: Commit verification note**

```bash
git add docs/plans/2026-03-05-winui3-fontconfig-bootstrap.md
git commit -m "docs: record winui3 fontconfig verification results"
```

### Task 5: Optional hardening (only if errors remain)

**Files:**
- Modify: `src/fontconfig/windows/fonts.conf`
- Possibly create: `src/fontconfig/windows/conf.d/*.conf`

**Step 1: Add targeted failing check**

If remaining error indicates missing include dir or cache path, capture exact line and assert repro command.

**Step 2: Minimal fix**

Add only required include/cache directives for Windows runtime; avoid broad distro-specific config.

**Step 3: Verify**

Run the same two 10s launch checks and confirm no new warnings/regressions.

**Step 4: Commit**

```bash
git add src/fontconfig/windows
git commit -m "win: harden bundled fontconfig defaults"
```

---

Plan complete and saved to `docs/plans/2026-03-05-winui3-fontconfig-bootstrap.md`. Two execution options:

**1. Subagent-Driven (this session)** - I execute task-by-task with checkpoints after each task.  
**2. Parallel Session (separate)** - open a new execution-focused session and run this plan end-to-end.

---

## Execution Notes (2026-03-05)

### Task 4 verification logs

- TabView enabled run log: `C:/Users/yuuji/ghostty-win/debug_tab_true.log`
- TabView disabled run log: `C:/Users/yuuji/ghostty-win/debug_tab_false.log`

Commands used:

```powershell
# tab=true
$env:GHOSTTY_WINUI3_ENABLE_TABVIEW='true'
.\zig-out\bin\ghostty.exe   # run ~8s, then terminate
Copy-Item debug.log debug_tab_true.log -Force

# tab=false
$env:GHOSTTY_WINUI3_ENABLE_TABVIEW='false'
.\zig-out\bin\ghostty.exe   # run ~8s, then terminate
Copy-Item debug.log debug_tab_false.log -Force

# error check
rg -n "Fontconfig error: Cannot load default config file" debug_tab_true.log
rg -n "Fontconfig error: Cannot load default config file" debug_tab_false.log
```

Observed results:

- No `Fontconfig error: Cannot load default config file` in either mode.
- Render signals present in both modes:
  - `D3D11 swap chain created`
  - `Swap chain bound to SwapChainPanel`
  - `Present OK frame=...`
