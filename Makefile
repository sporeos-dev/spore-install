SCRIPTS := macos/build.sh macos/install.sh macos/uninstall.sh

.DEFAULT_GOAL := check

.PHONY: check release

check:
	@echo "==> Running shellcheck..."
	@shellcheck $(SCRIPTS)
	@echo "==> All checks passed."

release:
	@echo "==> Building release..."
	@macos/build.sh
	@echo "==> Release build complete."
