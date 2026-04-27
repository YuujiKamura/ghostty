#!/usr/bin/env bash
# tools/lint-fork-isolation.sh
#
# apprt contract lint for ghostty-win (issue #238).
#
# Background: this fork has accumulated edits across ~85 upstream-shared files
# that violate the apprt contract. The apprt/ directory is upstream's explicit
# extension point: fork-driven changes belong inside src/apprt/winui3/ (or
# src/apprt/win32/) as wrapper layers, not as in-place modifications to
# upstream-shared core code.
#
# This script enforces the contract going forward. Existing violations are
# grandfathered (Option A from issue #238): the default mode lints only NEW
# changes (staged diff for pre-commit, branch diff vs fork/main for pre-push).
# The --audit mode analyses the full divergence from upstream merge-base and
# is informational, not blocking.
#
# Bypass for an upstream-shared edit that is genuinely unavoidable:
#   - add `// UPSTREAM-SHARED-OK: <reason>` on the modified line(s), OR
#   - add `UPSTREAM-SHARED-OK: <reason>` trailer to the commit message body
#
# Either is mandatory along with the maintainer self-check in the commit
# message (see docs/apprt-contract.md and AGENTS.md Operating Rule #7).
#
# Exit codes:
#   0   no violations
#   1   one or more violations found
#   2   internal error (missing tool, bad invocation)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

# ---------------------------------------------------------------------------
# Fork-owned path whitelist.
#
# Anything inside these prefixes is fork-owned and may be edited freely.
# Anything outside requires the UPSTREAM-SHARED-OK justification described
# above. Update this list (and the mirror in docs/apprt-contract.md and the
# Operating Rule in AGENTS.md) when the fork's surface area legitimately grows.
# ---------------------------------------------------------------------------
FORK_OWNED=(
    "src/apprt/winui3/"
    "src/apprt/win32/"
    "src/apprt/win32_replacement/"
    "vendor/zig-control-plane/"
    "xaml/"
    "tests/winui3/"
    "scripts/"
    "docs/"
    "tools/"
    "notes/"
    ".github/"
    ".dispatch/"
    ".kiro/"
    ".githooks/"
    ".config/"
    "lefthook.yml"
    "AGENTS.md"
    "CLAUDE.md"
    "NON-NEGOTIABLES.md"
    "AI_POLICY.md"
    "APPRT_INTERFACE.md"
    "PLAN.md"
    "CODEOWNERS"
    "OWNERS.md"
    "build-winui3.sh"
)

# Top-level *.md files (other than the explicit list above) are also allowed
# because they are routinely used as scratch design docs in this fork.
top_level_md_allowed() {
    case "$1" in
        */*) return 1 ;;          # not top-level
        *.md|*.MD) return 0 ;;
    esac
    return 1
}

# Top-level *.ps1 / *.zon variants and other scratch files used during
# investigations are also allowed if they sit at the repo root. We keep the
# rule conservative: only allow common extensions, never directory creation.
top_level_scratch_allowed() {
    case "$1" in
        */*) return 1 ;;
        *.ps1|*.zon|*.zon.*|*.txt|*.toml|*.json|*.yml|*.yaml|*.lock|*.nix) return 0 ;;
        Makefile|Doxyfile|DoxygenLayout.xml|CMakeLists.txt|LICENSE|.gitignore|.gitattributes|.gitmodules|.editorconfig|.envrc|.clang-format|.mailmap|.prettierignore|.shellcheckrc|.swiftlint.yml|.git) return 0 ;;
    esac
    return 1
}

is_fork_owned() {
    local path="$1"
    for prefix in "${FORK_OWNED[@]}"; do
        case "${prefix}" in
            */)
                # directory prefix — match by leading-string comparison
                if [ "${path#${prefix}}" != "${path}" ]; then
                    return 0
                fi
                ;;
            *)
                # exact file match
                if [ "${path}" = "${prefix}" ]; then
                    return 0
                fi
                ;;
        esac
    done
    if top_level_md_allowed "${path}"; then return 0; fi
    if top_level_scratch_allowed "${path}"; then return 0; fi
    return 1
}

# ---------------------------------------------------------------------------
# Mode + flag parsing
# ---------------------------------------------------------------------------
MODE="lint"          # lint | audit
QUIET=0
VERBOSE=0
COMPARE_REF=""

