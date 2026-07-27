#!/usr/bin/env bash
# Report how far the Tahoe niri/quickshell forks diverge from their upstreams.
#
# For each fork this prints:
#   - HEAD / upstream tip / merge-base (with date)
#   - commits ahead of upstream (Tahoe-only)
#   - commits behind upstream (unabsorbed upstream work)
#   - whether the configured `upstream` remote is present
#   - when histories were rewritten (no merge-base with real upstream), a
#     fork-baseline section against origin/<default> so the weekly report
#     still has a usable ahead/behind number
#
# By default this is offline-friendly: it uses whatever refs are already
# available (the local `upstream/<branch>` remote-tracking branch). If the
# tracking ref is missing, the script auto-fetches that one branch once
# (network required for first useful run after --ensure-remotes). Pass
# --fetch to force-refresh even when the ref already exists; pass
# --offline to never touch the network (missing ref → no-upstream-ref).
#
# Exit codes (stable contract — automation must call THIS script, not
# check-submodules.sh, if it needs the exit status):
#   0  both forks reported successfully (including history-rewritten).
#      Non-strict mode returns 0 even when behind > 0; read the
#      `caught-up:` / `shareable-behind:` summary fields, or pass --strict.
#   1  one or more forks could not be reported (missing checkout/remote,
#      fetch fail, …), OR --strict and (shareable-behind > 0 OR any
#      history-rewritten fork without FORK_LAG_ALLOW_REWRITTEN=true)
#   2  usage error
#
# "upstream" here means the REAL project upstream (niri-wm/niri,
# quickshell-mirror/quickshell). This is NOT the same word arch-update.sh
# uses when it says "updating niri submodule to latest upstream" — that
# path means origin/ (the Tahoe fork remote).

set -euo pipefail

log() {
  printf '[fork-lag] %s\n' "$*"
}

die() {
  printf '[fork-lag] ERROR: %s\n' "$*" >&2
  exit 2
}

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="${REPO_DIR:-"$(cd -- "$SCRIPT_DIR/.." && pwd)"}"
NIRI_DIR="${NIRI_DIR:-"$REPO_DIR/niri"}"
QUICKSHELL_DIR="${QUICKSHELL_DIR:-"$REPO_DIR/quickshell"}"

# Canonical upstreams for the Tahoe forks. Overridable for mirrors/airgapped
# setups; defaults match the public project homes used by T-01.
NIRI_UPSTREAM_URL="${NIRI_UPSTREAM_URL:-https://github.com/niri-wm/niri.git}"
NIRI_UPSTREAM_BRANCH="${NIRI_UPSTREAM_BRANCH:-main}"
QUICKSHELL_UPSTREAM_URL="${QUICKSHELL_UPSTREAM_URL:-https://github.com/quickshell-mirror/quickshell.git}"
QUICKSHELL_UPSTREAM_BRANCH="${QUICKSHELL_UPSTREAM_BRANCH:-master}"

# Optional per-fork freeze refs used when real-upstream history is disconnected
# (niri was re-imported; its SHA graph no longer shares a merge-base with
# niri-wm/niri). Defaults fall back to origin/main or origin/master.
NIRI_FORK_BASELINE_REF="${NIRI_FORK_BASELINE_REF:-origin/main}"
QUICKSHELL_FORK_BASELINE_REF="${QUICKSHELL_FORK_BASELINE_REF:-origin/master}"

# Under --strict, history-rewritten forks fail closed unless the operator
# explicitly acknowledges them (T-37 content rebase is the real fix).
ALLOW_REWRITTEN="${FORK_LAG_ALLOW_REWRITTEN:-false}"

DO_FETCH=false          # force refresh even when ref exists
OFFLINE=false           # never touch the network
ENSURE_REMOTES=false
STRICT=false

