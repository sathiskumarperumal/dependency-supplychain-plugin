---
name: depscan-merge-validation
description: This skill should be used when deciding whether a Java/Maven pull request may be merged based on the dependency & supply-chain pipeline results. Defines the merge gate — mvn test must pass, OWASP Dependency-Check and Grype must report zero unresolved CRITICAL/HIGH CVEs, and the supply-chain audit must not BLOCK. Provides the exact thresholds, the aggregate decision logic, and the merge/block evidence templates. Activates when the PR Validation Agent needs the gate ruleset, or when a user asks what conditions must pass before a dependency PR is merged.
---

# Stage 4 — Merge Validation (The Gate Ruleset)

## Overview

The decision table the **PR Validation Agent** enforces. It aggregates the outputs of every prior
stage into a single binary verdict: **PASS** (ready for human merge) or **BLOCK** (with reasons). The
gate never merges automatically — a human approves and merges. This skill is the policy;
the agent is the executor.

> **Scope:** this is a dependency & supply-chain gate. Code-quality metrics such as **line coverage
> are out of scope here** — they are owned by the separate code-quality gate (SonarQube / the Java
> Dev quality agents), not by this pipeline.

---

## The three gate checks

| # | Check | Command / source | Pass condition |
|---|---|---|---|
| 1 | Unit tests | `mvn -q test` | Build green, **0 test failures, 0 errors** |
| 2 | Known-CVE scan | OWASP Dependency-Check (Stage 1 report) | **0 unresolved CRITICAL, 0 unresolved HIGH** |
| 3 | Supply-chain audit | Grype + supply-chain audit | audit verdict ≠ `BLOCK` |

All three checks must pass. Any failure → `BLOCK`.

> **Execution efficiency (does not change the verdict):** build the project **once**
> (`mvn -q test package`) — that single reactor run produces the surefire reports (Check 1) and the
> packaged artifact for the SBOM (Check 3). Then run Checks 2–3 **in parallel** and aggregate. Reuse
> warm scanner DBs (OWASP `-DautoUpdate=false` + `NVD_API_KEY`; Grype `GRYPE_DB_AUTO_UPDATE=false`)
> and any fresh Stage 1 report / supply-chain audit report for this head SHA. Never early-exit —
> every failing check must be enumerated.

---

## Check 1 — Tests

```bash
mvn -q test
```

Parse `target/surefire-reports/*.xml`: sum `tests`, `failures`, `errors`, `skipped`.

| Condition | Result |
|---|---|
| `failures == 0 && errors == 0` | `PASS` |
| any failure or error | `FAIL` — list failing test names |
| build does not compile | `FAIL` — report compile error |

---

## Report freshness (reuse, don't re-run)

A report from an earlier stage is **fresh** — and must be reused instead of regenerated — when the
file exists, its `source_sha` equals the current `git rev-parse HEAD`, and `pom.xml` is unmodified.
Checks 2 and 3 below reuse the fresh Stage 1 report / supply-chain audit report; they re-run only
when the report is missing or stale. This is what keeps OWASP Dependency-Check and Grype to **one**
execution per run.

---

## Check 2 — OWASP Dependency-Check (zero-tolerance)

**Reuse the fresh Stage 1 `depscan-report.json`** if present (see freshness rule above); otherwise
run it. "Unresolved" = a CVE for which the dependency has **not** been bumped to a fixed version.

| Severity | Tolerance |
|---|---|
| CRITICAL | 0 |
| HIGH | 0 |
| MEDIUM | logged, non-blocking |
| LOW | ignored |

Any unresolved CRITICAL or HIGH → `FAIL`, with the CVE list and available fix versions.

---

## Check 3 — Supply-Chain Audit (Grype)

**Reuse the fresh `depscan-supplychain-audit.json`** if present (freshness rule above); otherwise run
`skills/depscan-supplychain-audit/SKILL.md`. Map its verdict directly:

| Audit verdict | Check result |
|---|---|
| `ALLOW` | `PASS` |
| `WARN` | `PASS` (warnings surfaced in evidence, do not block) |
| `BLOCK` | `FAIL` — include blocking findings |

---

## Aggregate decision

```
gate = PASS if (check1 == PASS and check2 == PASS and check3 == PASS)
       else BLOCK
```

> **Human-in-the-loop — no auto-merge.** A `PASS` verdict means the PR is *ready for merge*; it does
> **not** merge. The gate posts the report and a human reviewer approves and performs the merge.
> The agent never calls the merge API on a pass.

### PASS evidence (post as PR review COMMENT + Jira comment — awaiting human approval)

```
✅ Dependency & Supply-Chain Gate — PASSED (ready for human review)

| Check | Result | Detail |
|-------|--------|--------|
| Tests | ✅ PASS | <n> passed, 0 failed |
| OWASP CVE | ✅ PASS | 0 CRITICAL, 0 HIGH unresolved |
| Supply-Chain | ✅ PASS | ALLOW (<w> warnings) |

Verdict: PASS — gate cleared. Awaiting human approval to merge (no auto-merge).
```

### BLOCK evidence

```
❌ Dependency & Supply-Chain Gate — BLOCKED

| Check | Result | Reason |
|-------|--------|--------|
| Tests | ❌ FAIL | <failing tests> |
| OWASP CVE | ❌ FAIL | CVE-2024-1234 (CRITICAL, fix 1.2.5) |
| Supply-Chain | ✅ PASS | ALLOW |

Verdict: BLOCK — resolve the items above and re-run.
Required actions:
- Upgrade <artifactId> to <fix_version> (see Auto-Remediation)
```

Always enumerate **every** failing check, not just the first — a single pass to a green gate beats
iterative re-runs.
