"""Steady terminal output for exactly N seconds.
Deterministic workload for frame timing comparison.
"""
import sys, time

duration = float(sys.argv[1]) if len(sys.argv) > 1 else 10.0
line = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789 " * 2 + "\n"
chunk = line * 100  # ~12KB per write

end_time = time.monotonic() + duration
while time.monotonic() < end_time:
    sys.stdout.write(chunk)
    sys.stdout.flush()
