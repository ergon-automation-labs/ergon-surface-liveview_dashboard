#!/usr/bin/env bash
#
# Prune this repo's own release artifacts.
#
# WHY THIS EXISTS
# ---------------
# `mix release --overwrite` does not clear the release directory. Every build
# leaves its app copy behind:
#
#   _build/prod/rel/<rel>/lib/<app>-0.2.46
#   _build/prod/rel/<rel>/lib/<app>-0.2.47     ... one per version, forever
#   _build/prod/rel/<rel>/releases/0.2.46/
#   _build/prod/rel/<rel>/releases/0.2.47/
#
# and the tarball is built from that whole directory, so a release published
# today ships every past copy of the app. Measured 2026-09-29: the dashboard's
# 0.2.47 tarball carried 65 copies of the app (2194 files under lib/), and 64
# tarballs — 1.1 GB — had piled up at the repo root.
#
# So the two halves run at the two moments that matter:
#
#   * --build-tree, BEFORE `mix release`  → the artifact ships one app copy
#   * --archives,   AFTER a verified publish → GitHub holds the asset now
#
# WHAT IT WILL NEVER TOUCH
# ------------------------
#   * published GitHub releases (this script never calls `gh`)
#   * the current version, or the newest --keep-build / --keep-archives ones
#   * anything tracked by git, and anything outside _build/ or this repo root
#
# USAGE
#   scripts/prune_release_artifacts.sh                       # dry run, both halves
#   scripts/prune_release_artifacts.sh --build-tree --apply  # before `mix release`
#   scripts/prune_release_artifacts.sh --archives  --apply   # after a verified publish
#
#   --apply                actually delete (default: print the plan and stop)
#   --build-tree           prune _build/prod/rel only
#   --archives             prune root tarballs only
#   --keep-build N         versions kept in the build tree (default 1)
#   --keep-archives N      tarballs kept at the repo root (default 3)
#   --rel NAME             release directory under _build/prod/rel (default: the
#                          only one there; pass it if the tree holds several)
#   --repo DIR             repo root (default: the script's parent directory)
#
# Exit status: 0 whether or not anything was pruned. Non-zero only when the
# invocation itself is wrong (bad flag, unreadable mix.exs, ambiguous tree) —
# so a caller can safely run this as housekeeping without it becoming a gate.

set -euo pipefail

APPLY=0
DO_BUILD=0
DO_ARCHIVES=0
KEEP_BUILD=1
KEEP_ARCHIVES=3
REL_NAME=""
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  sed -n '/^# USAGE/,/^# Exit status/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

die() {
  echo "prune-release-artifacts: $*" >&2
  exit 1
}

while [ $# -gt 0 ]; do
  case "$1" in
    --apply) APPLY=1 ;;
    --build-tree) DO_BUILD=1 ;;
    --archives) DO_ARCHIVES=1 ;;
    --keep-build) KEEP_BUILD="${2:-}"; shift ;;
    --keep-archives) KEEP_ARCHIVES="${2:-}"; shift ;;
    --rel) REL_NAME="${2:-}"; shift ;;
    --repo) REPO="${2:-}"; shift ;;
    -h | --help)
      usage
      exit 0
      ;;
    *) die "unknown flag: $1 (try --help)" ;;
  esac
  shift
done

echo "$KEEP_BUILD" | grep -qE '^[0-9]+$' || die "--keep-build wants a number, got '$KEEP_BUILD'"
echo "$KEEP_ARCHIVES" | grep -qE '^[0-9]+$' || die "--keep-archives wants a number, got '$KEEP_ARCHIVES'"

if [ "$DO_BUILD" -eq 0 ] && [ "$DO_ARCHIVES" -eq 0 ]; then
  DO_BUILD=1
  DO_ARCHIVES=1
fi

[ -d "$REPO" ] || die "no such directory: $REPO"
cd "$REPO"

APP="$(grep -oE 'app:[[:space:]]*:[a-z0-9_]+' mix.exs 2>/dev/null | head -1 | sed 's/.*://')"
[ -n "$APP" ] || die "could not read 'app:' from $REPO/mix.exs"

# Version strings only, and only this app's. Deps in lib/ (asn1-5.3.4.2,
# phoenix-1.7.23) and non-version entries (COOKIE, start_erl.data) never match.
VERSION_RE='^[0-9]+\.[0-9]+\.[0-9]+$'

