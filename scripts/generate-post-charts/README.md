# Blog post charts from Datadog

Generates PNG charts under `static/images/posts/` for the WordPress ops posts. Data comes from the Datadog Metrics API (Traefik DogStatsD) and, when an Application Key is set, log aggregates.

## Prerequisites

```bash
python3 -m venv scripts/generate-post-charts/.venv
scripts/generate-post-charts/.venv/bin/pip install -r scripts/generate-post-charts/requirements.txt
```

## Credentials

Export keys from your local `.cursor/mcp.json` or operator env:

```bash
export DD_API_KEY='...'
export DD_APPLICATION_KEY='...'   # optional; improves log-error bar chart
export DD_SITE='datadoghq.eu'
```

## Run

```bash
./scripts/generate-post-charts/run.sh
```

Or directly:

```bash
scripts/generate-post-charts/.venv/bin/python scripts/generate-post-charts/generate_post_charts.py
```

Re-run after incidents or before publishing updates if you want fresh numbers. Chart time windows are fixed in the script to match the July 2026 posts (APO purge ~2026-07-01).

## Output

| Chart | Post slug |
|-------|-----------|
| `triage-signal-comparison.png` | `wordpress-incident-triage-apm-not-logs` |
| `imgproxy-403-vs-404.png` | triage + `stale-cloudflare-apo-imgproxy-r2-migration` |
| `admin-vs-public-p95.png` | `wordpress-opcache-full-block-editor-slow` |
| `opcache-before-after.png` | `wordpress-opcache-full-block-editor-slow` (static in-container values) |
