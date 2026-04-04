#!/bin/bash
# Run benchmark inside this terminal, save results, then exit
cd "$(dirname "$0")/.."
python scripts/bench_throughput_tty.py 10 3 /tmp/bench_newbuild.txt
# Keep window open briefly to flush
sleep 2
