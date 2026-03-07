---
title: "Rank Math sitemap not loading with Traefik (and how to fix it)"
date: 2026-03-07T12:00:00Z
draft: false
description: "Rank Math sitemap returns 404 with Traefik? Here's how to route sitemap_index.xml to WordPress and fix common sitemap issues."
tags: ["WordPress", "Traefik", "Rank Math", "SEO", "sitemap"]
---

We run a travel blog ([joyofexploringtheworld.com](https://joyofexploringtheworld.com/)) on a budget VPS with Docker Compose, Cloudflare, and Traefik. When we added Rank Math for SEO, the sitemap worked in the admin but returned 404 on the public URL. Here's what was going on and how we fixed it.

## The problem

Rank Math generates sitemaps at runtime via `index.php?sitemap=1`. On Apache or Nginx with `.htaccess`/rewrite rules, the pretty URL `/sitemap_index.xml` gets routed to WordPress automatically. With Traefik, that routing doesn't exist by default—Traefik doesn't use `.htaccess`, so `/sitemap_index.xml` never reaches WordPress and you get a 404.

## How to fix it

### 1. Isolate the issue

Test both URLs:

- `https://yoursite.com?sitemap=1` — if this works, WordPress is fine; the issue is routing
- `https://yoursite.com/sitemap_index.xml` — if this 404s, Traefik isn't sending the request to WordPress

### 2. Add Traefik path routing

Configure Traefik so `/sitemap_index.xml` and `*-sitemap*.xml` are routed to WordPress. Add a path prefix rule or middleware that forwards these requests to your WordPress backend. The exact config depends on your setup (Docker labels, file provider, etc.), but the goal is that any request for a sitemap path hits WordPress instead of returning 404.

```yaml
# Traefik static config — single-file provider
command:
  - '--providers.file.filename=/etc/traefik/dynamic/real-ip.yaml'
  # NOT --providers.file.directory — only this file is loaded
```

If Traefik uses `--providers.file.filename` (not `directory`), only that one file is loaded. WordPress rewrite rules rely on all requests hitting `index.php`, so Traefik must route `/sitemap_index.xml` to the WordPress backend.

### 3. Flush permalinks

In WordPress: **Settings → Permalinks → Save** (no need to change anything). This refreshes rewrite rules and can resolve stale routing.

### 4. Exclude sitemap from caching

If Cloudflare or a caching plugin caches the sitemap, search engines may see stale or empty content. Add a cache bypass rule for `/sitemap*.xml` or `/sitemap_index.xml`.

### 5. Remove conflicting static files

If you have a physical file named `sitemap_index.xml` in your web root, it can shadow Rank Math's virtual sitemap. Remove or rename it.

## What you can do

- Confirm Traefik routes sitemap paths to WordPress
- Flush permalinks after any routing change
- Exclude sitemaps from full-page cache
- Use [Rank Math's sitemap troubleshooting guide](https://rankmath.com/kb/fix-sitemap-issues/) for more checks

Virtual sitemaps need server rewrites; Traefik requires explicit config, unlike Apache's mod_rewrite. Once routing is correct, Rank Math's sitemap will work as expected.

The Traefik config is in the [companion repo](https://github.com/luismsousa/wordpress-docker-stack/blob/main/config/traefik/real-ip.yaml).

**See also**: [Running a WordPress Travel Blog on a Budget VPS: The Full Stack](/posts/wordpress-docker-compose-production-stack/) | [Why Our Site Went Down for an Hour](/posts/why-our-site-went-down-for-an-hour/)

{{< cta >}}
