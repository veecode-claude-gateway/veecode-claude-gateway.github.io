#!/usr/bin/env bash
# VeeCode Claude Gateway — installer for the `claude` wrapper (macOS / Linux).
# Per-user install, no sudo. Re-running upgrades the wrapper in place.
#
# The wrapper resolves its config (gateway URL) and the real `claude`
# binary at runtime, so this installer does no templating: it downloads
# the script verbatim, writes a small config file, and prepends the
# install dir to PATH. What Pages serves is exactly what runs.
set -euo pipefail

GATEWAY_URL="${CLAUDE_GATEWAY_URL:-https://claude-gateway.vee.codes}"
INSTALL_DIR="${CLAUDE_GATEWAY_INSTALL_DIR:-$HOME/.claude-gateway/bin}"
INSTALL_PATH="$INSTALL_DIR/claude"
WRAPPER_URL="${CLAUDE_GATEWAY_WRAPPER_URL:-https://veecode-claude-gateway.github.io/claude}"

PATH_BLOCK_BEGIN='# >>> veecode-claude-gateway >>>'
PATH_BLOCK_END='# <<< veecode-claude-gateway <<<'

die() { printf 'install: %s\n' "$*" >&2; exit 1; }
log() { printf 'install: %s\n' "$*"; }

# 1) Sanity-check that a real `claude` exists on PATH (the wrapper will
# locate it at runtime; failing fast here is friendlier than waiting
# for the first invocation to error). Skip our own install path and any
# existing wrapper (identified by a header marker).
real_claude=""
IFS=':' read -ra parts <<<"$PATH"
for d in "${parts[@]}"; do
  candidate="$d/claude"
  if [ -x "$candidate" ] && [ "$candidate" != "$INSTALL_PATH" ]; then
    if head -n 5 "$candidate" 2>/dev/null | grep -q 'VeeCode Claude Gateway wrapper'; then
      continue
    fi
    real_claude="$candidate"
    break
  fi
done
[ -n "$real_claude" ] || die "couldn't find real 'claude' on PATH. Install Claude Code first: https://docs.claude.com/en/docs/claude-code"
log "real claude binary: $real_claude"

# 2) Fetch the wrapper. Prefer a sibling file alongside this installer
# (so a repo checkout exercises local edits); fall back to Pages.
script_dir=$(cd "$(dirname "$0")" 2>/dev/null && pwd || true)
mkdir -p "$INSTALL_DIR"
if [ -n "${script_dir:-}" ] && [ -f "$script_dir/claude" ]; then
  cp "$script_dir/claude" "$INSTALL_PATH"
else
  curl -fsSL "$WRAPPER_URL" -o "$INSTALL_PATH" \
    || die "could not download wrapper from $WRAPPER_URL"
fi
chmod 755 "$INSTALL_PATH"
log "installed wrapper to $INSTALL_PATH"

# 3) Write the config file the wrapper sources at startup. Owner-managed
# afterward — edit to override the gateway URL without re-installing.
gw_state_dir="${XDG_CONFIG_HOME:-$HOME/.config}/claude-gateway"
mkdir -p "$gw_state_dir"
umask 077
printf 'GATEWAY_URL="%s"\n' "$GATEWAY_URL" > "$gw_state_dir/config"
chmod 600 "$gw_state_dir/config"
log "wrote config $gw_state_dir/config (GATEWAY_URL=$GATEWAY_URL)"

# Seed last_check so the freshly-installed wrapper waits a full cadence
# (24h) before its first self-update check. Without this, the wrapper's
# very first invocation would run a no-op update against identical
# content (harmless but wasteful + noisy in the banner).
date -u +%s > "$gw_state_dir/last_check"

# 4) Wire $INSTALL_DIR onto PATH in the user's shell rc files (idempotent).
ensure_path_block() {
  local rc="$1"
  [ -f "$rc" ] || return 0
  if grep -qF "$PATH_BLOCK_BEGIN" "$rc" 2>/dev/null; then
    return 0
  fi
  {
    printf '\n%s\n' "$PATH_BLOCK_BEGIN"
    printf '# Routes the `claude` CLI through the corporate gateway.\n'
    printf 'export PATH="%s:$PATH"\n' "$INSTALL_DIR"
    printf '%s\n' "$PATH_BLOCK_END"
  } >> "$rc"
  log "appended PATH-prepend block to $rc"
}

touched_rc=0
for rc in "$HOME/.zshrc" "$HOME/.bashrc" "$HOME/.bash_profile"; do
  if [ -f "$rc" ]; then
    ensure_path_block "$rc"
    touched_rc=1
  fi
done
if [ "$touched_rc" -eq 0 ]; then
  ensure_path_block "$HOME/.profile" || true
  touch "$HOME/.profile"
  ensure_path_block "$HOME/.profile"
fi

case ":$PATH:" in
  *":$INSTALL_DIR:"*) : ;;
  *) export PATH="$INSTALL_DIR:$PATH" ;;
esac

# 5) Verify by absolute path (does not depend on the rc edit being sourced).
mkdir -p "$gw_state_dir/claude"
if "$INSTALL_PATH" --version >/dev/null 2>&1; then
  log "verify ok: '$INSTALL_PATH --version' returned 0"
else
  log "warning: '$INSTALL_PATH --version' did not return 0"
  log "  most often this means 'gcloud auth login' has not been run yet — run it and try again"
  log "  override the gateway with: export CLAUDE_GATEWAY_URL=<url> (default: $GATEWAY_URL)"
fi

log "done. Open a new shell (or 'exec \$SHELL') so the PATH change takes effect, then run 'claude'."
