.SUFFIXES:

CARGO_BINS := peek time_fuzzer funnel mosaic
CLC_DIR    := tools/claude-commit

# profile detection: mac (Darwin) / x1 (Linux). override via `PROFILE=...`.
UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Darwin)
PROFILE ?= mac
else
PROFILE ?= x1
endif

STOW_TARGET    ?= $(HOME)
STOW_COMMON    := stow/common
STOW_PROFILE   := stow/$(PROFILE)

COMMON_DIRS  := $(shell find $(STOW_COMMON) -mindepth 1 -maxdepth 1 -type d | sed 's|^$(STOW_COMMON)/||' | sort)
PROFILE_DIRS := $(shell [ -d $(STOW_PROFILE) ] && find $(STOW_PROFILE) -mindepth 1 -maxdepth 1 -type d | sed 's|^$(STOW_PROFILE)/||' | sort)

help:  ## Show this help
	@echo "Profile: $(PROFILE) (override with PROFILE=mac|x1)"
	@echo "Available targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

.PHONY: build
build: $(addprefix build-,$(CARGO_BINS))  ## Build all rust binaries (release)

.PHONY: build-%
build-%:
	cargo build --release --manifest-path ./tools/$*/Cargo.toml

.PHONY: install
install: build sync  ## Symlink rust binaries + claude-commit launcher into ~/.local/bin
	mkdir -p $(HOME)/.local/bin
	@for b in $(CARGO_BINS); do \
		ln -sfv "$(PWD)/tools/$$b/target/release/$$b" "$(HOME)/.local/bin/$$b"; \
	done
	ln -sfv "$(PWD)/$(CLC_DIR)/bin/claude-commit" "$(HOME)/.local/bin/claude-commit"
	ln -sfv "$(PWD)/$(CLC_DIR)/bin/claude-commit" "$(HOME)/.local/bin/clc"

.PHONY: sync
sync:  ## Sync the claude-commit uv environment
	uv sync --project $(CLC_DIR)

.PHONY: stow
stow:  ## Stow common + $(PROFILE) packages into $$HOME
	@for d in $(COMMON_DIRS); do \
		stow --restow --no-folding --dir=$(STOW_COMMON) --target=$(STOW_TARGET) "$$d" && echo "Stowed common/$$d" || echo "Failed common/$$d"; \
	done
	@for d in $(PROFILE_DIRS); do \
		stow --restow --dir=$(STOW_PROFILE) --target=$(STOW_TARGET) "$$d" && echo "Stowed $(PROFILE)/$$d" || echo "Failed $(PROFILE)/$$d"; \
	done

.PHONY: restow
restow:  ## Restow common + $(PROFILE) packages into $$HOME
	@for d in $(COMMON_DIRS); do \
		stow --restow --no-folding --dir=$(STOW_COMMON) --target=$(STOW_TARGET) "$$d" && echo "Restowed common/$$d" || echo "Failed common/$$d"; \
	done
	@for d in $(PROFILE_DIRS); do \
		stow --restow --dir=$(STOW_PROFILE) --target=$(STOW_TARGET) "$$d" && echo "Restowed $(PROFILE)/$$d" || echo "Failed $(PROFILE)/$$d"; \
	done

.PHONY: unstow
unstow:  ## Unstow common + $(PROFILE) packages from $$HOME
	@for d in $(PROFILE_DIRS); do \
		stow --delete --dir=$(STOW_PROFILE) --target=$(STOW_TARGET) "$$d" && echo "Unstowed $(PROFILE)/$$d" || echo "Failed $(PROFILE)/$$d"; \
	done
	@for d in $(COMMON_DIRS); do \
		stow --delete --no-folding --dir=$(STOW_COMMON) --target=$(STOW_TARGET) "$$d" && echo "Unstowed common/$$d" || echo "Failed common/$$d"; \
	done

.PHONY: list-stow
list-stow:  ## List dotfile packages discovered for stow
	@echo "common:"
	@for d in $(COMMON_DIRS); do echo "  $$d"; done
	@echo "$(PROFILE):"
	@for d in $(PROFILE_DIRS); do echo "  $$d"; done

.PHONY: test
test: test-cargo test-hooks test-statusline test-py  ## Run all tests (rust + bats + pytest)

.PHONY: test-cargo
test-cargo: $(addprefix test-cargo-,$(CARGO_BINS))  ## cargo test all rust binaries

.PHONY: test-cargo-%
test-cargo-%:
	cargo test --manifest-path ./tools/$*/Cargo.toml

.PHONY: test-hooks
test-hooks:  ## Run bats tests for shell hooks
	bats tests/hooks/

.PHONY: test-statusline
test-statusline:  ## Run bats tests for claude statusline
	bats tests/statusline/

.PHONY: test-py
test-py:  ## Run pytest for python scripts
	uvx pytest tests/py/ -q

.PHONY: lint
lint: $(addprefix lint-,$(CARGO_BINS)) lint-py  ## cargo clippy + fmt --check + ruff

.PHONY: lint-%
lint-%:
	cargo clippy --manifest-path ./tools/$*/Cargo.toml -- -D warnings
	cargo fmt --manifest-path ./tools/$*/Cargo.toml -- --check

.PHONY: lint-py
lint-py:  ## ruff check claude-commit (no writes)
	uv run --project $(CLC_DIR) ruff check $(CLC_DIR)
	uv run --project $(CLC_DIR) ruff format --check $(CLC_DIR)

.PHONY: format
format: $(addprefix format-,$(CARGO_BINS)) format-py  ## cargo fmt + ruff format

.PHONY: format-%
format-%:
	cargo fmt --manifest-path ./tools/$*/Cargo.toml

.PHONY: format-py
format-py:  ## ruff format + fix claude-commit
	uv run --project $(CLC_DIR) ruff format $(CLC_DIR)
	uv run --project $(CLC_DIR) ruff check --fix $(CLC_DIR)

.PHONY: clean
clean:  ## Remove rust build artifacts
	@for b in $(CARGO_BINS); do \
		cargo clean --manifest-path ./tools/$$b/Cargo.toml; \
	done