sort_versions_desc() {
  # Newest first, numerically.
  #
  # NOT `sort -t. -k1,1n -k2,2n -k3,3n -r`: measured on macOS 2.3-Apple (199),
  # a global -r is IGNORED when the keys carry per-key n modifiers, so that line
  # sorts ASCENDING and hands back the oldest version as "newest" — which is how
  # a prune script deletes the version it was supposed to keep. Plain awk cannot
  # get this wrong.
  awk -F. '
    { v[NR] = $0; k[NR] = $1 * 1000000 + $2 * 1000 + $3 }
    END {
      for (i = 1; i <= NR; i++)
        for (j = i + 1; j <= NR; j++)
          if (k[j] > k[i]) {
            t = k[i]; k[i] = k[j]; k[j] = t
            s = v[i]; v[i] = v[j]; v[j] = s
          }
      for (i = 1; i <= NR; i++) print v[i]
    }'
}

# Prints the versions to KEEP: the newest N of those given, plus `current`
# (the version already built, or the newest archive) even if it is older.
kept_versions() {
  local keep="$1" current="$2"
  shift 2
  {
    [ -n "$current" ] && echo "$current"
    printf '%s\n' "$@" | sort_versions_desc | head -n "$keep"
  } | grep -vE '^$' | sort -u
}

kb_of() {
  # Size of one path in KiB; a missing path is 0, not an error.
  if [ -e "$1" ]; then
    du -sk "$1" 2>/dev/null | awk '{print $1}'
  else
    echo 0
  fi
}

bytes_of_file() {
  if [ -e "$1" ]; then
    wc -c <"$1" | tr -d ' '
  else
    echo 0
  fi
}

human_kb() {
  awk -v kb="$1" 'BEGIN {
    if (kb >= 1048576) printf "%.1f GB", kb / 1048576;
    else if (kb >= 1024) printf "%.1f MB", kb / 1024;
    else printf "%d KB", kb;
  }'
}

# List what would go, delete it if asked, and report both. Every path to be
# removed must sit inside $REPO and match the strict version shape above.
prune_paths() {
  local label="$1" freed_kb="$2" shown=0 total="$3"
  shift 3
  if [ "$APPLY" -eq 1 ]; then
    local p
    for p in "$@"; do
      case "$p" in "$REPO"/*) rm -rf -- "$p" ;; *) die "refusing to delete outside the repo: $p" ;; esac
    done
  fi
  local n=0
  for p in "$@"; do
    n=$((n + 1))
    if [ "$APPLY" -eq 1 ] || [ "$n" -le 5 ]; then
      echo "    - ${p#"$REPO"/}"
      shown=$((shown + 1))
    fi
  done
  if [ "$APPLY" -eq 0 ] && [ "$n" -gt "$shown" ]; then
    echo "    ... and $((n - shown)) more"
  fi
  printf '  %s: %s %s (%s)\n' "$label" \
    "$([ "$APPLY" -eq 1 ] && echo removed || echo to remove)" \
    "$total" "$(human_kb "$freed_kb")"
}

# ── the build tree ──────────────────────────────────────────────────────────
if [ "$DO_BUILD" -eq 1 ]; then
  REL_DIRS=()
  for d in "$REPO"/_build/prod/rel/*/; do
    [ -d "${d}releases" ] && REL_DIRS+=("${d%/}")
  done

  if [ "${#REL_DIRS[@]}" -eq 0 ]; then
    : # never built here yet — nothing to prune, not an error
  else
    if [ -n "$REL_NAME" ]; then
      REL="$REPO/_build/prod/rel/$REL_NAME"
      [ -d "$REL/releases" ] || die "--rel $REL_NAME is not a release directory under _build/prod/rel"
    elif [ "${#REL_DIRS[@]}" -eq 1 ]; then
      REL="${REL_DIRS[0]}"
    else
      die "more than one release directory under _build/prod/rel (${REL_DIRS[*]}) — pass --rel NAME"
    fi

    CURRENT=""
    if [ -f "$REL/releases/start_erl.data" ]; then
      CURRENT="$(awk '{print $2}' "$REL/releases/start_erl.data")"
    fi
    echo "$CURRENT" | grep -qE "$VERSION_RE" || CURRENT=""

    VERS=()
    for p in "$REL"/lib/"$APP"-[0-9]*.[0-9]*.[0-9]* "$REL"/releases/[0-9]*.[0-9]*.[0-9]*; do
      [ -d "$p" ] || continue
      v="$(basename "$p")"
      case "$v" in "$APP"-*) v="${v#"$APP"-}" ;; esac
      echo "$v" | grep -qE "$VERSION_RE" || continue
      VERS+=("$v")
    done

    KEEP_LIST=""
    [ "${#VERS[@]}" -gt 0 ] && KEEP_LIST="$(kept_versions "$KEEP_BUILD" "$CURRENT" "${VERS[@]}")"

    DOOMED=()
    DOOMED_KB=0

    for p in "$REL"/lib/"$APP"-[0-9]*.[0-9]*.[0-9]*; do
      [ -d "$p" ] || continue
      v="$(basename "$p" | sed "s/^$APP-//")"
      echo "$v" | grep -qE "$VERSION_RE" || continue
      echo "$KEEP_LIST" | grep -qx "$v" && continue
      DOOMED+=("$p")
      DOOMED_KB=$((DOOMED_KB + $(kb_of "$p")))
    done

    for p in "$REL"/releases/[0-9]*.[0-9]*.[0-9]*; do
      [ -d "$p" ] || continue
      v="$(basename "$p")"
      echo "$v" | grep -qE "$VERSION_RE" || continue
      echo "$KEEP_LIST" | grep -qx "$v" && continue
      DOOMED+=("$p")
      DOOMED_KB=$((DOOMED_KB + $(kb_of "$p")))
    done

    echo "🧹 build tree $REL (release $APP, built $([ -n "$CURRENT" ] && echo "$CURRENT" || echo 'never'))"
    echo "    keeping: $(echo "$KEEP_LIST" | tr '\n' ' ')"
    if [ "${#DOOMED[@]}" -eq 0 ]; then
      echo "  nothing to remove"
    else
      prune_paths "build tree" "$DOOMED_KB" "${#DOOMED[@]} entries" "${DOOMED[@]}"
    fi
  fi
