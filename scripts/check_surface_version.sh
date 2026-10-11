#!/usr/bin/env bash
#
# Refuse to publish a surface version that is already published.
#
# Why this exists
# ---------------
# A surface's pre-push hook and its `publish-release` target both build a
# tarball and upload it to GitHub under `v<version>`: `gh release create` the
# first time, `gh release upload --clobber` every time after. The deploy state
# then resolves the *latest* release and skips the download when that version's
# directory is already on disk:
#
#     if [ ! -d "$VERSION_DIR" ]; then ... fi     # salt/surfaces/<name>.sls
#
# So a change pushed without a version bump re-cuts the version that is already
# running: the upload clobbers the asset, the state says "already deployed", the
# `current` symlink does not move, and the health check compares the running
# version against a version file that says the same thing. Everything reports
# green and the old code is still serving. That is the one failure mode in this
# pipeline that looks exactly like success, and this is the cheapest place to
# stop it.
#
# Usage
# -----
#   scripts/check_surface_version.sh <version> <github-repo>
#
#   exit 0   the version is not published yet — publish it
#   exit 0   HOTFIX=1 — republish deliberately, said out loud
#   exit 0   GitHub could not be asked (offline, no auth, gh missing) — the
#            question is unanswered, so the push proceeds with a warning. This is
#            a gate, not a lock: a hook that blocks pushes on a flaky network
#            gets --no-verify'd, and then it protects nothing.
#   exit 1   v<version> is already published — bump the version, or set HOTFIX=1
#   exit 2   usage
#
# It never prints a token and never touches the working tree.
set -uo pipefail

VERSION="${1:-}"
REPO="${2:-}"

if [ -z "$VERSION" ] || [ -z "$REPO" ]; then
  echo "usage: check_surface_version.sh <version> <github-repo>"
  exit 2
fi

if [ -n "${HOTFIX:-}" ]; then
  echo "⚠️  HOTFIX=1 — republishing v$VERSION even if it is already published."
  echo "    Right when: the release is already correct and you are re-running a push,"
  echo "    or you deliberately mean to re-cut this version."
  echo "    Wrong when: you forgot to bump, and this is a code change."
  exit 0
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "⚠️  gh is not installed — cannot check whether v$VERSION is already published."
  exit 0
fi

# macOS ships no `timeout`; coreutils installs it as `timeout` (homebrew) or
# `gtimeout`. Use whichever exists, and if neither does, ask anyway.
TMO_SECONDS="${SURFACE_VERSION_CHECK_TIMEOUT:-15}"
TMO=""
if command -v timeout >/dev/null 2>&1; then
  TMO="timeout $TMO_SECONDS"
elif command -v gtimeout >/dev/null 2>&1; then
  TMO="gtimeout $TMO_SECONDS"
fi

OUT=$($TMO gh release view "v$VERSION" --repo "$REPO" --json tagName 2>&1)
RC=$?

if [ "$RC" -eq 0 ]; then
  echo "❌ v$VERSION is already published to $REPO."
  echo "   Publishing again would clobber that release's tarball, and the deploy state"
  echo "   skips a version whose directory already exists — so the deploy would report"
  echo "   success and leave the previous code serving."
  echo ""
  echo "   Do this:   make bump-version BUMP=patch     # then commit, then push"
  echo "   Or, if you mean to re-cut v$VERSION on purpose:   HOTFIX=1 make push"
  exit 1
fi

# gh says exactly "release not found" for a tag with no release. A repository
# that cannot be resolved, an expired token, or a timeout lands in the branch
# below instead: unanswered, which is not the same as "not published".
if printf '%s' "$OUT" | grep -qE 'release not found|HTTP 404|Not Found'; then
  echo "✓ v$VERSION is not published yet"
  exit 0
fi

echo "⚠️  could not ask GitHub whether v$VERSION is already published (rc=$RC):"
echo "    $(printf '%s' "$OUT" | head -1)"
echo "    Continuing. If the version was not bumped, the deploy will report success"
echo "    without changing anything — read the version in the deploy output."
exit 0
