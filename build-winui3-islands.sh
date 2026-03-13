#!/bin/bash
exec zig build -Dapp-runtime=winui3_islands -Dslow-safety=false --prefix zig-out-winui3-islands "$@"
