---
title: "SEO Housekeeping: Focus Keywords and Sitemaps That Match"
date: 2026-03-07T12:03:00Z
draft: false
description: "Align noindex with sitemaps, set focus keywords, enable redirections. Simple Rank Math habits that avoid mixed SEO signals."
tags: ["WordPress", "SEO", "Rank Math"]
---

We run a travel blog on a budget VPS ([joyofexploringtheworld.com](https://joyofexploringtheworld.com/)) that helps travellers plan itineraries. Keeping SEO clean without premium plugins is part of the game. Here’s how we fixed mixed signals between focus keywords, noindex, and sitemaps using Rank Math’s free tier.

## Why focus keywords matter

Each post should have one clear focus phrase—the main search term you want it to rank for. Rank Math stores this in `rank_math_focus_keyword` post meta. We filled gaps in bulk using WP-CLI, deriving keywords from post titles and search intent (e.g. “cherry blossoms in Paris”, “5 day itinerary Budapest”). Skip utility pages like checkout, receipt, and privacy—they don’t need focus keywords.

```bash
# Set focus keyword for a single post
wp post meta update 123 rank_math_focus_keyword "cherry blossoms in Paris"

# Bulk-update focus keywords from post titles (example loop)
wp post list --post_type=post --format=ids | xargs -I {} sh -c \
  'title=$(wp post get {} --field=post_title); wp post meta update {} rank_math_focus_keyword "$title"'
```

## Noindex and sitemap must align

We had a problem: some content types (tags, author archives) were set to **noindex** but were still **in the XML sitemap**. That invites Google to crawl pages we don’t want indexed and creates duplicate or thin signals. The fix: if it’s noindexed, remove it from the sitemap. We also noindexed paginated archive subpages and set attachment redirects to the parent post, not the homepage.

```bash
# Check which posts are noindexed
wp post meta list --meta_key=rank_math_robots --format=table

# Flush permalinks (fixes most sitemap issues)
wp rewrite flush
```

## Enable the features you rely on

Redirects weren’t working until we enabled the **Redirections** module in Rank Math > Dashboard > Modules. And we switched the default redirect code from 302 to **301** so link equity passes properly. After adding redirects, always confirm the module is active.

## What you can do

1. Set one focus keyword per URL; avoid stuffing.
2. Align noindex with sitemap: if it’s noindexed, remove it from the sitemap.
3. Use 301 (not 302) for redirects.
4. Enable the Redirections module in Rank Math if you use redirects.
5. Redirect attachments to the parent post, not the homepage.

**See also**: [Running a WordPress Travel Blog on a Budget VPS: The Full Stack](/posts/wordpress-docker-compose-production-stack/) | [Rank Math Sitemap Not Loading with Traefik](/posts/rank-math-sitemap-not-loading-traefik/)

{{< cta >}}
