# WinUI 3 Apprt Development Ownership Rules

This workspace uses parallel AI agents (Codex and Gemini). To prevent logic conflicts and interface mismatches, the following ownership rules are **FOUNDATIONAL MANDATES**.

## 1. Task Boundaries (STRICT)

### Codex Ownership (UI Logic Layer)
- **Files:**
  - `src/apprt/winui3/App.zig`
  - `src/apprt/winui3/Surface.zig`
- **Responsibilities:**
  - UI Lifecycle management (Init -> Run -> Terminate).
  - Multi-tab (TabView) logic and Surface transitions.
  - Implementing the `Loaded` event synchronization (deferring `SetSwapChain`).
  - Satisfying all interfaces required by core (`src/App.zig`, `src/Surface.zig`).

### Gemini Ownership (ABI & Infrastructure Layer)
- **Files:**
  - `src/apprt/winui3/com.zig`
  - `src/apprt/winui3/winrt.zig`
  - `scripts/winui3-test-lib.ps1` (and all verification tools)
- **Responsibilities:**
  - Ensuring correct IID/ABI VTable slot offsets (e.g., `IFrameworkElement.add_Loaded` at slot 61).
  - Maintaining WinRT infrastructure (HSTRING, QueryInterface helpers).
  - Managing the build and test staging environment (DLL bundling, runtime assertions).
  - Analyzing debug logs to identify and fix `E_NOINTERFACE` or other ABI failures.

## 2. Interaction Protocol
- **Gemini** MUST NOT directly edit UI Logic files (`App.zig`, `Surface.zig`) unless providing a standalone snippet for Codex to integrate.
- **Codex** MUST follow the ABI definitions provided by Gemini in `com.zig`.
- If an `E_NOINTERFACE` (0x80004002) occurs, Gemini identifies the correct IID/Slot and updates `com.zig`.

## 3. Verification Goals
1. All 3 tabs must report `SUCCESS` in binding their swap chains.
2. Log output must contain `AUDIT_RESULT: tabs=3 bound=3`.
3. Application must exit without `Segmentation fault`.
