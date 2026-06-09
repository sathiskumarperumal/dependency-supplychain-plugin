---
description: Depscan Doctor — verify this machine can run the Dependency & Supply-Chain pipeline (Docker, scanner wrappers + images, Maven/Java, and the GitHub/Jira/SonarQube MCP servers) and report exactly what is missing.
allowed-tools: [Bash, Read]
---

# Depscan Doctor

Run a **read-only** environment check for the Dependency & Supply-Chain plugin and print a
readiness table. Do **not** install anything — only report status and the fix for each gap.
Never print secret values; check only that a variable is set.

Check each item and classify ✅ pass / ⚠️ warn / ❌ fail:

## 1. Container runtime
- `docker --version` — Docker installed?
- `docker info` — daemon actually running?

## 2. Scanner wrappers + images (Docker model)
- Wrappers resolve on PATH: `grype version`, `syft version`, `dependency-check --version`.
  (These should be the Docker wrappers installed by `scripts/setup.ps1` / `setup.sh`.)
- Images present: `docker image ls` includes `anchore/grype`, `anchore/syft`, `owasp/dependency-check`.
- Cache volumes present: `docker volume ls` includes `depscan-grype-db`, `depscan-dc-data`.

## 3. Build toolchain
- `mvn -v` — Maven present.
- `java -version` — Java 17+ present.

## 4. MCP servers
- `claude mcp list` — confirm `github`, `jira`, `sonarqube` show **Connected**.
- Confirm the token env vars exist (names only, never echo values):
  `GITHUB_PERSONAL_ACCESS_TOKEN`, `ATLASSIAN_API_TOKEN`, `SONARQUBE_TOKEN`.

## 5. Optional accelerators
- `NVD_API_KEY` set — speeds up OWASP Dependency-Check's NVD download (warn if absent, not a failure).

## Output

Print one table: **Component | Status | Detail / Fix**, grouped by the sections above. Then print
the single most important next action, e.g.:
- "Start Docker Desktop" (daemon down)
- "Run `scripts/setup.ps1`" (wrappers/images missing)
- "Set `GITHUB_PERSONAL_ACCESS_TOKEN` then restart your shell" (MCP token unset)

If every required item passes, end with: **"READY — run the Stage 1 scan to begin."**
