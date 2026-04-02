#!/bin/bash
# WinUI3 build wrapper — enforces --prefix zig-out-winui3
set -e

PREFIX_STABLE="zig-out-winui3"
PREFIX_STAGING="zig-out-winui3-staging"
PREFIX_BUILD="zig-out-winui3-build"
PREFIX="$PREFIX_STABLE"
XAML_DIR="xaml"
PREBUILT_ONLY="${GHOSTTY_WINUI3_PREBUILT_ONLY:-0}"
PREBUILT_STRICT="${GHOSTTY_WINUI3_PREBUILT_STRICT:-0}"

# If the stable exe is locked (running), build to staging.
# If both stable and staging are locked, use a third prefix. Windows locks exe for writing while running.
is_locked() { [ -f "$1/bin/ghostty.exe" ] && ! (exec 3<> "$1/bin/ghostty.exe") 2>/dev/null; }
if is_locked "$PREFIX_STABLE"; then
    if is_locked "$PREFIX_STAGING"; then
        PREFIX="$PREFIX_BUILD"
        echo "[build-winui3] Both prefixes locked, building to $PREFIX"
    else
        echo "[build-winui3] ghostty.exe locked, building to $PREFIX_STAGING"
        PREFIX="$PREFIX_STAGING"
    fi
fi

# Detect Release mode from args
BUILD_CONFIG="Debug"
UPDATE_PREBUILT="0"
for arg in "$@"; do
    case "$arg" in
        -Doptimize=ReleaseFast|-Doptimize=ReleaseSafe|-Doptimize=ReleaseSmall)
            BUILD_CONFIG="Release"
            ;;
        --release|--release=*)
            BUILD_CONFIG="Release"
            ;;
        --update-prebuilt)
            UPDATE_PREBUILT="1"
            ;;
    esac
done

XAML_OBJ="$XAML_DIR/obj/x64/$BUILD_CONFIG/net9.0-windows10.0.22621.0"
XAML_BIN="$XAML_DIR/bin/x64/$BUILD_CONFIG/net9.0-windows10.0.22621.0"
XAML_OBJ_FALLBACK="$XAML_DIR/obj/x64/Debug/net9.0-windows10.0.22621.0"
XAML_BIN_FALLBACK="$XAML_DIR/bin/x64/Debug/net9.0-windows10.0.22621.0"
XAML_PREBUILT="$XAML_DIR/prebuilt"
XAML_RUNTIME="$XAML_DIR/prebuilt/runtime/x64"

pick_xaml_asset_dirs() {
    # If explicit prebuilt mode is requested, check the prebuilt directory first.
    if [ "$PREBUILT_ONLY" = "1" ] && [ -d "$XAML_PREBUILT" ] && [ -f "$XAML_PREBUILT/ghostty.pri" ]; then
        COPY_OBJ="$XAML_PREBUILT"
        COPY_BIN="$XAML_PREBUILT"
        COPY_LABEL="Prebuilt"
        return 0
    fi

    if [ -d "$XAML_OBJ" ] && [ -f "$XAML_BIN/ghostty.pri" ]; then
        COPY_OBJ="$XAML_OBJ"
        COPY_BIN="$XAML_BIN"
        COPY_LABEL="$BUILD_CONFIG"
        return 0
    fi
    if [ -d "$XAML_OBJ_FALLBACK" ] && [ -f "$XAML_BIN_FALLBACK/ghostty.pri" ]; then
        COPY_OBJ="$XAML_OBJ_FALLBACK"
        COPY_BIN="$XAML_BIN_FALLBACK"
        COPY_LABEL="Debug(fallback)"
        return 0
    fi

    # Final fallback to tracked prebuilt assets if MSBuild outputs are missing.
    if [ -d "$XAML_PREBUILT" ] && [ -f "$XAML_PREBUILT/ghostty.pri" ]; then
        COPY_OBJ="$XAML_PREBUILT"
        COPY_BIN="$XAML_PREBUILT"
        COPY_LABEL="Prebuilt(fallback)"
        return 0
    fi
    return 1
}

check_prebuilt_stale() {
    # If python3 is available, use manifest-based verification.
    if command -v python >/dev/null 2>&1; then
        if python xaml/prebuilt/manage_manifest.py --verify >/dev/null 2>&1; then
            return 1 # Not stale
        else
            return 0 # Stale
        fi
    fi

    # Fallback to simple timestamp check if python3 is missing.
    local pri_file="$1"
    local xbf_file="$2"
    if find "$XAML_DIR" -type f \( -name "*.xaml" -o -name "*.resw" -o -name "*.csproj" \) -newer "$pri_file" -print -quit 2>/dev/null | grep -q .; then
        return 0
    fi
    if find "$XAML_DIR" -type f \( -name "*.xaml" -o -name "*.resw" -o -name "*.csproj" \) -newer "$xbf_file" -print -quit 2>/dev/null | grep -q .; then
        return 0
    fi
    return 1
}

