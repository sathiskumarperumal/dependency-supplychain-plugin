---
name: depscan-auto-remediation
description: This skill should be used when safely upgrading vulnerable or outdated Maven dependencies and raising an auto-generated pull request. Covers selecting the minimal safe version bump that clears a CVE, editing pom.xml (dependencies and dependencyManagement), applying all safe fixes together on a single branch, verifying the build and tests still pass, generating a combined changelog with CVE fix details, and opening one consolidated pull request via the GitHub MCP. Activates when a user asks to fix, upgrade, or remediate vulnerable dependencies, or to auto-generate dependency-bump PRs.
---

# Stage 3 — Auto-Remediation (Safe Maven Upgrades → one consolidated PR)

## Overview

Turns the ranked risk report into a **safe, verified, reviewable** set of dependency fixes. The
guiding rule: *the smallest change that clears the vulnerability*. **All safe remediations are
applied to a single branch and raised as one consolidated pull request** — each fix is still
selected, applied, and tracked individually, but the reviewer gets one PR that takes the project
from vulnerable to clean. Items that cannot be auto-applied safely (`MAJOR_REVIEW`,
`BUILD_BROKEN`, `INEFFECTIVE`) are split out as separate follow-ups and never silently dropped.

## Input
- `depscan-risk-report.json` (Stage 2), or `depscan-report.json` (Stage 1)
- The **Stage 1 working tree** — this skill runs inside the repo already checked out by the entry
  agent (Stage 2); it does **not** take a repo path or re-clone. It derives `owner/repo` from
  `git remote get-url origin` and raises the fix PR in that tree.

---

## Step 1 — Select remediation candidates

From the risk report, take every dependency that has a safe, auto-applicable fix, ordered by risk
band (CRITICAL → HIGH → MEDIUM → LOW). Two kinds of candidate go into the batch:

- **Version bumps** — dependencies where a `fix_version` exists.
- **Supply-chain removals** — typosquatted / unresolvable / malicious coordinates whose action is
  "remove" (no `fix_version`). These belong in the consolidated PR too.

For each version bump, choose the **minimal safe target version**:

| Available fix | Preferred target |
|---|---|
| Patch release clears the CVE | the patch (e.g. `1.2.3 → 1.2.5`) |
| Only a minor release clears it | the minor (e.g. `1.2.3 → 1.3.0`) |
| Only a major release clears it | flag `MAJOR_REVIEW` — do **not** auto-bump; open an issue/PR draft instead |

Never jump more versions than necessary. Prefer the lowest version that is both non-vulnerable and
stable (no `-SNAPSHOT`, `-RC`, `-alpha`, `-beta`). A fix that only changes a flagged condition
without resolving it (e.g. a version bump that leaves a denied license unchanged) is **not** a safe
candidate — route it to human follow-up instead.

---

## Step 2 — One consolidated remediation branch

Create a **single** branch off the repo default for the entire batch:

```bash
git checkout -b fix/depscan-auto-remediation
```

All fixes in this run land on this one branch. Do **not** create a branch per dependency.

---

## Step 3 — Apply all POM edits

Apply every selected candidate to the same `pom.xml`, in this order:

1. **Removals first** — delete typosquatted / unresolvable coordinates. These often block
   dependency resolution outright, so removing them first lets the verification build run.
2. **Version bumps next** — for each:
   - **Direct dependency**: update the `<version>` of the matching `<dependency>`.
   - **Managed version / property**: prefer bumping the `<properties>` version property or the
     `<dependencyManagement>` entry over pinning inline.
   - **Transitive-only**: add or update a `<dependencyManagement>` entry to force the safe version
     (do not add a new top-level dependency just to pin a transitive one unless required).
   - **Lockstep families** (e.g. `log4j-api` + `log4j-core`, or a BOM): move all members together.

Use Edit for precise, minimal diffs. Do not reformat unrelated XML.

