# Fork Branch Protection (Recommended)

This document describes the recommended GitHub branch-protection settings for
the `YuujiKamura/ghostty` fork. These settings cannot be applied automatically
by code in the repository -- they live in the GitHub UI and require the repo
owner to enable them.

## Background

Issue [#229](https://github.com/YuujiKamura/ghostty/issues/229) tracks a 27k+
line `zig fmt` drift that accumulated on `main` because direct pushes
bypassed the PR-only formatter check. The cleanup landed in `f633095df`, and
the in-repo guards that prevent re-accumulation are:

1. `lefthook.yml` `pre-push` hook runs `zig fmt --check` locally.
2. `.github/workflows/ci.yml` now fires on `push` to `main` (not just on PRs).

Both guards are bypassable: a contributor can `git push --no-verify`, and
post-push CI is advisory unless branch protection blocks the merge / push.
Branch protection closes that gap.

## Recommended settings (`main`)

In GitHub: **Settings -> Branches -> Branch protection rules -> Add rule**.

- Branch name pattern: `main`
- [x] Require a pull request before merging
  - [x] Require approvals: `1` (or `0` for solo workflow if reviews are not used)
  - [x] Dismiss stale pull request approvals when new commits are pushed
- [x] Require status checks to pass before merging
  - [x] Require branches to be up to date before merging
  - Required status checks (search and add):
    - `zig fmt check`
    - `vtable manifest verification`
    - `Windows (WinUI3)` (from `fork-stable-ci.yml`)
- [x] Require conversation resolution before merging
- [x] Do not allow bypassing the above settings
  - This is the load-bearing checkbox. Without it, repo admins (including
    the owner) can `git push` straight to `main` and re-introduce drift.
- [ ] Allow force pushes -- leave **off**
- [ ] Allow deletions -- leave **off**

## Same settings for `winui3-apprt`

Apply the same rule pattern for `winui3-apprt` since it is the active
development branch and CI already gates it.

## Solo-developer note

If working solo and full PR-based review is overhead, the minimum useful
configuration is:

- Require status checks: `zig fmt check`
- Do not allow bypassing the above settings

This still allows direct pushes to `main` but rejects pushes that fail the
formatter, which is the failure mode #229 documents.

## Verification

After applying, verify with:

```bash
gh api repos/YuujiKamura/ghostty/branches/main/protection
```

The response should include `required_status_checks` with
`zig fmt check` listed, and `enforce_admins.enabled = true`.
