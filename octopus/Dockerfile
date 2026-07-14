# syntax=docker/dockerfile:1

# Find eligible builder and runner images on Docker Hub. We use Ubuntu/Debian
# instead of Alpine to avoid DNS resolution issues in production.
#
# https://hub.docker.com/r/hexpm/elixir/tags?page=1&name=ubuntu
# https://hub.docker.com/_/ubuntu?tab=tags
#
# This file is based on these images:
#
#   - https://hub.docker.com/r/hexpm/elixir/tags - for the build image
#   - https://hub.docker.com/_/debian?tab=tags&page=1&name=bullseye-20240423-slim - for the release image
#   - https://pkgs.org/ - resource for finding needed packages
#   - Ex: hexpm/elixir:1.16.2-erlang-26.2.4-debian-bullseye-20240423-slim
#
ARG ELIXIR_VERSION=1.20.0
ARG OTP_VERSION=29.0.1
ARG DEBIAN_VERSION=trixie-20260518

ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="debian:${DEBIAN_VERSION}"

FROM ${BUILDER_IMAGE} AS base

# cdn.debian.net is Debian's geo CDN (cdn.debian.org does not exist).
RUN sed -i 's|deb.debian.org|cdn.debian.net|g' /etc/apt/sources.list.d/debian.sources

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    apt-get update -y && apt-get install -y build-essential git curl npm \
    && apt-get clean && rm -f /var/lib/apt/lists/*_* \
    && git config --global --add url."https://github.com/".insteadOf ssh://git@github.com/ \
    && git config --global --add url."https://github.com/".insteadOf git@github.com:

RUN curl https://sh.rustup.rs -sSf | sh -s -- --no-modify-path -y --default-toolchain stable
ENV PATH="/root/.cargo/bin:${PATH}"

WORKDIR /app

RUN mix local.hex --force && \
    mix local.rebar --force

ENV MIX_ENV="prod"
ENV HEX_HTTP_CONCURRENCY=1
ENV HEX_HTTP_TIMEOUT=120
ENV NPM_CONFIG_FETCH_RETRIES=5
ENV NPM_CONFIG_FETCH_TIMEOUT=300000
ENV NPM_CONFIG_FETCH_RETRY_MINTIMEOUT=20000
ENV NPM_CONFIG_FETCH_RETRY_MAXTIMEOUT=120000

# Installation module — selectable at build time; defaults to Nation2026.
# Pass --build-arg INSTALLATION_MODULE=Octopus.Installation.Prototype to override,
# or set INSTALLATION_MODULE in deploy/<host>/.env (read by deploy/common/build-image.sh).
ARG INSTALLATION_MODULE=Octopus.Installation.Nation2026
ENV INSTALLATION_MODULE=$INSTALLATION_MODULE

FROM base AS deps

COPY mix.exs mix.lock ./
RUN --mount=type=cache,target=/root/.hex \
    --mount=type=cache,target=/root/.mix \
    mix deps.get --only $MIX_ENV

FROM deps AS deps_compile

RUN mkdir -p config
COPY config/config.exs config/${MIX_ENV}.exs config/
RUN --mount=type=cache,target=/root/.cargo/registry \
    --mount=type=cache,target=/root/.cargo/git \
    --mount=type=cache,target=/app/native/octopus_webp/target \
    mix deps.compile

FROM deps_compile AS assets

COPY assets/package.json assets/package-lock.json assets/
RUN --mount=type=cache,target=/root/.npm \
    cd assets && npm ci

COPY assets assets

FROM deps_compile AS builder

COPY priv priv
COPY lib lib
COPY src src
COPY native native
COPY --from=assets /app/assets assets

# Tailwind scans lib/octopus_web from assets/tailwind.config.js — lib must be
# present here, not in the assets stage, or utility classes won't be generated.
RUN --mount=type=cache,target=/root/.npm \
    mix tailwind.install --if-missing && \
    mix esbuild.install --if-missing && \
    mix assets.deploy

# Changes to config/runtime.exs / radar.exs don't require recompiling the code.
# radar.exs holds the physical sensor bindings and selects the active
# deployment by hostname at runtime.
COPY config/runtime.exs config/radar.exs config/

COPY rel rel
RUN --mount=type=cache,target=/root/.cargo/registry \
    --mount=type=cache,target=/root/.cargo/git \
    --mount=type=cache,target=/app/native/octopus_webp/target \
    mix compile

RUN --mount=type=cache,target=/root/.cargo/registry \
    --mount=type=cache,target=/root/.cargo/git \
    --mount=type=cache,target=/app/native/octopus_webp/target \
    mix release

FROM ${RUNNER_IMAGE}

RUN sed -i 's|deb.debian.org|cdn.debian.net|g' /etc/apt/sources.list.d/debian.sources

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    apt-get update -y && apt-get install -y libstdc++6 openssl libncurses6 locales libnss-mdns \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*

# Resolve *.local via the host Avahi daemon (mount its socket in compose).
RUN sed -i 's/^hosts:.*/hosts: files mdns4_minimal [NOTFOUND=return] dns/' /etc/nsswitch.conf

# Set the locale
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

WORKDIR "/app"
RUN chown nobody /app

# Ensure the data directory (mounted volume) is writable by the nobody user.
# Docker initialises named volume contents from the image on first use.
RUN mkdir -p /data && chown nobody:nogroup /data

# set runner ENV
ENV MIX_ENV="prod"

# Only copy the final release from the build stage
COPY --from=builder --chown=nobody:root /app/_build/${MIX_ENV}/rel/octopus ./

USER nobody

CMD ["/app/bin/server"]
