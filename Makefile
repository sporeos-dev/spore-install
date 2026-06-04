SCRIPTS := macos/build.sh macos/install.sh macos/uninstall.sh \
           linux/build.sh linux/install.sh linux/uninstall.sh

.DEFAULT_GOAL := check

.PHONY: setup check release release-linux

setup:
	@echo "==> Installing dependencies..."
	@if [ "$$(uname)" = "Darwin" ]; then \
		brew install shellcheck; \
	elif [ -f /etc/debian_version ]; then \
		sudo apt-get update && sudo apt-get install -y shellcheck; \
	elif [ -f /etc/fedora-release ]; then \
		sudo dnf install -y shellcheck; \
	elif [ -f /etc/os-release ] && grep -qi suse /etc/os-release; then \
		sudo zypper install -y shellcheck; \
	else \
		echo "Please install 'shellcheck' manually for your distribution."; \
	fi
	@echo "==> Setup complete."

check:
	@echo "==> Running shellcheck..."
	@shellcheck $(SCRIPTS)
	@echo "==> All checks passed."

release:
	@echo "==> Building macOS release..."
	@macos/build.sh
	@echo "==> Release build complete."

release-linux:
	@echo "==> Building Linux release..."
	@linux/build.sh
	@echo "==> Linux release build complete."
