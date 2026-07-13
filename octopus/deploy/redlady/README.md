# Redlady Deployment (Raspberry Pi)

Deploys octopus to `redlady` (`redlady.crested-frog.ts.net`) via Tailscale.
The stack runs two Docker containers in `network_mode: host`:

- **polychrome** — the Elixir/Phoenix app (HTTP on port 4000)
- **caddy** — reverse proxy that terminates TLS using Tailscale certificates

Both use host networking so UDP broadcast to ESP32 LED panels works without
Docker NAT.

## One-time setup on the Pi

### 1. Install Docker

Follow the official Docker install guide for Debian/arm64:

```bash
sudo apt update && sudo apt install -y ca-certificates curl gnupg
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | \
    sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/debian \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io \
    docker-buildx-plugin docker-compose-plugin
sudo usermod -aG docker tim
```

Log out and back in for the group change to take effect.

### 2. Issue a Tailscale certificate

```bash
sudo mkdir -p /var/lib/tailscale/certs
cd /var/lib/tailscale/certs && sudo tailscale cert redlady.crested-frog.ts.net
```

This creates:
- `/var/lib/tailscale/certs/redlady.crested-frog.ts.net.crt`
- `/var/lib/tailscale/certs/redlady.crested-frog.ts.net.key`

These files are mounted read-only into the Caddy container.

### 3. Set up certificate renewal (cron)

Tailscale certs are valid for 90 days. Add a cron job to renew them and
reload Caddy:

```bash
sudo crontab -e
```

Add:

```cron
0 3 1 */2 * cd /var/lib/tailscale/certs && tailscale cert redlady.crested-frog.ts.net && \
    cd /home/tim/polychrome/deploy/redlady && docker compose exec caddy caddy reload --config /etc/caddy/Caddyfile
```

This runs on the 1st of every other month at 03:00.

### 4. Prepare the environment file

```bash
cp deploy/redlady/.env.example deploy/redlady/.env
# Edit .env and fill in SECRET_KEY_BASE (generate: mix phx.gen.secret)
```

## Deploy

From your laptop (inside `octopus/`):

```bash
make deploy-redlady
```

This rsyncs the source to the Pi and builds the Docker image natively on arm64,
then runs migrations and starts the stack.

On first deploy the build will take several minutes (Elixir + Rust compilation).
Subsequent builds reuse Docker layer cache.

## Logs

```bash
ssh tim@redlady.crested-frog.ts.net \
    'cd /home/tim/polychrome/deploy/redlady && docker compose logs -f'
```

## Radar sensors

Nation 2026 defines six logical radar sensors (`:a`–`:f`) in the installation
module. This host maps them to USB serial ports in
`config/radar_deployments.exs` under the `"redlady"` deployment, selected by
`RADAR_DEPLOYMENT=redlady` in `deploy/redlady/.env` (see `.env.example`).

`RADAR_SOURCE_MODE=live` is the production default (use `off`, `exact`, or
`fuzzy` for other modes). On dev machines the default is `off` until you pick
a source in the radar UI.

To change sensor layout or orientation, edit the `:radar` block in
`lib/octopus/installation/nation2026.ex`. To change ports or adapters on this
Pi, edit the `"redlady"` entry in `config/radar_deployments.exs`. Serial
devices are passed through to the container via the `/dev` and `/dev/serial`
mounts in `docker-compose.yml`.
