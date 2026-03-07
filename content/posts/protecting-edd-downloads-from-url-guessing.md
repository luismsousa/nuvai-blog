---
title: "Protecting EDD Downloads from URL Guessing"
date: 2026-03-07T12:10:00Z
draft: false
description: "Stop EDD downloads being guessable. Use the protected edd/ directory, redirect method, and token validation for secure digital product delivery."
tags: ["WordPress", "EDD", "security", "digital products"]
---

We sell digital products on [joyofexploringtheworld.com](https://joyofexploringtheworld.com/) using Easy Digital Downloads. By default, EDD stores files in `wp-content/uploads/`—the same directory as every other WordPress upload. That means anyone who can guess the filename can download the file directly, bypassing purchase validation entirely.

## The problem

EDD download URLs contain a token that validates the purchase. But the actual file sits in a publicly accessible directory. If someone guesses or discovers the file path (e.g. from a cached CDN URL or a predictable naming pattern), they can download it without paying.

## The fix: three layers of protection

### 1. Move files to the protected directory

EDD provides a dedicated `wp-content/uploads/edd/` directory with an `.htaccess` file that returns 403 for all direct access:

```apache
# wp-content/uploads/edd/.htaccess
<FilesMatch ".*">
  Order Allow,Deny
  Deny from all
</FilesMatch>
```

Upload all downloadable files to this directory, not `wp-content/uploads/`.

### 2. Set the download method to "redirect"

In **Downloads > Settings > Misc**, set the download method to **Forced** (redirect). This makes PHP serve the file after validating the purchase token. The browser never gets a direct URL to the file on disk.

### 3. Use EDD for free lead magnets too

Free lead magnets (PDFs, guides, etc.) should also be created as EDD products with a price of £0.00. This way, even free downloads go through EDD's token validation system. Users enter their email (captured by your newsletter plugin), and the download is served through the protected flow.

## What you can do

1. Check where your EDD files are stored—if they're in `wp-content/uploads/` (not `wp-content/uploads/edd/`), move them.
2. Verify the `.htaccess` in the `edd/` directory denies direct access.
3. Set the download method to **Forced** in EDD settings.
4. Create free lead magnets as £0.00 EDD products, not direct file links.
5. Test by trying to access a file URL directly in an incognito window—you should get a 403.

**See also**: [Running a WordPress Travel Blog on a Budget VPS: The Full Stack](/posts/wordpress-docker-compose-production-stack/) | [Fixing EDD Checkout Header/Footer Overlap](/posts/fixing-edd-checkout-header-footer-overlap/)

{{< cta >}}
