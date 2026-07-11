# Shared Docker image build for polychrome deployments.
#
# Source this file from deploy/<host>/deploy.sh, then call:
#   build_polychrome_image ENV_FILE OCTOPUS_DIR IMAGE_NAME IMAGE_TAG
#
# INSTALLATION_MODULE is read from ENV_FILE when set (compile-time build arg).
# Radar and other runtime settings stay in the same .env and are loaded by
# docker compose on the remote host.

build_polychrome_image() {
    local env_file="$1"
    local octopus_dir="$2"
    local image_name="${3:-polychrome}"
    local image_tag="${4:-latest}"

    local installation_module
    installation_module=$(
        grep -E '^[[:space:]]*INSTALLATION_MODULE=' "${env_file}" 2>/dev/null \
            | tail -1 \
            | cut -d= -f2- \
            | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//"
    )

    local build_args=()
    if [ -n "${installation_module}" ]; then
        build_args+=(--build-arg "INSTALLATION_MODULE=${installation_module}")
        echo "Building Docker image ${image_name}:${image_tag} (${installation_module})..."
    else
        echo "Building Docker image ${image_name}:${image_tag} (Dockerfile default installation)..."
    fi

    local cache_dir="${HOME}/.cache/polychrome-docker"
    mkdir -p "${cache_dir}"

    if ! docker buildx inspect polychrome-cache >/dev/null 2>&1; then
        docker buildx create --name polychrome-cache --driver docker-container --bootstrap
    fi
    docker buildx use polychrome-cache

    docker buildx build \
        --load \
        "${build_args[@]}" \
        --cache-from "type=local,src=${cache_dir}" \
        --cache-to "type=local,dest=${cache_dir},mode=max" \
        -t "${image_name}:${image_tag}" \
        -f "${octopus_dir}/Dockerfile" \
        "${octopus_dir}"
}
