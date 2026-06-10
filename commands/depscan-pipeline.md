---
description: Orchestrate the full dependency & supply-chain pipeline end-to-end in one run. Mode `full` = Stage 1 scan → Stage 2 risk score → Stage 3 auto-remediation (one consolidated PR) → Stage 4 merge gate. Mode `gate-only` = run just the Stage 4 gate on an existing PR. Never auto-merges — posts an approval-ready verdict for a human. This is the single entry point that schedulers and the GitHub Actions workflow call.
argument-hint: <repo-path-or-URL> [--mode full|gate-only] [--pr <number>] [jira-id]
allowed-tools: [Bash, Read, Write, Edit, Glob, Grep, TodoWrite, Agent]
---

# Depscan Pipeline — Orchestrator

Single entry point that runs the dependency & supply-chain stages in order. Triggers (a scheduled
routine, the GitHub Actions workflow, or a human) all call **this** command — they never re-encode
the sequence.

## Parse arguments (from `$ARGUMENTS`)
- **target** — first positional: a repo path **or** Git URL/head. Required for `full`.
- **`--mode`** — `full` (default) or `gate-only`.
- **`--pr <number>`** — the PR to gate. Required for `gate-only`; in `full` it is the PR opened in
  Stage 3.
- **jira-id** — optional Jira key for audit linkage.

> If `--mode` is omitted: choose `gate-only` when `--pr` is supplied, otherwise `full`.

## Execution context (single working tree)
The repo is checked out **once** here; every stage runs inside that same working tree and on the
relevant PR. Derive `owner/repo` from `git remote get-url origin`. Do not re-clone between stages.

> **Headless / CI note:** when the interactive `github`/`jira` MCP servers are unavailable (cron,
> GitHub Actions), perform GitHub and Jira operations with the `gh` CLI / REST using the
> `GITHUB_TOKEN` (and a Jira API token) instead of the MCP tools. The logic is identical.

---

## Mode: `full`  (drift detection / fresh repo)

Run the stages in order, stopping at the human-merge boundary:

1. **Checkout (once).** Clone/checkout the target into the working tree. Record the head SHA.
2. **Stage 1–2 — Scan + Risk score.** Launch the `risk_scoring_agent` against the working tree. It
   runs the Stage 1 dependency scan (writing `depscan-report.json`, stamped with `source_sha`) and
   produces the ranked `depscan-risk-report.json`. Reuse a fresh report if one already exists for
   this SHA.
3. **Stage 3 — Auto-remediation.** Apply `skills/depscan-auto-remediation/SKILL.md`: batch all safe
   fixes onto the single branch `fix/depscan-auto-remediation`, build once (`mvn -q test package`),
   re-scan to confirm CVEs cleared, and open/update **one consolidated PR**. **Idempotency:** if that
   branch/PR already exists, push updates to it (do not open a duplicate); if there are no new
   fixable findings, stop and report "no drift — no PR".
4. **Stage 4 — Merge gate.** Launch the `pr_validation_agent` on the resulting PR (`gate-only`
   behaviour): one build, then the three checks (tests, OWASP CVE, supply-chain audit), reusing the
   fresh Stage 1 / supply-chain reports. Post the PASS/BLOCK evidence to the PR (and Jira if a key
   was given).
5. **Stop for human.** Do **not** merge. A PASS verdict means "ready for human review"; a human
   approves and merges.

---

## Mode: `gate-only`  (validate an existing PR)

1. **Checkout** the PR head in the working tree; record the head SHA.
2. **Stage 4 — Merge gate.** Launch the `pr_validation_agent` with `pr_number = --pr`. It runs the
   single build + three checks and posts the PASS/BLOCK review. Never merges.

Use this on `pull_request` events — it skips scan/score/remediation and only renders the gate verdict
for the PR that triggered it.

---

## Governance (both modes)
- **Never auto-merge.** The gate posts an approval-ready report; a human performs the merge
  (enforced in CI by branch protection / required reviews).
- **Never drop work silently.** `MAJOR_REVIEW`, `BUILD_BROKEN`, and `INEFFECTIVE` items are raised as
  tracking issues, not folded into the PR.

## Reports (professional PDFs)
Each run renders human-readable PDFs into **`depscan-reports/`** (CVE-Report, Risk-Scoring-Report,
Audit-Trail-Report) via `md-to-pdf` + the shared stylesheet (`templates/report/report.css`). In
`full` mode they are committed onto the fix branch so the PR reviewer can read them; see each
report skill and `templates/report/RENDER.md`.

## Final output
Report: mode, target/PR, per-stage outcome (scan counts → risk bands → remediation PR link → gate
verdict), the `depscan-reports/` PDF paths, and the ordered human follow-ups. In `full` mode with no
new findings, report "no drift detected".