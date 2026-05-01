#!/usr/bin/env bash
# tools/lint-deadlock.sh
#
# Deadlock anti-pattern lint for ghostty-win.
#
# Background: 2026-04-26 issue cluster #218/#219/#220/#221/#222/#223 all
# reduced to "infinite wait with no escape hatch on a thread that must stay
# responsive." This script greps for the four code shapes that produced those
# hangs and refuses any new occurrence.
#
# See notes/2026-04-26_deadlock_lint_rules.md for the rationale per rule, the
# allowlist marker syntax, and the recommended fix for each pattern.
#
# Exit codes:
#   0   no violations
#   1   one or more violations found
#   2   internal error (missing tool, bad invocation)
#
# Allowlist syntax: append `// LINT-ALLOW: <rule-id> (<reason>)` on the same
# line as the offending construct. The reason string is mandatory.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

# ---------------------------------------------------------------------------
# Tool check
# ---------------------------------------------------------------------------
if ! command -v grep >/dev/null 2>&1; then
    echo "lint-deadlock: grep is required" >&2
    exit 2
fi

# ---------------------------------------------------------------------------
# Globals
# ---------------------------------------------------------------------------
VIOLATIONS=0
WARNINGS=0
VERBOSE=0
QUIET=0

usage() {
    cat <<'EOF'
Usage: tools/lint-deadlock.sh [--verbose|-v] [--quiet|-q] [--help|-h]

Lints ghostty-win source for deadlock anti-patterns. See
notes/2026-04-26_deadlock_lint_rules.md for the rule list.

Options:
  -v, --verbose   Print every file scanned plus per-rule progress.
  -q, --quiet     Suppress headings; only emit violations and final summary.
  -h, --help      Show this help and exit.
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        -v|--verbose) VERBOSE=1 ;;
        -q|--quiet)   QUIET=1 ;;
        -h|--help)    usage; exit 0 ;;
        *) echo "lint-deadlock: unknown argument: $1" >&2; usage >&2; exit 2 ;;
    esac
    shift
done

log() {
    if [ "${QUIET}" -eq 0 ]; then echo "$@"; fi
}

vlog() {
    if [ "${VERBOSE}" -eq 1 ]; then echo "$@"; fi
}

# ---------------------------------------------------------------------------
# Allowlist matcher.
#
# A line is allowlisted when it contains:
#     // LINT-ALLOW: <rule-id> (<reason>)
# The reason in parentheses is mandatory; an empty `()` does not allowlist.
# Match is case-sensitive and the rule-id token must appear literally.
# ---------------------------------------------------------------------------
is_allowlisted() {
    local line_text="$1"
    local rule_id="$2"
    # Look for `LINT-ALLOW: <rule_id> (` followed by at least one non-`)` char
    # before the closing paren.
    if echo "${line_text}" | grep -Eq "LINT-ALLOW: ${rule_id} \([^)]+\)"; then
        return 0
    fi
    return 1
}

