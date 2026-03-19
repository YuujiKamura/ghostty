#!/bin/bash
# WinUI3 build wrapper — enforces --prefix zig-out-winui3
set -e

PREFIX="zig-out-winui3"
XAML_DIR="xaml"

# Detect Release mode from args
BUILD_CONFIG="Debug"
for arg in "$@"; do
    case "$arg" in
        -Doptimize=ReleaseFast|-Doptimize=ReleaseSafe|-Doptimize=ReleaseSmall)
            BUILD_CONFIG="Release"
            ;;
    esac
done

XAML_OBJ="$XAML_DIR/obj/x64/$BUILD_CONFIG/net9.0-windows10.0.22621.0"
XAML_BIN="$XAML_DIR/bin/x64/$BUILD_CONFIG/net9.0-windows10.0.22621.0"

# Step 1: Build XAML (XBF + PRI) via MSBuild if xaml/ project exists
if [ -f "$XAML_DIR/ghostty.csproj" ]; then
    MSBUILD="/c/Program Files/Microsoft Visual Studio/2022/Community/MSBuild/Current/Bin/MSBuild.exe"
    if [ -f "$MSBUILD" ]; then
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

# Step 4: Copy control_plane_server.dll if available
# This DLL provides the control plane (CP) for terminal automation and testing.
# Without it, ghostty runs fine but CP features (agent-ctl, TSF inject tests) are disabled.
# To build:
#   git clone https://github.com/YuujiKamura/control-plane-server.git ~/control-plane-server
#   cd ~/control-plane-server && cargo build --release
CP_DLL="$HOME/control-plane-server/target/release/control_plane_server.dll"
CP_DLL_DEBUG="$HOME/control-plane-server/target/debug/control_plane_server.dll"
if [ -f "$CP_DLL" ]; then
    cp "$CP_DLL" "$PREFIX/bin/"
    echo "[build-winui3] Copied control_plane_server.dll (release)"
elif [ -f "$CP_DLL_DEBUG" ]; then
    cp "$CP_DLL_DEBUG" "$PREFIX/bin/"
    echo "[build-winui3] Copied control_plane_server.dll (debug)"
else
    echo "[build-winui3] NOTE: control_plane_server.dll not found — CP disabled"
    echo "[build-winui3]   To enable: git clone https://github.com/YuujiKamura/control-plane-server.git ~/control-plane-server"
    echo "[build-winui3]             cd ~/control-plane-server && cargo build --release"
fi
