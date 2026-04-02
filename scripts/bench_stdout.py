#!/usr/bin/env python3
"""Terminal throughput benchmark - writes to stdout.
Results saved to file. Stats to stderr.
"""
import sys, time, os

def main():
    target_mb = float(sys.argv[1]) if len(sys.argv) > 1 else 10.0
    rounds = int(sys.argv[2]) if len(sys.argv) > 2 else 3
    result_file = sys.argv[3] if len(sys.argv) > 3 else None

    out = sys.stdout.buffer
    line = (b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
            b" The quick brown fox jumps over the lazy dog testing perf.\n")
    chunk = line * max(1, 65536 // len(line))
    chunk_len = len(chunk)
    target_bytes = int(target_mb * 1024 * 1024)

    results = []
    for r in range(rounds):
        # Warmup
        w = 0
        while w < 1024*1024:
            out.write(chunk)
            w += chunk_len
        out.flush()
        time.sleep(0.3)

        # Measure
        w = 0
        start = time.perf_counter()
        while w < target_bytes:
            out.write(chunk)
            w += chunk_len
        out.flush()
        elapsed = time.perf_counter() - start

        mb = w / (1024*1024)
        tp = mb / elapsed if elapsed > 0 else 0
        results.append(tp)
        sys.stderr.write(f"Round {r+1}: {mb:.1f}MB in {elapsed:.3f}s = {tp:.1f} MB/s\n")
        sys.stderr.flush()
        if r < rounds - 1:
            time.sleep(0.5)

    avg = sum(results) / len(results)
    best = max(results)
    worst = min(results)
    sys.stderr.write(f"\nAvg: {avg:.1f}  Best: {best:.1f}  Worst: {worst:.1f} MB/s\n")
    sys.stderr.flush()

    if result_file:
        with open(result_file, 'w') as f:
            f.write(f"avg={avg:.1f}\nbest={best:.1f}\nworst={worst:.1f}\n")
            for i, r in enumerate(results):
                f.write(f"round{i+1}={r:.1f}\n")

if __name__ == "__main__":
    main()
