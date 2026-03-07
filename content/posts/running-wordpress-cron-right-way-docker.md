---
title: "Running WordPress Cron the Right Way When Your Site Lives in Docker"
date: 2026-03-07T12:05:00Z
draft: false
description: "Disable WP-Cron self-ping and run a sidecar that executes due tasks every minute. Fewer timeouts, more reliable scheduled jobs."
tags: ["WordPress", "Docker", "WP-Cron", "cron"]
---

We host a travel blog ([joyofexploringtheworld.com](https://joyofexploringtheworld.com/)) on a low-cost VPS with Docker Compose and Cloudflare in front. WordPress’s built-in cron was causing intermittent timeouts in our logs. Here’s how we fixed it.

## The problem with WordPress cron in Docker

WordPress cron normally “pings itself” on each page load—an HTTP POST to the site from inside the container. Behind a CDN and in Docker, that ping can time out, fail, or hit the wrong instance. We saw cURL timeouts in Datadog and unreliable scheduled tasks.

## The solution: a cron sidecar

We set `DISABLE_WP_CRON` and run cron from a small sidecar container that executes `wp cron event run --due-now` every minute. The sidecar needs the same database and Redis config as the main WordPress service, and enough PHP memory (e.g. `php -d memory_limit=512M` when using a custom entrypoint).

```yaml
# docker-compose.yml — wp-cron sidecar service
wp-cron:
  image: wordpress:cli
  volumes_from:
    - wordpress
  entrypoint: /bin/sh
  command: >-
    -c 'while true; do php -d memory_limit=512M /usr/local/bin/wp cron event run --due-now; sleep 60; done'
  environment:
    WORDPRESS_DB_HOST: db
    WORDPRESS_DB_USER: $MYSQL_USER
    WORDPRESS_DB_PASSWORD: $MYSQL_PASSWORD
    WORDPRESS_DB_NAME: $MYSQL_DATABASE
    PHP_MEMORY_LIMIT: 512M
    WORDPRESS_CONFIG_EXTRA: |
      define('WP_REDIS_HOST', 'redis');
      define('WP_REDIS_PORT', '6379');
      define('WP_CACHE', true);
      define('DISABLE_WP_CRON', true);
      define('WP_MEMORY_LIMIT', '512M');
  depends_on:
    - wordpress
  restart: always
```

## What you can do

1. Set `DISABLE_WP_CRON` in `wp-config.php` or via `WORDPRESS_CONFIG_EXTRA`.
2. Add a cron sidecar to your Docker Compose that runs `wp cron event run --due-now` every 60 seconds.
3. Give the sidecar the same `WORDPRESS_DB_*` and Redis config as the main service.
4. Ensure sufficient PHP memory for the CLI container.

In containerised or CDN setups, scheduled tasks are more reliable when run by a dedicated process instead of page loads.

The full docker-compose.yml is in the [companion repo](https://github.com/luismsousa/wordpress-docker-stack/blob/main/docker-compose.yml).

**See also**: [Running a WordPress Travel Blog on a Budget VPS: The Full Stack](/posts/wordpress-docker-compose-production-stack/) | [How We Sped Up Our Travel Blog](/posts/how-we-sped-up-our-travel-blog/)

{{< cta >}}
