#!/bin/bash
set -e

REMOTE_HOST="tailscale-de.crested-frog.ts.net"
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
    echo "Copy deploy/metaebene/.env.example to deploy/metaebene/.env and fill in values."
    exit 1
fi

# Build image locally (native architecture — no --platform flag so Docker uses
# the Mac's native arm64; the metaebene server is an ARM VPS).
if [ "$SKIP_BUILD" = false ]; then
    CACHE_DIR="${HOME}/.cache/polychrome-docker"
    mkdir -p "${CACHE_DIR}"

    if ! docker buildx inspect polychrome-cache >/dev/null 2>&1; then
        docker buildx create --name polychrome-cache --driver docker-container --bootstrap
    fi
    docker buildx use polychrome-cache

    echo "Building Docker image ${IMAGE_NAME}:${IMAGE_TAG}..."
    docker buildx build \
        --load \
        --cache-from "type=local,src=${CACHE_DIR}" \
        --cache-to "type=local,dest=${CACHE_DIR},mode=max" \
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
ssh "${REMOTE_USER}@${REMOTE_HOST}" "mkdir -p ${REMOTE_DIR}/deploy/metaebene"

# Copy files to remote
echo "Copying image to ${REMOTE_HOST}..."
rsync -av --progress "/tmp/${TARBALL}" "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_DIR}/"
echo "Copying deploy config..."
rsync -av "${SCRIPT_DIR}/docker-compose.yml" "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_DIR}/deploy/metaebene/"
rsync -av "${ENV_FILE}" "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_DIR}/deploy/metaebene/.env"

# Deploy on remote
echo "Deploying on remote..."
ssh "${REMOTE_USER}@${REMOTE_HOST}" "
    set -e
    cd ${REMOTE_DIR}/deploy/metaebene

    echo 'Loading image...'
    gunzip -c ${REMOTE_DIR}/${TARBALL} | docker load

    echo 'Stopping existing container...'
    docker compose stop polychrome 2>/dev/null || true

    echo 'Ensuring data volume exists with correct permissions...'
    docker volume inspect polychrome_data >/dev/null 2>&1 || docker volume create polychrome_data
    docker run --rm -v polychrome_data:/data --user root polychrome:latest \
        sh -c 'chown nobody:nogroup /data'

    echo 'Ensuring metaebene_edge network exists...'
    docker network inspect metaebene_edge >/dev/null 2>&1 || docker network create metaebene_edge

    echo 'Starting service (migrations run automatically on startup)...'
    docker compose up -d polychrome

    echo 'Reloading Caddy to pick up site configuration...'
    docker compose -f /home/tim/metaebene-host/docker/docker-compose.yml exec caddy caddy reload --config /etc/caddy/Caddyfile

    echo 'Cleaning up tarball...'
    rm ${REMOTE_DIR}/${TARBALL}

    echo 'Deployment complete.'
"

# Clean up local tarball
rm "/tmp/${TARBALL}"

echo "Done. Check logs with: ssh ${REMOTE_USER}@${REMOTE_HOST} 'docker compose -f ${REMOTE_DIR}/deploy/metaebene/docker-compose.yml logs -f'"
