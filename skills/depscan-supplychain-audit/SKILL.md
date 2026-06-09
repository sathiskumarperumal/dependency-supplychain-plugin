---
name: depscan-supplychain-audit
description: This skill should be used when auditing the software supply chain of a Java/Maven project on a pull request. Covers generating a CycloneDX SBOM with Syft, scanning it with Grype for known vulnerabilities, and detecting supply-chain risks the dependency scanner does not — typosquatting against known-good package names, untrusted/non-standard Maven repositories, and license-policy violations. Produces a block/allow decision per PR. Activates when a user asks to audit an SBOM, check for typosquatting or untrusted dependency sources, or gate a PR on supply-chain risk.
---

# Supply-Chain Audit (SBOM + Grype) — component of the Stage 4 merge gate

## Overview

Goes beyond "is this dependency vulnerable?" to "can I trust where this dependency came from?".
On every PR it generates an SBOM and blocks risky dependencies across four checks:

1. **SBOM vulnerability scan** — Grype against the CycloneDX SBOM.
2. **Typosquatting** — names that are suspiciously close to popular packages.
3. **Untrusted sources** — artifacts resolved from non-standard / non-allowlisted repositories.
4. **License violations** — denied licenses (cross-checks Stage 1, enforced here).

This skill is **not a standalone pipeline stage** — it runs as a component of the **Stage 4 merge
gate** (the PR Validation Agent), which invokes it on every PR alongside tests and the CVE scan. It
can also be run on its own for early supply-chain feedback before a PR exists.

---

## Prerequisites

| Tool | Check | Role |
|---|---|---|
| Syft | `syft version` | SBOM generation (CycloneDX) |
| Grype | `grype version` | SBOM vulnerability scan |
| Maven | `mvn -v` | resolve repositories & coordinates |

Both Syft and Grype can run via Docker (`anchore/syft`, `anchore/grype`) if not installed locally.

> **Performance:** keep Grype's vuln DB warm in the `depscan-grype-db` volume and disable the
> per-run download — `export GRYPE_DB_AUTO_UPDATE=false` and point `GRYPE_DB_CACHE_DIR` at that
> volume. Refresh it only on first use or on a schedule: `grype db update`. When this skill runs as
> part of the PR Validation Agent, the project is **already built** — do not rebuild.

---

## Step 1 — Generate the SBOM (Syft)

The SBOM needs resolved artifacts. **Reuse an existing build** — if `target/` already contains the
packaged jar/classes (e.g. the PR Validation Agent's single build pass already ran), skip the build
and go straight to Syft. Only build when invoked standalone with no prior build:

```bash
# only if target/ has no built artifacts yet:
mvn -q -o -DskipTests package   # -o (offline) once dependencies are resolved
syft dir:. -o cyclonedx-json=target/sbom.cdx.json
```

The SBOM is the single source of truth for every subsequent check — audit the SBOM, not the
network, so results are reproducible.

---

## Step 2 — Vulnerability scan (Grype)

```bash
GRYPE_DB_AUTO_UPDATE=false grype sbom:target/sbom.cdx.json -o json > target/grype-report.json
```

(`GRYPE_DB_AUTO_UPDATE=false` reuses the cached DB in `depscan-grype-db` and skips the per-run
download — the largest single saving in this stage.)

Extract from `matches[]`: `artifact.name`, `artifact.version`, `vulnerability.id`,
`vulnerability.severity`, `vulnerability.fix.versions`. Normalize severities to
`CRITICAL/HIGH/MEDIUM/LOW`. These feed the PR defect trace and the Stage 5 health report.

---

## Step 3 — Typosquatting detection

For each `groupId:artifactId` in the SBOM, compare the artifactId against a list of popular Java
package names (jackson-databind, slf4j-api, commons-lang3, guava, spring-core, log4j-core, etc.).

Flag as **suspected typosquat** when an artifact is *not* an exact match but is within
**Levenshtein distance ≤ 2** of a popular name (e.g. `jackson-databnd`, `commons-lang33`,
`slf4-api`), **or** shares the name of a popular library under a different, unrecognized `groupId`.

Record: `coordinate`, `nearest_known`, `distance`, `groupId_trusted` (bool).

> Distance match is a heuristic — flag for human review, never auto-block on typosquatting alone
> unless `groupId` is also untrusted (Step 4).

---

## Step 4 — Untrusted source detection

Resolve where each artifact came from:

```bash
mvn -q -o help:effective-settings
mvn -q -o dependency:list-repositories
```

(`-o` runs offline — the single build pass already resolved dependencies, so these introspection
goals need no network.)

Build the allowlist of trusted repositories (default):

```
Maven Central   https://repo.maven.apache.org/maven2
Maven Central   https://repo1.maven.org/maven2
Google Maven    https://dl.google.com/dl/android/maven2
Gradle Plugins  https://plugins.gradle.org/m2
<your private mirror / Nexus / Artifactory — add here>
```

Any repository **not** on the allowlist → every artifact resolved from it is flagged
`untrusted_source`. HTTP (non-HTTPS) repositories are always flagged.

---

## Step 5 — License enforcement

Re-use the license classification already in the **fresh Stage 1 `depscan-report.json`** (matching
`source_sha`) rather than re-deriving it; only re-run `skills/depscan-dependency-scanner/SKILL.md`
Step 5 if no fresh report exists. Here, unlike Stage 1, a `VIOLATION` (denied or unknown license) is a
**blocking** condition.

---

## Step 6 — Audit decision

Produce `depscan-supplychain-audit.json` and a block/allow verdict.

### Block policy (any one → `BLOCK`)

| Condition | Result |
|---|---|
| Grype CRITICAL CVE with available fix | `BLOCK` |
| Grype HIGH CVE with available fix | `BLOCK` |
| Suspected typosquat **and** untrusted `groupId` | `BLOCK` |
| Artifact from an untrusted / HTTP repository | `BLOCK` |
| Denied or unknown license | `BLOCK` |
| Suspected typosquat with trusted groupId (only) | `WARN` (manual review) |
| Grype MEDIUM/LOW | `WARN` |

```json
{
  "project": "<artifactId>",
  "source_sha": "<git rev-parse HEAD of the audited tree>",
  "verdict": "BLOCK",
  "blocking_findings": [
    { "type": "untrusted_source", "coordinate": "com.evil:lib:1.0", "detail": "resolved from http://random.repo" }
  ],
  "warnings": [],
  "counts": { "grype_critical": 0, "grype_high": 0, "typosquat": 0, "untrusted": 0, "license_violations": 0 }
}
```

---

## Output

Report the verdict (`BLOCK` / `WARN` / `ALLOW`), the blocking findings with reasons, and the path
to `depscan-supplychain-audit.json`. As a component of the **Stage 4 merge gate**, the **PR
Validation Agent** treats `BLOCK` as a hard merge stop.