# ---------------------------------------------------------------------------
# Rule runner.
#
# Args:
#   rule_id         short identifier (e.g. "forever-ok")
#   pattern         ERE pattern passed to grep -E
#   description     human-readable rule summary
#   recommendation  what to do instead
#   severity        "error" (counts as violation, exits 1) or "warn"
#   path...         remaining args = paths to grep
# ---------------------------------------------------------------------------
run_rule() {
    local rule_id="$1"; shift
    local pattern="$1"; shift
    local description="$1"; shift
    local recommendation="$1"; shift
    local severity="$1"; shift

    log ""
    log "== rule: ${rule_id} (${severity}) =="
    log "   ${description}"
    log "   fix:  ${recommendation}"

    local rule_hits=0

    # Use grep -rEn to get file:line:content. -- to terminate flags. We only
    # scan files; pass paths individually so missing dirs are tolerated.
    local args=()
    for p in "$@"; do
        if [ -e "${p}" ]; then
            args+=("${p}")
        else
            vlog "   (skip missing path: ${p})"
        fi
    done

    if [ "${#args[@]}" -eq 0 ]; then
        vlog "   (no scan targets present; rule skipped)"
        return 0
    fi

    # `|| true` so set -e doesn't trip when grep finds nothing.
    local results
    results=$(grep -rEn -- "${pattern}" "${args[@]}" 2>/dev/null || true)

    if [ -z "${results}" ]; then
        log "   ok: 0 hits"
        return 0
    fi

    while IFS= read -r raw_line; do
        # raw_line format: path:line_no:content
        # Some paths on Windows contain colons after the drive letter when
        # absolute, but grep -r emits repo-relative paths so we are safe.
        local file_path line_no content
        file_path="${raw_line%%:*}"
        local rest="${raw_line#*:}"
        line_no="${rest%%:*}"
        content="${rest#*:}"

        if is_allowlisted "${content}" "${rule_id}"; then
            vlog "   allow: ${file_path}:${line_no}"
            continue
        fi

        # Strip leading whitespace once for the noise filters below.
        local trimmed
        trimmed="$(echo "${content}" | sed -E 's/^[[:space:]]+//')"

        # Skip pure-comment lines (Zig: `//` and `///`). The pattern matches
        # explanatory text in code comments, which is documentation, not
        # behaviour. We still flag inline trailing comments because grep
        # cannot distinguish reliably; the allowlist marker is the escape
        # hatch for those.
        case "${trimmed}" in
            //*) vlog "   skip (comment): ${file_path}:${line_no}"; continue ;;
        esac

        # Skip Zig `extern` declarations. A declaration of `SendMessageW`
        # is just a binding to user32; it is the *callers* we care about.
        # Same logic for `pub extern fn` / `extern "user32" fn` shapes.
        if echo "${trimmed}" | grep -Eq '(^|[[:space:]])extern[[:space:]]+("[^"]+"[[:space:]]+)?fn[[:space:]]'; then
            vlog "   skip (extern decl): ${file_path}:${line_no}"
            continue
        fi

        # Print violation in a clickable file:line format.
        echo "${file_path}:${line_no}: [${rule_id}] ${description}"
        # Show the offending source with leading whitespace stripped.
        echo "    > ${trimmed}"
        echo "    fix: ${recommendation}"
        echo "    allowlist: append \"// LINT-ALLOW: ${rule_id} (reason)\" if intentional"
        echo ""

        rule_hits=$((rule_hits + 1))
    done <<< "${results}"

    if [ "${rule_hits}" -gt 0 ]; then
        if [ "${severity}" = "error" ]; then
            VIOLATIONS=$((VIOLATIONS + rule_hits))
        else
            WARNINGS=$((WARNINGS + rule_hits))
        fi
    fi

    log "   hits: ${rule_hits}"
}

# ---------------------------------------------------------------------------
# Rule definitions
#
# Each rule's scope reflects the source-of-truth audits in
# notes/2026-04-26_forever_push_audit.md and the issues #218..#223. Adjust
# the path lists when extending the audit, not the script default.
# ---------------------------------------------------------------------------

# Rule 1: `.forever = {}` push on threads that may run on the UI thread.
#
# Source: #218 root cause. The classic shape is:
#     mailbox.push(msg, .{ .forever = {} })
# from a function reachable on the apprt UI thread. The audit in
# notes/2026-04-26_forever_push_audit.md enumerates every such site; the
# scopes below are the ones that thread the UI message pump.
run_rule \
    "forever-ok" \
    '\.forever[[:space:]]*=[[:space:]]*\{[[:space:]]*\}' \
    'BlockingQueue.push(.., .{ .forever = {} }) on a UI-thread reachable site (issue #218 family)' \
    "use .{ .instant = {} } and drop+log on full, or .{ .ns = N * std.time.ns_per_ms } with bounded retry" \
    "error" \
    "src/Surface.zig" \
    "src/apprt/winui3" \
    "src/apprt/win32"