usage() {
  cat <<'EOF'
Usage: report-fork-lag.sh [options]

Report commit lag of the Tahoe niri and quickshell forks vs their upstreams.

Options:
  --fetch            force-refresh upstream/<branch> (network required)
  --offline          never fetch; missing upstream/<branch> → no-upstream-ref
  --ensure-remotes   add the canonical `upstream` remote if missing
                     (does not overwrite an existing upstream URL; skips
                     checkouts that are not yet initialized)
  --strict           exit 1 if shareable-behind > 0, OR if any fork is
                     history-rewritten unless FORK_LAG_ALLOW_REWRITTEN=true
  -h, --help         show this help

Default network policy (neither --fetch nor --offline):
  use the existing upstream/<branch> ref when present; if it is missing
  after --ensure-remotes, auto-fetch that one branch once so a fresh clone
  produces real lag numbers without a second flag.

Environment overrides:
  REPO_DIR, NIRI_DIR, QUICKSHELL_DIR
  NIRI_UPSTREAM_URL, NIRI_UPSTREAM_BRANCH
  QUICKSHELL_UPSTREAM_URL, QUICKSHELL_UPSTREAM_BRANCH
  NIRI_FORK_BASELINE_REF, QUICKSHELL_FORK_BASELINE_REF
  FORK_LAG_ALLOW_REWRITTEN   (true/false; default false)

Exit codes: 0 = reported, 1 = incomplete or --strict gate failed, 2 = usage.
Automation that needs the exit status must call this script directly;
scripts/check-submodules.sh only surfaces the report on stdout and always
exits 0 itself (it is a diagnostic aggregator, not a gate).

Note: the word "upstream" here is the REAL project remote (niri-wm/niri,
quickshell-mirror/quickshell). arch-update.sh's "submodule upstream" means
origin/ (the Tahoe fork). The two are not interchangeable.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --fetch) DO_FETCH=true; shift ;;
    --offline) OFFLINE=true; shift ;;
    --ensure-remotes) ENSURE_REMOTES=true; shift ;;
    --strict) STRICT=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

if $DO_FETCH && $OFFLINE; then
  die "--fetch and --offline are mutually exclusive"
fi

# is_git_checkout <dir> — true when dir is a git work tree (regular or submodule).
is_git_checkout() {
  local dir="$1"
  [[ -e "$dir/.git" ]] || return 1
  git -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1
}

# ensure_upstream_remote <repo_dir> <url>
# Adds `upstream` pointing at <url> when absent. Refuses to silently retarget
# an existing upstream that points somewhere else. Returns 0 on success or
# "already present"; returns 1 if the checkout is missing/broken so the
# caller can continue with the other fork (never abort the whole script).
ensure_upstream_remote() {
  local repo_dir="$1"
  local url="$2"
  local existing
  local name
  name="$(basename "$repo_dir")"

  if ! is_git_checkout "$repo_dir"; then
    log "WARNING: $name is not a git checkout; cannot add upstream remote"
    return 1
  fi

  if ! git -C "$repo_dir" remote get-url upstream >/dev/null 2>&1; then
    log "adding upstream remote in $name: $url"
    if ! git -C "$repo_dir" remote add upstream "$url"; then
      log "WARNING: failed to add upstream remote in $name"
      return 1
    fi
    return 0
  fi

  existing="$(git -C "$repo_dir" remote get-url upstream)"
  if [[ "$existing" != "$url" ]]; then
    # Accept common mirror aliases (git.outfoxxed.me ↔ github mirror) only when
    # the operator already set them; do not rewrite. Just warn.
    log "WARNING: $name upstream is '$existing' (expected '$url'); leaving as-is"
  fi
  return 0
}

# short_hash <repo> <rev>
short_hash() {
  git -C "$1" rev-parse --short=12 "$2" 2>/dev/null
}

# commit_date_iso <repo> <rev>  →  YYYY-MM-DD
commit_date_iso() {
  git -C "$1" show -s --format='%cs' "$2" 2>/dev/null
}

# has_upstream_ref <repo_dir> <branch>
has_upstream_ref() {
  git -C "$1" rev-parse --verify "upstream/${2}" >/dev/null 2>&1
}

