---
title: "Why Datadog Apache Metrics Showed 404 (And When to Disable the Check)"
date: 2026-03-07T12:12:00Z
draft: false
description: "Datadog Apache check returning 404? The WordPress Docker image lacks mod_status. Disable the check or add it via a dedicated VirtualHost on a separate port."
tags: ["WordPress", "Docker", "Datadog", "Apache", "monitoring"]
---

We run [joyofexploringtheworld.com](https://joyofexploringtheworld.com/) with Datadog for observability. After setting up the Datadog Agent, we noticed the Apache integration was logging 404 errors every 15 seconds. Here's why—and two ways to fix it.

## The problem

Datadog's Apache integration polls `http://localhost/server-status?auto` to scrape metrics (requests per second, busy workers, etc.). The official `wordpress:latest` Docker image does not enable Apache's `mod_status` module. So the endpoint doesn't exist, and every poll returns 404.

## Option A: Disable the Apache check

If Traefik (or another reverse proxy) already exposes HTTP metrics via DogStatsD, the Apache-level metrics are redundant. Disable the check:

```yaml
# config/datadog/conf.d/apache.d/conf.yaml
instances: []
```

This silences the 404 errors without losing visibility—Traefik's DogStatsD metrics cover request rates, latency, and error codes at the proxy layer.

## Option B: Enable mod_status on a separate port

If you want Apache-level metrics (worker utilisation, scoreboard, etc.), enable `mod_status` on a dedicated port that is not exposed to the internet:

```apache
# config/apache/02-server-status.conf
Listen 8888

<IfModule mod_status.c>
    ExtendedStatus On
</IfModule>

<VirtualHost *:8888>
    DocumentRoot /var/www/html
    <Location /server-status>
        SetHandler server-status
        Require all granted
    </Location>
    <Directory /var/www/html>
        AllowOverride None
        Require all denied
    </Directory>
</VirtualHost>
```

Then point the Datadog check at port 8888:

```yaml
# config/datadog/conf.d/apache.d/conf.yaml
instances:
  - apache_status_url: "http://%%host%%:8888/server-status?auto"
    tags:
      - "env:production"
      - "service:wordpress"
```

The `VirtualHost` on 8888 only exposes `/server-status`—all other requests are denied. Expose port 8888 in your `docker-compose.yml` (internally only, not to the host) and the Datadog Agent will scrape it from the Docker network.

## Bake extensions into the Dockerfile

A related lesson: we originally installed Datadog's PHP tracer (`dd-trace-php`) and the `phpredis` extension at runtime in the container entrypoint. This caused slow starts and occasional 5xx errors. The fix was to bake them into the image:

```dockerfile
FROM wordpress:latest

RUN curl -sSLf https://github.com/DataDog/dd-trace-php/releases/latest/download/datadog-setup.php -o /tmp/datadog-setup.php \
    && php /tmp/datadog-setup.php --php-bin=all --enable-appsec --enable-profiling 2>&1 \
    && rm -f /tmp/datadog-setup.php

RUN pecl install redis \
    && docker-php-ext-enable redis
```

## What you can do

1. Check your Datadog Agent logs for Apache 404 errors.
2. Decide: do you need Apache-level metrics, or are Traefik/proxy metrics enough?
3. If not needed, set `instances: []` in the Apache check config.
4. If needed, add `mod_status` on a separate port with a locked-down VirtualHost.
5. Bake PHP extensions into your Dockerfile instead of installing at runtime.

The full Apache config and Dockerfile are in the [companion repo](https://github.com/luismsousa/wordpress-docker-stack).

**See also**: [Running a WordPress Travel Blog on a Budget VPS: The Full Stack](/posts/wordpress-docker-compose-production-stack/) | [How We Sped Up Our Travel Blog](/posts/how-we-sped-up-our-travel-blog/)

{{< cta >}}
