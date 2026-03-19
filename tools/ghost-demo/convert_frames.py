#!/usr/bin/env python3
"""Download ghost animation frames from ghostty-org/website and convert HTML to ANSI."""
import os
import re
import urllib.request

BASE_URL = "https://raw.githubusercontent.com/ghostty-org/website/main/terminals/home/animation_frames"
FRAME_COUNT = 235
OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "frames")
VT_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "ghost_animation.vt")


def html_to_ansi(html: str) -> str:
    """Convert HTML span tags to ANSI escape sequences.

    On the ghostty.org website, .b class is styled with --brand-color: #3551F3
    (a vivid blue-purple) on a near-black background (#0F0F11).
    We replicate this with 24-bit TrueColor ANSI: bold + RGB(53, 81, 243).
    """
    s = html
    s = re.sub(r'<span class="b">', '\033[1;38;2;53;81;243m', s)
    s = s.replace('</span>', '\033[0m')
    s = re.sub(r'<[^>]+>', '', s)  # strip any remaining HTML
    return s


def main():
    os.makedirs(OUT_DIR, exist_ok=True)

    frames = []
    for i in range(1, FRAME_COUNT + 1):
        url = f"{BASE_URL}/frame_{i:03d}.txt"
        try:
            with urllib.request.urlopen(url) as resp:
                raw = resp.read().decode("utf-8")
        except Exception as e:
            print(f"  SKIP frame {i:03d}: {e}")
            continue

        ansi = html_to_ansi(raw)
        frame_path = os.path.join(OUT_DIR, f"frame_{i:03d}.txt")
        with open(frame_path, "w", encoding="utf-8") as f:
            f.write(ansi)
        frames.append(ansi)

        if i % 10 == 0 or i == 1:
            print(f"  [{i:3d}/{FRAME_COUNT}] downloaded")

    # Build single VT animation file
    with open(VT_FILE, "w", encoding="utf-8") as f:
        for idx, frame in enumerate(frames):
            if idx == 0:
                f.write("\033[2J")  # clear screen on first frame
            f.write("\033[H")  # cursor home
            f.write(frame)

    print(f"\nDone: {len(frames)} frames -> {OUT_DIR}")
    print(f"Animation file: {VT_FILE}")


if __name__ == "__main__":
    main()
