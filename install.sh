#!/usr/bin/env bash
# VeeCode Claude Gateway — installer for the `claude` wrapper (macOS / Linux).
# Idempotent: re-running upgrades the wrapper in place. See
# https://github.com/veecode-claude-gateway/claude-gateway-parent/blob/main/docs/developer-setup.md
set -euo pipefail

GATEWAY_URL="${CLAUDE_GATEWAY_URL:-https://gateway.example.com}"
WRAPPER_VERSION="${CLAUDE_GATEWAY_VERSION:-dev}"
INSTALL_PATH="${CLAUDE_GATEWAY_INSTALL_PATH:-/usr/local/bin/claude}"
WRAPPER_URL="${CLAUDE_GATEWAY_WRAPPER_URL:-https://veecode-claude-gateway.github.io/claude}"

die() { printf 'install: %s\n' "$*" >&2; exit 1; }
log() { printf 'install: %s\n' "$*"; }

# 1) Locate the real `claude` binary, ignoring any wrapper we've previously installed.
real_claude=""
IFS=':' read -ra parts <<<"$PATH"
for d in "${parts[@]}"; do
  candidate="$d/claude"
  if [ -x "$candidate" ] && [ "$candidate" != "$INSTALL_PATH" ]; then
    # Skip a previously-installed wrapper (identified by its placeholder marker).
    if head -n 5 "$candidate" 2>/dev/null | grep -q 'VeeCode Claude Gateway wrapper'; then
      continue
    fi
    real_claude="$candidate"
    break
  fi
done
[ -n "$real_claude" ] || die "couldn't find real 'claude' on PATH. Install Claude Code first: https://docs.claude.com/en/docs/claude-code"
log "real claude binary: $real_claude"

# 2) Fetch the wrapper template (or use a local copy if present alongside this script).
script_dir=$(cd "$(dirname "$0")" 2>/dev/null && pwd || true)
if [ -n "${script_dir:-}" ] && [ -f "$script_dir/claude" ]; then
  template=$(cat "$script_dir/claude")
else
  template=$(curl -fsSL "$WRAPPER_URL") || die "could not download wrapper from $WRAPPER_URL"
fi

# 3) Substitute placeholders.
rendered=$(printf '%s' "$template" \
  | sed "s|@@GATEWAY_URL@@|$GATEWAY_URL|g" \
  | sed "s|@@REAL_CLAUDE@@|$real_claude|g" \
  | sed "s|@@WRAPPER_VERSION@@|$WRAPPER_VERSION|g")

# 4) Install (sudo if the target dir isn't writable).
target_dir=$(dirname "$INSTALL_PATH")
if [ -w "$target_dir" ]; then
  printf '%s' "$rendered" > "$INSTALL_PATH"
  chmod 755 "$INSTALL_PATH"
else
  log "writing $INSTALL_PATH (sudo required)"
  printf '%s' "$rendered" | sudo tee "$INSTALL_PATH" >/dev/null
  sudo chmod 755 "$INSTALL_PATH"
fi
log "installed wrapper to $INSTALL_PATH"

# 5) Verify.
mkdir -p "${XDG_CONFIG_HOME:-$HOME/.config}/claude-gateway"
if "$INSTALL_PATH" --version >/dev/null 2>&1; then
  log "verify ok: 'claude --version' returned 0"
else
  die "verify failed: '$INSTALL_PATH --version' did not exit 0"
fi
log "done. Run 'claude' to start a gateway-routed session."
