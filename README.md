# Dependency & Supply-Chain Plugin (Java)

A Claude Code plugin that delivers end-to-end **dependency & supply-chain hygiene** for Java/Maven
projects. It scans dependencies and SBOMs for vulnerabilities, outdated and unlicensed packages,
and supply-chain risks (typosquatting, untrusted sources); scores each dependency by risk;
auto-remediates with version-bump PRs; and gates PR merges on a full validation pipeline with an
auditable health report.

Built from the **7-Day Dependency & Supply-Chain Hygiene Plan** (`Claude_Initiative_Plans.xlsx`).

---

## What's inside

### Agents

| Agent | Stage | Purpose |
|---|---|---|
| `risk_scoring_agent` | 2 | Scores each Java dependency by CVE severity, exposure & business criticality using NVD CVSS, producing a ranked remediation backlog. Pipeline **entry point** — takes the repo once. |
| `pr_validation_agent` | 4 | Orchestrates the merge gate: `mvn test` → OWASP Dependency-Check → Grype supply-chain audit. All pass → ready for human merge; else block with reasons. |

### Skills

| Skill | Stage | Purpose |
|---|---|---|
| `depscan-dependency-scanner` | 1 | Scan Maven `pom.xml` → flag outdated, vulnerable & unlicensed packages (OWASP Dependency-Check). |
| `depscan-auto-remediation` | 3 | Safe Maven version upgrades → one consolidated PR with changelog summaries and CVE fix details. |
| `depscan-merge-validation` | 4 | The merge-gate ruleset the PR Validation Agent enforces (thresholds + decision logic). |
| `depscan-supplychain-audit` | 4 (gate component) | Scan SBOM → block risky deps: typosquatting, untrusted sources, license violations (Grype). Runs inside the Stage 4 gate. |
| `depscan-audit-trail` | 5 | Aggregate all scan results into a single dependency health report; drive the live demo flow. |

---

## Toolchain

| Tool | Used by | Role |
|---|---|---|
| **OWASP Dependency-Check** | Stage 1, 4 | Known-vulnerability (CVE) scanning of Maven dependencies. |
| **NVD CVSS Database** | Stage 2 | Authoritative CVSS base scores for risk scoring. |
| **Grype** | Stage 4 | SBOM / image vulnerability + supply-chain risk scanning. |
| **Syft** | Stage 4 | SBOM (CycloneDX) generation. |
| **SonarQube** (MCP) | Stage 4 | Static analysis gate (optional). |
| **GitHub** (MCP) | Stage 3, 4, 5 | PR creation, reviews, merge. |
| **Jira** (MCP) | Stage 2, 5 | Ticket linkage & audit comments. |

The scanners run as **native binaries** on `PATH` (Syft + Grype); OWASP Dependency-Check runs
via the Maven plugin. **No Docker is required.** See *Install on a new
machine* below.

---

## Install on a new machine

The plugin itself is just text (agents/skills/commands) — it cannot bundle native binaries, so each
machine that runs a scan needs a small **native** toolchain — **Java + Maven** (no Docker):

1. **Install** Claude Code, a **JDK 17+**, and **Maven** (no Docker required anywhere).
2. **Add the plugin** (from your marketplace or a local path).
3. **Install the scanners** (one time per machine) — installs **native** Syft + Grype
   binaries onto your `PATH` (no Docker, no images, no daemon):

   ```powershell
   # Windows
   .\scripts\setup.ps1
   ```
   ```bash
   # macOS / Linux
   ./scripts/setup.sh
   ```

4. **Set the MCP token env vars** (the `.mcp.json` reads these via `${VAR}`, so no secrets live in
   the repo):

   ```powershell
   [Environment]::SetEnvironmentVariable("GITHUB_PERSONAL_ACCESS_TOKEN","<pat>","User")
   [Environment]::SetEnvironmentVariable("ATLASSIAN_API_TOKEN","<token>","User")
   [Environment]::SetEnvironmentVariable("SONARQUBE_TOKEN","<token>","User")
   # optional, recommended — speeds up OWASP Dependency-Check's NVD download:
   [Environment]::SetEnvironmentVariable("NVD_API_KEY","<key>","User")
   ```

5. **Verify** — restart your shell, then run:

   ```text
   /depscan-doctor
   ```

   It checks Java/Maven and the native Syft/Grype binaries (no Docker), plus the MCP servers, and reports
   exactly what (if anything) is missing.

> **No Docker anywhere:** Syft + Grype are native binaries; OWASP Dependency-Check runs via the Maven
> plugin (`mvn org.owasp:dependency-check-maven:check`). The GitHub Actions workflow installs the same
> native tools, so local and CI match — no Docker required.

---

## Usage

