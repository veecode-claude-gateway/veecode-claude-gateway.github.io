# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

The org-default GitHub Pages site at `https://veecode-claude-gateway.github.io/`. It hosts four
files that pilots curl/iwr at install time. It is intentionally separate from the gateway runtime
repos (`claude-gateway-parent`, `litellm-gateway`) because those are private and the org's GitHub
plan does not include Pages on private repos. Bare-prefix Pages URLs (no nested path) are also
required by the install one-liners.

This repo carries **no secrets, no runtime config, no per-deployment values** beyond the default
gateway URL placeholder. Anything heavier belongs in the private meta-repo.

## Source-of-truth files

There is no build step. Edit, commit, push to `main`, Pages publishes within ~1 minute.

| File          | Role                                                            |
|---------------|-----------------------------------------------------------------|
| `claude`      | POSIX wrapper template (macOS/Linux). `@@`-delimited placeholders. |
| `claude.ps1`  | PowerShell wrapper template (Windows). Same placeholders.       |
| `install.sh`  | macOS/Linux installer — fetches the template, substitutes, drops it on PATH. |
| `install.ps1` | Windows installer — same flow, plus a `claude.cmd` shim and user-PATH edit. |
| `index.html`  | Public landing page with prerequisites, install one-liners, troubleshooting. |
| `README.md`   | Repo-internal note (not served as the landing page).            |

## Architecture: how the wrapper works

The wrapper shadows the real `claude` binary on PATH and forwards arguments after attaching gateway
auth. The flow on every invocation:

1. Read cached virtual key from `~/.config/claude-gateway/key` (Linux/macOS) or
   `%LOCALAPPDATA%\claude-gateway\key` (Windows). File format is two lines: key, then ISO8601
   `expires_at`. Mode 0600 on POSIX.
2. If missing or expiring within 1h, call `gcloud auth print-access-token` and POST it to
   `$GATEWAY_URL/issue-key`. The response (`{key, expires_at}`) is parsed inline — the POSIX
   wrapper deliberately avoids a `jq` dependency (`claude:57-58`).
3. Export `ANTHROPIC_BASE_URL`, `ANTHROPIC_API_KEY`, `CLAUDE_CONFIG_DIR`,
   `ANTHROPIC_DEFAULT_HEADERS` (carries `x-claude-gateway-cli: <version>` for server-side
   attribution), then `exec` (POSIX) / `&` (PowerShell) the real binary.

The wrappers stay under ~50 lines per platform on purpose. Design notes live in
`claude-gateway-parent` at `roadmap/milestones/M2/task-09-developer-wrapper-script.md`. Don't grow
them with features unless that doc is updated.

### Error-classification invariant

The wrappers split three error states that look the same to a user but mean different things:

- **Network/DNS/TLS failure** ("could not reach gateway") — `curl` non-zero exit, or PowerShell
  exception with `null` `Response`.
- **Identity rejected** (401/403) — token expired or unauthorized; tells the user to re-run
  `gcloud auth login`.
- **Gateway error** (5xx) — points at the runbook.

This split is load-bearing: an earlier version conflated them and pilots chased imaginary VPN
issues. See `claude:40-55` and `claude.ps1:38-62`. Preserve the split when editing.

## Architecture: how the installer works

Both installers follow the same five-step flow:

1. **Locate the real `claude`** by walking `PATH` and skipping (a) its own install path and
   (b) any file whose first 5 lines contain the marker `VeeCode Claude Gateway wrapper`. This is
   how re-running the installer upgrades in place without targeting itself.
2. **Get the wrapper template** — prefer a sibling file (`claude` or `claude.ps1` next to the
   installer), fall back to fetching from the Pages URL. The sibling-file path is what makes
   running `./install.sh` from a repo checkout test your local edits.
3. **Substitute** `@@GATEWAY_URL@@`, `@@REAL_CLAUDE@@`, `@@WRAPPER_VERSION@@`. Windows uses plain
   `String.Replace`, not `-replace`, because regex chews on backslashes in Windows paths
   (`install.ps1:40-45`).
4. **Install** to `~/.claude-gateway/bin/claude` (POSIX) or `%LOCALAPPDATA%\claude-gateway\bin\`
   with a `claude.cmd` shim (Windows). No sudo / no admin.
5. **Wire PATH** — POSIX appends an idempotent block (delimited by `# >>> veecode-claude-gateway >>>`
   markers) to `~/.zshrc`/`~/.bashrc`/`~/.bash_profile`, falling back to `~/.profile`. Windows
   prepends to the user `Path` env var via `[Environment]::SetEnvironmentVariable`.

Installer env-var overrides (honored by both platforms): `CLAUDE_GATEWAY_URL`,
`CLAUDE_GATEWAY_VERSION`, `CLAUDE_GATEWAY_INSTALL_DIR`, `CLAUDE_GATEWAY_WRAPPER_URL`. Default
gateway is `https://claude-gateway.vee.codes`.

## Local testing

There are no unit tests and no CI. To exercise changes:

```bash
# Local install run — picks up your edited `claude` template via the sibling-file path
# in install.sh:37-42, so you can iterate without pushing to Pages.
./install.sh

# Override gateway endpoint for testing
CLAUDE_GATEWAY_URL=https://staging-gateway.example ./install.sh

# Render index.html locally
python3 -m http.server 8000   # then open http://localhost:8000
```

For the Windows installer, equivalent: run `.\install.ps1` from a checkout in PowerShell 7+; the
sibling-file path at `install.ps1:32-38` mirrors the POSIX behavior.

## Conventions specific to this repo

- BSD vs GNU `date` — the POSIX wrapper deliberately tries both flag styles for ISO8601 parsing
  (`claude:28-30`). Don't simplify to one.
- `printf` over `echo`, `sed` over `awk` for the JSON-extract one-liners — keeps the wrapper
  dependency surface to coreutils only (no `jq`, no Python).
- The installer must remain idempotent: re-running upgrades the wrapper, never duplicates the
  PATH block (`grep -qF` guard at `install.sh:60`), and never targets itself as the "real"
  binary.
- Don't add a build step or a package.json. The whole point of this repo is that it's static
  files served raw.