# fetch_upstream_branch <repo_dir> <branch>
# Explicit refspec so upstream/<branch> is created even on a fresh remote add.
fetch_upstream_branch() {
  local repo_dir="$1"
  local branch="$2"
  git -C "$repo_dir" fetch --quiet upstream \
    "+refs/heads/${branch}:refs/remotes/upstream/${branch}"
}

# resolve_upstream_sha <repo_dir> <branch>
resolve_upstream_sha() {
  local repo_dir="$1"
  local branch="$2"
  local ref="upstream/${branch}"
  local sha

  if sha="$(git -C "$repo_dir" rev-parse --verify "$ref" 2>/dev/null)"; then
    printf '%s\n' "$sha"
    return 0
  fi
  return 1
}

# print_baseline <repo_dir> <baseline_ref>
# Secondary lag number against the fork's own recorded baseline (typically
# origin/main). Useful when real-upstream history was rewritten so rev-list
# against upstream/* is meaningless.
print_baseline() {
  local repo_dir="$1"
  local baseline_ref="$2"
  local base_sha ahead behind base_date

  if ! base_sha="$(git -C "$repo_dir" rev-parse --verify "$baseline_ref" 2>/dev/null)"; then
    printf 'fork-baseline: %s (missing)\n' "$baseline_ref"
    return 0
  fi
  if ! git -C "$repo_dir" merge-base HEAD "$base_sha" >/dev/null 2>&1; then
    printf 'fork-baseline: %s (%s) — no common ancestor with HEAD either\n' \
      "$baseline_ref" "$(short_hash "$repo_dir" "$base_sha")"
    return 0
  fi

  behind=0
  ahead=0
  read -r behind ahead < <(git -C "$repo_dir" rev-list --left-right --count "${base_sha}...HEAD") \
    || true
  base_date="$(commit_date_iso "$repo_dir" "$base_sha")"
  printf 'fork-baseline: %s (%s, %s)\n' \
    "$baseline_ref" "$(short_hash "$repo_dir" "$base_sha")" "$base_date"
  printf 'fork-baseline-ahead: %s  (commits on HEAD not in baseline)\n' "$ahead"
  printf 'fork-baseline-behind: %s  (commits on baseline not in HEAD)\n' "$behind"
  printf 'fork-baseline-note: baseline is the Tahoe fork remote, NOT real upstream; behind=0 here does not mean upstream is absorbed\n'
}

