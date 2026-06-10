#!/usr/bin/env bash
# Docker-free bootstrap for the Dependency & Supply-Chain plugin (macOS / Linux / CI).
#
# Installs NATIVE Syft + Grype binaries on PATH. OWASP Dependency-Check needs no install — it runs
# via the Maven plugin (mvn org.owasp:dependency-check-maven:check). Java 17+ and Maven must already
# be present. No Docker, no image pulls, no daemon.
set -euo pipefail

BIN_DIR="${DEPSCAN_BIN:-$HOME/.local/bin}"
mkdir -p "$BIN_DIR"

echo "== Dependency & Supply-Chain plugin - native setup (no Docker) =="

# Prerequisite checks (advisory — install these via your OS package manager / SDK)
command -v java >/dev/null 2>&1 || echo "WARN: Java not found — install a JDK 17+."
command -v mvn  >/dev/null 2>&1 || echo "WARN: Maven not found — install Maven (or use ./mvnw)."

# Install Syft + Grype natively into $BIN_DIR
echo "Installing Syft  -> $BIN_DIR"
curl -sSfL https://raw.githubusercontent.com/anchore/syft/main/install.sh  | sh -s -- -b "$BIN_DIR"
echo "Installing Grype -> $BIN_DIR"
curl -sSfL https://raw.githubusercontent.com/anchore/grype/main/install.sh | sh -s -- -b "$BIN_DIR"

case ":$PATH:" in
    *":$BIN_DIR:"*) echo "$BIN_DIR already on PATH" ;;
    *) echo "Add this to your shell profile:  export PATH=\"$BIN_DIR:\$PATH\"" ;;
esac

echo
echo "Setup complete (no Docker)."
echo "  • Verify with: /depscan-doctor"
echo "  • Optional: export NVD_API_KEY to speed up OWASP Dependency-Check."
echo "  • Local Claude Code use also needs the MCP token vars (GITHUB_PERSONAL_ACCESS_TOKEN, ATLASSIAN_API_TOKEN)."
