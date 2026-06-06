# Multi-stage Dockerfile for LiveView surfaces.
# Based on Bot Army patterns from bot-army-starter.

# =============================================
# Build stage: compile release
# =============================================
FROM elixir:1.17.3-otp-27 AS build

RUN apt-get update && apt-get install -y --no-install-recommends \
  git \
  build-essential \
  && rm -rf /var/lib/apt/lists/*
RUN mix local.hex --force && mix local.rebar --force

WORKDIR /app

# Copy mix.exs first for dep caching (mix.lock may not exist in fresh clone)
COPY mix.exs ./
RUN mix deps.get && mix deps.compile

# Copy full source and build release
COPY . .
RUN MIX_ENV=prod mix release

# =============================================
# Runtime stage: Debian slim with release only
# =============================================
FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
  libstdc++6 \
  libgcc-s1 \
  openssl \
  libncurses6 \
  ca-certificates \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy release from builder
COPY --from=build /app/_build/prod/rel/bot_army_dashboard_liveview ./

# Expose default port (override in docker-compose or runtime)
EXPOSE 4000

# Start the release
CMD ["bin/bot_army_dashboard_liveview", "start"]
