#!/usr/bin/env python3
"""Terminal throughput benchmark.

Run this script INSIDE the terminal you want to benchmark.
It outputs a large volume of text and measures how fast the terminal
can process it.

Usage:
    python bench_throughput.py              # Default: 10MB of text
    python bench_throughput.py --size 50    # 50MB of text
    python bench_throughput.py --lines      # Report lines/sec too

The key metric is MB/s (throughput). Compare this number between
different terminals or before/after code changes.

Typical results:
    - Slow terminal:  10-30 MB/s
    - Fast terminal:  50-200 MB/s
    - Very fast:      200+ MB/s
"""

import sys
import time
import argparse
import os


def generate_line(width: int = 200) -> bytes:
    """Generate a single line of printable ASCII."""
    # Mix of characters to exercise different code paths
    chars = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 .,-=+*/#@!?"
    line = bytearray()
    for i in range(width):
        line.append(chars[i % len(chars)])
    line.append(ord('\n'))
    return bytes(line)


def run_benchmark(target_mb: float, report_lines: bool, warmup_mb: float = 1.0):
    out = sys.stdout.buffer

    line = generate_line(200)
    line_len = len(line)

    # Build a chunk of ~64KB for efficient writes
    lines_per_chunk = max(1, 65536 // line_len)
    chunk = line * lines_per_chunk
    chunk_len = len(chunk)
    chunk_lines = lines_per_chunk

    target_bytes = int(target_mb * 1024 * 1024)
    warmup_bytes = int(warmup_mb * 1024 * 1024)

    # Warmup phase (not measured)
    sys.stderr.write(f"Warming up ({warmup_mb:.0f} MB)...\n")
    sys.stderr.flush()
    written = 0
    while written < warmup_bytes:
        out.write(chunk)
        written += chunk_len
    out.flush()

    # Small pause to let terminal catch up
    time.sleep(0.5)

    # Benchmark phase
    sys.stderr.write(f"Benchmarking ({target_mb:.0f} MB)...\n")
    sys.stderr.flush()

    written = 0
    total_lines = 0
    start = time.perf_counter()

    while written < target_bytes:
        out.write(chunk)
        written += chunk_len
        total_lines += chunk_lines

    out.flush()
    elapsed = time.perf_counter() - start

    # Results
    mb_written = written / (1024 * 1024)
    throughput = mb_written / elapsed if elapsed > 0 else 0

    sys.stderr.write("\n")
    sys.stderr.write("=" * 50 + "\n")
    sys.stderr.write(f"  Data written:  {mb_written:.1f} MB\n")
    sys.stderr.write(f"  Time elapsed:  {elapsed:.3f} s\n")
    sys.stderr.write(f"  Throughput:    {throughput:.1f} MB/s\n")
    if report_lines:
        lps = total_lines / elapsed if elapsed > 0 else 0
        sys.stderr.write(f"  Lines/sec:     {lps:,.0f}\n")
    sys.stderr.write("=" * 50 + "\n")
    sys.stderr.flush()

    return throughput


def main():
    parser = argparse.ArgumentParser(description="Terminal throughput benchmark")
    parser.add_argument("--size", type=float, default=10.0,
                        help="Amount of data to output in MB (default: 10)")
    parser.add_argument("--lines", action="store_true",
                        help="Also report lines/sec")
    parser.add_argument("--rounds", type=int, default=3,
                        help="Number of rounds (default: 3)")
    parser.add_argument("--warmup", type=float, default=1.0,
                        help="Warmup data in MB (default: 1)")
    args = parser.parse_args()

    sys.stderr.write(f"Terminal Throughput Benchmark\n")
    sys.stderr.write(f"Terminal: {os.environ.get('TERM_PROGRAM', 'unknown')}\n")
    sys.stderr.write(f"Rounds: {args.rounds}, Size: {args.size} MB each\n")
    sys.stderr.write("-" * 50 + "\n")
    sys.stderr.flush()

    results = []
    for i in range(args.rounds):
        sys.stderr.write(f"\n--- Round {i + 1}/{args.rounds} ---\n")
        sys.stderr.flush()
        tp = run_benchmark(args.size, args.lines, args.warmup)
        results.append(tp)
        if i < args.rounds - 1:
            time.sleep(1.0)

    if len(results) > 1:
        avg = sum(results) / len(results)
        best = max(results)
        worst = min(results)
        sys.stderr.write(f"\n{'=' * 50}\n")
        sys.stderr.write(f"  SUMMARY ({len(results)} rounds)\n")
        sys.stderr.write(f"  Average:  {avg:.1f} MB/s\n")
        sys.stderr.write(f"  Best:     {best:.1f} MB/s\n")
        sys.stderr.write(f"  Worst:    {worst:.1f} MB/s\n")
        sys.stderr.write(f"{'=' * 50}\n")
        sys.stderr.flush()


if __name__ == "__main__":
    main()
