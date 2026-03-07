---
title: "When \"There Has Been an Error Cropping Your Image\" Isn't About the Image"
date: 2026-03-07T12:04:00Z
draft: false
description: "The crop error was a 403 on admin-ajax, not missing GD. How to debug and fix when imgproxy or WAF blocks the request."
tags: ["WordPress", "troubleshooting", "imgproxy", "EDD"]
---

We run a travel blog on a budget stack ([joyofexploringtheworld.com](https://joyofexploringtheworld.com/)) with Docker, Cloudflare, and imgproxy for images. When we hit “There has been an error cropping your image” in the WordPress media editor, the message pointed at the image—but the real cause was elsewhere.

## The misleading error

The error suggests missing image libraries (GD or Imagick). We confirmed both were installed and working. The actual problem: the crop request to `admin-ajax.php` was returning **403 Forbidden**. That can come from a security plugin, WAF, or nonce validation—not from the image itself.

## Check the real response

Before assuming missing extensions, check server and plugin logs for the HTTP status of the crop request. A 403 means something is blocking the request before WordPress can process it. If you use a service that rewrites image URLs (e.g. imgproxy), make sure the crop flow in the admin still talks to your own server—exclude admin/AJAX from any URL rewrite so crop requests use local URLs.

```php
// From imgproxy-rewrite.php — bypass admin, AJAX, and JSON requests
private static function should_bypass_request_context(): bool {
    return is_admin() || wp_doing_ajax() || wp_is_json_request();
}
```

The MU-plugin checks `should_bypass_request_context()` before every rewrite. Admin pages, AJAX calls (including the crop request), and REST API calls all skip the rewrite entirely, so the crop flow uses local URLs.

## What you can do

1. Check server and plugin logs for the crop request’s HTTP status.
2. If it’s 403, look at security plugins, WAF rules, or nonce validation.
3. If you use imgproxy or similar, exclude admin/AJAX from the rewrite.
4. Verify GD or Imagick only if the request returns 200 and the error persists.

The full MU-plugin is in the [companion repo](https://github.com/luismsousa/wordpress-docker-stack/blob/main/wp-content/mu-plugins/imgproxy-rewrite.php).

**See also**: [Running a WordPress Travel Blog on a Budget VPS: The Full Stack](/posts/wordpress-docker-compose-production-stack/) | [Self-hosted image optimization with imgproxy](/posts/self-hosted-wordpress-imgproxy/)

{{< cta >}}
