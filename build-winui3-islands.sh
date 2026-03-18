#!/bin/bash
# WinUI3 Islands build wrapper — enforces --prefix zig-out-winui3-islands
set -e

PREFIX="zig-out-winui3-islands"
XAML_DIR="xaml"
XAML_OBJ="$XAML_DIR/obj/x64/Debug/net9.0-windows10.0.22621.0"
XAML_BIN="$XAML_DIR/bin/x64/Debug/net9.0-windows10.0.22621.0"

# Step 1: Build XAML (XBF + PRI) via MSBuild if xaml/ project exists
if [ -f "$XAML_DIR/ghostty.csproj" ]; then
    MSBUILD="/c/Program Files/Microsoft Visual Studio/2022/Community/MSBuild/Current/Bin/MSBuild.exe"
    if [ -f "$MSBUILD" ]; then
        echo "[build-winui3-islands] Building XAML resources (XBF + PRI)..."
        "$MSBUILD" "$XAML_DIR/ghostty.csproj" -p:Configuration=Debug -p:Platform=x64 -restore -nologo -v:minimal
    else
        echo "[build-winui3-islands] WARNING: MSBuild not found, skipping XAML build"
    fi
fi

# Step 2: Build Zig
zig build -Dapp-runtime=winui3_islands -Dslow-safety=false --prefix "$PREFIX" "$@"

# Step 3: Copy XBF and PRI to bin directory
if [ -d "$XAML_OBJ" ]; then
    cp -f "$XAML_OBJ"/*.xbf "$PREFIX/bin/" 2>/dev/null && echo "[build-winui3-islands] Copied XBF files"
    cp -f "$XAML_BIN"/ghostty.pri "$PREFIX/bin/resources.pri" 2>/dev/null && echo "[build-winui3-islands] Copied PRI file"
fi

# Step 4: Copy control_plane_server.dll if available
if [ -f "$HOME/control-plane-server/target/release/control_plane_server.dll" ]; then
    cp "$HOME/control-plane-server/target/release/control_plane_server.dll" "$PREFIX/bin/"
    echo "[build-winui3-islands] Copied control_plane_server.dll"
fi
