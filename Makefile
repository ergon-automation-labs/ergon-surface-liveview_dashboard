.PHONY: run deps compile test credo clean help setup setup-hooks init release publish-release prune-releases push git-push deploy-surface docker-build docker-up docker-down

help:
	@echo "LiveView Surface Template"
	@echo ""
	@echo "Setup (run once in a new clone):"
	@echo "  make setup       - git init (if needed), deps, install githooks"
	@echo "  make setup-hooks - Install git hooks (core.hooksPath = git-hooks)"
	@echo ""
	@echo "Development:"
	@echo "  make deps    - mix deps.get"
	@echo "  make compile - mix compile"
	@echo "  make test    - mix test (the suite; this target is a RULE, not the test/ dir)"
	@echo "  make credo   - mix credo (advisory: this repo carries pre-existing findings)"
	@echo "  make run     - mix run --no-halt (PORT via SURFACE_LIVEVIEW_PORT or config default)"
	@echo "  make clean   - mix clean"
	@echo ""
	@echo "Docker (for multi-app bundling):"
	@echo "  make docker-build - Build Docker image (release inside container)"
	@echo "  make docker-up    - Start containers (docker-compose up)"
	@echo "  make docker-down  - Stop containers (docker-compose down)"
	@echo ""
	@echo "Release (normally via git pre-push):"
	@echo "  make release         - Build OTP release, then drop the stale copies it leaves behind"
	@echo "  make publish-release - Build, tarball, and publish to GitHub"
	@echo "  make prune-releases  - Show stale release artifacts (APPLY=1 to delete)"
	@echo ""
	@echo "Push (test + compile first, then the push that triggers the release):"
	@echo "  make push        - Validate, then git push origin main"
	@echo "  make git-push    - Push only, logging to /tmp (no validation)"
	@echo "  make deploy-surface - Deploy the published release to air via bot_army_infra"
	@echo ""

setup: init deps setup-hooks
	@echo "✓ Setup complete. Run 'make run' to start; push to main to build and publish release."

setup-hooks:
	@git config core.hooksPath git-hooks
	@echo "✓ Git hooks installed (core.hooksPath = git-hooks)"

init:
	@if [ ! -d .git ]; then git init; echo "Git initialized."; else echo "Git already initialized."; fi

deps:
	mix deps.get

compile:
	mix compile

# A rule has to exist. Without one, a `test/` directory in the repo root satisfies
# `make test`: make prints "Nothing to be done for 'test'" and exits 0. That is how
# this repo spent its whole life looking green while running nothing.
test:
	mix test

## Advisory, and deliberately not part of `push:` — this repo carries pre-existing
## findings (credo --strict exits 12), so a gate here would block every push and a
## gate that is always bypassed is not a gate. Report; never narrow the checks to
## make it pass.
credo:
	@mix credo || echo "ℹ️  credo reported findings (advisory, not a gate)"

run: deps
	mix run --no-halt

clean:
	mix clean

release:
	MIX_ENV=prod mix release --overwrite
	@scripts/prune_release_artifacts.sh --build-tree --apply
	@echo "✓ Release built in _build/prod/rel/"

publish-release: release
	@echo "Publishing to GitHub..."
	@RELEASE_NAME="bot_army_dashboard_liveview"; \
	VERSION=$$(cat _build/prod/rel/$$RELEASE_NAME/releases/start_erl.data | awk '{print $$2}'); \
	tar -czf $$RELEASE_NAME-$$VERSION.tar.gz -C _build/prod/rel $$RELEASE_NAME/; \
	gh release create v$$VERSION $$RELEASE_NAME-$$VERSION.tar.gz --draft=false; \
	echo "✓ Published v$$VERSION"

# `mix release --overwrite` never clears the release dir, so every past version
# stays behind and rides into the next tarball. Dry run by default; APPLY=1 acts.
# The pre-push hook calls the same script (build tree after the build, archives
# after the asset is published). Keep the build-tree prune AFTER the build: it
# keeps the version just built, so running it first would leave that version AND
# the new one in the release directory.
prune-releases:
	@scripts/prune_release_artifacts.sh $(if $(APPLY),--apply,)
	@echo ""
	@echo "  add APPLY=1 to act:  make prune-releases APPLY=1"

docker-build:
	docker-compose build
	@echo "✓ Docker image built"

docker-up:
	docker-compose up -d
	@echo "✓ Containers started (run 'make docker-down' to stop)"

docker-down:
	docker-compose down
	@echo "✓ Containers stopped"

# ── push ─────────────────────────────────────────────────────────────────────
#
# Same contract as the bot directories, minus the ones that do not apply here:
# validate, write the proof, then push through the logging target.
#
# Two things this target does NOT do, both by design and both worth knowing:
#
#   * It does not COMMIT. `make push` validates the working tree and then pushes
#     whatever is at HEAD, so stage every file you edited first — a green run
#     with an unstaged edit proves nothing about the commit that ships.
#   * It does not publish. It does not need to: this repo's pre-push hook builds
#     the release and publishes it, idempotently, when the push lands on main.
#     Adding `publish-release` here would build and try to create the same
#     release twice.
push: test compile
	@echo "✅ All validations passed"
	@echo "$$(date +%s)" > .push-validated
	@echo "✓ Proof-of-validation created"
	@$(MAKE) git-push

## Push only, capturing output to a log.
##
## Writes to the log then cats it, rather than piping through tee: a pipeline
## reports the exit status of its last command, so `git push | tee` returned 0
## even when the push was rejected.
git-push:
	@LOG_FILE="/tmp/git-push-bot_army_dashboard_liveview-$$(date +%s).log"; \
	echo "Pushing origin/main and logging to $$LOG_FILE..."; \
	if git push origin main > "$$LOG_FILE" 2>&1; then \
		cat "$$LOG_FILE"; \
		echo "✓ Log saved: $$LOG_FILE"; \
	else \
		cat "$$LOG_FILE"; \
		echo "✗ Push failed — log: $$LOG_FILE"; \
		exit 1; \
	fi

## Deploy the published release to air. The version deployed is whatever GitHub
## holds as the latest release, so push (and let the hook publish) first.
##
## The search stops at / and fails rather than looping: `cd ..` at / stays at /,
## so an unguarded `while [ ! -d ... ]; do cd ..; done` never terminates on a
## checkout that is not under the monorepo.
deploy-surface:
	@INFRA_DIR=""; dir="$(CURDIR)"; \
	while [ "$$dir" != "/" ]; do \
		if [ -d "$$dir/bots/bot_army_infra" ]; then INFRA_DIR="$$dir/bots/bot_army_infra"; break; fi; \
		dir=$$(dirname "$$dir"); \
	done; \
	if [ -z "$$INFRA_DIR" ]; then \
		echo "❌ could not find bots/bot_army_infra above $(CURDIR)"; exit 1; \
	fi; \
	echo "Deploying surface_dashboard via $$INFRA_DIR"; \
	$(MAKE) -C "$$INFRA_DIR" deploy-surface SURFACE=dashboard
