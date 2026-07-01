---
title: "Your Logs Look Fine — Start WordPress Incident Triage in APM"
date: 2026-07-01T14:00:00Z
draft: false
description: "A 24-hour Datadog review on our hybrid WordPress stack found one log error and several real issues in Error Tracking — plus monitor blind spots around dual Traefik services and imgproxy status codes."
tags: ["WordPress", "Datadog", "monitoring", "Traefik", "incident", "hybrid"]
---

We run [joyofexploringtheworld.com](https://joyofexploringtheworld.com/) on a [hybrid stack](/posts/hybrid-wordpress-oracle-elitedesk-ipsec/) — Oracle edge for HTTP, a home EliteDesk for MariaDB and wp-cron, Cloudflare APO, imgproxy, and Datadog EU for observability. After a busy week of deploys and tuning, we ran a structured 24-hour error review.

The log index looked almost clean. **That was the wrong place to start.**

## What we expected vs what we found

| Source | 24h signal | Useful for triage? |
|--------|------------|-------------------|
| Log index (`status:error`) | 1 Traefik line | No — nearly empty |
| Error Tracking | imgproxy source errors, PHP fatals, bot noise | **Yes** |
| APM spans | Slow admin paths, high PHP compilation time | **Yes** |
| Monitors | TLS cert false alert, imgproxy 404s, 502/503 No Data | Mixed |

Our workflow is now: **Error Tracking → APM → monitors → host verification → logs last.**

![Where the signal was during 24h triage — log index vs imgproxy Traefik status codes](/images/posts/wordpress-incident-triage-apm-not-logs/triage-signal-comparison.png)

*Live Datadog counts for the triage window (30 Jun–1 Jul 2026). The log index barely moved; imgproxy **404** at Traefik was the user-impact signal — not the 403s we had tuned for.*

## P0: a TLS monitor that lied after Traefik restarted

A certificate-expiry monitor fired: “TLS cert expiring within 14 days.” Manual checks showed certs were fine — roughly 31 days remaining.

Root cause: after a Traefik container restart, the metric `traefik.tls.certs.notAfterTimestamp` stopped reporting for our Let's Encrypt resolver. The monitor kept evaluating against **stale data** and stayed in Alert.

Fixes:

1. Restart Traefik to restore cert metric emission (short-term).
2. Scope the monitor to our public hostnames only — not every cert Traefik ever saw.
3. Add `notify_no_data` so “metric gone silent” pages differently from “cert actually expiring.”

**Lesson:** infrastructure restarts can break *reporting*, not just the thing being monitored. No-data handling matters.

## P1: imgproxy 404s, not the 403s we tuned for

After moving media to Cloudflare R2, imgproxy only accepts HTTPS sources:

```bash
IMGPROXY_ALLOWED_SOURCES=https://media.example.com/
```

Our mu-plugin rewrites upload URLs to that CDN host — it **never emits `local://`** in current code. Yet Error Tracking showed ~111 hits in 24 hours like:

```
Source URL is not allowed: local:///wp-content/uploads/2025/…/photo.jpg
```

Origin HTML from a fresh request was correct. Production pages still referenced signed `local://` imgproxy paths. Redis and WordPress object cache were flushed; the errors continued until we **purged Cloudflare APO** (full HTML cache).

That incident deserves its own write-up — see [Stale Cloudflare APO HTML After an imgproxy R2 Cutover](/posts/stale-cloudflare-apo-imgproxy-r2-migration/). Here, the observability angle: we almost missed it because our imgproxy monitor watched **`code:403`** while blocked sources returned **404**.

We added:

- A combined imgproxy 403 + 404 error-rate monitor with a volume floor (`clamp_min`)
- A dedicated 404 / `security_error` log monitor for imgproxy
- Dashboard tiles for both status codes on the incident triage board

![imgproxy 403 vs 404 at Traefik over seven days](/images/posts/wordpress-incident-triage-apm-not-logs/imgproxy-403-vs-404.png)

*404 “source not allowed” dominated once stale HTML kept serving `local://` URLs; 403 bot noise stayed a separate, smaller line.*

Bot paths (`robots.txt`, `ip`, invalid signatures) still pollute Error Tracking — we marked those issues **Ignored** so real user-impact errors surface first. That complements the earlier [imgproxy bot alert tuning](/posts/datadog-imgproxy-bot-alerts-not-outages/) work on 403 noise.

## P2: the invisible wp-admin backend

Traefik exposes **two DogStatsD service tags** on the same WordPress containers:

| Traffic | Traefik `service:` tag |
|---------|------------------------|
| Public site | `wordpress_docker` |
| wp-admin, wp-login, wp-json, admin-ajax | `wordpress-admin_docker` |

Our 502/503 monitor queried only `service:wordpress_docker`. Admin-only failures showed as **No Data** — not OK, not Alert, just invisible.

Any monitor or dashboard for HTTP errors, latency, or availability on this stack must **sum or OR both tags**. Same rule for the incident triage dashboard JSON we keep in git and apply via script (or Datadog API from a dev machine when an Application Key is not on the host).

## P3: noise we could safely ignore

Not everything in Error Tracking is an incident:

| Pattern | Count (24h) | Action |
|---------|-------------|--------|
| imgproxy `Invalid path: robots.txt` | ~101 | Ignore in Error Tracking |
| imgproxy `Invalid path: ip` | ~92 | Ignore |
| imgproxy invalid signature | ~53 | Ignore (bots; see bot alert post) |
| Site Kit fatal (missing `Pointer.php`) | 1 | Partial plugin update; file present on disk |
| curl 1001ms timeout to `admin-ajax.php?action=as_async_request_queue_runner` | ~36 | Expected — Action Scheduler loopback under load |

We also added Error Tracking monitors for **new PHP fatals** so the next real fatal does not wait for a manual review.

## What we changed in the runbook

1. **Triage order** — Error Tracking and APM before log search.
2. **Dual-service queries** — every Traefik metric alert includes both WordPress service tags.
3. **imgproxy status codes** — monitor 403 and 404; security denials are not always 403.
4. **TLS monitors** — hostname scope + no-data notification.
5. **Dashboard as code** — incident triage JSON in git; apply after edits so the board matches monitors.

Example 502/503 query shape (both backends):

```
sum(last_5m):sum:traefik.service.request.total{
  (service:wordpress_docker OR service:wordpress-admin_docker),
  code:502
}.as_count()
```

## What you can do

1. Run a 24h review starting in **Error Tracking**, not Logs — especially on PHP apps where stderr may not reach your log pipeline.
2. List every Traefik `service:` tag your stack emits; grep monitors and dashboards for missing tags.
3. After imgproxy or CDN changes, check **404 rate**, not just 403 — allowlist rejections may not match your old alert.
4. Add `notify_no_data` on metrics that can stop reporting after restarts.
5. Keep monitor JSON in git; document apply steps so tuning survives the next incident.

Patterns transfer to any APM stack — we happen to use Datadog on Docker with Traefik DogStatsD.

**See also:** [When Datadog Alerts Are Bots, Not Outages (imgproxy srcset Noise)](/posts/datadog-imgproxy-bot-alerts-not-outages/) | [Hybrid WordPress: Free Oracle VM + Home EliteDesk over IPSec](/posts/hybrid-wordpress-oracle-elitedesk-ipsec/) | [Why Our Site Went Down for an Hour](/posts/why-our-site-went-down-for-an-hour/)

{{< cta >}}