fi

# ── the archives at the repo root ───────────────────────────────────────────
if [ "$DO_ARCHIVES" -eq 1 ]; then
  ARCHIVE_RE="^$APP-[0-9]+\.[0-9]+\.[0-9]+\.tar\.gz$"

  VERSIONS=()
  for f in "$APP"-[0-9]*.[0-9]*.[0-9]*.tar.gz; do
    [ -f "$f" ] || continue
    basename "$f" | grep -qE "$ARCHIVE_RE" || continue
    VERSIONS+=("$(basename "$f" | sed "s/^$APP-//; s/\.tar\.gz$//")")
  done

  if [ "${#VERSIONS[@]}" -eq 0 ]; then
    echo "🧹 archives: none for $APP"
  else
    CURRENT_ARCHIVE="$(printf '%s\n' "${VERSIONS[@]}" | sort_versions_desc | head -1)"
    KEEP_ARCH="$(kept_versions "$KEEP_ARCHIVES" "$CURRENT_ARCHIVE" "${VERSIONS[@]}")"

    DOOMED=()
    DOOMED_KB=0
    for v in "${VERSIONS[@]}"; do
      echo "$KEEP_ARCH" | grep -qx "$v" && continue
      f="$REPO/$APP-$v.tar.gz"
      DOOMED+=("$f")
      # KiB, to match the build-tree total
      DOOMED_KB=$((DOOMED_KB + ($(bytes_of_file "$f") + 1023) / 1024))
    done

    echo "🧹 archives at $REPO/ (${#VERSIONS[@]} for $APP)"
    echo "    keeping: $(echo "$KEEP_ARCH" | tr '\n' ' ')"
    if [ "${#DOOMED[@]}" -eq 0 ]; then
      echo "  nothing to remove"
    else
      prune_paths "archives" "$DOOMED_KB" "${#DOOMED[@]} tarballs" "${DOOMED[@]}"
    fi
  fi
fi

if [ "$APPLY" -eq 0 ]; then
  echo ""
  echo "Dry run — nothing was deleted. Add --apply to act."
fi
