---
description: Risk Scoring Agent — Scan a Java/Maven repo (or load an existing depscan-report.json), confirm CVSS scores against the NVD, and score every dependency by CVE severity, exposure, and business criticality into a ranked remediation backlog.
argument-hint: <path-to-java-repo | path-to-depscan-report.json>
allowed-tools: [Bash, Read, Write, Edit, Glob, Grep, TodoWrite]
---

# Risk Scoring Agent

Target: **$ARGUMENTS**

Launch the `risk_scoring_agent` to score every dependency in **$ARGUMENTS** by risk.

If **$ARGUMENTS** is a repository path, run the Stage 1 dependency scan first; if it is a
`depscan-report.json`, load it directly. Pass `repo_path` or `report_path` accordingly and report
the ranked risk table and the path to `depscan-risk-report.json` when done.
