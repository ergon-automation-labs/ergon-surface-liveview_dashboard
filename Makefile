.PHONY: run deps compile clean help setup setup-hooks init release publish-release prune-releases docker-build docker-up docker-down

help:
	@echo "LiveView Surface Template"
	@echo ""
	@echo "Setup (run once in a new clone):"
	@echo "  make setup       - git init (if needed), deps, install githooks"
	@echo "  make setup-hooks - Install git hooks (core.hooksPath = git-hooks)"
	@echo ""
	@echo "Development:"
	@echo "  make deps    - mix deps.get"
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

setup: init deps setup-hooks
	@echo "✓ Setup complete. Run 'make run' to start; push to main to build and publish release."

setup-hooks:
	@git config core.hooksPath git-hooks
	@echo "✓ Git hooks installed (core.hooksPath = git-hooks)"

init:
	@if [ ! -d .git ]; then git init; echo "Git initialized."; else echo "Git already initialized."; fi

deps:
	mix deps.get

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
