# Rendering reports to professional PDF

All three human-readable reports (CVE, Risk Scoring, Audit-Trail) are written as **Markdown** and
converted to **PDF** with a shared professional stylesheet via **md-to-pdf** (headless Chromium).
This runs anywhere Node is available — including the GitHub Actions runner ("remotely").

## One render command (per report)

```bash
npx --yes md-to-pdf \
  --stylesheet "<plugin>/templates/report/report.css" \
  --pdf-options '{"format":"A4","margin":{"top":"18mm","bottom":"20mm","left":"16mm","right":"16mm"},"printBackground":true}' \
  --document-title "Dependency & Supply-Chain Report" \
  <report>.md
# produces <report>.pdf next to the .md
```

## Output layout (committed on the fix branch for the reviewer)

```
depscan-reports/
  CVE-Report.pdf            # Stage 1 — dependency / known-CVE scan
  Risk-Scoring-Report.pdf   # Stage 2 — weighted risk ranking + backlog
  Audit-Trail-Report.pdf    # Stage 5 — health score, trend, remediation, gate
  README.md                 # one-line description of each
```

## Notes
- **Severity badges:** in the Markdown, wrap the level in a span so the CSS colours it, e.g.
  `<span class="badge crit">CRITICAL</span>`, `… high`, `… med`, `… low`, `… ok`.
- **Title block:** the first `# H1` becomes the banner; the paragraph immediately under it is the
  metadata line (project · generated · scope) and is styled as a subtitle.
- **CI caching:** cache `~/.cache/puppeteer` so Chromium isn't re-downloaded every run.
- Keep the `.md` and `.json` alongside the PDF — JSON for machines, MD for diffs, PDF for humans.
