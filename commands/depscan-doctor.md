---
description: Depscan Doctor — verify this machine or CI runner can run the Dependency & Supply-Chain pipeline using NATIVE tools (Java 17+, Maven, Syft, Grype) — no Docker required. Reports exactly what's missing and the native install command for each gap.
allowed-tools: [Bash, Read]
---

# Depscan Doctor (native — no Docker)

Run a **read-only** environment check and print a readiness table. **No Docker is used or required.**
Do not install anything — only report status and the native fix for each gap. Never print secret
values; check only that a variable is set.

Classify ✅ pass / ⚠️ warn / ❌ fail:

## 1. Build toolchain (required)
- `java -version` — Java **17+**. Fix: install Temurin/OpenJDK 17+ via your OS package manager.
- `mvn -v` — Maven present. Fix: install Maven, or use the project's `./mvnw` wrapper.

## 2. Scanners — native binaries on PATH (required)
- `syft version` — Syft (SBOM generation).
  Fix (Linux/macOS/CI): `curl -sSfL https://raw.githubusercontent.com/anchore/syft/main/install.sh | sh -s -- -b "$HOME/.local/bin"`
  Fix (Windows): run `scripts\setup.ps1` (or `scoop install syft`).
- `grype version` — Grype (vulnerability scan).
  Fix (Linux/macOS/CI): `curl -sSfL https://raw.githubusercontent.com/anchore/grype/main/install.sh | sh -s -- -b "$HOME/.local/bin"`
  Fix (Windows): run `scripts\setup.ps1` (or `scoop install grype`).

> **OWASP Dependency-Check needs no binary and no Docker** — it runs via the Maven plugin
> (`mvn org.owasp:dependency-check-maven:check`). Nothing to install or check here beyond Maven + network.

## 3. Network / accelerators
- Outbound HTTPS to **Maven Central** and the **NVD** (the Maven/OWASP goals fetch from these).
- `NVD_API_KEY` set — speeds the OWASP Dependency-Check NVD sync (⚠️ warn if absent, not a failure).

## 4. MCP servers (local Claude Code use only — N/A in CI)
- `claude mcp list` — `github` / `jira` show **Connected**. Only needed when running locally; in CI
  the workflow supplies MCP via `templates/github-actions/mcp.ci.json`. ⚠️ warn (not fail) if absent.
- Token vars set (names only, never echo): `GITHUB_PERSONAL_ACCESS_TOKEN`, `ATLASSIAN_API_TOKEN`.

## One-shot native install (any machine / any CI — no Docker)
- Linux / macOS / CI: `bash scripts/setup.sh`
- Windows: `pwsh scripts/setup.ps1`
(Installs Syft + Grype natively; Java 17+ and Maven must already be present.)

## Output
Print one table: **Component | Status | Detail / Fix**, grouped by the sections above. Then print the
single most important next action, e.g.:
- "Install Java 17+" (toolchain missing)
- "Run `scripts/setup.sh` to install Syft + Grype natively" (scanners missing)
- "Set `NVD_API_KEY` to speed the NVD sync" (optional)

If every required item passes, end with: **"READY — run the Stage 1 scan to begin (no Docker needed)."**
