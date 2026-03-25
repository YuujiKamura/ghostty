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
ALT_SCREEN_ON = "\033[?1049h"
ALT_SCREEN_OFF = "\033[?1049l"


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


def crop_line_to_width(line, max_cols):
    """Crop a single line to max visible characters, preserving ANSI escapes."""
    vis = strip_ansi(line)
    if len(vis) <= max_cols:
        return line
    out = []
    vis_count = 0
    i = 0
    while i < len(line) and vis_count < max_cols:
        if line[i] == '\033':
            j = i + 1
            while j < len(line) and line[j] != 'm':
                j += 1
            out.append(line[i:j+1])
            i = j + 1
        else:
            out.append(line[i])
            vis_count += 1
            i += 1
    out.append(RESET)
    return ''.join(out)


def fit_frames(frames, cols, rows):
    """Crop frames to fit terminal size. Reserve 1 row for status line."""
    max_rows = rows - 1
    fitted = []
    for frame in frames:
        lines = frame.split('\n')[:max_rows]
        fitted.append('\n'.join(crop_line_to_width(l, cols) for l in lines))
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
    total = len(frames)
    loop = 0
    current_fps = fps
    min_fps = 1
    max_fps = 120
    fps_step = 5

    # Non-blocking key input on Windows
    if sys.platform == "win32":
        import msvcrt
        def get_key():
            if msvcrt.kbhit():
                ch = msvcrt.getch()
                if ch == b'\xe0' or ch == b'\x00':  # Arrow key prefix
                    ch2 = msvcrt.getch()
                    if ch2 == b'H': return 'UP'
                    if ch2 == b'P': return 'DOWN'
                    if ch2 == b'M': return 'RIGHT'
                    if ch2 == b'K': return 'LEFT'
                elif ch == b'q' or ch == b'Q': return 'QUIT'
            return None
    else:
        def get_key():
            return None

    # Ghost frame layout: 16 cols left pad, 68 cols wide, 41 lines
    frame_left = 16
    frame_w = 68
    status_row = 44  # 41 (frame) + 2 (spacer) + 1

    import random
    _haunt_until = 0
    _next_haunt = time.time() + random.uniform(30, 120)  # first haunting in 30-120s

    sys.stdout.write(ALT_SCREEN_ON + CLEAR_SCREEN + HIDE_CURSOR)
    sys.stdout.flush()
    try:
        while True:
            loop += 1
            for i, frame in enumerate(frames):
                now = time.time()
                # Spontaneous haunting: triggers randomly, lasts 1-3 seconds
                if now >= _next_haunt and now >= _haunt_until:
                    _haunt_until = now + random.uniform(1, 3)
                    _next_haunt = now + random.uniform(45, 180)
                if now < _haunt_until and random.random() < 0.35:
                    sys.stdout.write(CLEAR_SCREEN)
                sys.stdout.write(CURSOR_HOME)
                sys.stdout.write(frame)
                # Status line centered within ghost display area
                content = f"loop {loop} | frame {i+1}/{total} | {current_fps}fps | Up/Down:FPS  q:quit"
                clen = min(len(content), frame_w)
                inner_pad = (frame_w - clen) // 2
                col = frame_left + inner_pad + 1
                sys.stdout.write(f"\033[{status_row};{col}H\033[1;37;44m{content[:clen]}\033[0m")
                sys.stdout.flush()

                # Handle key input
                key = get_key()
                if key == 'UP' or key == 'RIGHT':
                    current_fps = min(current_fps + fps_step, max_fps)
                elif key == 'DOWN' or key == 'LEFT':
                    current_fps = max(current_fps - fps_step, min_fps)
                elif key == 'QUIT':
                    raise KeyboardInterrupt

                time.sleep(1.0 / current_fps)
    except KeyboardInterrupt:
        pass
    finally:
        sys.stdout.write(SHOW_CURSOR + RESET + ALT_SCREEN_OFF)
        sys.stdout.flush()
        print(f"Played {loop} loops at last FPS: {current_fps}.")


def run_benchmark(frames, iterations):
    total_frames = len(frames)
    # Pre-build output strings for zero-overhead in the loop
    outputs = [CURSOR_HOME + frame for frame in frames]

    sys.stdout.write(ALT_SCREEN_ON + HIDE_CURSOR)
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
        sys.stdout.write(SHOW_CURSOR + RESET + ALT_SCREEN_OFF)
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
    parser.add_argument("--fps", type=int, default=60, help="Playback FPS (default: 60)")
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
