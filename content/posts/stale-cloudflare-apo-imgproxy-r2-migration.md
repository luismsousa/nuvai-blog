---
title: "Stale Cloudflare APO HTML After an imgproxy R2 Cutover"
date: 2026-07-01T15:00:00Z
draft: false
description: "Broken images after moving WordPress media to R2 — origin was fixed, Redis was flushed, but Cloudflare APO kept serving HTML with old local:// imgproxy URLs for days."
tags: ["WordPress", "imgproxy", "Cloudflare", "Docker", "incident"]
---

We run [joyofexploringtheworld.com](https://joyofexploringtheworld.com/) with [self-hosted imgproxy](/posts/self-hosted-wordpress-imgproxy/) for on-the-fly WebP/AVIF. Originally, imgproxy read uploads from a shared Docker volume via `local://` paths. After [moving the media library to Cloudflare R2](/posts/hybrid-wordpress-oracle-elitedesk-ipsec/#phase-3-cloudflare-r2--imgproxy), imgproxy fetches HTTPS from a dedicated media subdomain only.

The cutover code was correct. Production still served broken images for hours — because we purged the wrong cache layer.

## The symptom

Datadog Error Tracking reported imgproxy errors at roughly **111 hits per 24 hours**:

```
Source URL is not allowed: local:///wp-content/uploads/2025/06/example.jpg
```

Visitors saw missing or broken images on otherwise normal pages. imgproxy returned **404** with a `security_error` — not the invalid-signature **403** we had tuned monitors for after [bot noise](/posts/datadog-imgproxy-bot-alerts-not-outages/).

![imgproxy 404 spike before APO purge — Traefik metrics](/images/posts/stale-cloudflare-apo-imgproxy-r2-migration/imgproxy-403-vs-404.png)

*Seven-day Traefik view: 404s (red) from disallowed `local://` sources persisted after origin and Redis were fixed; the dashed line marks the full Cloudflare APO purge.*

## What imgproxy expects now

Post-R2, allowlisted sources are HTTPS only:

```bash
IMGPROXY_ALLOWED_SOURCES=https://media.example.com/
IMGPROXY_LOCAL_FILESYSTEM_ROOT=/data   # still mounted, but unused for public media
```

The mu-plugin maps legacy `/wp-content/uploads/YYYY/MM/file.jpg` paths to the CDN URL imgproxy should fetch:

```php
// encode_source() — R2-offloaded and legacy upload paths → CDN HTTPS
if (preg_match('#^/wp-content/uploads/(\d{4}/\d{2}/.+)$#', $path, $matches)) {
    return 'https://' . self::media_cdn_host() . '/' . $matches[1];
}
```

Current git code **never signs `local://`** for public media. A curl against origin with cache-bypass returned fresh HTML with correct `https://media.example.com/…` sources inside signed imgproxy URLs.

So this was not a deploy gap — mu-plugins on the edge already matched git.

## The red herring: Redis and WordPress object cache

First instinct: flush Redis object cache and WordPress transients. We did. Errors persisted.

That made sense in hindsight. Redis caches **WordPress objects** (posts, options, query results). It does not store the fully rendered HTML document that Cloudflare APO cached at the edge.

## Root cause: stale APO HTML

Cloudflare **Automatic Platform Optimization (APO)** caches full HTML pages at the edge, including inline `srcset` strings with signed imgproxy URLs baked in at render time.

Timeline:

1. **Before R2** — pages rendered with `local://` imgproxy sources; APO cached that HTML.
2. **After R2** — origin mu-plugin emitted CDN HTTPS sources; imgproxy rejected any remaining `local://` requests.
3. **Edge** — APO continued serving old HTML with `local://` signatures until a **full APO purge**.

Redis flush alone cannot fix HTML that Cloudflare already holds. imgproxy's own image cache is a third layer — usually irrelevant when the signed URL in HTML points at a disallowed source.

| Layer | What it caches | Purge when |
|-------|----------------|------------|
| Redis object cache | WP posts, options, fragments | Config / mu-plugin changes |
| Cloudflare APO | **Full HTML** with signed imgproxy URLs | **imgproxy or media URL rewrites** |
| imgproxy | Processed raster output | Usually automatic on new valid URLs |
| Cloudflare CDN (image subdomain) | imgproxy responses | After signing key rotation |

## How we verified

1. **Error Tracking** — grouped by imgproxy message; confirmed `local://` not signature errors.
2. **Origin bypass** — request HTML with `Cache-Control: no-cache` or a cache-bypass header; confirmed new URLs were CDN-based.
3. **Database audit** — sampled post content for raw `local://` or stale upload URLs; **no bad URLs in DB** (90 posts checked).
4. **Full APO purge** — errors dropped toward zero in the next Error Tracking window.

## Monitor gap we fixed at the same time

Our imgproxy Traefik alert filtered `code:403`. Security denials for disallowed sources returned **404**. The real user-impact signal was invisible to the alert we had been watching. We now monitor 403 **and** 404 with a volume floor — see [APM-first triage](/posts/wordpress-incident-triage-apm-not-logs/).

## What you can do

1. After **any** imgproxy source change (local disk → object storage, CDN host rename, allowlist edit), plan a **Cloudflare APO purge** — not just Redis.
2. Compare edge HTML vs origin HTML before redeploying WordPress again.
3. Audit post content, but do not assume the DB is wrong — stale **edge HTML** can lie while the database is clean.
4. Watch imgproxy **404** and `security_error`, not only 403 / invalid signature.
5. Document cache layers in your runbook so the next migration does not repeat the purge order mistake.

If you still serve `local://` today, the R2 migration path in our [hybrid architecture post](/posts/hybrid-wordpress-oracle-elitedesk-ipsec/) describes mu-plugin and env changes. This post is the operational footnote: **fix the HTML cache, not just the origin.**

**See also:** [Self-hosted image optimization for WordPress with imgproxy](/posts/self-hosted-wordpress-imgproxy/) | [When Datadog Alerts Are Bots, Not Outages](/posts/datadog-imgproxy-bot-alerts-not-outages/) | [Your Logs Look Fine — Start WordPress Incident Triage in APM](/posts/wordpress-incident-triage-apm-not-logs/)

{{< cta >}}