usage() {
    cat <<'EOF'
Usage: tools/lint-fork-isolation.sh [--audit] [--quiet] [--verbose] [--against <ref>]

Default (lint mode): inspects the changes about to be committed/pushed.
  - If staged changes exist, scans `git diff --cached`.
  - Otherwise compares HEAD against fork/main (or --against <ref>).
  - Existing fork divergence prior to those changes is grandfathered.

--audit  Reports the full divergence between fork/main and the upstream
         merge-base (origin/main). Informational only, never exits 1.

--quiet  Suppress headings; print only violations and the final summary.
--verbose Print per-file scan progress.
--against <ref>  Compare against the named ref (default: fork/main).
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --audit) MODE="audit" ;;
        --quiet|-q) QUIET=1 ;;
        --verbose|-v) VERBOSE=1 ;;
        --against) shift; COMPARE_REF="${1:-}" ;;
        --help|-h) usage; exit 0 ;;
        *) echo "lint-fork-isolation: unknown argument: $1" >&2; usage >&2; exit 2 ;;
    esac
    shift
done

log()  { if [ "${QUIET}"   -eq 0 ]; then echo "$@"; fi; }
vlog() { if [ "${VERBOSE}" -eq 1 ]; then echo "$@"; fi; }

# ---------------------------------------------------------------------------
# Justification check.
#
# A file outside fork-owned paths is allowed to be modified if EITHER:
#   - the file's diff hunks contain an `UPSTREAM-SHARED-OK:` marker, OR
#   - the most recent commit message body contains an `UPSTREAM-SHARED-OK:`
#     trailer (this lets a single commit cover multiple files without
#     littering each line)
# ---------------------------------------------------------------------------
diff_has_marker() {
    local file_path="$1"
    local diff_cmd="$2"
    if eval "${diff_cmd} -- '${file_path}'" 2>/dev/null \
        | grep -Eq 'UPSTREAM-SHARED-OK:[[:space:]]*[^[:space:]]'; then
        return 0
    fi
    return 1
}

commit_has_marker() {
    local ref="$1"
    if git log -1 --format=%B "${ref}" 2>/dev/null \
        | grep -Eq 'UPSTREAM-SHARED-OK:[[:space:]]*[^[:space:]]'; then
        return 0
    fi
    return 1
}

# ---------------------------------------------------------------------------
# lint mode
# ---------------------------------------------------------------------------
run_lint() {
    local diff_cmd
    local ref_for_msg=""
    local has_staged
    has_staged="$(git diff --cached --name-only 2>/dev/null | head -1 || true)"

    if [ -n "${has_staged}" ]; then
        log "lint-fork-isolation: scanning staged changes"
        diff_cmd="git diff --cached"
    else
        local base_ref="${COMPARE_REF:-fork/main}"
        # If fork/main is unknown (e.g. fresh clone), fall back to origin/main.
        if ! git rev-parse --verify "${base_ref}" >/dev/null 2>&1; then
            base_ref="origin/main"
        fi
        if ! git rev-parse --verify "${base_ref}" >/dev/null 2>&1; then
            log "lint-fork-isolation: no comparison ref available; nothing to lint"
            exit 0
        fi
        log "lint-fork-isolation: scanning HEAD..${base_ref} (branch divergence)"
        diff_cmd="git diff ${base_ref}..HEAD"
        ref_for_msg="HEAD"
    fi

    local files
    files="$(eval "${diff_cmd}" --name-only 2>/dev/null || true)"

    if [ -z "${files}" ]; then
        log "lint-fork-isolation: no changed files; ok"
        exit 0
    fi

    local violations=0
    while IFS= read -r f; do
        [ -z "${f}" ] && continue
        if is_fork_owned "${f}"; then
            vlog "  ok (fork-owned): ${f}"
            continue
        fi

        # Outside fork-owned paths. Look for justification.
        if diff_has_marker "${f}" "${diff_cmd}"; then
            vlog "  ok (in-diff marker): ${f}"
            continue
        fi
        if [ -n "${ref_for_msg}" ] && commit_has_marker "${ref_for_msg}"; then
            vlog "  ok (commit-trailer marker): ${f}"
            continue
        fi

        echo "${f}: apprt contract violation — file is outside fork-owned paths"
        echo "    fix:    move the change into src/apprt/winui3/ as a wrapper, OR"
        echo "    bypass: add \`// UPSTREAM-SHARED-OK: <reason>\` to the diff,"
        echo "            OR add \`UPSTREAM-SHARED-OK: <reason>\` trailer to commit message,"
        echo "            AND include the maintainer self-check in the commit body."
        echo "    See docs/apprt-contract.md and AGENTS.md Operating Rule #7."
        echo ""
        violations=$((violations + 1))
    done <<< "${files}"

    if [ "${violations}" -gt 0 ]; then
        echo "lint-fork-isolation: ${violations} apprt contract violation(s)"
        exit 1
    fi
    log "lint-fork-isolation: 0 violations"
    exit 0
}

