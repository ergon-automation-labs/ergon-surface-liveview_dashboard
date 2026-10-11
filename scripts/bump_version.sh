#!/bin/bash
# bump_version.sh - Increment version in mix.exs
# Usage: ./scripts/bump_version.sh <path-to-mix.exs> <major|minor|patch>

set -e

MIX_FILE="$1"
BUMP_TYPE="${2:-minor}"

if [ -z "$MIX_FILE" ] || [ ! -f "$MIX_FILE" ]; then
  echo "Error: mix.exs not found: $MIX_FILE"
  exit 1
fi

if ! [[ "$BUMP_TYPE" =~ ^(major|minor|patch)$ ]]; then
  echo "Error: BUMP_TYPE must be major, minor, or patch"
  exit 1
fi

# Extract current version
CURRENT=$(grep 'version:' "$MIX_FILE" | head -1 | sed -E 's/.*version: "([^"]+)".*/\1/')

if [ -z "$CURRENT" ]; then
  echo "Error: Could not parse version from $MIX_FILE"
  exit 1
fi

# Parse version components
IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT"
PATCH=${PATCH%%[^0-9]*}  # Remove any non-numeric suffix

# Calculate new version
case "$BUMP_TYPE" in
  major)
    MAJOR=$((MAJOR + 1))
    MINOR=0
    PATCH=0
    ;;
  minor)
    MINOR=$((MINOR + 1))
    PATCH=0
    ;;
  patch)
    PATCH=$((PATCH + 1))
    ;;
esac

NEW_VERSION="$MAJOR.$MINOR.$PATCH"

# Update mix.exs
sed -i '' "s/version: \"$CURRENT\"/version: \"$NEW_VERSION\"/" "$MIX_FILE"

# Output for caller
echo "$NEW_VERSION"
