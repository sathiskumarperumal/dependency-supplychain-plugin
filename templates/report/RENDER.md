# Rendering reports to professional PDF

All three human-readable reports (CVE, Risk Scoring, Audit-Trail) are written as **Markdown** and
converted to **PDF** with a shared professional stylesheet via **md-to-pdf** (headless Chromium).
This runs anywhere Node is available — including the GitHub Actions runner ("remotely").

## One render command (per report)

```bash
# Stylesheet path MUST be correct or the PDF renders unstyled. Use $DEPSCAN_REPORT_CSS if the caller
# set it; otherwise the plugin's own copy. In CI the plugin is checked out at .depscan-plugin/, so the
# absolute path is "$PWD/.depscan-plugin/templates/report/report.css".
CSS="${DEPSCAN_REPORT_CSS:-$PWD/templates/report/report.css}"

npx --yes md-to-pdf \
  --stylesheet "$CSS" \
  --launch-options '{"args":["--no-sandbox","--disable-setuid-sandbox"]}' \
  --pdf-options '{"format":"A4","margin":{"top":"18mm","bottom":"20mm","left":"16mm","right":"16mm"},"printBackground":true}' \
  --document-title "Dependency & Supply-Chain Report" \
  <report>.md
# produces <report>.pdf next to the .md
```

> **CI needs `--launch-options '{"args":["--no-sandbox"]}'`.** On GitHub-hosted runners headless
> Chromium fails with "Failed to launch the browser process" unless the sandbox is disabled.

> **`printBackground:true` is MANDATORY.** Without it headless Chromium drops every background colour,
> so the blue title banner, the severity badge pills, and the blue table headers all render blank —
> the PDF looks like plain text. A missing/wrong `--stylesheet` path has the same effect: verify the
> CSS file exists before rendering.
>
> **In CI you do not render manually** — the GitHub Actions workflow has a dedicated
> "Render report PDFs (styled)" step that renders every `depscan-reports/*.md` with the correct
> stylesheet and commits the PDFs onto the fix branch. The skills only need to produce the `.md`.

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
