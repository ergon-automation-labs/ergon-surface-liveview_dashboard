# LiveView Surface Template (Elixir)

A **template** for building Bot Army web surfaces with **Phoenix LiveView**: minimal Plug + Cowboy + LiveView, ready to wire to your bot via NATS or HTTP. Includes a **Jenkinsfile** so surfaces can be deployed via Jenkins (same pattern as bots), with a **non-conflicting port** chosen at setup.

**Run the setup script; it will prompt for an HTTP port (checked as free), then generate the app as its own git repo with githooks, port, and Jenkinsfile.**

## Layout

- **Router** — Plug.Router with a home page and a sample LiveView route (`/dashboard`).
- **Dashboard Live** — One example LiveView with assigns and a “Replace with your surface” message.
- **Optional** — Add a NATS bridge (GenServer that subscribes/publishes) and broadcast to LiveViews via Phoenix.PubSub.
- **git-hooks/pre-push** — On push to `main`: compile, build OTP release, create tarball, publish to GitHub. Jenkins then deploys from that release.
- **Jenkinsfile** — Deploy from GitHub releases (download tarball, deploy to `/opt/ergon/releases/<surface_name>`, restart service). Port is baked in at setup.
- **Own git repo** — The generated surface is `git init`’d and uses `core.hooksPath = git-hooks` so each surface is a separate repo for Jenkins and hooks run on push.

## Requirements

- Elixir 1.14+
- Phoenix ~> 1.7, Phoenix.LiveView ~> 0.20, Plug.Cowboy ~> 2.6
- (Optional) NATS: add `gnat` and a bridge module.

## Quick start

**Use the setup script (recommended):**

```bash
cd surfaces/elixir/liveview-surface-template
./setup_new_surface.sh terrain_liveview TerrainLiveview
# Prompts: HTTP port [4000]. Script checks the port is free and bakes it into config + Jenkinsfile.
cd ../terrain_liveview
mix deps.get
mix compile
mix run --no-halt
# Open http://localhost:<chosen_port> and http://localhost:<chosen_port>/dashboard
```

Override port at runtime with `<APP_SNAKE_UPPER>_PORT`, e.g. `TERRAIN_LIVEVIEW_PORT=4001 mix run --no-halt`.

**Copy manually (no port prompt / Jenkinsfile):**

```bash
cp -r liveview-surface-template ../my-surface-liveview
cd ../my-surface-liveview
# Rename app and modules, set port in config (see Customization checklist)
mix deps.get && mix compile
```

## Port, githooks, and Jenkins deploy

- **Setup** asks for an HTTP port, validates it (1–65535), and checks it is **currently free**. Optionally warns if the port is in `surfaces/elixir/port_registry.txt`. The chosen port is written into `config/config.exs` and the **Jenkinsfile**.
- **Own git repo** — The setup script runs `git init` in the new directory and sets `git config core.hooksPath git-hooks`. Surfaces are separate repos so Jenkins can clone and build each one; githooks run in that repo.
- **Pre-push hook** — Pushing to `main` runs `git-hooks/pre-push`: compile, build OTP release, create tarball, publish to GitHub with `gh release create`. Jenkins then downloads that release and deploys (same pattern as other bots).
- After setup, run `make setup` in the new surface to ensure deps and hooks are ready, then add a remote and push. Pushing to `main` will build and publish the release; Jenkins will deploy it.

## Customization checklist

