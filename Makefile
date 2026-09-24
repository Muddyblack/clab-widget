.PHONY: help view view-h view-hyprland hyprland install test test-py test-js lint format pack run-desktop demo icons app-icons tag
.DEFAULT_GOAL := help

help: ## list targets
	@awk 'BEGIN{FS=":.*##"} /^[a-z][a-zA-Z0-9_-]+:.*##/ {printf "  make %-13s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

view: ## preview the widget on a desktop (planar)
	@if command -v nix >/dev/null 2>&1 && [ -f flake.nix ]; then \
	  nix run .#view; \
	else \
	  plasmoidviewer -a package -f planar; \
	fi

view-h: ## preview the widget in a panel (horizontal)
	@if command -v nix >/dev/null 2>&1 && [ -f flake.nix ]; then \
	  nix run .#view -- horizontal; \
	else \
	  plasmoidviewer -a package -f horizontal; \
	fi

view-hyprland: ## run the Quickshell pill / desktop card
	@if command -v nix >/dev/null 2>&1 && [ -f flake.nix ]; then \
	  nix run .#view-hyprland; \
	else \
	  qs -p "$$PWD/shell.qml"; \
	fi

hyprland: view-hyprland

run-desktop: ## run the tray app (the Windows/macOS frontend) on this machine
	@if command -v nix >/dev/null 2>&1 && [ -f flake.nix ]; then \
	  nix run .#desktop; \
	else \
	  python3 desktop/app.py; \
	fi

demo: ## write demo labs to /tmp/clab-demo (use: eval "$(make -s demo)")
	@python3 tests/demo.py /tmp/clab-demo --large

install: ## install a test copy into the local Plasma session
	@./test_install.sh

test: ## run all test suites (backend, schema, shared QML logic)
	@$(MAKE) --no-print-directory test-py
	@$(MAKE) --no-print-directory test-js

test-py: ## backend + snapshot schema tests
	@python3 -m unittest discover -s tests

test-js: ## shared QML logic tests (Labs.js)
	@if command -v node >/dev/null 2>&1; then node tests/labs.test.js; \
	  else echo "skipping tests/labs.test.js (node not found)"; fi

lint: ## ruff + qmlformat check (dev only; `nix develop` has the tools)
	@ruff check . && ruff format --check .
	@find package/contents hyprland desktop -name '*.qml' -not -path '*/card/*' -print0 | \
	  xargs -0 qmlformat --dry-run 2>&1 | grep -q "would reformat" && \
	  { echo "QML needs formatting: make format"; exit 1; } || true

format: ## apply ruff format + qmlformat
	@ruff format .
	@find package/contents hyprland desktop -name '*.qml' -not -path '*/card/*' -print0 | xargs -0 qmlformat -i

icons: ## regenerate code/Icons.js from the Lucide SVGs
	@python3 tools/lucide-to-js.py

app-icons: ## rebuild icons/app/* from assets/icon.png and assets/icon-<name>.png (needs Pillow)
	@python3 tools/make-app-icons.py

pack: ## build the .plasmoid archive
	@if command -v nix >/dev/null 2>&1 && [ -f flake.nix ]; then \
	  nix run .#pack; \
	else \
	  ver=$$(grep -oE '"Version":[[:space:]]*"[^"]+"' package/metadata.json | head -1 | sed -E 's/.*"([^"]+)"$$/\1/'); \
	  name=$$(basename "$$PWD"); \
	  out="$$PWD/$$name-$$ver.plasmoid"; \
	  rm -f "$$out"; \
	  (cd package && zip -r "$$out" . -x '*.swp' '*~' '*/__pycache__/*'); \
	  echo "wrote $$out"; \
	fi

tag: ## bump version, commit, tag, push (CI builds the release)
	@./tag.sh
