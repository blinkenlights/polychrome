#!/bin/bash
set -e

REMOTE_HOST="redlady.crested-frog.ts.net"
REMOTE_USER="tim"
REMOTE_DIR="/home/tim/polychrome"
IMAGE_NAME="polychrome"
IMAGE_TAG="latest"
TARBALL="${IMAGE_NAME}-${IMAGE_TAG}.tar.gz"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OCTOPUS_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Parse arguments
SKIP_BUILD=false
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --skip-build) SKIP_BUILD=true ;;
        *) echo "Unknown parameter: $1"; exit 1 ;;
    esac
    shift
done

ENV_FILE="${SCRIPT_DIR}/.env"
if [ ! -f "${ENV_FILE}" ]; then
    echo "Error: ${ENV_FILE} not found."
    echo "Copy deploy/redlady/.env.example to deploy/redlady/.env and fill in values."
    exit 1
fi

# Build image locally (native architecture — no --platform flag so Docker uses
# the Mac's native arm64; the Raspberry Pi is also arm64).
if [ "$SKIP_BUILD" = false ]; then
    echo "Building Docker image ${IMAGE_NAME}:${IMAGE_TAG}..."
    docker build \
        -t "${IMAGE_NAME}:${IMAGE_TAG}" \
        -f "${OCTOPUS_DIR}/Dockerfile" \
        "${OCTOPUS_DIR}"

    echo "Saving image to tarball..."
    docker save "${IMAGE_NAME}:${IMAGE_TAG}" | gzip > "/tmp/${TARBALL}"
else
    if [ ! -f "/tmp/${TARBALL}" ]; then
        echo "Error: No existing tarball at /tmp/${TARBALL}. Run without --skip-build."
        exit 1
    fi
    echo "Using existing tarball..."
fi

# Prepare remote directory
echo "Preparing remote directory ${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_DIR}..."
ssh "${REMOTE_USER}@${REMOTE_HOST}" "mkdir -p ${REMOTE_DIR}/deploy/redlady/data"

# Copy files to remote
echo "Copying files to remote..."
rsync -av "/tmp/${TARBALL}" "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_DIR}/"
rsync -av "${SCRIPT_DIR}/docker-compose.yml" "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_DIR}/deploy/redlady/"
rsync -av "${SCRIPT_DIR}/Caddyfile" "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_DIR}/deploy/redlady/"
rsync -av "${ENV_FILE}" "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_DIR}/deploy/redlady/.env"

# Sync radar.local.exs if present (gitignored, host-specific sensor config).
# Place it at deploy/redlady/data/radar.local.exs locally and it will be
# deployed to /data/radar.local.exs inside the container.
RADAR_LOCAL="${SCRIPT_DIR}/data/radar.local.exs"
if [ -f "${RADAR_LOCAL}" ]; then
    echo "Syncing radar.local.exs..."
    rsync -av "${RADAR_LOCAL}" \
        "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_DIR}/deploy/redlady/data/radar.local.exs"
fi

# Deploy on remote
echo "Deploying on ${REMOTE_HOST}..."
ssh "${REMOTE_USER}@${REMOTE_HOST}" "
    set -e
    cd ${REMOTE_DIR}/deploy/redlady

    echo 'Loading image...'
    gunzip -c ${REMOTE_DIR}/${TARBALL} | docker load

    echo 'Stopping existing container...'
    docker compose stop polychrome 2>/dev/null || true

    echo 'Ensuring data directory has correct permissions...'
    sudo chown -R nobody:nogroup ${REMOTE_DIR}/deploy/redlady/data

    echo 'Starting services (migrations run automatically on startup)...'
    docker compose up -d

    echo 'Cleaning up tarball...'
    rm ${REMOTE_DIR}/${TARBALL}

    echo 'Deployment complete.'
"

# Clean up local tarball
rm "/tmp/${TARBALL}"

echo "Done. Check logs with: ssh ${REMOTE_USER}@${REMOTE_HOST} 'cd ${REMOTE_DIR}/deploy/redlady && docker compose logs -f'"
