## Summary

<!-- What does this PR do? Why? -->

## Deadlock review (required for changes touching mailbox / blocking_queue / Win32 wait / pipe / SendMessage / UI message dispatch)

- [ ] Does this PR introduce or modify any **blocking call** (`mailbox.push`, `.wait`, `WaitForSingleObject`, `SendMessage*`, `ReadFile`/`WriteFile` on a pipe handle, `JoinThread`)?
- [ ] If yes: does each blocking call have an **escape valve** — timeout, cancellation token, or shutdown signal?
- [ ] If yes: when the counterparty (other end of the channel / target window / child process) dies or wedges, **how does the caller unblock**?
- [ ] Is any of this code reachable from the **UI thread** (focus callback, input handler, message pump, COM vtable entry)? If yes: NO `.forever` / `INFINITE` / `bWait=TRUE` allowed — period.
- [ ] Did `bash tools/lint-deadlock.sh` pass without warnings? (Runs automatically in CI + pre-push.)
- [ ] If a `LINT-ALLOW: <rule-id>` marker was added, is the justification comment specific enough that a reviewer 6 months from now can re-evaluate it?

See [`docs/deadlock-discipline.md`](../docs/deadlock-discipline.md) for the rationale and escape-valve patterns behind each item.

## Test plan

<!-- How was this verified? UIA suite? Repro test? Manual? -->

## Related issues

<!-- Closes #N, refs #M -->
