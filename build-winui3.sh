#!/bin/bash
# WinUI3 build wrapper — enforces --prefix zig-out-winui3
# Disables slow integrity checks for usable debug builds (re-enable with -Dslow-safety=true)
exec zig build -Dapp-runtime=winui3 -Dslow-safety=false --prefix zig-out-winui3 "$@"
