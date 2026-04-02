"""Targeted load generator that exercises specific internal state accumulators.

Unlike steady_load.py (pure text throughput), this stresses:
1. Scrollback accumulation (pages, page_size) via large output bursts
2. Font atlas growth via diverse Unicode/CJK/emoji characters
3. Alternate screen switching (tracked_pins churn)
4. Rapid cursor movement / selection-like patterns
5. Interleaved input waits (mailbox queue pressure)

Usage: python targeted_load.py [duration_seconds] [mode]
  mode: all (default), scrollback, font, screen, mixed
"""
import sys
import time
import random

duration = float(sys.argv[1]) if len(sys.argv) > 1 else 120.0
mode = sys.argv[2] if len(sys.argv) > 2 else "all"


def burst_scrollback():
    """Large output burst to grow pages and page_size."""
    line = "X" * 200 + "\n"
    sys.stdout.write(line * 500)  # 500 lines at once
    sys.stdout.flush()


def font_atlas_stress():
    """Diverse characters to grow font atlas node count."""
    # ASCII
    sys.stdout.write("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789\n")
    # CJK Unified Ideographs (U+4E00-U+9FFF) - random subset
    cjk = "".join(chr(random.randint(0x4E00, 0x9FFF)) for _ in range(80))
    sys.stdout.write(cjk + "\n")
    # Hiragana + Katakana
    sys.stdout.write("あいうえおかきくけこさしすせそたちつてとなにぬねのはひふへほまみむめもやゆよらりるれろわをん\n")
    sys.stdout.write("アイウエオカキクケコサシスセソタチツテトナニヌネノハヒフヘホマミムメモヤユヨラリルレロワヲン\n")
    # Emoji (various blocks)
    emoji = "😀😎🔥💻🎯🚀⚡🎉🔧📊🌍🎨🔍💡🎮🏗️🔬📡🛡️🎵"
    sys.stdout.write(emoji + "\n")
    # Box drawing / math symbols
    sys.stdout.write("┌─┬─┐│ ├─┼─┤└─┴─┘ ═║╔╗╚╝ ∀∃∅∈∉∋∌∏∑ ≤≥≠≈∞\n")
    # Combining characters (diacritics)
    sys.stdout.write("a\u0301e\u0301i\u0301o\u0301u\u0301 n\u0303 c\u0327 o\u0308u\u0308\n")
    sys.stdout.flush()


def alternate_screen_churn():
    """Switch to alternate screen and back to churn tracked_pins."""
    # Enter alternate screen (smcup)
    sys.stdout.write("\x1b[?1049h")
    sys.stdout.flush()
    # Write some content on alt screen
    for row in range(1, 20):
        sys.stdout.write(f"\x1b[{row};1HAlt screen line {row}: " + "=" * 60 + "\n")
    sys.stdout.flush()
    time.sleep(0.1)
    # Exit alternate screen (rmcup)
    sys.stdout.write("\x1b[?1049l")
    sys.stdout.flush()


def cursor_movement_storm():
    """Rapid cursor positioning to stress terminal state."""
    # Save cursor, move around, restore
    sys.stdout.write("\x1b7")  # save
    for _ in range(50):
        row = random.randint(1, 40)
        col = random.randint(1, 80)
        sys.stdout.write(f"\x1b[{row};{col}H*")
    sys.stdout.write("\x1b8")  # restore
    sys.stdout.flush()


def scroll_region_stress():
    """Set scroll regions and scroll within them."""
    sys.stdout.write("\x1b[5;20r")  # set scroll region lines 5-20
    for _ in range(30):
        sys.stdout.write("\x1b[20;1H" + "Scroll region fill " * 4 + "\n")
    sys.stdout.write("\x1b[r")  # reset scroll region
    sys.stdout.flush()


def interleaved_io():
    """Short output bursts with tiny sleeps to stress mailbox interleaving."""
    for _ in range(20):
        sys.stdout.write("IO burst: " + "." * 100 + "\n")
        sys.stdout.flush()
        time.sleep(0.005)  # 5ms gaps force mailbox drain cycles


# --- Main loop ---
ops = {
    "scrollback": [burst_scrollback],
    "font": [font_atlas_stress],
    "screen": [alternate_screen_churn],
    "mixed": [burst_scrollback, font_atlas_stress, cursor_movement_storm,
              scroll_region_stress, interleaved_io],
    "all": [burst_scrollback, font_atlas_stress, alternate_screen_churn,
            cursor_movement_storm, scroll_region_stress, interleaved_io],
}

funcs = ops.get(mode, ops["all"])
end_time = time.monotonic() + duration
cycle = 0

while time.monotonic() < end_time:
    fn = funcs[cycle % len(funcs)]
    try:
        fn()
    except (BrokenPipeError, OSError):
        break
    cycle += 1
    time.sleep(0.05)  # 50ms between operations

sys.stdout.write(f"\n[targeted_load] Completed {cycle} cycles in {duration}s, mode={mode}\n")
sys.stdout.flush()
