# Fly.io Deployment

The octopus app was previously deployed continuously to Fly.io at
https://polychrome.fly.dev. Auto-deploy is currently **disabled** — the GitHub
Actions push trigger has been removed so pushes to `main` no longer trigger a
Fly deployment automatically.

## Reactivating auto-deploy

In `.github/workflows/fly.yml`, restore the `push` trigger:

```yaml
on:
  push:
    branches:
      - main
    paths:
      - octopus/**
  workflow_dispatch:
```

## Manual deploy

From the `octopus/` directory:

```bash
make deploy-fly
# equivalent: fly deploy --config deploy/fly/fly.toml
```

Or trigger the GitHub Actions workflow manually via the GitHub UI
(Actions → "Fly Deploy" → "Run workflow").

## Prerequisites

- `flyctl` installed and authenticated (`fly auth login`)
- `FLY_API_TOKEN` secret set in GitHub repository settings (for CI)
- Fly volume `octopus_data` must exist (`fly volumes list`)
- Runtime secrets set on the Fly app (`fly secrets list`):
  - `SECRET_KEY_BASE`
  - Optionally: `TELEGRAM_BOT_SECRET`

## Configuration

`fly.toml` in this directory holds all Fly-specific settings:
- App name: `polychrome`, region: `ams`
- HTTP on port 8080 with forced HTTPS
- UDP ports 2342 (frame relay) and 8000 (OSC) exposed
- Persistent volume mounted at `/data`
