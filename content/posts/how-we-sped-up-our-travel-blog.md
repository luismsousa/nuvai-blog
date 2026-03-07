---
title: "How We Sped Up Our Travel Blog (Without Changing Hosts)"
date: 2026-03-07T12:00:00Z
draft: false
description: "Database memory, OPcache, health checks, and LCP image priority—four changes that improved our WordPress speed on a budget VPS."
tags: ["WordPress", "performance", "Docker", "MariaDB", "Redis"]
---

We run a travel blog at [joyofexploringtheworld.com](https://joyofexploringtheworld.com/) that helps travellers plan itineraries—hosted on a low-cost VPS with Docker Compose and Cloudflare’s free tier. Here are four changes that improved speed without changing hosts or paying for premium plugins.

## 1. Give the database more memory

On a 24 GB VPS, MariaDB’s default InnoDB buffer pool (~128 MB) was too small. We increased it to 2 GB and set a 4 GB memory limit on the DB container. Redis’s `maxmemory` was raised from 1 GB to 2 GB.

```ini
# config/mariadb/conf.d/98-innodb-tuning.cnf
[mysqld]
innodb_buffer_pool_size = 2G
```

**Lesson**: Match DB and cache memory to available RAM. Set container limits to avoid runaways.

## 2. Turn off PHP “check for file changes” in production

In production, PHP’s OPcache was still checking whether files had changed on every request. We set `opcache.validate_timestamps=0` in a dedicated config file (e.g. `99-opcache.ini`) mounted into the container. PHP no longer stats files on every request.

```ini
; config/php/99-opcache.ini
opcache.validate_timestamps=0
opcache.memory_consumption=256
```

**Lesson**: In production, disable file-change checks so OPcache serves cached bytecode without extra I/O.

## 3. Add a lightweight health-check page

We replaced the healthcheck target from `wp-cron.php` (or worse, `admin-ajax.php`, which returns 400 without an `action` parameter) with a minimal `/health.php` that returns 200 without bootstrapping WordPress. Every healthcheck poll no longer hits full WordPress.

```php
<?php
// config/health.php — returns 200 without loading WordPress
http_response_code(200);
header('Content-Type: text/plain');
echo 'OK';
```

**Lesson**: Use an endpoint that returns 200 on a simple GET. Avoid `admin-ajax.php` for healthchecks.

## 4. Prioritise the first big image (LCP)

The first large above-the-fold image had no `fetchpriority="high"` and was lazy-loaded. We added an output buffer or filter to set `fetchpriority="high"` and `loading="eager"` on the first large content image (excluding the small logo).

**Lesson**: The first large image drives LCP. Give it high priority and avoid lazy-loading it.

---

## What you can do

1. Check your MariaDB `innodb_buffer_pool_size` and Redis `maxmemory` against available RAM.
2. Set `opcache.validate_timestamps=0` in production.
3. Use a minimal health endpoint for Docker/Traefik healthchecks.
4. Ensure the first large image has `fetchpriority="high"` and `loading="eager"`.

Small, focused changes like these can improve speed without a migration.

All config files are in the [companion repo](https://github.com/luismsousa/wordpress-docker-stack). See also the [Dockerfile](https://github.com/luismsousa/wordpress-docker-stack/blob/main/Dockerfile) and [asset-optimizer MU-plugin](https://github.com/luismsousa/wordpress-docker-stack/blob/main/wp-content/mu-plugins/asset-optimizer.php).

**See also**: [Running a WordPress Travel Blog on a Budget VPS: The Full Stack](/posts/wordpress-docker-compose-production-stack/) | [Self-hosted image optimization with imgproxy](/posts/self-hosted-wordpress-imgproxy/)

{{< cta >}}
