#!/usr/bin/env bash
# VeeCode Claude Gateway — installer for the `claude` wrapper (macOS / Linux).
# Per-user install, no sudo. Re-running upgrades the wrapper in place. See
# https://github.com/veecode-claude-gateway/claude-gateway-parent/blob/main/docs/developer-setup.md
set -euo pipefail

GATEWAY_URL="${CLAUDE_GATEWAY_URL:-https://claude-gateway.vee.codes}"
WRAPPER_VERSION="${CLAUDE_GATEWAY_VERSION:-dev}"
INSTALL_DIR="${CLAUDE_GATEWAY_INSTALL_DIR:-$HOME/.claude-gateway/bin}"
INSTALL_PATH="$INSTALL_DIR/claude"
WRAPPER_URL="${CLAUDE_GATEWAY_WRAPPER_URL:-https://veecode-claude-gateway.github.io/claude}"

PATH_BLOCK_BEGIN='# >>> veecode-claude-gateway >>>'
PATH_BLOCK_END='# <<< veecode-claude-gateway <<<'

die() { printf 'install: %s\n' "$*" >&2; exit 1; }
log() { printf 'install: %s\n' "$*"; }

# 1) Locate the real `claude` binary, ignoring our own install path and any
# previously-installed wrapper (identified by a marker in its header comment).
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

# 4) Install — per-user, no sudo.
mkdir -p "$INSTALL_DIR"
printf '%s' "$rendered" > "$INSTALL_PATH"
chmod 755 "$INSTALL_PATH"
log "installed wrapper to $INSTALL_PATH"

# 5) Wire $INSTALL_DIR onto PATH in the user's shell rc files (idempotent).
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
  # No rc found; create ~/.profile so login shells pick it up.
  ensure_path_block "$HOME/.profile" || true
  touch "$HOME/.profile"
  ensure_path_block "$HOME/.profile"
fi

# Make $INSTALL_DIR visible to this same shell so the verify step finds it.
case ":$PATH:" in
  *":$INSTALL_DIR:"*) : ;;
  *) export PATH="$INSTALL_DIR:$PATH" ;;
esac

# 6) Seed self-update state so the freshly-installed wrapper doesn't
# trigger an immediate update check on first invocation. The wrapper
# fetches the template from the same Pages URL we just installed from
# and compares the SHA-256 — by recording that hash here, a fresh
# install starts the 24h cadence from `now`. Best-effort: if shasum
# isn't available, the wrapper's first run will simply self-update with
# identical content, which is harmless. (M2 self-update spec.)
gw_state_dir="${XDG_CONFIG_HOME:-$HOME/.config}/claude-gateway"
mkdir -p "$gw_state_dir"
if command -v shasum >/dev/null 2>&1; then
  printf '%s' "$template" | shasum -a 256 | cut -d' ' -f1 > "$gw_state_dir/template_hash"
elif command -v sha256sum >/dev/null 2>&1; then
  printf '%s' "$template" | sha256sum | cut -d' ' -f1 > "$gw_state_dir/template_hash"
fi
date -u +%s > "$gw_state_dir/last_check"

# 7) Verify by absolute path (does not depend on the rc edit being sourced).
if "$INSTALL_PATH" --version >/dev/null 2>&1; then
  log "verify ok: '$INSTALL_PATH --version' returned 0"
else
  log "warning: '$INSTALL_PATH --version' did not return 0"
  log "  most often this means 'gcloud auth login' has not been run yet — run it and try again"
  log "  override the gateway with: export CLAUDE_GATEWAY_URL=<url> (default: $GATEWAY_URL)"
fi

log "done. Open a new shell (or 'exec \$SHELL') so the PATH change takes effect, then run 'claude'."
