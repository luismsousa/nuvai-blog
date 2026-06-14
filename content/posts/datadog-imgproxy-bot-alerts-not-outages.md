---
title: "When Datadog Alerts Are Bots, Not Outages (imgproxy srcset Noise)"
date: 2026-06-13T12:00:00Z
draft: false
description: "Overnight email floods from imgproxy 403 monitors flapping on malformed bot URLs — and how we tuned Datadog to alert on real outages only."
tags: ["Datadog", "WordPress", "imgproxy", "monitoring", "Traefik"]
---

Nothing wakes you up like a Datadog email at 03:00 — especially when the site is healthy, synthetics eventually pass, and the “incident” is a crawler requesting an entire `srcset` attribute as one imgproxy path.

That was our overnight alert pattern on [joyofexploringtheworld.com](https://joyofexploringtheworld.com/), using [imgproxy](https://imgproxy.net/) behind Traefik with signed URLs at a dedicated image subdomain (e.g. `img.example.com`).

## The alert pattern

Between roughly 22:00 and 09:00 UTC, monitors fired in cycles:

| Monitor | Approx. emails | Real user impact |
|---------|----------------|------------------|
| imgproxy HTTP 403 error rate (Traefik) | ~10 warn/trigger/recover cycles | None |
| imgproxy Invalid signature (log alert) | 2 | Same underlying noise |
| Synthetics HTTP health | 2 at 00:20 UTC | False positive — origin returned 200 internally |
| Backup downtime audit | 2 | Informational only |

No 502/503 spikes. No Apache worker alerts. No memory fatals. The site was fine; **monitor sensitivity** was not.

## What the imgproxy logs showed

Bots were requesting URLs like this (truncated):

```
/…/image.avif%201250w,%20https:/img.example.com/…/other-image.avif%20300w
```

That is not broken HTML from WordPress. Crawlers sometimes mash a full `srcset` string into a single `src` or path. imgproxy correctly returns **403 Invalid signature** — the path is not a valid signed URL.

Client IPs were scattered cloud hosts (typical VPS providers), consistent with SEO crawlers, not visitors.

## Why one bot burst became a dozen emails

Three tuning choices amplified noise:

1. **Warning threshold at 3%** — emails even below critical
2. **Two monitors** for the same condition (Traefik metric + log count)
3. **Recovery notifications** on every flap

With low overnight imgproxy volume, ~11 invalid-signature requests could cross 3% of traffic. Each crossing produced warn → triggered → recovered → repeat — **×2 monitors**.

Backup maintenance downtime (02:00–02:15 UTC) suppressed alerts briefly; imgproxy noise resumed at 02:38 when downtime ended — same bots, not backup-related.

## Synthetics false positive

The HTTP health check failed once from `aws:eu-west-1` at 00:20 UTC with `min_failure_duration: 0` — **one failed probe = immediate email**. Internal health checks on both WordPress containers returned 200 the whole time. Likely a transient Cloudflare or edge timeout on the homepage (5s limit).

## What we changed

### 1. One imgproxy monitor, critical only

Retired the log-based “Invalid signature” monitor (duplicate of the Traefik error-rate alert).

On the remaining metric alert:

- Removed the **warning** threshold — alert at critical (10%) only
- Raised volume floor: `clamp_min(..., 100)` so tiny bot bursts do not cross 10%
- `renotify_statuses: ["alert"]` — no recovery emails
- `renotify_interval: 240` (4 hours)

Example query shape:

```
sum(last_15m):sum:traefik.service.request.total{service:imgproxy_docker,code:403}.as_count()
  / clamp_min(sum:traefik.service.request.total{service:imgproxy_docker}.as_count(), 100) * 100 > 10
```

### 2. Harden synthetics

```json
"min_failure_duration": 300
```

Require **five minutes** of sustained failure before alerting. Single blips from one PoP should not page you.

### 3. Document the bot pattern in the monitor message

Future-you (and on-call agents) should see: “check for `%20` / comma in path — likely srcset bot, not origin HTML corruption.”

## Optional hardening (not yet deployed)

Reject obviously malformed paths at Traefik or imgproxy (comma, `%20` in path segment) with a cheap **400** before signature validation. That reduces log noise but is cosmetic — bots will still try weird URLs.

## Monitoring hygiene lessons

| Lesson | Detail |
|--------|--------|
| Low-traffic services need volume floors | Percentage alerts without `clamp_min` flap on bot replay |
| Duplicate monitors duplicate emails | One signal per incident |
| Warning thresholds email too | If you only care about critical, drop warn |
| Synthetics need failure duration | `min_failure_duration: 0` is a pager |
| Read logs before tuning | 403 imgproxy ≠ site down |

## Repo-as-code for monitors

We keep monitors in version-controlled config and apply with a shell script so tuning is reviewable in git — same pattern as the [Apache 404 check write-up](/posts/datadog-apache-404-wordpress-docker/) on this blog.

After these changes, overnight imgproxy bot bursts should not flood your inbox. Real widespread broken images — stale Cloudflare APO HTML, bad mu-plugin rewrites — still trip the 10% critical alert with enough volume to matter.

If your stack serves signed images through imgproxy, check whether your 403 alerts correlate with bot srcset garbage before you purge caches or redeploy WordPress.
