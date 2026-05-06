# veecode-claude-gateway.github.io

Public landing page and developer install assets for the **VeeCode Claude Gateway**.

This is the org-default GitHub Pages site (`https://veecode-claude-gateway.github.io/`). It exists separately from the gateway runtime repos because those are private and the org's GitHub plan does not include Pages on private repos. Putting the assets here also gives bare-prefix URLs without nested paths.

## Contents

| File | Purpose |
|------|---------|
| `claude` | POSIX wrapper template — substituted at install time. |
| `claude.ps1` | PowerShell wrapper template (Windows). |
| `install.sh` | macOS / Linux installer one-liner target. |
| `install.ps1` | Windows installer one-liner target. |
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

## Where docs and source live

- **Architecture, ADRs, runbooks, roadmap** → [`claude-gateway-parent`](https://github.com/veecode-claude-gateway/claude-gateway-parent) (private)
- **Gateway image source** → [`litellm-gateway`](https://github.com/veecode-claude-gateway/litellm-gateway) (private)
- **Developer onboarding doc** → meta-repo `docs/developer-setup.md`

## Updating the wrappers

These four files are the **source of truth**. Edit, commit, push to `main` — Pages publishes within ~1 minute. Keep this repo small and minimal: it should never carry secrets, runtime config, or anything specific to a single deployment beyond the gateway URL placeholder that `install.sh` substitutes in.

The wrapper logic deliberately stays under ~50 lines per platform; see meta-repo `roadmap/milestones/M2/task-09-developer-wrapper-script.md` for the design notes.