---

## Step 4 — Verify once, isolate failures

After all edits are applied, verify the **whole batch** once. Build and tests must pass before the
PR is raised:

```bash
mvn -q -DskipTests=false clean verify
```

Then re-scan to confirm the targeted CVEs are actually cleared:

```bash
mvn org.owasp:dependency-check-maven:check -Dformat=JSON -DoutputDirectory=target/depscan-verify
```

| Result | Action |
|---|---|
| Build passes **and** all targeted CVEs gone | proceed to PR with the full batch |
| Build fails | **bisect** — drop the single offending fix, mark it `BUILD_BROKEN`, try its next-higher safe version once; if still broken, leave it out and re-verify the rest so one bad bump never sinks the whole PR |
| A specific CVE still present | mark that dependency `INEFFECTIVE`, remove it from the batch, re-verify |

> **Pre-existing gate caveat:** if `verify` fails on a check unrelated to the dependency changes
> (e.g. a coverage or style gate in the target repo that was already failing before this run),
> report it honestly but do **not** attribute it to a bump. Use `mvn clean test` to confirm the
> bumps themselves compile and pass tests, and note the pre-existing gate separately.

---

## Step 5 — Combined changelog summary

Build **one** changelog covering every fix that made it into the batch. For each included item
capture:
- Old → new version (or "removed" for supply-chain removals)
- CVE(s) resolved with CVSS and a one-line description
- Notable breaking changes between versions (from release notes, if any)

Then record the batch-level verification status: build/tests result and whether the re-scan is
clean.

---

## Step 6 — Raise ONE consolidated PR (GitHub MCP)

Commit each fix as its own commit on the single branch (granular history, easy per-fix review),
then push once:

```bash
git add -A
git commit -m "fix(deps): bump <artifactId> <old> -> <new> (resolves <CVE>)"   # one per fix
# ...repeat per fix (and a "remove typosquat" commit for removals)...
git push -u origin fix/depscan-auto-remediation
```

Open a **single** PR with `mcp__github__create_pull_request` using this consolidated body template:

```
## Dependency Remediation — consolidated

Auto-applied safe fixes from the Stage 2 risk report. One PR takes this project from
vulnerable to clean; unsafe items are tracked separately (see below).

### Fixes in this PR
| Coordinate | old → new / action | Type | Risk band | CVEs cleared |
|-----------|--------------------|------|-----------|--------------|
| org.apache.logging.log4j:log4j-core | 2.14.1 → 2.17.1 | minor | HIGH | CVE-2021-44228, ... |
| com.example:bad-typosquat | REMOVE | removal | CRITICAL | n/a (supply-chain) |

### CVEs Resolved
| CVE | CVSS | Summary |
|-----|------|---------|
| CVE-2024-1234 | 9.8 | <one-line> |

### Changelog Highlights
- <notable changes / breaking notes across all included fixes>

### Verification
- [x] `mvn clean verify` passes (or `mvn clean test` + noted pre-existing gate)
- [x] OWASP Dependency-Check re-scan: targeted CVEs no longer present
- [ ] Reviewer: confirm no behavioral regression

### Not included (human follow-up)
- MAJOR_REVIEW: <coordinate> (major-version jump) → issue #N
- BUILD_BROKEN / INEFFECTIVE: <coordinate> + reason

> Auto-generated by the Dependency & Supply-Chain Plugin (Stage 3 — Auto-Remediation).
```

Infer `owner`/`repo` from `git remote get-url origin`. Base branch is the repo default unless told
otherwise.

---

## Output

A single consolidated PR link, plus a table of every remediation considered:
**Coordinate | old → new / action | CVEs cleared | build | included?**. List `MAJOR_REVIEW`,
`BUILD_BROKEN`, and `INEFFECTIVE` items separately for human follow-up (as issues or PR drafts) —
never fold them silently into the PR and never drop a candidate without recording why.
