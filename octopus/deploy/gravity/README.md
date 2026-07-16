# Gravity Deployment (Raspberry Pi)

Deploys octopus to `gravity` (`gravity.crested-frog.ts.net`) via Tailscale.
The stack runs four Docker containers in `network_mode: host`:

- **polychrome-woodstock** — Installation Woodstock, Boot App Fire (HTTP port 4000)
- **polychrome-pixie** — Installation Pixie, Boot App PixelFun3d / Seegras (HTTP port 4001)
- **caddy** — reverse proxy that terminates TLS using Tailscale certificates

Both app instances use host networking so UDP broadcast to ESP32 LED panels works
without Docker NAT. Caddy exposes both on the same hostname via different HTTPS ports:

| Instance | URL |
|----------|-----|
| Pixie | `https://gravity.crested-frog.ts.net` (port 443) |
| Woodstock | `https://gravity.crested-frog.ts.net:8443` |

There is no HTTPS port conflict: only Caddy listens on 443/8443. The two Octopus
instances run on internal HTTP ports 4000/4001 and are never exposed directly.

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
cd /var/lib/tailscale/certs && sudo tailscale cert gravity.crested-frog.ts.net
```

This creates:
- `/var/lib/tailscale/certs/gravity.crested-frog.ts.net.crt`
- `/var/lib/tailscale/certs/gravity.crested-frog.ts.net.key`

These files are mounted read-only into the Caddy container.

### 3. Set up certificate renewal (cron)

Tailscale certs are valid for 90 days. Add a cron job to renew them and
reload Caddy:

```bash
sudo crontab -e
```

Add:

```cron
0 3 1 */2 * cd /var/lib/tailscale/certs && tailscale cert gravity.crested-frog.ts.net && \
    cd /home/tim/polychrome/deploy/gravity && docker compose exec caddy caddy reload --config /etc/caddy/Caddyfile
```

This runs on the 1st of every other month at 03:00.

### 4. Prepare the environment file

```bash
cp deploy/gravity/.env.example deploy/gravity/.env
# Edit .env and fill in both SECRET_KEY_BASE values:
#   SECRET_KEY_BASE       — for the Woodstock instance
#   PIXIE_SECRET_KEY_BASE — for the Pixie instance
# Generate each with: mix phx.gen.secret
```

## Deploy

From your laptop (inside `octopus/`):

```bash
make deploy-gravity
```

This rsyncs the source to the Pi and builds the Docker image natively on arm64,
then runs migrations and starts the stack.

On first deploy the build will take several minutes (Elixir + Rust compilation).
Subsequent builds reuse Docker layer cache.

## Logs

```bash
# All services
ssh tim@gravity.crested-frog.ts.net \
    'cd /home/tim/polychrome/deploy/gravity && docker compose logs -f'

# Single service
ssh tim@gravity.crested-frog.ts.net \
    'cd /home/tim/polychrome/deploy/gravity && docker compose logs -f polychrome-woodstock'
ssh tim@gravity.crested-frog.ts.net \
    'cd /home/tim/polychrome/deploy/gravity && docker compose logs -f polychrome-pixie'
```

## Installation profiles

Both instances share a **single Docker image** built from the same release. The
installation module is selected at container startup via the `INSTALLATION_MODULE`
environment variable (set in `docker-compose.yml`), which overrides the compile-time
default from `config.exs`. All installation modules are compiled into the release,
so no separate image build is needed.

| Service | Installation | Boot App | Boot Mode | HTTP-Port | HTTPS-Port |
|---------|-------------|----------|-----------|-----------|------------|
| `polychrome-pixie` | `Octopus.Installation.Pixie` | `PixelFun3d` | `seegras` | 4001 | 443 |
| `polychrome-woodstock` | `Octopus.Installation.Woodstock` | `Fire` | — | 4000 | 8443 |

To change the boot app or preset, edit `docker-compose.yml` and redeploy.

## mDNS / `.local` hostnames

Panel controllers are addressed as `blinkenleds-….local`. Resolution works two ways:

1. **Octopus** queries mDNS via `mdns_lite` (multicast on the host network).
2. **NSS** in the image uses `libnss-mdns` against the host Avahi socket mounted
   at `/var/run/avahi-daemon/socket` (requires `avahi-daemon` on the Pi).

## Radar sensors

The Woodstock installation does not define radar sensors. If you add radar to an
installation later, add an entry for this host (keyed by its hostname) to the
`deployments` map in `config/radar.exs` and mount serial devices via
`docker-compose.yml`.