# report_one <name> <repo_dir> <upstream_url> <upstream_branch> <baseline_ref>
# Prints a multi-line STATUS block and returns 0 on success, 1 on failure.
# Sets globals:
#   __behind  commits behind a shareable upstream (0 for history-rewritten)
#   __state   last reported state string (ok|history-rewritten|…)
__behind=0
__state=""
report_one() {
  local name="$1"
  local repo_dir="$2"
  local upstream_url="$3"
  local upstream_branch="$4"
  local baseline_ref="$5"
  local head_sha upstream_sha base_sha
  local ahead behind base_date upstream_date head_date
  local remote_url upstream_ref

  __behind=0
  __state=""
  printf '\n=== %s ===\n' "$name"

  if ! is_git_checkout "$repo_dir"; then
    __state="missing"
    printf 'state: missing\n'
    printf 'detail: %s is not a git checkout\n' "$repo_dir"
    return 1
  fi

  if ! head_sha="$(git -C "$repo_dir" rev-parse HEAD 2>/dev/null)"; then
    __state="broken"
    printf 'state: broken\n'
    printf 'detail: cannot resolve HEAD in %s\n' "$repo_dir"
    return 1
  fi

  head_date="$(commit_date_iso "$repo_dir" HEAD)"

  if ! remote_url="$(git -C "$repo_dir" remote get-url upstream 2>/dev/null)"; then
    __state="no-upstream-remote"
    printf 'state: no-upstream-remote\n'
    printf 'head: %s (%s)\n' "$(short_hash "$repo_dir" HEAD)" "$head_date"
    printf 'detail: remote "upstream" is not configured (expected %s)\n' "$upstream_url"
    printf 'action: re-run with --ensure-remotes, or: git -C %s remote add upstream %s\n' \
      "$repo_dir" "$upstream_url"
    print_baseline "$repo_dir" "$baseline_ref"
    return 1
  fi

  printf 'upstream-remote: %s\n' "$remote_url"

  # Fetch policy:
  #   --fetch   → always refresh
  #   --offline → never
  #   default   → fetch only when upstream/<branch> is missing (first-run path)
  if $DO_FETCH; then
    log "fetching $name upstream ($upstream_branch)"
    if ! fetch_upstream_branch "$repo_dir" "$upstream_branch"; then
      __state="fetch-failed"
      printf 'state: fetch-failed\n'
      printf 'head: %s (%s)\n' "$(short_hash "$repo_dir" HEAD)" "$head_date"
      printf 'detail: git fetch upstream %s failed\n' "$upstream_branch"
      print_baseline "$repo_dir" "$baseline_ref"
      return 1
    fi
  elif ! $OFFLINE && ! has_upstream_ref "$repo_dir" "$upstream_branch"; then
    log "upstream/${upstream_branch} missing in $name; auto-fetching once"
    if ! fetch_upstream_branch "$repo_dir" "$upstream_branch"; then
      __state="fetch-failed"
      printf 'state: fetch-failed\n'
      printf 'head: %s (%s)\n' "$(short_hash "$repo_dir" HEAD)" "$head_date"
      printf 'detail: auto-fetch of upstream %s failed (pass --offline to skip)\n' "$upstream_branch"
      print_baseline "$repo_dir" "$baseline_ref"
      return 1
    fi
  fi

  upstream_ref="upstream/${upstream_branch}"
  if ! upstream_sha="$(resolve_upstream_sha "$repo_dir" "$upstream_branch")"; then
    __state="no-upstream-ref"
    printf 'state: no-upstream-ref\n'
    printf 'head: %s (%s)\n' "$(short_hash "$repo_dir" HEAD)" "$head_date"
    printf 'detail: missing ref %s — pass --fetch (or drop --offline) after --ensure-remotes\n' "$upstream_ref"
    print_baseline "$repo_dir" "$baseline_ref"
    return 1
  fi

  upstream_date="$(commit_date_iso "$repo_dir" "$upstream_sha")"
  printf 'head: %s (%s)\n' "$(short_hash "$repo_dir" HEAD)" "$head_date"
  printf 'upstream: %s (%s) [%s]\n' \
    "$(short_hash "$repo_dir" "$upstream_sha")" "$upstream_date" "$upstream_ref"

  if ! base_sha="$(git -C "$repo_dir" merge-base HEAD "$upstream_sha" 2>/dev/null)"; then
    # The Tahoe niri fork re-imported history (root commit is a Tahoe
    # snapshot, not upstream's "Init from smallvil"), so SHA-level rev-list
    # against niri-wm/niri is meaningless. Report that honestly and fall
    # back to the fork baseline for a usable ahead count.
    __state="history-rewritten"
    printf 'state: history-rewritten\n'
    printf 'merge-base: (none — fork history does not share commits with real upstream)\n'
    printf 'ahead: n/a\n'
    printf 'behind: n/a\n'
    printf 'upstream-tip-date: %s\n' "$upstream_date"
    printf 'head-tip-date: %s\n' "$head_date"
    printf 'note: SHA graphs are disconnected; tip dates are NOT lag — a newer HEAD date does not mean upstream is absorbed\n'
    printf 'note: use fork-baseline counts below; schedule a content-based rebase (roadmap T-37)\n'
    print_baseline "$repo_dir" "$baseline_ref"
    __behind=0
    return 0
  fi

  # rev-list --left-right --count A...B → "<left>\t<right>" where left =
  # commits reachable from A not B, right = from B not A.
  # With A=upstream, B=HEAD: left=behind, right=ahead.
  behind=0
  ahead=0
  read -r behind ahead < <(git -C "$repo_dir" rev-list --left-right --count "${upstream_sha}...HEAD") \
    || true
  __behind="$behind"
  __state="ok"
  base_date="$(commit_date_iso "$repo_dir" "$base_sha")"

  printf 'state: ok\n'
  printf 'merge-base: %s (%s)\n' "$(short_hash "$repo_dir" "$base_sha")" "$base_date"
  printf 'ahead: %s  (Tahoe commits not in upstream)\n' "$ahead"
  printf 'behind: %s  (upstream commits not absorbed)\n' "$behind"

  if [[ "$behind" -gt 0 ]]; then
    printf 'note: fork is behind upstream; schedule a rebase window (see roadmap T-37)\n'
  fi
  if [[ "$ahead" -eq 0 && "$behind" -eq 0 ]]; then
    printf 'note: HEAD matches upstream tip\n'
  fi
  return 0
}

