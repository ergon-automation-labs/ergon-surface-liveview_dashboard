# Multi-App Pattern: Bundling Multiple LiveView Surfaces

This guide explains how to bundle multiple LiveView surfaces (e.g., Chore, Fitness, Notifications) into **one Docker container and OTP release** for consistency with Bot Army packs.

**Why?** Simplifies deployment: one Docker build, one container, one OTP process. Each surface has its own router, LiveView modules, and port. All share NATS, PubSub, and environment.

**Trade-off:** Breaks traditional Docker "one process per container" rule, but matches Bot Army's philosophy of bundling services.

---

## Architecture Overview

```
┌─ Docker Container (all_surfaces) ─────────────────────┐
│                                                         │
│  ┌─ Supervision Tree ─────────────────────────────────┤
│  │                                                      │
│  ├─ Phoenix.PubSub (shared across all surfaces)        │
│  │                                                      │
│  ├─ Plug.Cowboy (Chore surface)                        │
│  │  └─ ChoreLiveview.Router (port 4001)                │
│  │     ├─ /chore (route)                               │
│  │     └─ /chore/tasks (route)                         │
│  │                                                      │
│  ├─ Plug.Cowboy (Fitness surface)                      │
│  │  └─ FitnessLiveview.Router (port 4002)              │
│  │     ├─ /fitness (route)                             │
│  │     └─ /fitness/workouts (route)                    │
│  │                                                      │
│  ├─ Plug.Cowboy (Notifications surface)                │
│  │  └─ NotificationsLiveview.Router (port 4003)        │
│  │     └─ /notifications (route)                       │
│  │                                                      │
│  └─ Gnat (NATS client, optional)                       │
│     └─ Subscriptions to chore.task.*, fitness.*, etc.  │
│                                                         │
└─────────────────────────────────────────────────────────┘

External Access (via reverse proxy):
  http://localhost:8080/chore          → web:4001 → ChoreLiveview
  http://localhost:8080/fitness        → web:4002 → FitnessLiveview
  http://localhost:8080/notifications  → web:4003 → NotificationsLiveview
```

---

## Step-by-Step Setup

### 1. Create Individual Surfaces

Each surface is created separately using `setup_new_surface.sh`:

```bash
cd surfaces/elixir/liveview-surface-template

# Create each surface (they'll prompt for port, but we'll override them in the bundled app)
./setup_new_surface.sh chore_liveview ChoreLiveview
./setup_new_surface.sh fitness_liveview FitnessLiveview
./setup_new_surface.sh notifications_liveview NotificationsLiveview
```

