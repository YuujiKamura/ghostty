#!/bin/bash
set -e

# Tier 2 Smoke Test for Ghostty WinUI3
# Usage: bash scripts/test_smoke.sh

EXE="./zig-out/bin/ghostty.exe"
LOG="debug.log"

if [ ! -f "$EXE" ]; then
    echo "Error: ghostty.exe not found at $EXE. Run zig build first."
    exit 1
fi

rm -f "$LOG"

echo "Running Smoke Test 1: Basic Start and Shutdown..."
GHOSTTY_WINUI3_CLOSE_AFTER_MS=2000 "$EXE" || true

if grep -q "WinUI 3 Window created and activated" "$LOG"; then
    echo "  ✓ Window created"
else
    echo "  ✗ Window creation not found in log"
    exit 1
fi

if grep -q "WinUI 3 application terminated" "$LOG"; then
    echo "  ✓ Application terminated cleanly"
else
    echo "  ✗ Clean termination not found in log"
    exit 1
fi

echo "Running Smoke Test 2: New Tab on Init..."
rm -f "$LOG"
GHOSTTY_WINUI3_CLOSE_AFTER_MS=3000 GHOSTTY_WINUI3_NEW_TAB_ON_INIT=1 "$EXE" || true

if grep -q "newTab completed: idx=1 total=2" "$LOG"; then
    echo "  ✓ New tab created and verified (total=2)"
else
    echo "  ✗ New tab verification failed"
    exit 1
fi

echo "Running Smoke Test 3: Resize..."
rm -f "$LOG"
GHOSTTY_WINUI3_CLOSE_AFTER_MS=3000 GHOSTTY_WINUI3_TEST_RESIZE=1 "$EXE" || true

if grep -q "initXaml step 10: test_resize triggered" "$LOG"; then
    echo "  ✓ Resize triggered"
else
    echo "  ✗ Resize trigger not found"
    exit 1
fi

echo "Running Smoke Test 4: Title Synchronization (tracing GhosttyTitleUITests)..."
rm -f "$LOG"
CONF_DIR="tmp_smoke_config"
rm -rf "$CONF_DIR"
mkdir -p "$CONF_DIR/ghostty"
echo 'title = "SmokeTestTitle"' > "$CONF_DIR/ghostty/config"

# Launch with custom config dir via XDG_CONFIG_HOME
# Need absolute path for XDG_CONFIG_HOME to be safe
XDG_CONFIG_HOME_ABS=$(powershell.exe -Command "Resolve-Path '$CONF_DIR' | Select-Object -ExpandProperty Path")
GHOSTTY_WINUI3_CLOSE_AFTER_MS=2000 XDG_CONFIG_HOME="$XDG_CONFIG_HOME_ABS" "$EXE" || true

if grep -q "setTitle: \"SmokeTestTitle\"" "$LOG"; then
    echo "  ✓ Title synchronization verified in log"
else
    echo "  ✗ Title synchronization NOT found in log"
    # Dump log for debugging if failed
    # cat "$LOG"
    exit 1
fi

rm -rf "$CONF_DIR"

echo "Running Smoke Test 5: Tab Closure Shutdown (tracing official behavior)..."
rm -f "$LOG"
GHOSTTY_WINUI3_CLOSE_TAB_AFTER_MS=2000 "$EXE" || true

if grep -q "closeTab: no tabs remain, requesting app exit" "$LOG"; then
    echo "  ✓ Last tab closure triggered app exit"
else
    echo "  ✗ App exit on last tab closure NOT verified"
    exit 1
fi

echo "Running Smoke Test 6: WinUI 3 TabView Parity Validation..."
if grep -q "PARITY_FAIL" "$LOG"; then
    echo "  ✗ Parity Validation FAILED! Check debug.log for details."
    grep "PARITY_FAIL" "$LOG"
    exit 1
fi
if grep -q "validateTabViewParity: ALL CHECKS PASSED" "$LOG"; then
    echo "  ✓ TabView structural integrity verified"
else
    echo "  ✗ Structural audit not completed"
    exit 1
fi

echo "Running Smoke Test 7: TabView Fallback Logic (Injecting failure)..."
rm -f "$LOG"
# GHOSTTY_WINUI3_TABVIEW_ITEM_NO_CONTENT=true simulates a failure in TabViewItem content
GHOSTTY_WINUI3_CLOSE_AFTER_MS=2000 GHOSTTY_WINUI3_TABVIEW_ITEM_NO_CONTENT=1 "$EXE" || true
if grep -q "TabViewItem content appears null after putContent; falling back" "$LOG"; then
    echo "  ✓ Fallback to single-tab mode verified"
else
    echo "  ✗ Fallback logic FAILED to trigger"
    exit 1
fi

echo "Running Smoke Test 8: Visual Rendering Verification..."
powershell.exe -ExecutionPolicy Bypass -File scripts/test_visual.ps1
if [ $? -eq 0 ]; then
    echo "  ✓ Visual rendering verified (no white screen)"
else
    echo "  ✗ Visual rendering FAILED"
    exit 1
fi

echo "All Tier 2 Smoke Tests passed!"