# Step 1: Build XAML (XBF + PRI) via MSBuild if xaml/ project exists
if [ -f "$XAML_DIR/ghostty.csproj" ]; then
    if [ "$PREBUILT_ONLY" = "1" ]; then
        echo "[build-winui3] PREBUILT_ONLY=1: skipping MSBuild and using prebuilt XBF/PRI"
    else
        MSBUILD=""
        for candidate in \
            "/c/Program Files/Microsoft Visual Studio/2022/Community/MSBuild/Current/Bin/MSBuild.exe" \
            "/c/Program Files (x86)/Microsoft Visual Studio/2022/BuildTools/MSBuild/Current/Bin/MSBuild.exe" \
            "/c/Program Files/Microsoft Visual Studio/2022/BuildTools/MSBuild/Current/Bin/MSBuild.exe" \
            "/c/Program Files/Microsoft Visual Studio/2022/Enterprise/MSBuild/Current/Bin/MSBuild.exe" \
            "/c/Program Files/Microsoft Visual Studio/2022/Professional/MSBuild/Current/Bin/MSBuild.exe"; do
            [ -f "$candidate" ] && MSBUILD="$candidate" && break
        done
        if [ -n "$MSBUILD" ]; then
            echo "[build-winui3] Building XAML resources ($BUILD_CONFIG)..."
            "$MSBUILD" "$XAML_DIR/ghostty.csproj" -p:Configuration=$BUILD_CONFIG -p:Platform=x64 -restore -nologo -v:minimal
        else
            echo "[build-winui3] WARNING: MSBuild not found, skipping XAML build"
        fi
    fi
fi

# Step 2: Build Zig
ZIG_ARGS=()
for arg in "$@"; do
    case "$arg" in
        --update-prebuilt)
            # Filter out shell-only flag
            ;;
        *)
            ZIG_ARGS+=("$arg")
            ;;
    esac
done

zig build -Dapp-runtime=winui3 -Dslow-safety=false --prefix "$PREFIX" "${ZIG_ARGS[@]}"

# Step 3: Copy XBF and PRI to bin directory
if pick_xaml_asset_dirs; then
    [ "$COPY_LABEL" = "$BUILD_CONFIG" ] || echo "[build-winui3] WARNING: $BUILD_CONFIG XAML not found, falling back to $COPY_LABEL"
    # Copy WinUI 3 runtime DLLs if available in prebuilt/runtime
    if [ -d "$XAML_RUNTIME" ]; then
        cp -f "$XAML_RUNTIME"/*.dll "$PREFIX/bin/" 2>/dev/null
        # Framework resources.pri (renamed to Microsoft.WindowsAppRuntime.pri to avoid collision)
        if [ -f "$XAML_RUNTIME/Microsoft.WindowsAppRuntime.pri" ]; then
            cp -f "$XAML_RUNTIME/Microsoft.WindowsAppRuntime.pri" "$PREFIX/bin/"
        fi
        echo "[build-winui3] Copied WinUI 3 runtime DLLs from $XAML_RUNTIME"
    fi

    # Copy App's XBF and PRI (Must be resources.pri for WinUI3 to find them)
    cp -f "$COPY_OBJ"/*.xbf "$PREFIX/bin/" 2>/dev/null && echo "[build-winui3] Copied XBF files ($COPY_LABEL)"
    cp -f "$COPY_BIN"/ghostty.pri "$PREFIX/bin/resources.pri" 2>/dev/null && echo "[build-winui3] Copied PRI file ($COPY_LABEL)"

    # Stale detection for prebuilt mode / no-MSBuild mode.
    xbf_sample="$(ls -1 "$COPY_OBJ"/*.xbf 2>/dev/null | head -n1 || true)"
    pri_file="$COPY_BIN/ghostty.pri"
    if [ -n "$xbf_sample" ] && [ -f "$pri_file" ] && check_prebuilt_stale "$pri_file" "$xbf_sample"; then
        msg="[build-winui3] WARNING: prebuilt XBF/PRI may be stale against current xaml/ sources"
        if [ "$PREBUILT_STRICT" = "1" ]; then
            echo "$msg (strict mode: failing)"
            exit 2
        fi
        echo "$msg"
    fi

    # Step 4: Update prebuilt if requested (Developer mode)
    if [ "$UPDATE_PREBUILT" = "1" ] && [ "$COPY_LABEL" != "Prebuilt" ]; then
        echo "[build-winui3] Updating $XAML_PREBUILT assets from $COPY_LABEL..."
        mkdir -p "$XAML_PREBUILT"
        cp -v "$COPY_OBJ"/*.xbf "$XAML_PREBUILT/"
        cp -v "$COPY_BIN"/ghostty.pri "$XAML_PREBUILT/ghostty.pri"
        if command -v python >/dev/null 2>&1; then
            python xaml/prebuilt/manage_manifest.py
        fi
        echo "[build-winui3] Update complete. Commit these changes to track new assets."
    fi
else
    echo "[build-winui3] WARNING: No XBF/PRI assets found under $XAML_DIR"
    if [ "$PREBUILT_ONLY" = "1" ] || [ "$PREBUILT_STRICT" = "1" ]; then
        echo "[build-winui3] ERROR: prebuilt mode requested but assets are missing"
        exit 2
    fi
fi

# Staging is only a temporary fallback. Once a stable build succeeds again,
# remove the stale staging directory so external tools always converge on stable.
if [ "$PREFIX" = "$PREFIX_STABLE" ] && [ -d "$PREFIX_STAGING" ]; then
    rm -r "$PREFIX_STAGING" 2>/dev/null || true
    [ ! -d "$PREFIX_STAGING" ] && echo "[build-winui3] Removed stale staging output"
fi

# Clean up orphaned build directories not managed by this script.
for orphan in zig-out-winui3-next zig-out-winui3-v2 zig-out-winui3-test zig-out-winui3-fast; do
    if [ -d "$orphan" ]; then
        # Skip if any running ghostty.exe exists in this directory
        if [ -f "$orphan/bin/ghostty.exe" ] && is_locked "$orphan"; then
            echo "[build-winui3] WARNING: $orphan in use by running process, skipping cleanup"
        else
            rm -r "$orphan" 2>/dev/null || echo "[build-winui3] WARNING: partial cleanup of $orphan (some files locked)"
            [ ! -d "$orphan" ] && echo "[build-winui3] Removed orphaned $orphan"
        fi
    fi
done
