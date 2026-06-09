#!/usr/bin/env bash
# One-time bootstrap for the Dependency & Supply-Chain plugin on macOS / Linux.
#
# Makes the plugin portable: instead of installing Grype / Syft / OWASP Dependency-Check
# natively, it installs thin Docker wrappers on PATH and pre-pulls the scanner images.
# After this runs, the only host prerequisite for scanning is Docker.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BIN_DIR="${DEPSCAN_BIN:-$HOME/.depscan/bin}"

echo "== Dependency & Supply-Chain plugin - setup =="

# 1. Docker present and running?
command -v docker >/dev/null 2>&1 || { echo "ERROR: Docker not found on PATH. Install Docker and re-run."; exit 1; }
docker info >/dev/null 2>&1 || { echo "ERROR: Docker daemon not running. Start Docker and re-run."; exit 1; }
echo "Docker OK"

# 2. Pre-pull scanner images
for img in anchore/grype:latest anchore/syft:latest owasp/dependency-check:latest; do
    echo "Pulling $img ..."
    docker pull "$img" >/dev/null
done
echo "Images ready"

# 3. Create DB cache volumes
for vol in depscan-grype-db depscan-dc-data; do
    docker volume create "$vol" >/dev/null
done

# 4. Install wrappers on PATH (extensionless so `grype`/`syft`/`dependency-check` resolve)
mkdir -p "$BIN_DIR"
for tool in grype syft dependency-check; do
    cp "$SCRIPT_DIR/$tool.sh" "$BIN_DIR/$tool"
    chmod +x "$BIN_DIR/$tool"
done
echo "Wrappers installed to $BIN_DIR"

case ":$PATH:" in
    *":$BIN_DIR:"*) echo "$BIN_DIR already on PATH" ;;
    *) echo "Add this to your shell profile:  export PATH=\"$BIN_DIR:\$PATH\"" ;;
esac

echo
echo "Setup complete. Next:"
echo "  1. Export the MCP token env vars: GITHUB_PERSONAL_ACCESS_TOKEN, ATLASSIAN_API_TOKEN, SONARQUBE_TOKEN"
echo "     (optional: NVD_API_KEY to speed up OWASP Dependency-Check)"
echo "  2. Restart your shell, then run /depscan-doctor to verify."