```text
/depscan-doctor                              # verify the machine is ready
/risk_scoring_agent <path-to-java-repo>      # Stage 1–2 — entry point: scan + rank by risk
/pr_validation_agent <PR-number>             # Stage 4 — run the merge gate on a PR
/depscan-pipeline <repo> [--mode full|gate-only] [--pr N]   # whole pipeline in one run
```

Skills activate automatically when their described situation arises, or invoke them by name.

---

## Automate with GitHub Actions (Flavor B)

The whole pipeline can run on a schedule and per-PR in CI, with Claude executing the agents (so the
intelligent risk-scoring and remediation are preserved) and the deterministic scanners running as
native steps. The human merge is preserved via branch protection — the workflow never merges.

**One orchestrator, two triggers:**

| Trigger | Mode | What runs |
|---|---|---|
| `schedule:` (nightly cron) | `full` | scan → score → remediate → open/update fix PR → gate verdict (drift detection) |
| `pull_request:` | `gate-only` | just the Stage 4 gate on the PR that triggered it |
| `workflow_dispatch:` | `full` (default) | manual run |

Both triggers call the single entry point — the **`/depscan-pipeline`** command — so the sequence is
defined once, not re-encoded per trigger.

**Setup (in the target Java/Maven repo):**

1. Copy [`templates/github-actions/depscan.yml`](templates/github-actions/depscan.yml) to
   `.github/workflows/depscan.yml`.
2. Add repo secrets: `ANTHROPIC_API_KEY`, `NVD_API_KEY`, and (optional, for Jira) `ATLASSIAN_API_TOKEN`. `GITHUB_TOKEN` is automatic.
3. No plugin token needed — the plugin repo is **public**, so the workflow checks it out directly.
4. Add a **branch-protection rule** requiring a human review before merge — this is the
   human-in-the-loop; the workflow only posts PASS/BLOCK.

> **MCP in CI:** the workflow loads templates/github-actions/mcp.ci.json via --mcp-config, running the
> github + jira MCP servers so the agents MCP tools resolve; creds come from the Actions secrets above.

---

## Pipeline order & fast-path (performance)

### Order of execution (single repo)

```
/depscan-doctor                 # preflight (one-time / on demand)
   │
   ▼
Stage 1  depscan-dependency-scanner   → depscan-report.json
Stage 2  risk_scoring_agent           → depscan-risk-report.json     (reuses Stage 1)
Stage 3  depscan-auto-remediation     → consolidated fix PR
Stage 4  pr_validation_agent (gate)   → MERGE / BLOCK
            └─ runs: tests + OWASP CVE + supply-chain audit
Stage 5  depscan-audit-trail          → dependency-health-report.md
```

The **supply-chain audit** is not a standalone stage — it runs as a component **inside the Stage 4
gate** (alongside tests and the CVE scan). Stage 5 is reporting, outside the gate.

### Execution context (single repo input)

The repo/head is supplied **once**, to the entry agent (**Stage 2 `risk_scoring_agent`**), which
checks it out into a child working directory (cloning if given a URL/head). Every later stage runs
**inside that same working tree and on the resulting PR** — Stage 3 auto-remediation raises the fix
PR there; Stage 4 takes `pr_number` and the Stage 5 report reads that PR's live state. Downstream
stages derive `owner/repo` from `git remote get-url origin`; they never take a repo path or re-clone.

### Fast-path reuse contract

The pipeline avoids re-doing expensive work via three rules:

1. **Build once.** The first stage that needs a build runs `mvn -q test package` — one reactor run
   yields the Surefire reports and the packaged artifact for the SBOM. Later stages reuse the
   populated `target/` instead of rebuilding.
2. **Reuse-if-fresh, else regenerate.** Every report is stamped with `source_sha` (`git rev-parse
   HEAD`). A downstream stage reuses an upstream report when it exists, its `source_sha` equals the
   current HEAD, and `pom.xml` is unmodified — so **OWASP Dependency-Check and Grype each run once**
   per HEAD (the Stage 4 gate consumes the Stage 1 report + supply-chain audit rather than
   re-scanning).
3. **Warm scanner DBs.** Keep the NVD DB in the `depscan-dc-data` volume (`-DautoUpdate=false` +
   `NVD_API_KEY`) and the Grype DB in `depscan-grype-db` (`GRYPE_DB_AUTO_UPDATE=false`); refresh them
   on a schedule, not per run. The independent gate checks run in parallel.

Net effect of a warm run: one build (not 3–4), each vulnerability scanner executed once (not up to
3×), no per-run DB downloads — the gate becomes mostly report-loading + aggregation. Thresholds,
scoring, and the human-in-the-loop no-auto-merge rule are unchanged.
