---
name: depscan-dependency-scanner
description: This skill should be used when scanning a Java/Maven project's dependencies for security and hygiene issues. Covers locating pom.xml files, resolving the full dependency tree, running OWASP Dependency-Check to flag known-vulnerable (CVE) packages, detecting outdated versions via the Maven Versions plugin, and detecting unlicensed or non-compliant licenses. Produces a normalized findings report consumed by the risk-scoring, remediation, and merge-validation steps. Activates when a user asks to scan Maven dependencies for vulnerable, outdated, or unlicensed packages.
---

# Stage 1 — Dependency Scanner (Maven + OWASP Dependency-Check)

## Overview

Scans a Java/Maven project to flag three classes of dependency problems:

1. **Vulnerable** — dependencies with known CVEs (OWASP Dependency-Check against the NVD).
2. **Outdated** — dependencies with newer stable releases available (Maven Versions plugin).
3. **Unlicensed / non-compliant** — dependencies with missing, unknown, or denied licenses (Maven License plugin).

Output is a single normalized JSON report (`depscan-report.json`) that downstream skills/agents
consume. This skill **detects and reports** — it does not modify `pom.xml` (that is Stage 3
auto-remediation).

---

## Prerequisites

| Tool | Check | Install / fallback |
|---|---|---|
| Maven | `mvn -v` | required |
| OWASP Dependency-Check CLI | `dependency-check --version` | `choco install dependency-check` or run via plugin goal below |
| Java 17+ | `java -version` | required |
| `NVD_API_KEY` (env) | `echo $NVD_API_KEY` is set | strongly recommended — ~10× faster NVD sync (50 vs 5 req/30s) |
| Warm NVD DB volume | `docker volume ls` includes `depscan-dc-data` | persists the CVE DB between runs so it isn't re-downloaded |

If the standalone CLI is unavailable, use the Maven plugin goal (no install needed):
`mvn org.owasp:dependency-check-maven:check`.

> **Performance:** the NVD database download/refresh dominates a cold run. Keep the DB in the
> `depscan-dc-data` volume and pass `NVD_API_KEY`; on a warm DB use `-DautoUpdate=false` so the scan
> skips the sync entirely. The four scan goals below are independent — **run them in parallel**.

---

## Step 1 — Locate Maven projects

Use Glob to find every `pom.xml` (multi-module aware):

```
**/pom.xml
```

Record the root `pom.xml` and each module. Skip `target/` directories. If no `pom.xml` exists,
stop and report: "No Maven project found."

---

## Step 2 — Resolve the dependency tree

```bash
mvn -q dependency:tree -DoutputType=text -DappendOutput=true -Dscope=compile
```

Capture the full resolved tree (including transitive deps). Each line yields
`groupId:artifactId:version:scope`. Store as the canonical dependency inventory — every finding is
keyed to a `groupId:artifactId:version` coordinate.

---

## Step 3 — Vulnerability scan (OWASP Dependency-Check)

Run against the project. Emit a JSON report so it can be parsed deterministically. Reuse the warm
NVD DB and the API key so the scan does not re-download the database:

```bash
mvn org.owasp:dependency-check-maven:check \
  -Dformat=JSON \
  -DfailBuildOnCVSS=11 \
  -DnvdApiKey=$NVD_API_KEY \
  -DautoUpdate=false \
  -DdataDirectory=/usr/share/dependency-check/data \
  -DoutputDirectory=target/depscan
```

> `failBuildOnCVSS=11` keeps the scan **non-blocking** here — gating happens in Stage 4, not Stage 1.
>
> **Warm DB:** `-DautoUpdate=false` reuses the CVE DB in the `depscan-dc-data` volume (mounted at
> `dataDirectory`) and skips the multi-minute NVD sync — the biggest single speed-up. Run a refresh
> only on first use or on a schedule:
> ```bash
> mvn org.owasp:dependency-check-maven:update-only -DnvdApiKey=$NVD_API_KEY
> ```
> If the DB has never been populated, drop `-DautoUpdate=false` for that first run.

Parse `target/depscan/dependency-check-report.json`. For each `dependencies[].vulnerabilities[]`
extract:

| Field | Source |
|---|---|
| `coordinate` | matched `groupId:artifactId:version` |
| `cve` | `vulnerabilities[].name` |
| `cvss_score` | `vulnerabilities[].cvssv3.baseScore` (fall back to `cvssv2.score`) |
| `severity` | `CRITICAL` ≥ 9.0, `HIGH` 7.0–8.9, `MEDIUM` 4.0–6.9, `LOW` < 4.0 |
| `fix_version` | first non-vulnerable release if known (else `null`) |

