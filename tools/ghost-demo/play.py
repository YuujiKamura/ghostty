#!/usr/bin/env python3
"""Ghost AA animation player and benchmark.

Usage:
  python play.py              # Demo at 15fps, loop until Ctrl+C
  python play.py --fps 30     # Faster demo
  python play.py --benchmark  # Benchmark: max speed, 3 iterations
  python play.py --benchmark --iterations 5
"""
import argparse
import glob
import os
import sys
import time

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
FRAMES_DIR = os.path.join(SCRIPT_DIR, "frames")
MIN_COLS = 95
MIN_ROWS = 43

# Enable ANSI escapes on Windows and force UTF-8 output
if sys.platform == "win32":
    os.system("")
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

HIDE_CURSOR = "\033[?25l"
SHOW_CURSOR = "\033[?25h"
CURSOR_HOME = "\033[H"
CLEAR_SCREEN = "\033[2J"
RESET = "\033[0m"


def get_term_size():
    try:
        return os.get_terminal_size()
    except OSError:
        return os.terminal_size((80, 24))


def check_terminal_size():
    """Check if terminal is large enough. Returns (cols, rows)."""
    sz = get_term_size()
    if sz.columns < MIN_COLS or sz.lines < MIN_ROWS:
        print(f"Terminal too small: {sz.columns}x{sz.lines}")
        print(f"Required minimum:  {MIN_COLS}x{MIN_ROWS}")
        print(f"\nTrying to resize via escape sequence...")
        sys.stdout.write(f"\033[8;{MIN_ROWS};{MIN_COLS}t")
        sys.stdout.flush()
        time.sleep(0.5)
        sz = get_term_size()
        if sz.columns < MIN_COLS or sz.lines < MIN_ROWS:
            print(f"Still {sz.columns}x{sz.lines}. Please resize manually and press Enter.")
            input()
            sz = get_term_size()
    return sz


def strip_ansi(s):
    """Remove ANSI escape sequences to get visible length."""
    import re
    return re.sub(r'\033\[[^m]*m', '', s)


def fit_frames(frames, cols, rows):
    """Crop frames to fit terminal size. Reserve 1 row for status line."""
    max_rows = rows - 1
    fitted = []
    for frame in frames:
        lines = frame.split('\n')
        # Trim to max rows
        lines = lines[:max_rows]
        # Trim each line to visible width (preserving ANSI escapes)
        cropped = []
        for line in lines:
            vis = strip_ansi(line)
            if len(vis) > cols:
                # Walk the string keeping ANSI escapes, crop visible chars
                out = []
                vis_count = 0
                i = 0
                while i < len(line) and vis_count < cols:
                    if line[i] == '\033':
                        # Consume entire escape sequence
                        j = i + 1
                        while j < len(line) and line[j] != 'm':
                            j += 1
                        out.append(line[i:j+1])
                        i = j + 1
                    else:
                        out.append(line[i])
                        vis_count += 1
                        i += 1
                out.append(RESET)  # close any open style
                cropped.append(''.join(out))
            else:
                cropped.append(line)
        fitted.append('\n'.join(cropped))
    return fitted


def load_frames():
    pattern = os.path.join(FRAMES_DIR, "frame_*.txt")
    paths = sorted(glob.glob(pattern))
    if not paths:
        print(f"Error: No frames found in {FRAMES_DIR}", file=sys.stderr)
        print("Run: python convert_frames.py", file=sys.stderr)
        sys.exit(1)
    frames = []
    for p in paths:
        with open(p, "r", encoding="utf-8") as f:
            frames.append(f.read())
    return frames


def play_demo(frames, fps, rows):
    delay = 1.0 / fps
    total = len(frames)
    loop = 0
    sys.stdout.write(CLEAR_SCREEN + HIDE_CURSOR)
    sys.stdout.flush()
    try:
        while True:
            loop += 1
            for i, frame in enumerate(frames):
                sys.stdout.write(CURSOR_HOME)
                sys.stdout.write(frame)
                # Status line at bottom of screen
                status = f" loop {loop} | frame {i+1}/{total} | {fps}fps | Ctrl+C to quit "
                sys.stdout.write(f"\033[{rows};1H\033[7m{status}\033[0m")
                sys.stdout.flush()
                time.sleep(delay)
    except KeyboardInterrupt:
        pass
    finally:
        sys.stdout.write(SHOW_CURSOR + RESET + CLEAR_SCREEN + CURSOR_HOME)
        sys.stdout.flush()
        print(f"Played {loop} loops.")


def run_benchmark(frames, iterations):
    total_frames = len(frames)
    # Pre-build output strings for zero-overhead in the loop
    outputs = [CURSOR_HOME + frame for frame in frames]

    sys.stdout.write(HIDE_CURSOR)
    sys.stdout.flush()
    times = []
    try:
        for it in range(iterations):
            sys.stdout.write(CLEAR_SCREEN + CURSOR_HOME)
            sys.stdout.flush()
            start = time.perf_counter()
            for out in outputs:
                sys.stdout.write(out)
                sys.stdout.flush()
            elapsed = time.perf_counter() - start
            times.append(elapsed)
    finally:
        sys.stdout.write(SHOW_CURSOR + RESET + CLEAR_SCREEN + CURSOR_HOME)
        sys.stdout.flush()

    # Results
    print(f"Ghost Animation Benchmark ({total_frames} frames x {iterations} iterations)")
    print("=" * 60)
    print(f"{'Iter':>6} {'Time (s)':>10} {'FPS':>10} {'ms/frame':>10}")
    print("-" * 60)
    for i, t in enumerate(times):
        fps = total_frames / t
        ms = (t / total_frames) * 1000
        print(f"{i+1:>6} {t:>10.3f} {fps:>10.1f} {ms:>10.2f}")
    print("-" * 60)
    avg_t = sum(times) / len(times)
    avg_fps = total_frames / avg_t
    avg_ms = (avg_t / total_frames) * 1000
    print(f"{'avg':>6} {avg_t:>10.3f} {avg_fps:>10.1f} {avg_ms:>10.2f}")
    print(f"{'min':>6} {min(times):>10.3f} {total_frames/min(times):>10.1f} {min(times)/total_frames*1000:>10.2f}")
    print(f"{'max':>6} {max(times):>10.3f} {total_frames/max(times):>10.1f} {max(times)/total_frames*1000:>10.2f}")


def main():
    parser = argparse.ArgumentParser(description="Ghost AA animation player/benchmark")
    parser.add_argument("--fps", type=int, default=15, help="Playback FPS (default: 15)")
    parser.add_argument("--benchmark", action="store_true", help="Run benchmark mode")
    parser.add_argument("--iterations", type=int, default=3, help="Benchmark iterations (default: 3)")
    args = parser.parse_args()

    frames = load_frames()
    sz = get_term_size()
    print(f"Loaded {len(frames)} frames from {FRAMES_DIR}")
    print(f"Terminal: {sz.columns}x{sz.lines}")

    # Auto-fit frames to terminal size
    frames = fit_frames(frames, sz.columns, sz.lines)

    if not args.benchmark:
        play_demo(frames, args.fps, sz.lines)
    else:
        run_benchmark(frames, args.iterations)


if __name__ == "__main__":
    main()
