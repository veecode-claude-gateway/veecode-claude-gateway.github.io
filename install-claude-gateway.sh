#!/usr/bin/env bash
# VeeCode Claude Gateway — installer for the `claude-gateway` repo-owner CLI
# (macOS / Linux). Per-user install, no sudo. Re-running upgrades in place.
# Coexists with the `claude` wrapper installer at install.sh — the two
# share `~/.claude-gateway/bin` and the same PATH-prepend block.
# See M2/task-14 in claude-gateway-parent.
set -euo pipefail

GATEWAY_URL="${CLAUDE_GATEWAY_URL:-https://claude-gateway.vee.codes}"
CLI_VERSION="${CLAUDE_GATEWAY_CLI_VERSION:-dev}"
INSTALL_DIR="${CLAUDE_GATEWAY_INSTALL_DIR:-$HOME/.claude-gateway/bin}"
INSTALL_PATH="$INSTALL_DIR/claude-gateway"
TEMPLATE_URL="${CLAUDE_GATEWAY_CLI_URL:-https://veecode-claude-gateway.github.io/claude-gateway}"

PATH_BLOCK_BEGIN='# >>> veecode-claude-gateway >>>'
PATH_BLOCK_END='# <<< veecode-claude-gateway <<<'

die() { printf 'install-claude-gateway: %s\n' "$*" >&2; exit 1; }
log() { printf 'install-claude-gateway: %s\n' "$*"; }

# 1) Fetch the CLI template (or use a sibling copy if present alongside this
# installer). Sibling-file path is what makes a local checkout iterable.
script_dir=$(cd "$(dirname "$0")" 2>/dev/null && pwd || true)
if [ -n "${script_dir:-}" ] && [ -f "$script_dir/claude-gateway" ]; then
  template=$(cat "$script_dir/claude-gateway")
else
  template=$(curl -fsSL "$TEMPLATE_URL") || die "could not download CLI from $TEMPLATE_URL"
fi

# 2) Substitute placeholders. Same scheme as install.sh.
rendered=$(printf '%s' "$template" \
  | sed "s|@@GATEWAY_URL@@|$GATEWAY_URL|g" \
  | sed "s|@@CLI_VERSION@@|$CLI_VERSION|g")

# 3) Install — per-user, no sudo.
mkdir -p "$INSTALL_DIR"
printf '%s' "$rendered" > "$INSTALL_PATH"
chmod 755 "$INSTALL_PATH"
log "installed CLI to $INSTALL_PATH"

# 4) Wire $INSTALL_DIR onto PATH (idempotent — same block markers as
# install.sh, so re-running either installer is a no-op for PATH).
ensure_path_block() {
  local rc="$1"
  [ -f "$rc" ] || return 0
  if grep -qF "$PATH_BLOCK_BEGIN" "$rc" 2>/dev/null; then
    return 0
  fi
  {
    printf '\n%s\n' "$PATH_BLOCK_BEGIN"
    printf '# Routes the `claude` CLI through the corporate gateway,\n'
    printf '# and exposes `claude-gateway` for repo-owner CI key management.\n'
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

# 5) Smoke test — `--version` doesn't require gcloud or network.
if "$INSTALL_PATH" --version >/dev/null 2>&1; then
  log "verify ok: '$INSTALL_PATH --version' returned 0"
else
  log "warning: '$INSTALL_PATH --version' did not return 0"
fi

log "done. Open a new shell (or 'exec \$SHELL') so PATH picks up the CLI, then run 'claude-gateway --help'."
