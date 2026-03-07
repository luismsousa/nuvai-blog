---
title: "Running a WordPress Travel Blog on a Budget VPS: The Full Docker Stack"
date: 2026-03-07T09:00:00Z
draft: false
description: "A production Docker Compose stack for WordPress with Traefik, Redis, MariaDB, imgproxy, Datadog, automated backups, and a cron sidecar—all on a single budget VPS."
tags: ["WordPress", "Docker", "Traefik", "Redis", "MariaDB", "imgproxy", "self-hosted", "DevOps"]
---

We run [joyofexploringtheworld.com](https://joyofexploringtheworld.com) — a travel blog — on a single 24 GB VPS using Docker Compose and free-tier Cloudflare. No managed WordPress hosting, no premium plugins, no surprise invoices. Here is the full stack, laid out so you can steal whatever is useful.

## Architecture overview

The request path looks like this:

```
Internet
  -> Cloudflare (CDN / APO / edge SSL)
    -> Traefik v3 (reverse proxy, TLS termination for origin)
      -> 2 WordPress containers (round-robin with sticky session cookies)
        -> MariaDB 11 (single-writer database)
        -> Redis (persistent object cache)
```

Alongside the main request path we run a handful of supporting services: **imgproxy** on a dedicated subdomain for on-the-fly image resizing and format conversion, a **wp-cron sidecar** that hits `wp-cron.php` every five minutes so we can disable the default front-end cron, an **automated backup** container that dumps the database and syncs uploads to Hetzner Storage Box nightly, and the **Datadog agent** for logs, traces, and container metrics.

Everything is defined in a single `docker-compose.yml`. The full sanitised config lives in the companion GitHub repo: [wordpress-docker-stack](https://github.com/luismsousa/wordpress-docker-stack).

## The services

The stack has ten services (nine named, plus WordPress scaled to two replicas). Here is what each one does.

### redis

An Alpine Redis 7 instance used as the WordPress object cache backend via the `redis` PHP extension. It listens on a private Docker network only — no port is exposed to the host. We pin `maxmemory` at 128 MB with an `allkeys-lru` eviction policy so it never eats into the VPS RAM budget.

### wordpress (x2)

Two replicas of our custom WordPress image, load-balanced by Traefik with sticky session cookies so logged-in users always hit the same container. Each replica mounts the same `wp-content` volume for shared uploads and plugins. Environment variables wire up the database, Redis, and Datadog connection details.

### db (MariaDB)

MariaDB 11 with a tuned InnoDB buffer pool and redo log config. The data directory lives on a named volume so it survives container recreation. A custom healthcheck runs `healthcheck.sh` to make sure the container only reports healthy once it can actually accept queries.

### reverse-proxy (Traefik v3)

Traefik handles TLS certificate management via Let's Encrypt, routes traffic to WordPress and imgproxy based on hostname rules, and applies middlewares for real-IP forwarding and gzip/brotli compression. It exposes ports 80 and 443 on the host, and its dashboard is locked behind basic auth on an internal port.

### imgproxy

A self-hosted [imgproxy](https://imgproxy.net/) instance that serves optimised images (WebP/AVIF, resized, stripped of metadata) from a dedicated subdomain. WordPress source images are read from the shared uploads volume. A companion MU-plugin rewrites image URLs at render time so visitors get optimised versions without any manual work.

### datadog-agent

The Datadog agent container collects container logs via the Docker socket, APM traces from the PHP tracer baked into the WordPress image, and host-level metrics. We keep profiling and AppSec disabled to save overhead on a budget VPS — tracing alone gives us enough visibility to catch slow queries and plugin regressions.

### backup

A lightweight Alpine container that runs on a cron schedule via `ofelia` labels. Each night it dumps the MariaDB database with `mariadb-dump`, compresses it, and rsyncs both the dump and the `wp-content/uploads` directory to a Hetzner Storage Box over SSH. Old backups are pruned after 14 days.

### wp-cron

A tiny sidecar that curls `wp-cron.php` on the internal Docker network every five minutes. This lets us set `DISABLE_WP_CRON=true` in the WordPress containers so scheduled tasks (newsletter sends, post scheduling, EDD cleanup) run reliably without depending on visitor traffic to trigger them.

### wpcli

An on-demand utility container for running WP-CLI commands (`wp plugin update --all`, `wp cache flush`, database migrations, etc.) without shelling into a live WordPress container. It shares the same volumes and environment variables, so it sees the exact same WordPress install.

## The Dockerfile

The entire custom image is nine lines:

```dockerfile
FROM wordpress:latest

RUN curl -sSLf https://github.com/DataDog/dd-trace-php/releases/latest/download/datadog-setup.php -o /tmp/datadog-setup.php \
    && php /tmp/datadog-setup.php --php-bin=all --enable-appsec --enable-profiling 2>&1 \
    && rm -f /tmp/datadog-setup.php

RUN pecl install redis \
    && docker-php-ext-enable redis
```

We bake both the Datadog PHP tracer and the Redis PECL extension into the image at build time. Early on we tried installing them at container startup via an entrypoint script. That added 30-40 seconds to every container start and, worse, caused 5xx errors during rolling restarts because Traefik would route traffic to a container that was technically "running" but still compiling extensions. Building them into the image means the container is ready to serve requests the moment it starts.

## Key config files

The repo includes a handful of config files that get bind-mounted into the relevant containers. Each one is small and focused on a single concern.

- **config/health.php** — A minimal PHP health-check endpoint that returns `200 OK` if WordPress can connect to the database. Traefik uses this for its container healthcheck so it only routes to healthy replicas. [View in repo](https://github.com/luismsousa/wordpress-docker-stack/blob/main/config/health.php).

- **config/php/99-opcache.ini** — OPcache tuning: `opcache.memory_consumption=128`, `revalidate_freq=60`, `max_accelerated_files=10000`. These settings keep compiled PHP bytecode in shared memory and avoid hammering `stat()` on every request. [View in repo](https://github.com/luismsousa/wordpress-docker-stack/blob/main/config/php/99-opcache.ini).

- **config/apache/01-static-cache-headers.conf** — Sets far-future `Cache-Control` and `Expires` headers on static assets (images, CSS, JS, fonts) so Cloudflare and browsers cache them aggressively. [View in repo](https://github.com/luismsousa/wordpress-docker-stack/blob/main/config/apache/01-static-cache-headers.conf).

- **config/mariadb/conf.d/98-innodb-tuning.cnf** — InnoDB buffer pool sized to roughly 50-60% of available RAM, plus redo log and flush settings tuned for a write-light WordPress workload. [View in repo](https://github.com/luismsousa/wordpress-docker-stack/blob/main/config/mariadb/conf.d/98-innodb-tuning.cnf).

- **config/traefik/real-ip.yaml** — A Traefik file provider that defines two middlewares: one to extract the real client IP from the `CF-Connecting-IP` header (since all traffic arrives via Cloudflare), and one for gzip and brotli compression on responses. [View in repo](https://github.com/luismsousa/wordpress-docker-stack/blob/main/config/traefik/real-ip.yaml).

## MU-plugins

We use two custom must-use plugins that live in `wp-content/mu-plugins/` and load automatically on every request.

### imgproxy-rewrite.php

This plugin hooks into WordPress's image output pipeline and rewrites image URLs at render time to point at our self-hosted imgproxy instance. A source URL like `https://joyofexploringtheworld.com/wp-content/uploads/2025/12/photo.jpg` becomes `https://img.joyofexploringtheworld.com/insecure/rs:fill:800:600/plain/local:///uploads/2025/12/photo.jpg@webp`. The visitor gets a properly sized, modern-format image without us having to generate thumbnails at upload time or install a heavy optimisation plugin.

### asset-optimizer.php

A front-end performance MU-plugin that handles several small but impactful optimisations: deferring render-blocking scripts, async-loading CSS, promoting the LCP image with a `fetchpriority="high"` attribute, and pruning unused Google Fonts weights. Together these changes shaved a couple of seconds off our Largest Contentful Paint without touching theme files.

## Infrastructure as Code

The `terraform/` directory in the repo manages our Cloudflare configuration declaratively:

- **DNS records** — A/AAAA records pointing to the VPS, CNAME for the imgproxy subdomain, and MX records for email.
- **Redirect rules** — www-to-apex 301 redirects handled at the Cloudflare edge so they never hit the origin.
- **Cache rules** — Page rules and cache rules that control Cloudflare APO behaviour, bypass caching for logged-in users, and set TTLs for static assets.

Managing these in Terraform means we can review changes in a PR, roll back mistakes with `terraform apply`, and keep the Cloudflare config version-controlled alongside the Docker stack.

## Deep dives

Each part of this stack has its own post with the full story, gotchas, and config snippets:

- [How We Sped Up Our Travel Blog](/posts/how-we-sped-up-our-travel-blog/) — the performance audit that kicked off most of these changes.
- [Self-hosted image optimization with imgproxy](/posts/self-hosted-wordpress-imgproxy/) — setting up imgproxy, the MU-plugin, and Cloudflare caching in front of it.
- [Running WordPress Cron the Right Way in Docker](/posts/running-wordpress-cron-right-way-docker/) — why `DISABLE_WP_CRON` matters and how the sidecar works.
- [Why Our Site Went Down for an Hour](/posts/why-our-site-went-down-for-an-hour/) — the runtime extension install disaster that led to the custom Dockerfile.
- [Rank Math Sitemap Not Loading with Traefik](/posts/rank-math-sitemap-not-loading-traefik/) — a subtle content-type issue between Traefik compression and Rank Math's XML output.
- [SEO Housekeeping: Focus Keywords and Sitemaps](/posts/seo-housekeeping-focus-keywords-sitemaps/) — routine SEO maintenance on a WordPress travel blog.
- [Cloudflare www-to-apex Redirects with Terraform](/posts/cloudflare-www-to-apex-redirects-terraform/) — managing redirect rules declaratively.
- [When the Image Crop Error Isn't About the Image](/posts/when-image-crop-error-isnt-about-the-image/) — debugging a misleading WordPress error that was actually a memory limit issue.
- [Fixing EDD Checkout Header/Footer Overlap](/posts/fixing-edd-checkout-header-footer-overlap/) — a CSS fix for Easy Digital Downloads with a full-site-editing theme.
- [Automated WordPress Backups to Hetzner with Docker](/posts/wordpress-docker-automated-backups-hetzner/) — the backup container, Hetzner Storage Box setup, and retention policy.

## Get the full config

The entire stack — `docker-compose.yml`, Dockerfile, config files, MU-plugins, Terraform, and a detailed README — is available in the companion repo:

**[github.com/luismsousa/wordpress-docker-stack](https://github.com/luismsousa/wordpress-docker-stack)**

Clone it, swap in your own domain and credentials, and you have a production WordPress setup on a single VPS for the cost of the server alone.

{{< cta >}}
