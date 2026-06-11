---
description: Orchestrate the full dependency & supply-chain pipeline end-to-end in one run, against a repo from ANY Git host (GitHub, GitLab, Bitbucket, self-hosted). Mode `full` = Stage 1 scan → Stage 2 risk score → Stage 3 auto-remediation (one consolidated PR/MR) → Stage 4 merge gate. Mode `gate-only` = run just the Stage 4 gate on an existing PR/MR. Never auto-merges — posts an approval-ready verdict for a human. Single entry point that schedulers and CI call.
argument-hint: <repo-path-or-Git-URL> [--mode full|gate-only] [--pr <number>] [jira-id]
allowed-tools: [Bash, Read, Write, Edit, Glob, Grep, TodoWrite, Agent, mcp__github, mcp__jira]
---

# Depscan Pipeline — Orchestrator

Single entry point that runs the dependency & supply-chain stages in order. Triggers (a scheduled
routine, the GitHub Actions workflow, or a human) all call **this** command — they never re-encode
the sequence.

## Parse arguments (from `$ARGUMENTS`)
- **target** — first positional: a local repo path **or** a Git URL/SSH from **any host**
  (GitHub, GitLab, Bitbucket, self-hosted). Required for `full`.
- **`--mode`** — `full` (default) or `gate-only`.
- **`--pr <number>`** — the PR/MR to gate. Required for `gate-only`; in `full` it is the PR/MR opened
  in Stage 3.
- **jira-id** — optional Jira key for audit linkage.

> If `--mode` is omitted: choose `gate-only` when `--pr` is supplied, otherwise `full`.

## Execution context (single working tree)
The repo is checked out **once** here with plain `git` (any host); every stage runs inside that same
working tree and on the relevant PR/MR. Derive `owner/repo` from `git remote get-url origin`. Do not
re-clone between stages.

## Provider detection & publishing adapter
The scan / score / remediate / push / report steps are **host-agnostic** (plain `git` + Maven +
scanners). Only three operations are provider-specific — route them through this adapter. Detect the
provider from the `origin` host:

| Host | Provider |
|---|---|
| `github.com` / GitHub Enterprise | **github** |
| `gitlab.com` / self-hosted GitLab | **gitlab** |
| `bitbucket.org` | **bitbucket** |
| anything else | **generic** |

| Operation | github | gitlab | bitbucket | generic / unknown |
|---|---|---|---|---|
| Open PR/MR | `gh` (or GitHub MCP) | `glab mr create` / GitLab MR API | Bitbucket REST | **push branch** + print "open MR at `<compare-url>`" |
| Post gate verdict | PR review (`COMMENT`/`REQUEST_CHANGES`) | MR note | PR comment | write `depscan-verdict.md` |
| Open tracking issue | issues API | issues API | issues API | append to `depscan-verdict.md` |

**Credentials (token from env/secret, pick the one matching the host):** `GITHUB_TOKEN` ·
`GITLAB_TOKEN` (+ `CI_SERVER_URL` for self-hosted) · `BITBUCKET_TOKEN`. In CI the interactive MCP
servers may be absent — use the provider CLI / REST instead; the logic is identical.

> **Graceful degradation — never hard-fail on the host.** If the provider is unknown or its CLI/token
> is missing, still clone → scan → score → remediate → **push the fix branch** → emit
> `depscan-reports/` + `depscan-verdict.md`, then print the manual "open the MR here" URL. The
> security value is delivered regardless of host.

---

## Mode: `full`  (drift detection / fresh repo)

Run the stages in order, stopping at the human-merge boundary:

1. **Checkout (once).** Clone/checkout the target into the working tree. Record the head SHA.
2. **Stage 1–2 — Scan + Risk score.** Launch the `risk_scoring_agent` against the working tree. It
   runs the Stage 1 dependency scan (writing `depscan-report.json`, stamped with `source_sha`) and
   produces the ranked `depscan-risk-report.json`.
   > **CI runners start empty — always (re)generate.** Only reuse a prior report if the file is
   > physically present in *this* working tree AND its `source_sha` matches the current head SHA.
   > Never assume a previous run's files persist and never "reuse" a report you cannot read off
   > disk right now. The JSON files (`depscan-report.json`, `depscan-risk-report.json`, and the
   > Stage-4 `depscan-supplychain-audit.json` + `target/sbom.cdx.json`) MUST exist at the repo root
   > at the end of the run so CI can upload them as artifacts.
