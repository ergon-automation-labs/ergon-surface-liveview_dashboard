#!/bin/bash
# Create a new LiveView web surface from this template.
# Usage: ./setup_new_surface.sh <app_snake_name> [app_pascal_name]
# Example: ./setup_new_surface.sh terrain_liveview TerrainLiveview
#
# Prompts for HTTP port (non-conflicting), checks it's free, then generates
# the app with port baked in and a Jenkinsfile for deploy (same pattern as bots).
#
# Output: ../<app_snake_name>/ with OTP app, module names, port, and Jenkinsfile set.

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

error() { echo -e "${RED}Error: $1${NC}" >&2; exit 1; }
success() { echo -e "${GREEN}$1${NC}"; }
info() { echo -e "${YELLOW}$1${NC}"; }

# Check if a port is free (nothing listening).
port_is_free() {
  local port=$1
  if command -v nc &>/dev/null; then
    ! nc -z 127.0.0.1 "$port" 2>/dev/null
  elif command -v lsof &>/dev/null; then
    ! lsof -i ":$port" 2>/dev/null | grep -q LISTEN
  else
    # Can't check; assume free
    return 0
  fi
}

if [ $# -lt 1 ]; then
  echo "Usage: $0 <app_snake_name> [app_pascal_name]"
  echo ""
  echo "  app_snake_name  - OTP app name in snake_case (e.g. terrain_liveview)"
  echo "  app_pascal_name - Module name in PascalCase (default: derived from snake)"
  echo ""
  echo "Example: $0 terrain_liveview TerrainLiveview"
  exit 1
fi

APP_SNAKE="$1"
# PascalCase: optional second arg, or derive from snake_case (e.g. terrain_liveview -> TerrainLiveview)
APP_PASCAL="${2:-$(echo "$APP_SNAKE" | awk -F_ '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) substr($i,2)}1' OFS='')}"

# ---- Port prompt ----
echo ""
info "HTTP port for this surface (used by Phoenix and by Jenkins deploy)."
read -r -p "Port [4000]: " PORT_IN
SURFACE_PORT="${PORT_IN:-4000}"

# Validate numeric and range
if ! [[ "$SURFACE_PORT" =~ ^[0-9]+$ ]]; then
  error "Port must be a number (got: $SURFACE_PORT)"
fi
if [ "$SURFACE_PORT" -lt 1 ] || [ "$SURFACE_PORT" -gt 65535 ]; then
  error "Port must be between 1 and 65535 (got: $SURFACE_PORT)"
fi

# Check port is free
if ! port_is_free "$SURFACE_PORT"; then
  error "Port $SURFACE_PORT is already in use. Choose another or free the port."
fi
# Optional: warn if port is in registry (another surface may use it)
PORT_REGISTRY="$(dirname "$TEMPLATE_DIR")/port_registry.txt"
if [ -f "$PORT_REGISTRY" ] && grep -q "^[^:]*:${SURFACE_PORT}$" "$PORT_REGISTRY" 2>/dev/null; then
  info "Warning: port $SURFACE_PORT is listed in port_registry.txt (another surface may use it)."
  read -r -p "Use it anyway? [y/N]: " USE_ANYWAY
  case "${USE_ANYWAY:-n}" in
    [yY]|[yY][eE][sS]) ;;
    *) error "Choose a different port." ;;
  esac
fi
success "Port $SURFACE_PORT will be used for this surface."
echo ""

TEMPLATE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="$(dirname "$TEMPLATE_DIR")/$APP_SNAKE"
OLD_SNAKE="surface_liveview_template"
OLD_PASCAL="SurfaceLiveviewTemplate"

if [ -d "$TARGET_DIR" ]; then
  error "Target already exists: $TARGET_DIR"
fi

info "Creating $APP_SNAKE from LiveView template..."
cp -R "$TEMPLATE_DIR" "$TARGET_DIR"
success "Copied to $TARGET_DIR"

rm -f "$TARGET_DIR/setup_new_surface.sh"
rm -rf "$TARGET_DIR/_build" "$TARGET_DIR/deps" 2>/dev/null || true
# Do not remove .git if present (e.g. re-running); we will git init if missing

# Replace app/module names in all Elixir, config, markdown, Makefile, Jenkinsfile, Dockerfile, docker-compose
find "$TARGET_DIR" -type f \( -name "*.ex" -o -name "*.exs" -o -name "*.md" -o -name "Makefile" -o -name "Jenkinsfile" -o -name "Dockerfile" -o -name "docker-compose.yml" -o -name "*.conf*" \) -print0 | while IFS= read -r -d '' f; do
  if sed --version 2>/dev/null | grep -q GNU; then
    sed -i "s|$OLD_PASCAL|$APP_PASCAL|g" "$f"
    sed -i "s|$OLD_SNAKE|$APP_SNAKE|g" "$f"
  else
    sed -i '' "s|$OLD_PASCAL|$APP_PASCAL|g" "$f"
    sed -i '' "s|$OLD_SNAKE|$APP_SNAKE|g" "$f"
  fi
done

