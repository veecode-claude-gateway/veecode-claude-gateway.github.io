# veecode-claude-gateway.github.io

Public landing page and developer install assets for the **VeeCode Claude Gateway**.

This is the org-default GitHub Pages site (`https://veecode-claude-gateway.github.io/`). It exists separately from the gateway runtime repos because those are private and the org's GitHub plan does not include Pages on private repos. Putting the assets here also gives bare-prefix URLs without nested paths.

## Contents

| File | Purpose |
|------|---------|
| `claude` | POSIX wrapper template — substituted at install time. |
| `claude.ps1` | PowerShell wrapper template (Windows). |
| `install.sh` | macOS / Linux installer one-liner target. Per-user install, no sudo. |
| `install.ps1` | Windows installer one-liner target. Per-user install, no admin. |
| `index.html` | Public landing page. |

## Install

```bash
# macOS / Linux
curl -fsSL https://veecode-claude-gateway.github.io/install.sh | bash
```

```powershell
# Windows PowerShell 7+
iwr https://veecode-claude-gateway.github.io/install.ps1 | iex
```

Both honor `CLAUDE_GATEWAY_URL` to override the gateway endpoint at install time.

## Modes

The wrapper picks one auth source per session. Default is OAuth pass-through (cases 2/3); set `CLAUDE_GATEWAY_USE_API_KEY=1` to fall back to the gcloud → virtual-key flow (case 4). Decision logic lives at the top of `claude` / `claude.ps1`. See [ADR-0010](https://github.com/veecode-claude-gateway/claude-gateway-parent/blob/main/adr/0010-team-plan-oauth-passthrough.md) in the meta-repo.

| # | Setup | Auth path | Gateway | LiteLLM telemetry | CLI telemetry |
|---|---|---|---|---|---|
| 1 | **No wrapper.** Real `claude` directly. | Anthropic OAuth → `api.anthropic.com` | ❌ | ❌ | ❌ ¹ |
| 2 | **Wrapper, OAuth already valid.** Default mode. | Anthropic OAuth → gateway → Anthropic | ✅ | ✅ | ✅ |
| 3 | **Wrapper, no OAuth yet.** Default mode. | Claude Code prompts `claude login`; after login → case 2 | ✅ ² | ✅ | ✅ |
| 4 | **Wrapper + `CLAUDE_GATEWAY_USE_API_KEY=1`.** Legacy path; CI when Claude Code is involved. | gcloud → `/issue-key` → virtual key → gateway → upstream API key → Anthropic | ✅ | ✅ | ✅ |
| 5 | **CI workflow with a CI virtual key, no wrapper.** Plain HTTP from a script/SDK. | `Authorization: Bearer sk-…` → gateway → upstream API key → Anthropic | ✅ | ✅ | ❌ ³ |

¹ Unless the user has set `CLAUDE_CODE_ENABLE_TELEMETRY=1` outside our env, in which case the laptop emits CLI telemetry to wherever they configured. Out of scope here.

² During the `claude login` flow itself, Claude Code talks to Anthropic Console (browser/device-code flow), not `ANTHROPIC_BASE_URL`. Login works regardless of gateway state. After login completes, subsequent `/v1/messages` calls follow case 2.

³ No Claude Code process means no `claude_code.*` metrics. CI rows show up only on the LiteLLM-source path, with `user_email=ci:owner/repo` from the CI key's team metadata.

### Identity attribution on the OAuth path

The wrapper sends `x-claude-gateway-user` on every request and the gateway uses it to populate the `user_email` Prometheus label. The wrapper picks the header value in three steps, first match wins:

1. `CLAUDE_GATEWAY_API_USER` if you exported it (usually your email — recommended; this is the only form that matches the server-validated label on the API-key path, so a single user appears as a single row in the dashboards).
2. `$USER` (POSIX) or `%USERNAME%` (Windows). Set by every interactive shell, so most pilots get attributed automatically without any setup — `andre`, `lcastro`, etc.
3. The placeholder `claude-gw-user` if neither is available (non-interactive contexts only).

Trust level is laptop-set, same as `client_version` — the gateway accepts the header on faith. The API-key path remains server-validated and is the source of truth for billing-grade attribution.

## Where docs and source live

- **Architecture, ADRs, runbooks, roadmap** → [`claude-gateway-parent`](https://github.com/veecode-claude-gateway/claude-gateway-parent) (private)
- **Gateway image source** → [`litellm-gateway`](https://github.com/veecode-claude-gateway/litellm-gateway) (private)
- **Developer onboarding doc** → meta-repo `docs/developer-setup.md`

## Updating the wrappers

These four files are the **source of truth**. Edit, commit, push to `main` — Pages publishes within ~1 minute. Keep this repo small and minimal: it should never carry secrets, runtime config, or anything specific to a single deployment beyond the gateway URL placeholder that `install.sh` substitutes in.

The wrapper logic deliberately stays under ~50 lines per platform; see meta-repo `roadmap/milestones/M2/task-09-developer-wrapper-script.md` for the design notes.
