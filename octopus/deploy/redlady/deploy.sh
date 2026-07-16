#!/bin/bash
set -e

REMOTE_HOST="redlady.crested-frog.ts.net"
REMOTE_USER="tim"
REMOTE_DIR="/home/tim/polychrome"
IMAGE_NAME="polychrome"
IMAGE_TAG="latest"
TARBALL="/tmp/${IMAGE_NAME}-${IMAGE_TAG}.tar.gz"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OCTOPUS_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
# shellcheck source=../common/build-image.sh
source "${SCRIPT_DIR}/../common/build-image.sh"

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
    build_polychrome_image "${ENV_FILE}" "${OCTOPUS_DIR}" "${IMAGE_NAME}" "${IMAGE_TAG}"
else
    if [ ! -f "${TARBALL}" ]; then
        echo "Error: No existing tarball at ${TARBALL}. Run without --skip-build."
        exit 1
    fi
    echo "Using existing tarball..."
fi

# Prepare remote directory
echo "Preparing remote directory ${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_DIR}..."
ssh "${REMOTE_USER}@${REMOTE_HOST}" "mkdir -p ${REMOTE_DIR}/deploy/redlady/data"

# Copy deploy config
echo "Copying deploy config..."
rsync -av "${SCRIPT_DIR}/docker-compose.yml" "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_DIR}/deploy/redlady/"
rsync -av "${SCRIPT_DIR}/Caddyfile" "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_DIR}/deploy/redlady/"
rsync -av "${ENV_FILE}" "${REMOTE_USER}@${REMOTE_HOST}:${REMOTE_DIR}/deploy/redlady/.env"

# Stream image directly to remote docker. tee simultaneously saves a local tarball
# (reused by --skip-build on subsequent runs) while piping to the remote in one pass.
echo "Streaming image to ${REMOTE_HOST}..."
if [ "$SKIP_BUILD" = false ]; then
    IMAGE_SIZE=$(docker image inspect --format='{{.Size}}' "${IMAGE_NAME}:${IMAGE_TAG}")
    if command -v pv &>/dev/null; then
        docker save "${IMAGE_NAME}:${IMAGE_TAG}" | pv -s "${IMAGE_SIZE}" -pterab | gzip | tee "${TARBALL}" | ssh "${REMOTE_USER}@${REMOTE_HOST}" "gunzip | docker load"
    else
        docker save "${IMAGE_NAME}:${IMAGE_TAG}" | gzip | tee "${TARBALL}" | ssh "${REMOTE_USER}@${REMOTE_HOST}" "gunzip | docker load"
    fi
else
    if command -v pv &>/dev/null; then
        TARBALL_SIZE=$(stat -f%z "${TARBALL}")
        pv -s "${TARBALL_SIZE}" -pterab "${TARBALL}" | ssh "${REMOTE_USER}@${REMOTE_HOST}" "gunzip | docker load"
    else
        ssh "${REMOTE_USER}@${REMOTE_HOST}" "gunzip | docker load" < "${TARBALL}"
    fi
fi

# Deploy on remote
echo "Deploying on ${REMOTE_HOST}..."
ssh "${REMOTE_USER}@${REMOTE_HOST}" "
    set -e
    cd ${REMOTE_DIR}/deploy/redlady

    echo 'Cleaning up old images...'
    docker image prune -f

    echo 'Stopping existing container...'
    docker compose stop polychrome 2>/dev/null || true

    echo 'Ensuring data directory has correct permissions...'
    docker run --rm -v ${REMOTE_DIR}/deploy/redlady/data:/data --user root polychrome:latest \
        sh -c 'chown nobody:nogroup /data && chmod 777 /data'

    echo 'Starting services (migrations run automatically on startup)...'
    docker compose up -d

    echo 'Deployment complete.'
"

echo "Done. Check logs with: ssh ${REMOTE_USER}@${REMOTE_HOST} 'cd ${REMOTE_DIR}/deploy/redlady && docker compose logs -f --tail=100 polychrome'"
