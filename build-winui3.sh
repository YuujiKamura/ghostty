#!/bin/bash
# WinUI3 build wrapper — enforces --prefix zig-out-winui3
set -e

PREFIX_STABLE="zig-out-winui3"
PREFIX_STAGING="zig-out-winui3-staging"
PREFIX_BUILD="zig-out-winui3-build"
PREFIX="$PREFIX_STABLE"
XAML_DIR="xaml"

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
for arg in "$@"; do
    case "$arg" in
        -Doptimize=ReleaseFast|-Doptimize=ReleaseSafe|-Doptimize=ReleaseSmall)
            BUILD_CONFIG="Release"
            ;;
        --release|--release=*)
            BUILD_CONFIG="Release"
            ;;
    esac
done

XAML_OBJ="$XAML_DIR/obj/x64/$BUILD_CONFIG/net9.0-windows10.0.22621.0"
XAML_BIN="$XAML_DIR/bin/x64/$BUILD_CONFIG/net9.0-windows10.0.22621.0"

# Step 1: Build XAML (XBF + PRI) via MSBuild if xaml/ project exists
if [ -f "$XAML_DIR/ghostty.csproj" ]; then
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

# Step 2: Build Zig
zig build -Dapp-runtime=winui3 -Dslow-safety=false --prefix "$PREFIX" "$@"

# Step 3: Copy XBF and PRI to bin directory
if [ -d "$XAML_OBJ" ]; then
    cp -f "$XAML_OBJ"/*.xbf "$PREFIX/bin/" 2>/dev/null && echo "[build-winui3] Copied XBF files"
    cp -f "$XAML_BIN"/ghostty.pri "$PREFIX/bin/resources.pri" 2>/dev/null && echo "[build-winui3] Copied PRI file"
else
    # Fallback: try Debug paths if Release not available
    XAML_OBJ_FALLBACK="$XAML_DIR/obj/x64/Debug/net9.0-windows10.0.22621.0"
    XAML_BIN_FALLBACK="$XAML_DIR/bin/x64/Debug/net9.0-windows10.0.22621.0"
    if [ -d "$XAML_OBJ_FALLBACK" ]; then
        echo "[build-winui3] WARNING: $BUILD_CONFIG XAML not found, falling back to Debug"
        cp -f "$XAML_OBJ_FALLBACK"/*.xbf "$PREFIX/bin/" 2>/dev/null && echo "[build-winui3] Copied XBF files (Debug)"
        cp -f "$XAML_BIN_FALLBACK"/ghostty.pri "$PREFIX/bin/resources.pri" 2>/dev/null && echo "[build-winui3] Copied PRI file (Debug)"
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
