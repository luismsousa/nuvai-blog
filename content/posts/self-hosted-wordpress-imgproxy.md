---
title: "Self-hosted image optimization for WordPress with imgproxy (no premium plugins)"
date: 2026-03-07T12:06:00Z
draft: false
description: "Dynamic resize and WebP/AVIF for WordPress using imgproxy in Docker, a small MU-plugin, and Cloudflare—no post edits, no recurring plugin costs."
tags: ["WordPress", "Docker", "imgproxy", "Cloudflare", "self-hosted"]
---

We run a travel blog ([joyofexploringtheworld.com](https://joyofexploringtheworld.com/)) on a budget VPS with Docker Compose and free Cloudflare. Premium image plugins like ShortPixel charge for resize and optimize—we wanted dynamic images without recurring costs. Here’s how we did it with imgproxy.

## Why imgproxy

imgproxy runs in Docker, supports signed URLs and allowlisted sources, and outputs WebP/AVIF. We use the official image `ghcr.io/imgproxy/imgproxy` and pin a version tag for stable deploys. No post edits needed: we rewrite image URLs at runtime via a WordPress MU-plugin so existing content and our Bricksy Pro FSE output stay unchanged.

## No post edits—runtime rewrite

The MU-plugin rewrites `src`, `srcset`, `data-src`, and `data-srcset` for images under `wp-content/uploads` only. Because FSE themes can bypass `the_content`, we added an output-buffer fallback to catch final HTML. We restrict rewrites to real image extensions so fonts and other assets don’t go through imgproxy. A bypass flag (`IMGPROXY_BYPASS=true`) lets us roll back instantly.

```php
// From imgproxy-rewrite.php — convert upload URLs to local:// paths
// so imgproxy reads from the shared Docker volume (no network hop)
private static function to_local_source(string $url): string {
    $path = (string) wp_parse_url($url, PHP_URL_PATH);
    if (str_starts_with($path, '/wp-content/uploads/')) {
        return 'local://' . $path;
    }
    return $url;
}
```

## Docker Compose and Cloudflare

We added an imgproxy service to our stack, a Traefik route for a dedicated subdomain (e.g. `img.example.com`), and env vars for key, salt, and bypass. Cloudflare caches the image subdomain with a long TTL (e.g. 30 days), optionally managed via Terraform. On go-live, we flushed Redis, WP object cache, and Cloudflare so users see transformed images.

```yaml
# docker-compose.yml — imgproxy service
imgproxy:
  image: ghcr.io/imgproxy/imgproxy:v3
  restart: always
  environment:
    IMGPROXY_KEY: ${IMGPROXY_KEY}
    IMGPROXY_SALT: ${IMGPROXY_SALT}
    IMGPROXY_ALLOWED_SOURCES: ${IMGPROXY_ALLOWED_SOURCES}
    IMGPROXY_LOCAL_FILESYSTEM_ROOT: /data
    IMGPROXY_AUTO_WEBP: "true"
    IMGPROXY_AUTO_AVIF: "true"
    IMGPROXY_QUALITY: "82"
  volumes:
    - wordpress:/data:ro
  labels:
    - 'traefik.enable=true'
    - 'traefik.http.routers.imgproxy.rule=Host(`img.example.com`)'
    - 'traefik.http.services.imgproxy.loadbalancer.server.port=8080'
```

## What you can do

1. Run [imgproxy](https://docs.imgproxy.net/installation) in Docker with a pinned image.
2. Add a MU-plugin to rewrite image URLs at runtime; include an output-buffer fallback for FSE.
3. Restrict rewrites to `wp-content/uploads` and real image extensions.
4. Use Cloudflare (or similar) to cache the image subdomain.
5. Flush all caches after cutover.

No premium plugins, no recurring fees—just free, controllable image optimization.

The full MU-plugin and docker-compose.yml are in the [companion repo](https://github.com/luismsousa/wordpress-docker-stack).

**See also**: [Running a WordPress Travel Blog on a Budget VPS: The Full Stack](/posts/wordpress-docker-compose-production-stack/) | [When the Image Crop Error Isn't About the Image](/posts/when-image-crop-error-isnt-about-the-image/)

{{< cta >}}
