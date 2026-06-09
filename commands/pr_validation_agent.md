---
description: PR Validation Agent — Run the full dependency & supply-chain merge gate on a PR (mvn test → OWASP Dependency-Check → Grype supply-chain audit). Ready for human merge if all pass, otherwise blocks with structured reasons and posts evidence to GitHub and Jira.
argument-hint: <PR-NUMBER> [JIRA-TICKET-ID]
allowed-tools: [Bash, Read, Write, Edit, Glob, Grep, TodoWrite]
---

# PR Validation Agent — Merge Gate

PR: **$ARGUMENTS**

Launch the `pr_validation_agent` to run the complete dependency & supply-chain merge gate on PR
**$ARGUMENTS**.

Pass `pr_number` (and `ticket_id` if a Jira id is included) to the agent. Report the per-stage
results, the final MERGE/BLOCK verdict, and either the merge commit SHA or the ordered list of
required actions when done.