1. **Naming** — Handled by the setup script (app snake + Pascal, port, Jenkinsfile placeholders).
2. **Router** — Add routes and `send_live(conn, YourLiveModule)` for each LiveView. Update the home page in `router.ex`.
3. **LiveViews** — Add modules under `lib/<app_snake>/live/`. Use `use Phoenix.LiveView`, implement `mount/3`, `render/1`, and handle events.
4. **LiveView client (required for interactivity)** — Add `/assets/app.js` that sets up the LiveView socket (phoenix + phoenix_live_view + LiveSocket). See [Phoenix LiveView installation](https://hexdocs.pm/phoenix_live_view/installation.html).
5. **NATS (optional)** — Add a GenServer that connects to NATS and broadcasts to `Phoenix.PubSub` so LiveViews can subscribe.
6. **Port** — Set at setup. Override at runtime with `<APP_SNAKE_UPPER>_PORT`.

## Surfaces UI Standards

- Every screen should show what the user can do (links, buttons, hints).
- Empty states should explain how to populate data (e.g. “No items yet — connect NATS or add from the toolbar”).

## Multi-App Pattern: Bundling Surfaces Together

**Why?** For consistency with bot packs, you can run multiple LiveView surfaces in a single Docker container and OTP release, each on its own port with shared NATS and PubSub.

This breaks traditional Docker rules (one app per container) but matches how Bot Army bundles bots, simplifying deployment while maintaining separation between surfaces.

### Example: Combining Chore + Fitness + Notifications Surfaces

**1. Create each surface separately:**
```bash
./setup_new_surface.sh chore_liveview ChoreLiveview
./setup_new_surface.sh fitness_liveview FitnessLiveview
./setup_new_surface.sh notifications_liveview NotificationsLiveview
```

**2. Create a parent app that bundles them** (e.g., `all_surfaces`):
```bash
./setup_new_surface.sh all_surfaces AllSurfaces
cd ../all_surfaces
```

**3. In `mix.exs`, add each surface as a local dependency:**
```elixir
defp deps do
  [
    {:phoenix, "~> 1.7"},
    {:phoenix_live_view, "~> 0.20"},
    {:plug_cowboy, "~> 2.6"},
    {:gnat, "~> 1.3"},
    {:chore_liveview, path: "../chore_liveview"},
    {:fitness_liveview, path: "../fitness_liveview"},
    {:notifications_liveview, path: "../notifications_liveview"},
  ]
end
```

**4. In `lib/all_surfaces/application.ex`, supervise multiple routers:**
```elixir
children = [
  {Phoenix.PubSub, name: AllSurfaces.PubSub},
  {Plug.Cowboy, plug: ChoreLiveview.Router, options: [port: 4001]},
  {Plug.Cowboy, plug: FitnessLiveview.Router, options: [port: 4002]},
  {Plug.Cowboy, plug: NotificationsLiveview.Router, options: [port: 4003]},
]
```

**5. In `docker-compose.yml`, expose all ports:**
```yaml
services:
  web:
    build: .
    ports:
      - "4001:4001"  # chore
      - "4002:4002"  # fitness
      - "4003:4003"  # notifications
    environment:
      NATS_HOST: host.docker.internal
      NATS_PORT: 4222
```

**6. (Optional) Add a reverse proxy for a single entry point:**

Create `nginx.conf`:
```
upstream chore { server localhost:4001; }
upstream fitness { server localhost:4002; }
upstream notifications { server localhost:4003; }

server {
  listen 8080;
  
  location /chore/ { proxy_pass http://chore/; }
  location /fitness/ { proxy_pass http://fitness/; }
  location /notifications/ { proxy_pass http://notifications/; }
}
```

Update `docker-compose.yml`:
```yaml
  reverse-proxy:
    image: nginx:latest
    ports:
      - "8080:8080"
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf
    depends_on:
      - web
```

Now all surfaces are accessible via:
- http://localhost:8080/chore
- http://localhost:8080/fitness
- http://localhost:8080/notifications

All surfaces share:
- **Same NATS connection** (via `NATS_HOST` / `NATS_PORT`)
- **Same Phoenix.PubSub** (for inter-surface communication)
- **Same OTP release** (one Docker build, one container process)

## Docker: Running in Containers

**Key principle**: Surfaces are **not exposed on the host machine by default** (ports are commented out in `docker-compose.yml`). They listen only within the Docker network. For external access, use a reverse proxy (nginx) that listens on a single host port.

### Single Surface (Dev with Port Exposure)

Uncomment `ports:` in `docker-compose.yml` for local testing:
```yaml
ports:
  - "4000:4000"
```

Then:
```bash
docker-compose up
# Visit http://localhost:4000
```

### Multiple Surfaces (Multi-App, No Port Exposure)

**Surfaces run internally only**, all routable from within the Docker network:
```bash
# From parent app directory (e.g., all_surfaces)
docker-compose up
# Surfaces listen internally:
#   - http://web:4001 (from inside Docker)
#   - http://web:4002
#   - http://web:4003
# Not accessible on host machine by default.
```

**For external access**, enable the reverse proxy in `docker-compose.yml`:
```yaml
  reverse-proxy:
    image: nginx:latest
    ports:
      - "8080:8080"
    volumes:
      - ./nginx.conf:/etc/nginx/conf.d/default.conf
```

Then create `nginx.conf`:
```
upstream chore { server web:4001; }
upstream fitness { server web:4002; }
upstream notifications { server web:4003; }

server {
  listen 8080;
  location /chore/ { proxy_pass http://chore/; }
  location /fitness/ { proxy_pass http://fitness/; }
  location /notifications/ { proxy_pass http://notifications/; }
}
```

Visit http://localhost:8080/chore, etc.

**NATS connection** — Set `NATS_HOST` to:
- **Mac with Docker Desktop**: `host.docker.internal:4222`
- **Docker network (same host, NATS in another container)**: `nats:4222`
- **Kubernetes**: `nats.default.svc.cluster.local:4222`
- **Remote**: IP address or hostname

## Reference

- Existing surface: `surfaces/elixir/global_surface_liveview/` (multi-view routing, NATS bridge, styling).
- Existing surface: `surfaces/elixir/bot_army_job_applications_liveview/` (router, LiveViews, NATS bridge).
- North star: Bot Army docs in the main repo (CLAUDE.md, Surfaces UI Standards).
- Application.ex comments show the multi-app supervisor pattern.