3. **Stage 3 — Auto-remediation.** Apply `skills/depscan-auto-remediation/SKILL.md`: batch all safe
   fixes onto the single branch `fix/depscan-auto-remediation`, build once (`mvn -q test package`),
   re-scan to confirm CVEs cleared, and open/update **one consolidated PR/MR via the publishing
   adapter** (GitHub PR · GitLab MR · else push + manual-MR link).
   > **On GitHub you MUST actually open the PR — do not stop at a compare URL.** A token is present
   > (`GITHUB_TOKEN` feeds the github MCP in CI), so call `mcp__github__create_pull_request`
   > directly; if that errors, fall back to `gh pr create` (preinstalled on GitHub runners). Only
   > emit a manual `<compare-url>` when the host is genuinely non-GitHub or no token exists. The Actions
   > `GITHUB_TOKEN` *can* create same-repo PRs — the "Actions token cannot create PRs" assumption is
   > false; the only caveat is a `GITHUB_TOKEN`-opened PR won't re-trigger the `pull_request` gate
   > workflow (not needed here — `full` runs the gate inline).
   - **All tracking lives on the PR.** The consolidated PR body carries the fix table, the CVEs
     cleared, the **Stage 4 gate verdict**, links to the `depscan-reports/` PDFs, and references to
     every `MAJOR_REVIEW` / `BUILD_BROKEN` / `INEFFECTIVE` follow-up issue (open those with
     `mcp__github__create_issue` and link them back in the PR). Post the gate verdict as a PR review
     via `mcp__github__create_pull_request_review`.
   - **Always finish a `full` run with exactly one OPEN PR — never stop after Stage 1–2.** Even when
     the branch already exists or the finding set is large, proceed through Stage 3 and Stage 4.
     Decide PR state by **drift**, not by branch existence:
     - `git fetch origin main` then diff `origin/main...fix/depscan-auto-remediation`. **No diff** →
       `main` already contains the fixes → report "no drift — no PR" and stop.
     - **Diff present + an OPEN PR already exists** for the branch → push the freshly rebuilt branch
       to it (update in place, no duplicate).
     - **Diff present + NO open PR** (first run, or the previous PR was closed/merged) → open a
       **new** PR with `mcp__github__create_pull_request`. A closed prior PR does **not** count as
       "already exists" — check PR **state** via `mcp__github__list_pull_requests` (state=open) and
       open a fresh one if none are open.
4. **Stage 4 — Merge gate.** Launch the `pr_validation_agent` on the resulting PR (`gate-only`
   behaviour): one build, then the three checks (tests, OWASP CVE, supply-chain audit), reusing the
   fresh Stage 1 / supply-chain reports. Post the PASS/BLOCK evidence **via the publishing adapter**
   (PR review · MR note · else `depscan-verdict.md`), and to Jira if a key was given.
5. **Stop for human.** Do **not** merge. A PASS verdict means "ready for human review"; a human
   approves and merges.

---

## Mode: `gate-only`  (validate an existing PR)

1. **Checkout** the PR head in the working tree; record the head SHA.
2. **Stage 4 — Merge gate.** Launch the `pr_validation_agent` with `pr_number = --pr`. It runs the
   single build + three checks and posts the PASS/BLOCK verdict **via the publishing adapter** (PR
   review · MR note · else `depscan-verdict.md`). Never merges.

Use this on `pull_request` / merge-request events — it skips scan/score/remediation and only renders
the gate verdict for the PR/MR that triggered it.

---

## Governance (both modes)
- **Never auto-merge.** The gate posts an approval-ready report; a human performs the merge
  (enforced in CI by branch protection / required reviews).
- **Never drop work silently.** `MAJOR_REVIEW`, `BUILD_BROKEN`, and `INEFFECTIVE` items are raised as
  tracking issues, not folded into the PR.

## Reports (professional PDFs) — required every run
Every run MUST write the three reports as **both `.md` and a rendered `.pdf`** into
**`depscan-reports/`**: `CVE-Report`, `Risk-Scoring-Report`, and the final `Audit-Trail-Report`
(produced by the `depscan-audit-trail` skill — it is the consolidated final report, not optional).
Render each `.md → .pdf` with `md-to-pdf` (use `npx md-to-pdf` if not installed) + the shared
stylesheet (`templates/report/report.css`); see `templates/report/RENDER.md`. Do **not** skip
rendering because an older PDF exists — regenerate from this run's markdown.

In `full` mode, `git add depscan-reports/ && git commit` these onto the fix branch **before opening
the PR**, so they ride in the consolidated PR and CI uploads them as artifacts. **Always commit this
run's freshly rendered PDFs/MD even if the branch already carries older copies — overwrite them so
the PR never shows stale reports** (a `git diff --quiet -- depscan-reports/` that reports no change
means the render did not actually run — re-render). The root JSON intermediates stay at the repo
root (see Stage 1–2) for the artifact step; the human-readable PDFs live in `depscan-reports/`.

## Final output
Report: mode, target/PR, per-stage outcome (scan counts → risk bands → remediation PR link → gate
verdict), the `depscan-reports/` PDF paths, and the ordered human follow-ups. In `full` mode with no
new findings, report "no drift detected".