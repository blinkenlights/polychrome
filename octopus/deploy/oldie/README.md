# Oldie Deployment

Deploys the octopus app to `oldie` — a bare-metal host reachable via Tailscale
(`oldie.mule-nunki.ts.net`). The source is rsynced and run as a native Elixir
release managed by systemd.

## Deploy

From the `octopus/` directory:

```bash
make deploy-oldie
```

This runs:
1. `rsync` — syncs the source tree to `/opt/octopus` on the remote host
2. `ssh … sudo systemctl restart octopus.service` — restarts the service

## Prerequisites on the remote host

### Elixir / Erlang / Rust

The release is compiled on the remote host, so it needs:

```bash
# Elixir + Erlang (via asdf or system packages)
asdf install  # if .tool-versions is present

# Rust (for native/octopus_webp)
curl https://sh.rustup.rs -sSf | sh
```

### Environment

Create `/opt/octopus/config/runtime_secrets.exs` (gitignored) or set
environment variables in the systemd unit. Required at runtime:

- `DATABASE_PATH` — path to the SQLite database file (e.g. `/data/octopus.db`)
- `SECRET_KEY_BASE` — generate with `mix phx.gen.secret`
- `PHX_HOST` — public hostname (e.g. `oldie.mule-nunki.ts.net`)
- `PORT` — HTTP port the app binds to (default `4000`)

### Systemd unit

Create `/etc/systemd/system/octopus.service`:

```ini
[Unit]
Description=Octopus
After=network.target

[Service]
Type=exec
User=octopus
WorkingDirectory=/opt/octopus
Environment=MIX_ENV=prod
Environment=DATABASE_PATH=/data/octopus.db
Environment=SECRET_KEY_BASE=<secret>
Environment=PHX_HOST=oldie.mule-nunki.ts.net
Environment=PORT=4000
ExecStartPre=/bin/sh -c 'cd /opt/octopus && MIX_ENV=prod mix deps.get --only prod && mix compile && mix release --overwrite'
ExecStart=/opt/octopus/_build/prod/rel/octopus/bin/server
Restart=on-failure

[Install]
WantedBy=multi-user.target
```

Then enable and start:

```bash
sudo systemctl daemon-reload
sudo systemctl enable octopus
sudo systemctl start octopus
```

## Logs

```bash
make remote-logs
# equivalent: ssh oldie@oldie.mule-nunki.ts.net "sudo journalctl -u octopus.service -f"
```
