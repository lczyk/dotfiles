.SUFFIXES:

CARGO_BINS := peek time_fuzzer
STOW_DIRS := $(shell find . -maxdepth 1 -type d ! -name '.*' ! -name 'bin' ! -name '.' | sed 's|^\./||' | sort)
STOW_TARGET ?= $(HOME)

help:  ## Show this help
	@echo "Available targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

.PHONY: build
build: $(addprefix build-,$(CARGO_BINS))  ## Build all rust binaries (release)

.PHONY: build-%
build-%:
	cargo build --release --manifest-path ./bin/$*/Cargo.toml

.PHONY: install
install: build  ## Symlink built rust binaries into ~/.local/bin
	mkdir -p $(HOME)/.local/bin
	@for b in $(CARGO_BINS); do \
		ln -sfv "$(PWD)/bin/$$b/target/release/$$b" "$(HOME)/.local/bin/$$b"; \
	done

.PHONY: stow
stow:  ## Stow all dotfile packages into $$HOME
	@for d in $(STOW_DIRS); do \
		stow --target="$(STOW_TARGET)" "$$d" && echo "Stowed $$d" || echo "Failed to stow $$d"; \
	done

.PHONY: restow
restow:  ## Restow all dotfile packages into $$HOME
	@for d in $(STOW_DIRS); do \
		stow --restow --target="$(STOW_TARGET)" "$$d" && echo "Restowed $$d" || echo "Failed to restow $$d"; \
	done

.PHONY: unstow
unstow:  ## Unstow all dotfile packages from $$HOME
	@for d in $(STOW_DIRS); do \
		stow --delete --target="$(STOW_TARGET)" "$$d" && echo "Unstowed $$d" || echo "Failed to unstow $$d"; \
	done

.PHONY: list-stow
list-stow:  ## List dotfile packages discovered for stow
	@for d in $(STOW_DIRS); do echo "$$d"; done

.PHONY: test
test: $(addprefix test-,$(CARGO_BINS))  ## cargo test all rust binaries

.PHONY: test-%
test-%:
	cargo test --manifest-path ./bin/$*/Cargo.toml

.PHONY: lint
lint: $(addprefix lint-,$(CARGO_BINS))  ## cargo clippy + fmt --check

.PHONY: lint-%
lint-%:
	cargo clippy --manifest-path ./bin/$*/Cargo.toml -- -D warnings
	cargo fmt --manifest-path ./bin/$*/Cargo.toml -- --check

.PHONY: format
format: $(addprefix format-,$(CARGO_BINS))  ## cargo fmt all rust binaries

.PHONY: format-%
format-%:
	cargo fmt --manifest-path ./bin/$*/Cargo.toml

.PHONY: clean
clean:  ## Remove rust build artifacts
	@for b in $(CARGO_BINS); do \
		cargo clean --manifest-path ./bin/$$b/Cargo.toml; \
	done
