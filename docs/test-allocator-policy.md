# Test allocator policy

Default allocator rule for every `test { ... }` block in `ghostty-win`.

`std.testing.allocator` (a `GeneralPurposeAllocator` configured for safety
checks) reports leaks at test teardown by panicking. Using any other
allocator inside a test bypasses that check, and a leak that escapes one
test happily survives 100% green output. This doc fixes the rule, names
the exempt protocol, and lists the follow-up briefs that build on it.

Zig version at time of writing: `0.15.2` (see `.zigversion` /
`build.zig.zon`). The `std.testing.allocator` semantics described here
match that release; revisit on a Zig bump.

## Rule

Inside any `test "..." { ... }` block, the allocator passed to code under
test **must** be `std.testing.allocator` unless an exempt comment is
present (see below).

This applies to:

- Direct `alloc` / `dupe` / `create` calls in the test body.
- Allocators handed to constructors / fixtures / helpers that the test
  drives (the helper takes `Allocator`, the test passes
  `std.testing.allocator`).
- Indirect allocation through arenas / pools / fixed buffers **created
  inside the test** -- those wrappers are themselves backed by
  `std.testing.allocator`.

Disallowed by default in test code:

- `std.heap.page_allocator`
- `std.heap.c_allocator`
- `std.heap.smp_allocator`
- A local `GeneralPurposeAllocator` instance other than the one behind
  `std.testing.allocator`
- A bare `FixedBufferAllocator` / `ArenaAllocator` whose backing is not
  `std.testing.allocator`

The reason these are disallowed is not that they are wrong allocators in
production -- it is that they do not panic on leak at test teardown, so
they silently mask the bug class this policy exists to surface.

## Exempt protocol

Some tests legitimately need a different allocator: very large image
buffers, performance-sensitive arenas, tests that exercise an allocator
implementation itself, or fuzz drivers that need a bounded fixed buffer
to constrain input size.

To opt out, the test block **must** carry a leading line comment of the
form:

```zig
test "huge framebuffer round-trip" {
    // allocator-exempt: 256 MiB image buffer, GPA bookkeeping dominates runtime
    var buf: [256 * 1024 * 1024]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&buf);
    const alloc = fba.allocator();
    // ...
}
```

Rules for the comment:

- Exact prefix `// allocator-exempt:` (single space after the colon).
- Must be the first non-blank line inside the `test { ... }` block.
- Reason text after the colon must be a one-line human sentence -- "TODO"
  / "legacy" / empty are not acceptable reasons.

The audit script (see follow-ups below) greps for this token to count
exemptions; silent escapes (use a non-`testing.allocator` without the
comment) are the violation class the audit catches.

If the exemption is genuinely needed long-term, leave it. If it is a
shortcut to make a flaky test green, fix the test instead -- that is
exactly the leak this policy wants to surface.

## Existing violations

This doc lands the rule. It does **not** retro-fix existing tests.

Tests that currently use a non-`testing.allocator` without the exempt
comment are grandfathered at landing time: they neither break the build
nor block this commit. The follow-up briefs below carry the cleanup
work.

Do not write **new** violations after this doc lands. Reviewers should
treat a missing `allocator-exempt:` comment on a non-`testing.allocator`
in test code as a review block, the same way an unexplained `// TODO`
on a security-sensitive path would be.

## Follow-up briefs

These build on this doc and should be filed as separate briefs (each
declares `depends-on: [testing-leak-detection-default]`):

1. **`testing-leak-detection-audit-script`**
   Add `tools/audit-test-allocator.sh` that greps `src/`, `pkg/`,
   `vendor/` for non-`testing.allocator` use inside `test "..." { }`
   blocks, subtracts the exempt comments, and prints a violation count
   plus file:line list. Output stable enough to diff in CI.

2. **`testing-leak-detection-fix-violations`**
   Walk the violation list from the audit script, convert each test to
   `std.testing.allocator` or add a justified `allocator-exempt:`
   comment. One commit per module is fine; do not bundle unrelated
   modules.

3. **`testing-leak-detection-precommit-hook`**
   Wire the audit script into `lefthook.yml` `pre-commit` so a new
   violation introduced in a commit fails the hook. Run it on changed
   files only to keep the hook fast; full-tree run lives in CI.

The chain order matters: audit first (to know the floor), then fix (to
drive the count to 0), then hook (to keep it at 0). Landing the hook
before the fix would make every commit on a dirty tree fail.

## Why this matters

`zig build test` printing "all 1234 tests passed" is the strongest claim
the test suite can make. If a fraction of those tests run on
`page_allocator`, the claim is locally true and globally a lie -- the
leak detector never ran on those paths. This policy is the cheapest way
to keep the claim honest: one allocator by default, one comment for
every escape, one grep to audit.
