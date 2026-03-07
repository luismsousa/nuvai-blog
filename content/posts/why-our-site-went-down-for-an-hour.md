---
title: "Why Our Site Went Down for an Hour (And What We Fixed)"
date: 2026-03-07T10:00:00Z
draft: false
description: "One Traefik config mistake took our site down. How we fixed it and what we learned about dynamic config loading."
tags: ["WordPress", "Traefik", "Docker", "incident"]
---

We run a travel blog ([joyofexploringtheworld.com](https://joyofexploringtheworld.com/)) that helps people plan itineraries—hosted on a low-cost VPS with Docker Compose and Cloudflare. One small performance tweak took the whole site offline for an hour. Here's what happened and how we fixed it.

## What Went Wrong

We added a Traefik compression middleware to speed up responses. The new config lived in a **separate YAML file**. Traefik was configured to load only a **single file** (e.g. `real-ip.yaml`), not the whole directory. The router referenced `compress@file`, but that file was never loaded. Every request failed.

## The Fix

We merged the compression middleware into the file Traefik actually loads. Once the middleware existed in the loaded config, the site came back immediately.

```yaml
# config/traefik/real-ip.yaml — all middlewares in one file
http:
  middlewares:
    real-ip-cf:
      plugin:
        real-ip:
          Proxy:
            - realIP: Cf-Connecting-Ip
              OverwriteXFF: true
    compress:
      compress:
        encodings:
          - br
          - gzip
        minResponseBodyBytes: 1024
```

## Lesson for Readers

When you add a new feature—reverse proxy, CDN, plugin, or middleware—**confirm how config is loaded**. Is it a single file or a directory? If it's a single file, put new middlewares in that file. Test before assuming the change is active.

## What You Can Do

1. Check your Traefik `--providers.file.filename` (or `directory`) setting.
2. Add new middlewares to the file that Traefik loads.
3. Restart Traefik and verify the middleware appears in the API/dashboard.
4. Test a sample request before declaring victory.

The full Traefik config is in the [companion repo](https://github.com/luismsousa/wordpress-docker-stack/blob/main/config/traefik/real-ip.yaml).

**See also**: [Running a WordPress Travel Blog on a Budget VPS: The Full Stack](/posts/wordpress-docker-compose-production-stack/) | [Rank Math Sitemap Not Loading with Traefik](/posts/rank-math-sitemap-not-loading-traefik/)

{{< cta >}}
