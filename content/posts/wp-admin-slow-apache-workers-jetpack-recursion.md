---
title: "Why wp-admin Was Painfully Slow on a 4-Worker WordPress Docker Stack"
date: 2026-06-13T10:00:00Z
draft: false
description: "Apache worker starvation, sticky sessions, and a Jetpack mu-plugin recursion bug — three compounding causes of slow wp-admin navigation."
tags: ["WordPress", "Docker", "performance", "Jetpack", "Traefik"]
---

We run a travel blog ([joyofexploringtheworld.com](https://joyofexploringtheworld.com/)) on a memory-constrained Docker stack behind Traefik. If wp-admin feels fine on a quiet morning and then turns to treacle the moment you open the block editor, the problem is rarely “WordPress is slow.” It is usually **capacity math** — and sometimes a single filter hook that eats 1.5 GB of RAM.

This is what we found on production with two WordPress replicas, each with **four Apache prefork workers** and a **1536M PHP memory limit**.

## The symptom

Clicking between wp-admin screens felt stuck. Pages hung for several seconds. Datadog APM showed individual admin requests taking **3–5 seconds**, and Apache logged:

```
AH00161: server reached MaxRequestWorkers setting
```

At the same time, PHP fatals appeared in the logs:

```
Allowed memory size of 1610612736 bytes exhausted in jetpack-ops-fixes.php on line 37
```

Two separate problems, one miserable editing experience.

## Cause 1: the block editor fires a REST storm

The Gutenberg block editor does not load “a page.” It loads a page **plus** dozens of parallel REST and admin-ajax calls:

- `/wp-json/wp/v2/categories`, `/wp/v2/media/*`, `/wp/v2/posts/*`
- Jetpack: `/wp-json/jetpack/v4/module/all`, AI assistant endpoints, sync hooks
- Rank Math, Content Views, Newsletter, heartbeat every ~10 seconds

With **four workers per container**, the fifth concurrent request waits in queue. Traefik sticky sessions (`wp_sticky` cookie) pinned the editor to **one** replica, so all of that traffic hit a pool of four PHP processes — not eight.

Logged-in REST requests bypass our anonymous REST response cache, so every call is a full WordPress bootstrap with **47 active plugins**.

## Cause 2: Jetpack loopback recursion in a mu-plugin

We had a must-use plugin that rewrote Jetpack’s `spawn-sync` URL to loopback (to avoid Cloudflare hairpin issues). The `pre_http_request` filter called `wp_remote_request()` for the same URL — which **re-entered the filter** because the URL still contained `spawn-sync`.

Result: infinite recursion until PHP hit the 1536M ceiling and killed the worker mid-request. That made the worker queue worse.

The fix is a static re-entry guard:

```php
add_filter('pre_http_request', function ($preempt, $parsed_args, $url) {
    static $jetpack_spawn_sync_inflight = false;

    if ($jetpack_spawn_sync_inflight || strpos((string) $url, '/jetpack/v4/sync/spawn-sync') === false) {
        return $preempt;
    }

    $jetpack_spawn_sync_inflight = true;
    try {
        // ... wp_remote_request() to 127.0.0.1 with Host header ...
    } finally {
        $jetpack_spawn_sync_inflight = false;
    }
}, 10, 3);
```

**Rule:** never call `wp_remote_request()` inside `pre_http_request` for the same URL without a re-entry flag.

## Cause 3: raising MaxRequestWorkers is not free

The temptation is to bump `MaxRequestWorkers` from 4 to 8. On this stack, each worker can use up to 1536M PHP memory. Worst case is roughly **4 × 1536M ≈ 6 GB per container**, which is why the Docker `mem_limit` is set around 6656m. Adding workers without raising the container cap just moves the failure mode from “queue” to “OOM kill.”

## What actually helped

| Change | Effect |
|--------|--------|
| Re-entry guard on Jetpack loopback | Stops 1.5 GB fatals during autosave/sync |
| Separate Traefik service for admin (`wordpress-admin`, round-robin, no sticky) | Spreads `/wp-admin` and `/wp-json` across both replicas → **8 workers** for editor traffic |
| Keep sticky sessions for public traffic | Cache-friendly browsing unchanged |
| Operational hygiene | No bulk WP-CLI while the block editor is open |

After routing admin REST across both replicas, the same editor session stopped pinning one saturated container.

## Traefik sketch

Public traffic stays sticky:

```yaml
# wordpress service — sticky wp_sticky cookie
traefik.http.services.wordpress.loadbalancer.sticky.cookie.name=wp_sticky
```

Admin and REST use a second service without sticky:

```yaml
# wordpress-admin service — round-robin
# Routers: /wp-admin/*, /wp-json/*, /wp-login.php, admin-ajax.php
traefik.http.routers.wordpress-admin.service=wordpress-admin
```

When both services exist on the same container, the main public router must explicitly set `traefik.http.routers.wordpress.service=wordpress` or Traefik may pick the wrong backend.

## How to diagnose this on your stack

1. **Apache server-status** (or `BusyWorkers` / `MaxRequestWorkers` in logs) while reproducing slowness in wp-admin.
2. **Count parallel `/wp-json` requests** from your IP during a single editor session — if it is 20+ and workers are 4, you have found the queue.
3. **Search logs for memory fatals** during admin use, especially in mu-plugins that touch HTTP API filters.
4. **Check Traefik routing** — is admin sticky to one replica?

## Takeaways

- Block editor slowness on small prefork pools is often **worker starvation**, not database tuning.
- Sticky sessions help public caching but **hurt admin** unless you split routing.
- Mu-plugin HTTP filters are sharp tools; recursion bugs show up as “random” admin freezes.
- Do not solve worker limits by blindly raising `MaxRequestWorkers` — do the memory arithmetic first.

If you are running agents or automation against the same host while editing, overlap makes this worse. See [bulk WP-CLI guardrails](/posts/bulk-wp-cli-guardrails-three-reboots/) for how we stopped that from taking down the host.