---

## Step 4 — Outdated-version scan

```bash
mvn -q versions:display-dependency-updates -DprocessDependencyManagement=true
```

For each dependency reporting an update, record `current_version`, `latest_version`, and
`update_type` (`major` | `minor` | `patch`) derived by comparing SemVer segments. Patch/minor
updates are "safe candidates"; major updates are flagged for manual review.

---

## Step 5 — License scan

```bash
mvn -q org.codehaus.mojo:license-maven-plugin:aggregate-third-party-report
```

Parse the generated `THIRD-PARTY.txt`. Classify each dependency license against the policy:

| Category | Examples | Status |
|---|---|---|
| Allowed | Apache-2.0, MIT, BSD-2/3, EPL-2.0 | `OK` |
| Review | LGPL, MPL-2.0, CDDL | `WARN` |
| Denied | GPL-3.0, AGPL-3.0, "No license", "Unknown" | `VIOLATION` |

---

## Run the scan goals efficiently

Steps 2–5 are independent of each other — do not run them back-to-back. To minimise wall-clock:

- **Parallelise.** Launch `dependency:tree`, `dependency-check:check`,
  `versions:display-dependency-updates`, and the license report **concurrently** (background jobs)
  and join, instead of four sequential JVM starts. Total time ≈ the slowest goal, not the sum.
- **Resolve once, then go offline.** Run `dependency:tree` first to populate the local repo, then add
  `-o` (offline) to the version and license goals so they don't re-hit the network.
- **Skip what the score doesn't need.** Only the CVE scan feeds the Stage 2 risk score. When the caller
  needs a *score only* (not the full report), you may skip the outdated and license goals entirely.
- **Reuse the warm NVD DB + API key** for the CVE scan (see Step 3) — the largest single saving.

> Re-scan avoidance: if a current `depscan-report.json` already exists and `pom.xml` is unchanged,
> skip this skill and hand the existing report straight to Stage 2.

---

## Step 6 — Normalized report

Merge all findings into `depscan-report.json`:

```json
{
  "project": "<artifactId>",
  "scanned_at": "<ISO-8601, supplied by caller>",
  "source_sha": "<git rev-parse HEAD of the scanned tree>",
  "dependency_count": 0,
  "findings": [
    {
      "coordinate": "com.example:lib:1.2.3",
      "scope": "compile",
      "vulnerable": true,
      "cves": [{ "cve": "CVE-2024-1234", "cvss_score": 9.8, "severity": "CRITICAL", "fix_version": "1.2.5" }],
      "outdated": { "latest_version": "1.4.0", "update_type": "minor" },
      "license": { "name": "GPL-3.0", "status": "VIOLATION" }
    }
  ],
  "summary": { "critical": 0, "high": 0, "medium": 0, "low": 0, "outdated": 0, "license_violations": 0 }
}
```

> Do not fabricate a timestamp — `Date.now()`/`new Date()` are not reliable here. The caller passes
> `scanned_at`; if absent, leave it `null`.
>
> **Provenance for reuse:** stamp `source_sha` with `git rev-parse HEAD` of the scanned tree.
> Downstream stages (Stage 2 risk scoring, Stage 4 gate) treat this report as **fresh and reusable** when
> `source_sha` matches the current HEAD and `pom.xml` is unmodified — so the expensive OWASP scan
> runs **once** and is reused instead of re-run. If `git` is unavailable, leave `source_sha` `null`
> (downstream then re-scans to be safe).

---

## Output

Report to the user:
- Dependency count scanned
- Counts by severity (CRITICAL / HIGH / MEDIUM / LOW)
- Outdated count (safe vs. major)
- License violations
- Path to `depscan-report.json`

Hand `depscan-report.json` to the **Risk Scoring Agent** (Stage 2) for prioritization.

### Professional PDF (for humans / PR review)
Also emit a human-readable **`CVE-Report.md`** (title block + summary counts + CVE table with
severity badges + supply-chain alerts) and render it to **`depscan-reports/CVE-Report.pdf`** using
the shared stylesheet — see `templates/report/RENDER.md`:
```bash
npx --yes md-to-pdf --stylesheet templates/report/report.css \
  --pdf-options '{"format":"A4","margin":"18mm","printBackground":true}' CVE-Report.md
```
Keep the `.json` (machines), `.md` (diffs) and `.pdf` (humans) together under `depscan-reports/`.