# ---------------------------------------------------------------------------
# audit mode
#
# Reads the full divergence between fork/main (or HEAD) and the upstream
# merge-base (origin/main). Categorises each upstream-shared edit so the
# refactor backlog can be planned. Never exits 1.
# ---------------------------------------------------------------------------
run_audit() {
    local fork_ref="${COMPARE_REF:-fork/main}"
    if ! git rev-parse --verify "${fork_ref}" >/dev/null 2>&1; then
        fork_ref="HEAD"
    fi

    local upstream_ref="origin/main"
    if [ -n "${MERGE_BASE:-}" ]; then
        local mb="${MERGE_BASE}"
    else
        if ! git rev-parse --verify "${upstream_ref}" >/dev/null 2>&1; then
            echo "lint-fork-isolation: --audit needs origin/main (run 'git fetch origin main')" >&2
            exit 2
        fi
        local mb
        mb="$(git merge-base "${fork_ref}" "${upstream_ref}")"
    fi

    log "lint-fork-isolation --audit: ${fork_ref} vs merge-base ${mb}"
    log ""

    local files
    files="$(git diff --name-only "${mb}..${fork_ref}" 2>/dev/null || true)"

    local movable=()
    local stdlib=()
    local cross_apprt=()
    local core=()

    while IFS= read -r f; do
        [ -z "${f}" ] && continue
        if is_fork_owned "${f}"; then continue; fi

        # Skip top-level scratch files (already covered by is_fork_owned for
        # the common cases; this is just defensive).
        case "${f}" in
            src/*) ;;            # only audit src/ for category breakdown
            *) continue ;;
        esac

        case "${f}" in
            src/apprt/embedded.zig|src/apprt/embedded/*|src/apprt/gtk/*|src/apprt/macos/*)
                cross_apprt+=("${f}")
                continue
                ;;
            src/datastruct/*|src/os/*)
                stdlib+=("${f}")
                continue
                ;;
        esac

        if git diff "${mb}..${fork_ref}" -- "${f}" 2>/dev/null \
            | grep -qiE '(winui3|win32|d3d11|directwrite|hlsl|fontconfig)'; then
            movable+=("${f}")
        else
            core+=("${f}")
        fi
    done <<< "${files}"

    log "================================================================"
    log "summary:"
    log "  MOVABLE (mentions winui3/win32/d3d11/etc):   ${#movable[@]}"
    log "  STDLIB-WRAPPABLE (datastruct/, os/):         ${#stdlib[@]}"
    log "  CROSS-APPRT-CONTAMINATION (other apprts):    ${#cross_apprt[@]}"
    log "  CORE-ADAPTATION (everything else under src): ${#core[@]}"
    log "================================================================"
    log ""

    print_section() {
        local title="$1"; shift
        echo "## ${title}"
        if [ "$#" -eq 0 ]; then
            echo "(0 files)"
            echo ""
            return
        fi
        for f in "$@"; do echo "- ${f}"; done
        echo ""
    }

    print_section "MOVABLE — extract to apprt/winui3/" "${movable[@]+"${movable[@]}"}"
    print_section "STDLIB-WRAPPABLE — wrap in apprt/winui3/ instead of modifying stdlib types" "${stdlib[@]+"${stdlib[@]}"}"
    print_section "CROSS-APPRT-CONTAMINATION — revert on next upstream merge" "${cross_apprt[@]+"${cross_apprt[@]}"}"
    print_section "CORE-ADAPTATION — case-by-case analysis required" "${core[@]+"${core[@]}"}"

    exit 0
}

case "${MODE}" in
    lint)  run_lint ;;
    audit) run_audit ;;
esac
