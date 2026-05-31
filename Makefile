SCRIPTS := macos/build.sh macos/install.sh macos/uninstall.sh

.DEFAULT_GOAL := check

.PHONY: setup check release

setup:
	@echo "==> Installing dependencies..."
	@brew install shellcheck
	@echo "==> Setup complete."

check:
	@echo "==> Running shellcheck..."
	@shellcheck $(SCRIPTS)
	@echo "==> All checks passed."

release:
	@echo "==> Building release..."
	@macos/build.sh
	@echo "==> Release build complete."
