# 2026-04-27 12:51:02 → 12:59:14 timeline summary

## Session launch
- 12:51:02 ghostty-37564 (codex) launched, pipe \.\pipe\ghostty-winui3-ghostty-37564-37564
- 12:51:04 ghostty-42852 (gemini) launched, pipe \.\pipe\ghostty-winui3-ghostty-42852-42852
- 12:51:35 deckpilot auto-registered cross-callbacks (37564 ↔ 42852)
- 12:51:37 idle callback "ghostty-37564 is idle" sent to 42852

## renderer_locked events (server: BUSY|renderer_locked)
- 12:52:38 gemini-42852 (first occurrence — 1m34s after launch, before any approver active)
- 12:54:34 codex-37564
- 12:57:10 gemini-42852
- 12:57:16 gemini-42852
- 12:57:56 gemini-42852
- 12:58:07 gemini-42852
- 12:58:22 gemini-42852
- 12:58:58 gemini-42852

## Manual approver fires (note: 3 sends total, not a "storm")
- 12:57:33 approved
- 12:57:52 approved
- 12:58:06 approved

## Death
- 12:59:13 first pipe disconnect on both pipes (simultaneous)
- 12:59:14 daemon marks both sessions dead after 3 consecutive failures
- Profiles: codex 8m12s/981 polls/6 fail; gemini 8m10s/968 polls/10 fail

## Counter-hypothesis: auto-approver was NOT the trigger
- renderer_locked started 12:52:38, approver only ran 12:57:33+ (5min later)
- Built-in auto-approvals died after 1 line (`detected agent=gemini`)
- Manual approver fired 3 times in 35s window — not a poll storm
- BUSY|renderer_locked was already established before approver activity

## Likely real triggers
- deckpilot baseline polling: 981 polls / 492s = ~2/s per session × 2 sessions = ~4/s aggregate to CP pipes
- cross-session idle callback notifications (auto-registered hooks)
- WinUI3 UI thread contention under simultaneous zig test runs (two parallel agent workloads)