# Replace default port in config and env var name
CONFIG_EXS="$TARGET_DIR/config/config.exs"
PORT_ENV_NAME="$(echo "$APP_SNAKE" | tr 'a-z' 'A-Z' | tr '-' '_')_PORT"
if [ -f "$CONFIG_EXS" ]; then
  if sed --version 2>/dev/null | grep -q GNU; then
    sed -i "s/4000/$SURFACE_PORT/g" "$CONFIG_EXS"
    sed -i "s/SURFACE_LIVEVIEW_PORT/$PORT_ENV_NAME/g" "$CONFIG_EXS"
  else
    sed -i '' "s/4000/$SURFACE_PORT/g" "$CONFIG_EXS"
    sed -i '' "s/SURFACE_LIVEVIEW_PORT/$PORT_ENV_NAME/g" "$CONFIG_EXS"
  fi
  success "Config set to port $SURFACE_PORT (override with ${PORT_ENV_NAME})"
fi

# Replace Jenkinsfile placeholders
JENKINSFILE="$TARGET_DIR/Jenkinsfile"
if [ -f "$JENKINSFILE" ]; then
  # __SURFACE_NAME__ -> app_snake_name, __SURFACE_PORT__ -> port, __GITHUB_REPO_SUFFIX__ -> repo (kebab, no leading/trailing -)
  GITHUB_REPO_SUFFIX="$(echo "${APP_SNAKE//_/-}" | sed 's/^-*//;s/-*$//')"
  [ -z "$GITHUB_REPO_SUFFIX" ] && GITHUB_REPO_SUFFIX="$APP_SNAKE"
  for placeholder in __SURFACE_NAME__ __SURFACE_PORT__ __GITHUB_REPO_SUFFIX__; do
    case "$placeholder" in
      __SURFACE_NAME__)     value="$APP_SNAKE" ;;
      __SURFACE_PORT__)     value="$SURFACE_PORT" ;;
      __GITHUB_REPO_SUFFIX__) value="$GITHUB_REPO_SUFFIX" ;;
      *) value="" ;;
    esac
    [ -z "$value" ] && continue
    if sed --version 2>/dev/null | grep -q GNU; then
      sed -i "s|$placeholder|$value|g" "$JENKINSFILE"
    else
      sed -i '' "s|$placeholder|$value|g" "$JENKINSFILE"
    fi
  done
  success "Jenkinsfile set (SURFACE_NAME=$APP_SNAKE, PORT=$SURFACE_PORT, GITHUB_REPO=$GITHUB_REPO_SUFFIX)"
fi

# Rename lib/surface_liveview_template -> lib/<app_snake>
if [ -d "$TARGET_DIR/lib/$OLD_SNAKE" ]; then
  mv "$TARGET_DIR/lib/$OLD_SNAKE" "$TARGET_DIR/lib/$APP_SNAKE"
  success "Renamed lib/$OLD_SNAKE -> lib/$APP_SNAKE"
fi

# Append to port registry so future setup runs can warn on conflicts
if [ -n "$SURFACE_PORT" ]; then
  echo "${APP_SNAKE}:${SURFACE_PORT}" >> "$PORT_REGISTRY" 2>/dev/null || true
fi

# Replace placeholders in git-hooks/pre-push (same as Jenkinsfile, minus PORT)
PREPUSH="$TARGET_DIR/git-hooks/pre-push"
if [ -f "$PREPUSH" ]; then
  GITHUB_REPO_SUFFIX_HOOK="$(echo "${APP_SNAKE//_/-}" | sed 's/^-*//;s/-*$//')"
  [ -z "$GITHUB_REPO_SUFFIX_HOOK" ] && GITHUB_REPO_SUFFIX_HOOK="$APP_SNAKE"
  for placeholder in __SURFACE_NAME__ __GITHUB_REPO_SUFFIX__; do
    case "$placeholder" in
      __SURFACE_NAME__) value="$APP_SNAKE" ;;
      __GITHUB_REPO_SUFFIX__) value="$GITHUB_REPO_SUFFIX_HOOK" ;;
      *) value="" ;;
    esac
    [ -z "$value" ] && continue
    if sed --version 2>/dev/null | grep -q GNU; then
      sed -i "s|$placeholder|$value|g" "$PREPUSH"
    else
      sed -i '' "s|$placeholder|$value|g" "$PREPUSH"
    fi
  done
  chmod +x "$PREPUSH"
  success "git-hooks/pre-push configured and executable"
fi

# Initialize as its own git repo and configure githooks (surfaces are separate repos for Jenkins)
if [ ! -d "$TARGET_DIR/.git" ]; then
  (cd "$TARGET_DIR" && git init)
  success "Initialized git repo in $TARGET_DIR"
fi
(cd "$TARGET_DIR" && git config core.hooksPath git-hooks)
success "Git hooks path set (core.hooksPath = git-hooks)"

success "Done."
echo ""
echo "Next steps:"
echo "  cd $TARGET_DIR"
echo "  make setup          # deps + confirm githooks"
echo "  git remote add origin git@github.com:ergon-automation-labs/${GITHUB_REPO_SUFFIX}.git   # or your repo URL"
echo "  Add LiveView client (assets) and your routes/LiveViews (see README)."
echo "  git add . && git commit -m 'Initial surface' && git push -u origin main"
echo "  (Pushing to main runs pre-push: build release, publish to GitHub; Jenkins then deploys.)"
echo ""