# ── main ──────────────────────────────────────────────────────────────────
log "repo: $REPO_DIR"

if $ENSURE_REMOTES; then
  # Best-effort: a missing checkout must not abort the other fork's report
  # (previously `git -C missing` under set -e produced exit 128 outside the
  # documented 0/1/2 contract).
  ensure_upstream_remote "$NIRI_DIR" "$NIRI_UPSTREAM_URL" || true
  ensure_upstream_remote "$QUICKSHELL_DIR" "$QUICKSHELL_UPSTREAM_URL" || true
fi

failures=0
behind_total=0
rewritten=0

if ! report_one "niri" "$NIRI_DIR" "$NIRI_UPSTREAM_URL" "$NIRI_UPSTREAM_BRANCH" "$NIRI_FORK_BASELINE_REF"; then
  failures=$((failures + 1))
else
  behind_total=$((behind_total + __behind))
  if [[ "$__state" == "history-rewritten" ]]; then
    rewritten=$((rewritten + 1))
  fi
fi

if ! report_one "quickshell" "$QUICKSHELL_DIR" "$QUICKSHELL_UPSTREAM_URL" "$QUICKSHELL_UPSTREAM_BRANCH" "$QUICKSHELL_FORK_BASELINE_REF"; then
  failures=$((failures + 1))
else
  behind_total=$((behind_total + __behind))
  if [[ "$__state" == "history-rewritten" ]]; then
    rewritten=$((rewritten + 1))
  fi
fi

printf '\n=== summary ===\n'
printf 'shareable-behind: %s\n' "$behind_total"
printf 'history-rewritten-forks: %s\n' "$rewritten"
if [[ "$behind_total" -eq 0 && "$rewritten" -eq 0 && "$failures" -eq 0 ]]; then
  printf 'caught-up: yes\n'
else
  printf 'caught-up: no\n'
fi

if [[ "$failures" -gt 0 ]]; then
  printf 'result: INCOMPLETE (%s fork(s) could not be reported)\n' "$failures"
  exit 1
fi

if $STRICT; then
  strict_fail=false
  if [[ "$behind_total" -gt 0 ]]; then
    strict_fail=true
  fi
  if [[ "$rewritten" -gt 0 && "$ALLOW_REWRITTEN" != "true" ]]; then
    strict_fail=true
    printf 'strict-note: %s history-rewritten fork(s) fail --strict unless FORK_LAG_ALLOW_REWRITTEN=true\n' "$rewritten"
  fi
  if $strict_fail; then
    printf 'result: BEHIND (strict gate failed; shareable-behind=%s rewritten=%s)\n' \
      "$behind_total" "$rewritten"
    exit 1
  fi
fi

# "REPORTED" (not "OK") so grepping result: OK cannot mistake a lagging tree
# for a healthy one. Use caught-up: yes for the clean signal.
printf 'result: REPORTED (shareable-behind=%s rewritten=%s)\n' "$behind_total" "$rewritten"
exit 0