# Note: src/apprt/embedded.zig and src/apprt/gtk/* were previously listed
# above. They were dropped per the fork-sprawl cleanup (.dispatch/team-sprawl-A1):
# we do not ship the embedded/gtk apprts, so cross-apprt-contamination edits
# (including #218-family fixes) are not our responsibility — those files are
# kept verbatim from upstream. Re-adding them here would force us to either
# carry local edits in non-shipping apprts or LINT-ALLOW them, both of which
# violate heavy-fork-stewardship. See `wrap-first-in-apprt`.

# Rule 2: `INFINITE` argument to a Win32 wait / message-wait API.
#
# Source: #221 (Command.wait) and the dispatcher hangs that motivated the
# winui3 watchdog. WaitForSingleObject / WaitForMultipleObjects /
# MsgWaitForMultipleObjectsEx with INFINITE on a thread that owns user-visible
# state never recovers from a stuck child or a broken handle. The constant
# definitions themselves (`pub const INFINITE`) are excluded by the
# `INFINITE[[:space:]]*[:=]` shape — we only flag *call sites*.
run_rule \
    "infinite-wait" \
    '(WaitForSingleObject|WaitForMultipleObjects|WaitForMultipleObjectsEx|MsgWaitForMultipleObjectsEx|SignalObjectAndWait)[A-Za-z_]*[[:space:]]*\([^;]*INFINITE' \
    'Win32 wait API called with INFINITE on a thread that must stay responsive (issue #221 family)' \
    "pass a finite ms (e.g. 5000) and treat WAIT_TIMEOUT as a failure to escalate; for UI threads also use MsgWaitForMultipleObjectsEx with QS_ALLINPUT and bounded ms" \
    "error" \
    "src/Command.zig" \
    "src/apprt/winui3" \
    "src/apprt/win32"

# Rule 3: GetOverlappedResult with bWait=TRUE inside the CP pipe server.
#
# Source: #222 root cause. Overlapped IO with bWait=TRUE wedges forever when
# the peer dies between the IO start and the result query. The fix is the
# bWait=FALSE polling pattern + cancel-via-CancelIoEx that vendor/zig-control-
# plane already adopted. Re-introducing TRUE is a regression.
run_rule \
    "overlapped-bwait" \
    'GetOverlappedResult[[:space:]]*\([^;]*,[[:space:]]*(TRUE|true|1)[[:space:]]*\)' \
    'GetOverlappedResult(..., bWait=TRUE) wedges if the peer dies (issue #222)' \
    "use GetOverlappedResult(..., FALSE) + WaitForSingleObject(event, finite_ms) and CancelIoEx on timeout" \
    "error" \
    "vendor/zig-control-plane/src" \
    "src/apprt/winui3" \
    "src/apprt/win32"

# Rule 4: SendMessageW (no-timeout variant) called from a thread that may
# block on the destination window's message pump.
#
# Source: #169 + #223. SendMessageW is synchronous and inherits the
# destination thread's responsiveness. SendMessageTimeoutW with
# SMTO_ABORTIFHUNG bounds the worst case. This is a warning (not error)
# because intra-process callbacks (NCHITTEST forwarding) are sometimes safe
# and the right fix is case-by-case.
run_rule \
    "sendmessagew" \
    '(^|[^a-zA-Z_])SendMessageW[[:space:]]*\(' \
    'SendMessageW has no timeout; if the destination thread hangs, the caller hangs (#169, #223)' \
    "switch to SendMessageTimeoutW with SMTO_ABORTIFHUNG and a small ms (50-500), or use PostMessageW if the call is fire-and-forget" \
    "warn" \
    "src/apprt/winui3" \
    "src/apprt/win32"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
log ""
log "================================================================"
if [ "${VIOLATIONS}" -gt 0 ]; then
    echo "lint-deadlock: ${VIOLATIONS} violation(s), ${WARNINGS} warning(s)"
    echo "lint-deadlock: see notes/2026-04-26_deadlock_lint_rules.md for the rule rationale and fix patterns"
    echo "lint-deadlock: see docs/deadlock-discipline.md for the design rules + escape-valve patterns"
    exit 1
fi

log "lint-deadlock: 0 violations, ${WARNINGS} warning(s)"
exit 0
