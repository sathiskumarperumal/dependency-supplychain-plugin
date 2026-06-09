---
name: depscan-audit-trail
description: This skill should be used when aggregating the outputs of the dependency & supply-chain pipeline into a single dependency health report and preparing a live demonstration. Covers collecting all per-stage reports (scan, risk score, supply-chain audit, remediation PRs, merge-gate verdicts), computing an overall health score and trend, rendering a Markdown/HTML report, and scripting the end-to-end demo flow: vulnerable project → CVEs detected → scored → fixed → PRs merged. Activates when a user asks for a dependency health report, an audit summary, or demo preparation.
---

# Stage 5 — Audit Trail & Demo Readiness

## Overview

Closes the loop. Aggregates every artifact the pipeline produced into one **dependency health
report** that an engineering lead or auditor can read in two minutes, and scripts the **live demo**
that walks a vulnerable project from detection to merged fix.

---

## Step 1 — Collect the evidence

Gather all reports produced across the run (some may be absent — note which):

| Source | File | Stage |
|---|---|---|
| Dependency scan | `depscan-report.json` | 1 |
| Risk score | `depscan-risk-report.json` | 2 |
| Remediation PRs | from GitHub MCP (open/merged fix PRs) | 3 |
| Supply-chain audit | `depscan-supplychain-audit.json` | 4 (gate component) |
| Merge-gate verdicts | PR reviews / `depscan-merge-validation` output | 4 |

For PRs and Jira, pull live state via the GitHub and Jira MCP tools so the report reflects reality
at render time, not a stale snapshot.

---

## Step 2 — Compute the health score

A single 0–100 score per project (higher = healthier):

```
start at 100
- 15 per unresolved CRITICAL CVE
-  8 per unresolved HIGH CVE
-  2 per unresolved MEDIUM CVE
- 10 per supply-chain BLOCK finding (untrusted source / typosquat / denied license)
-  3 per outdated major-version dependency
floor at 0
```

| Score | Grade |
|---|---|
| 90–100 | A — healthy |
| 75–89 | B — minor issues |
| 50–74 | C — needs attention |
| < 50 | D — high risk |

Also report the **trend** vs. the previous run if a prior report exists (CVEs fixed, score delta,
PRs merged).

---

## Step 3 — Render the health report

Write `dependency-health-report.md` (and optionally HTML):

```
# Dependency Health Report — <project>
Generated: <ISO timestamp supplied by caller>   |   Health Score: 82 / 100 (Grade B)

## Executive Summary
- <n> dependencies scanned, <c> CRITICAL / <h> HIGH CVEs found, <f> fixed via auto-PR
- Supply-chain: <verdict> (<k> blocking findings)
- Gate outcome on latest PR: MERGE/BLOCK

## Top Risks (ranked)
| Coordinate | Risk | Band | Top CVE | Status |
|------------|------|------|---------|--------|

## Remediation Activity
| Dependency | old → new | CVEs cleared | PR | Merged? |

## Supply-Chain Findings
| Type | Coordinate | Detail | Action |

## Tests
- Tests: <passed>/<total>

## Trend vs. Previous Run
- Health score: <prev> → <now> (Δ)
- CVEs resolved this cycle: <n>

## Appendix — Full Findings
<link or embed of per-day JSON reports>
```

> Use the caller-supplied timestamp; do not invent one.

---

## Step 4 — Demo script (live readiness)

Prepare the canonical demo narrative and verify each beat runs cleanly beforehand:

1. **Show a vulnerable project** — open its `pom.xml`; highlight a known-bad dependency.
2. **Detect** — run the Stage 1 scan; CVEs appear with severities. *(`/risk_scoring_agent <repo>`)*
3. **Score** — show the ranked risk report; the worst dependency floats to the top with rationale.
4. **Fix** — run Stage 3 auto-remediation; an auto-PR opens with changelog + CVE fix details.
5. **Gate & merge** — run `/pr_validation_agent <PR>`; gate passes; PR merges.
6. **Prove** — re-render this health report; score jumps, CVE count drops, trend shows the fix.

Provide a **rollback note** (how to reset the demo repo) and a **pre-flight checklist** (tools on
PATH, MCP credentials valid, demo repo at known commit) so the demo is repeatable.

---

## Output

- `dependency-health-report.md` (+ optional HTML)
- Health score, grade, and trend
- The verified demo script with pre-flight checklist
- A one-paragraph "state of supply-chain hygiene" suitable for a stakeholder update
