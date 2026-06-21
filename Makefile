# Copyright 2026 Matt Harrison
# SPDX-License-Identifier: Apache-2.0

# OS detection
ifeq ($(OS),Windows_NT)
    PLATFORM := windows
else
    UNAME_S := $(shell uname -s)
    ifeq ($(UNAME_S),Linux)
        PLATFORM := linux
    else ifeq ($(UNAME_S),Darwin)
        PLATFORM := macos
    endif
endif

SCRIPTS := macos/build.sh macos/install.sh macos/uninstall.sh \
           linux/build.sh linux/install.sh linux/uninstall.sh \
           macos/develop.sh macos/startdev.sh \
           linux/develop.sh linux/startdev.sh

.DEFAULT_GOAL := check

.PHONY: setup check release develop startdev

setup:
ifeq ($(PLATFORM),windows)
	@echo "==> [Windows] Installing dependencies..."
	@powershell -NoProfile -ExecutionPolicy Bypass -Command "Install-Module -Name PSScriptAnalyzer -Force -Scope CurrentUser -AllowClobber"
	@echo "==> Setup complete."
else ifeq ($(PLATFORM),macos)
	@echo "==> [macOS] Installing dependencies..."
	@brew install shellcheck
	@echo "==> Setup complete."
else ifeq ($(PLATFORM),linux)
	@echo "==> [Linux] Installing dependencies..."
	@if command -v apt-get >/dev/null; then \
		sudo apt-get update && sudo apt-get install -y shellcheck; \
	elif command -v dnf >/dev/null; then \
		sudo dnf install -y shellcheck; \
	elif command -v yum >/dev/null; then \
		sudo yum install -y shellcheck; \
	elif command -v zypper >/dev/null; then \
		sudo zypper install -y shellcheck; \
	elif command -v apk >/dev/null; then \
		sudo apk add shellcheck; \
	else \
		echo "Please install 'shellcheck' manually via your package manager."; \
		exit 1; \
	fi
	@echo "==> Setup complete."
else
	@echo "Unsupported platform: $(PLATFORM)"
	@exit 1
endif

check:
ifeq ($(PLATFORM),windows)
	@echo "==> [Windows] Running PSScriptAnalyzer..."
	@powershell -NoProfile -ExecutionPolicy Bypass -Command "$$scripts = Get-ChildItem windows/*.ps1; if (-not (Get-Command Invoke-ScriptAnalyzer -ErrorAction SilentlyContinue)) { Write-Host 'WARNING: PSScriptAnalyzer is not installed! Run ''make setup'' to install.' -ForegroundColor Yellow } else { $$results = $$scripts | Invoke-ScriptAnalyzer; if ($$results) { $$results | Format-Table; exit 1 } }"
	@echo "==> All checks passed."
else ifeq ($(PLATFORM),macos)
	@echo "==> [macOS] Running shellcheck..."
	@shellcheck $(SCRIPTS)
	@echo "==> All checks passed."
else ifeq ($(PLATFORM),linux)
	@echo "==> [Linux] Running shellcheck..."
	@shellcheck $(SCRIPTS)
	@echo "==> All checks passed."
else
	@echo "Unsupported platform: $(PLATFORM)"
	@exit 1
endif

release:
ifeq ($(PLATFORM),windows)
	@echo "==> [Windows] Building release..."
	@powershell -NoProfile -ExecutionPolicy Bypass -File windows/build.ps1
	@echo "==> Release build complete."
else ifeq ($(PLATFORM),macos)
	@echo "==> [macOS] Building release..."
	@macos/build.sh
	@echo "==> Release build complete."
else ifeq ($(PLATFORM),linux)
	@echo "==> [Linux] Building release..."
	@linux/build.sh
	@echo "==> Release build complete."
else
	@echo "Unsupported platform: $(PLATFORM)"
	@exit 1
endif

develop:
ifeq ($(PLATFORM),windows)
	@echo "==> [Windows] Building for development..."
	@powershell -NoProfile -ExecutionPolicy Bypass -File windows/develop.ps1
	@echo "==> Development build complete."
else ifeq ($(PLATFORM),macos)
	@echo "==> [macOS] Building for development..."
	@macos/develop.sh
	@echo "==> Development build complete."
else ifeq ($(PLATFORM),linux)
	@echo "==> [Linux] Building for development..."
	@linux/develop.sh
	@echo "==> Development build complete."
else
	@echo "Unsupported platform: $(PLATFORM)"
	@exit 1
endif

startdev:
ifeq ($(PLATFORM),windows)
	@echo "==> [Windows] Starting development environment..."
	@powershell -NoProfile -ExecutionPolicy Bypass -File windows/startdev.ps1
else ifeq ($(PLATFORM),macos)
	@echo "==> [macOS] Starting development environment..."
	@macos/startdev.sh
else ifeq ($(PLATFORM),linux)
	@echo "==> [Linux] Starting development environment..."
	@linux/startdev.sh
else
	@echo "Unsupported platform: $(PLATFORM)"
	@exit 1
endif
