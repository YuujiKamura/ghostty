#!/usr/bin/env python3
"""Terminal throughput benchmark - writes directly to /dev/tty.

This version writes output directly to the terminal device,
bypassing any pipe/capture. Stats go to a result file.
"""

import sys
import time
import os


def main():
    target_mb = float(sys.argv[1]) if len(sys.argv) > 1 else 10.0
    rounds = int(sys.argv[2]) if len(sys.argv) > 2 else 3
    result_file = sys.argv[3] if len(sys.argv) > 3 else None

    # Open the terminal device directly
    if os.name == 'nt':
        tty = open('CON', 'wb')
    else:
        tty = open('/dev/tty', 'wb')

    # Build output data
    line = (b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
            b" The quick brown fox jumps over the lazy dog. Testing terminal"
            b" rendering performance with lots of text output padding here.\n")
    lines_per_chunk = max(1, 65536 // len(line))
    chunk = line * lines_per_chunk
    chunk_len = len(chunk)
    target_bytes = int(target_mb * 1024 * 1024)

    results = []
    for r in range(rounds):
        # Warmup
        written = 0
        warmup_bytes = 1024 * 1024
        while written < warmup_bytes:
            tty.write(chunk)
            written += chunk_len
        tty.flush()
        time.sleep(0.3)

        # Benchmark
        written = 0
        start = time.perf_counter()
        while written < target_bytes:
            tty.write(chunk)
            written += chunk_len
        tty.flush()
        elapsed = time.perf_counter() - start

        mb = written / (1024 * 1024)
        tp = mb / elapsed if elapsed > 0 else 0
        results.append(tp)

        msg = f"Round {r+1}: {mb:.1f}MB in {elapsed:.3f}s = {tp:.1f} MB/s\n"
        sys.stderr.write(msg)
        sys.stderr.flush()
        if r < rounds - 1:
            time.sleep(0.5)

    tty.close()

    avg = sum(results) / len(results)
    best = max(results)
    worst = min(results)

    summary = (f"\nSUMMARY ({len(results)} rounds):\n"
               f"  Avg:   {avg:.1f} MB/s\n"
               f"  Best:  {best:.1f} MB/s\n"
               f"  Worst: {worst:.1f} MB/s\n")
    sys.stderr.write(summary)
    sys.stderr.flush()

    if result_file:
        with open(result_file, 'w') as f:
            f.write(f"avg={avg:.1f}\nbest={best:.1f}\nworst={worst:.1f}\n")
            for i, r in enumerate(results):
                f.write(f"round{i+1}={r:.1f}\n")


if __name__ == "__main__":
    main()
