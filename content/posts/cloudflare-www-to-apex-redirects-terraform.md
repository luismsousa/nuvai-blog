---
title: "Managing Cloudflare www-to-apex redirects with Terraform for WordPress SEO"
date: 2026-03-07T12:00:00Z
draft: false
description: "Canonical www-to-apex redirect via Cloudflare Terraform: import existing ruleset, add redirect rule, avoid 'exceeded maximum rulesets' errors."
tags: ["Terraform", "Cloudflare", "WordPress", "SEO", "DevOps"]
---

For SEO, `www.example.com` should 301 redirect to `example.com` so search engines see one canonical host. We manage our travel blog's infrastructure with Terraform, including Cloudflare. When we tried to add the www-to-apex redirect, we hit "exceeded maximum number of zone rulesets." Here's how we fixed it and manage redirects as code.

## Why Terraform for Cloudflare

Terraform gives you versioned, repeatable config. No manual dashboard drift, no "who changed what" surprises. Redirects live in `main.tf` and are applied consistently.

## The ruleset limit gotcha

Cloudflare allows only one zone ruleset per phase. The `http_request_dynamic_redirect` phase is used for redirects. If you try to create a new ruleset with `resource "cloudflare_ruleset"`, Terraform will create it—but Cloudflare will reject it because you've exceeded the limit. The fix: **import** the existing ruleset and update it, don't create a second one.

## Steps to add the redirect

### 1. Token scopes

Your Cloudflare API token needs: Zone:Read, DNS:Edit, Zone Settings:Edit, and **Ruleset edit**. Without Ruleset edit, Terraform can't manage redirect rules.

### 2. Discover the existing ruleset

Use the Cloudflare API or dashboard to find the ruleset ID for the `http_request_dynamic_redirect` phase. You'll need the zone ID and ruleset ID for the import.

### 3. Import into Terraform

```bash
terraform import cloudflare_ruleset.redirect_ruleset <zone_id>/<ruleset_id>
```

```bash
# Import existing ruleset before creating
terraform import cloudflare_ruleset.canonical_redirects <zone_id>/<ruleset_id>
```

### 4. Add the www-to-apex rule in main.tf

Define the ruleset resource and add a rule that matches `www.example.com` and redirects to `https://example.com` with status 301. The exact HCL depends on the Cloudflare provider version; the rule typically uses `http_request_dynamic_redirect` and a `redirect` action.

```hcl
# terraform/provider.tf
terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5"
    }
  }
}

provider "cloudflare" {}
```

```hcl
# terraform/main.tf — www-to-apex redirect
resource "cloudflare_ruleset" "canonical_redirects" {
  zone_id = var.cloudflare_zone_id
  name    = "Default Redirect Rules"
  kind    = "zone"
  phase   = "http_request_dynamic_redirect"

  rules = [
    {
      description = "Canonical www to apex"
      expression  = "(http.host eq \"www.example.com\")"
      enabled     = true
      action      = "redirect"

      action_parameters = {
        from_value = {
          status_code = 301
          target_url = {
            expression = "concat(\"https://example.com\", http.request.uri)"
          }
          preserve_query_string = true
        }
      }
    }
  ]
}
```

### 5. Apply and verify

```bash
terraform apply
curl -I https://www.example.com
```

You should see `301 Moved Permanently` and `Location: https://example.com`.

### 6. Purge cache after redirect changes

After changing redirects, purge the Cloudflare cache so the new behaviour propagates quickly.

## What you can do

- Import before create when Cloudflare phase limits apply
- Manage redirects as code for consistency
- Verify with `curl -I` after apply
- Purge cache when redirect rules change

Once the existing ruleset is under Terraform, adding or changing redirect rules is straightforward and repeatable.

The full Terraform config is in the [companion repo](https://github.com/luismsousa/wordpress-docker-stack/tree/main/terraform).

**See also**: [Running a WordPress Travel Blog on a Budget VPS: The Full Stack](/posts/wordpress-docker-compose-production-stack/) | [SEO Housekeeping: Focus Keywords and Sitemaps](/posts/seo-housekeeping-focus-keywords-sitemaps/)

{{< cta >}}