Each surface now has its own directory with:
- `mix.exs` (defines the OTP app)
- `lib/<surface>/router.ex` (routes)
- `lib/<surface>/live/*.ex` (LiveView modules)
- `lib/<surface>/application.ex` (supervisor; we'll ignore this in the bundled version)

### 2. Create Parent Bundle App

```bash
./setup_new_surface.sh all_surfaces AllSurfaces
cd ../all_surfaces
```

This creates the parent app that will bundle all surfaces.

### 3. Update Parent `mix.exs`

Add each surface as a **local path dependency**:

```elixir
# all_surfaces/mix.exs

def project do
  [
    app: :all_surfaces,
    version: "0.1.0",
    # ... rest of config
  ]
end

defp deps do
  [
    {:phoenix, "~> 1.7"},
    {:phoenix_live_view, "~> 0.20"},
    {:plug_cowboy, "~> 2.6"},
    {:jason, "~> 1.4"},
    {:gnat, "~> 1.3"},
    
    # Add all surfaces as local path deps
    {:chore_liveview, path: "../chore_liveview"},
    {:fitness_liveview, path: "../fitness_liveview"},
    {:notifications_liveview, path: "../notifications_liveview"},
    
    {:credo, "~> 1.7", only: [:dev, :test]},
  ]
end
```

Run `mix deps.get` to fetch and link them.

### 4. Update Parent `lib/all_surfaces/application.ex`

Supervise **multiple Plug.Cowboy listeners**, each with its own router:

```elixir
# all_surfaces/lib/all_surfaces/application.ex

defmodule AllSurfaces.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Shared PubSub (all surfaces can broadcast/subscribe)
      {Phoenix.PubSub, name: AllSurfaces.PubSub},
      
      # Optional: NATS bridge for subscribing to other bots
      # AllSurfaces.NATS.Bridge,
      
      # Chore surface (port 4001)
      {Plug.Cowboy,
       scheme: :http,
       plug: ChoreLiveview.Router,
       options: [port: 4001]},
      
      # Fitness surface (port 4002)
      {Plug.Cowboy,
       scheme: :http,
       plug: FitnessLiveview.Router,
       options: [port: 4002]},
      
      # Notifications surface (port 4003)
      {Plug.Cowboy,
       scheme: :http,
       plug: NotificationsLiveview.Router,
       options: [port: 4003]},
    ]

    opts = [strategy: :one_for_one, name: AllSurfaces.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

**Key points:**
- Each surface has its own `Plug.Cowboy` instance on a different port
- All surfaces share `AllSurfaces.PubSub` (can communicate via `Phoenix.PubSub.broadcast/3`)
- The parent app's Supervisor oversees all of them

### 5. Update Parent `config/config.exs`

Configure NATS and environment:

```elixir
# all_surfaces/config/config.exs

import Config

config :all_surfaces, :port, 4000  # Not used in multi-app, but kept for compatibility

config :gnat,
  nats_host: System.get_env("NATS_HOST", "localhost"),
  nats_port: System.get_env("NATS_PORT", "4222") |> String.to_integer(),
  nats_servers: [
    %{
      host: System.get_env("NATS_HOST", "localhost"),
      port: System.get_env("NATS_PORT", "4222") |> String.to_integer()
    }
  ]
```

### 6. Update `docker-compose.yml`

Expose all surface ports (or use a reverse proxy for a single entry point):

```yaml
# all_surfaces/docker-compose.yml

version: '3.8'

services:
  web:
    build: .
    container_name: all_surfaces
    # Do NOT expose individual ports on host (only for dev/testing)
    # ports:
    #   - "4001:4001"
    #   - "4002:4002"
    #   - "4003:4003"
    environment:
      NATS_HOST: host.docker.internal
      NATS_PORT: 4222
      SECRET_KEY_BASE: "dev_secret_key_base_change_in_prod"
    networks:
      - bot-army
    restart: unless-stopped

  # Reverse proxy: single host entry point for all surfaces
  reverse-proxy:
    image: nginx:latest
    container_name: all_surfaces_reverse_proxy
    ports:
      - "8080:8080"
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - web
    networks:
      - bot-army

networks:
  bot-army:
    driver: bridge
```

### 7. Create `nginx.conf`

Route `/chore`, `/fitness`, `/notifications` to their respective ports:

```
upstream chore { server web:4001; }
upstream fitness { server web:4002; }
upstream notifications { server web:4003; }

server {
  listen 8080;

  location /chore/ { proxy_pass http://chore/; proxy_http_version 1.1; proxy_set_header Upgrade $http_upgrade; proxy_set_header Connection "upgrade"; }
  location /fitness/ { proxy_pass http://fitness/; proxy_http_version 1.1; proxy_set_header Upgrade $http_upgrade; proxy_set_header Connection "upgrade"; }
  location /notifications/ { proxy_pass http://notifications/; proxy_http_version 1.1; proxy_set_header Upgrade $http_upgrade; proxy_set_header Connection "upgrade"; }
}
```

(See `nginx.conf.example` in the template for a complete example.)

### 8. Build and Run

```bash
# Build release inside Docker
make docker-build

# Start containers
make docker-up

# Check logs
docker-compose logs -f web

# Access surfaces
curl http://localhost:8080/chore
curl http://localhost:8080/fitness
curl http://localhost:8080/notifications

# Stop
make docker-down
```

---

## Sharing Data Between Surfaces (Inter-Surface Communication)

All surfaces share `AllSurfaces.PubSub`, so they can communicate:

**Surface A (Chore) emits an event:**
```elixir
Phoenix.PubSub.broadcast(AllSurfaces.PubSub, "system_events", {:chore_completed, task_id})
```

**Surface B (Fitness) listens:**
```elixir
defmodule FitnessLiveview.SummaryLive do
  use Phoenix.LiveView

  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Subscribe to events from other surfaces
      Phoenix.PubSub.subscribe(AllSurfaces.PubSub, "system_events")
    end
    {:ok, socket}
  end

  def handle_info({:chore_completed, task_id}, socket) do
    # React to chore completion (maybe unlock a fitness achievement)
    {:noreply, socket}
  end
end
```

---

## Customization: Adding More Surfaces

To add a new surface to the bundle:

1. **Create the surface:**
   ```bash
   ./setup_new_surface.sh new_surface_liveview NewSurfaceLiveview
   ```

2. **Add to parent `mix.exs`:**
   ```elixir
   {:new_surface_liveview, path: "../new_surface_liveview"},
   ```

3. **Add to parent `application.ex`:**
   ```elixir
   {Plug.Cowboy,
    scheme: :http,
    plug: NewSurfaceLiveview.Router,
    options: [port: 4004]},  # Next available port
   ```

4. **Add to `nginx.conf`:**
   ```
   upstream new_surface { server web:4004; }
   
   location /new_surface/ { proxy_pass http://new_surface/; ... }
   ```

5. **Rebuild:**
   ```bash
   mix deps.get
   make docker-build
   make docker-up
   ```

---

## Deployment (Jenkins / Salt)

The bundled app (`all_surfaces`) is deployed like any other surface:

1. Version bump in `mix.exs`
2. Pre-push hook builds release + publishes to GitHub
3. Jenkins clones, builds, publishes
4. Salt deploys OTP release to `/opt/ergon/releases/all_surfaces`

The Dockerfile handles the build; Salt starts the release.

---

## Troubleshooting

**"Connection refused to web:4001"** — Ensure services are linked in `docker-compose.yml` and surfaces are supervised in `application.ex`.

**"Address already in use"** — Ports 4001–4003 are taken by other processes. Change them in `application.ex` and `nginx.conf`.

**NATS not connecting** — Check `NATS_HOST` (use `host.docker.internal` on Mac) and `NATS_PORT` in `docker-compose.yml`.

**LiveView not reloading** — Ensure surfaces subscribe to `AllSurfaces.PubSub` (not a custom one).

---

## References

- Template: `surfaces/elixir/liveview-surface-template/`
- Existing examples: `surfaces/elixir/global_surface_liveview/` (multi-view routing)
- Phoenix LiveView docs: https://hexdocs.pm/phoenix_live_view/
- Nginx proxy docs: https://nginx.org/en/docs/http/ngx_http_proxy_module.html
