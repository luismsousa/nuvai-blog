# Agent guide: writing blog posts from issue summaries

This repo is the Hugo source for [blog.nuvai.cloud](https://blog.nuvai.cloud) — practical DevOps/SRE write-ups, mostly about running a self-hosted WordPress travel blog on Docker. Your job is to turn a **raw issue or incident summary** (from the user, a GitHub issue, chat logs, or debugging notes) into a **publish-ready post** in `content/posts/`.

Read this file first. Do not ask the user to re-explain repo conventions unless something is genuinely ambiguous.

---

## What you receive

The user will typically provide a short summary covering some or all of:

- What broke or what they were trying to do
- Symptoms (alerts, errors, user impact)
- Root cause (once known)
- Fix or mitigation
- Commands, config snippets, or monitor queries they used
- Optional: links to commits or files in the companion infra repo

Treat that input as **confidential until sanitized**. Your output must be safe to publish on the public internet.

---

## Workflow

1. **Read 2–3 similar posts** in `content/posts/` to match tone and structure (e.g. incident posts like `why-our-site-went-down-for-an-hour.md`, monitoring posts like `datadog-imgproxy-bot-alerts-not-outages.md`).
2. **Sanitize** all sensitive details (see [Sanitization rules](#sanitization-rules)). When in doubt, generalize or redact.
3. **Draft the post** as a new Markdown file under `content/posts/`.
4. **Cross-link** related posts already in this repo (grep `content/posts/` for tags and topics).
5. **End with** a "See also" line and the `{{< cta >}}` shortcode (standard on published posts).
6. Set `draft: true` unless the user explicitly asks to publish.
7. **Do not commit or push** unless the user asks.

Optional local preview (requires Hugo and git submodules):

```bash
./build.sh && hugo server -D
```

---

## Sanitization rules

Posts are public. The companion stack repo ([wordpress-docker-stack](https://github.com/luismsousa/wordpress-docker-stack)) is also public but uses sanitized configs — match that level of care.

### Safe to name explicitly

| Item | Usage |
|------|--------|
| [joyofexploringtheworld.com](https://joyofexploringtheworld.com/) | The public travel blog this stack runs; link in the opening paragraph |
| [blog.nuvai.cloud](https://blog.nuvai.cloud) | This blog's URL |
| [nuvai.cloud](https://nuvai.cloud) | Author's public brand / Bluesky |
| Public GitHub repos | `luismsousa/nuvai-blog`, `luismsousa/wordpress-docker-stack` — link to specific paths when helpful |
| Generic cloud/SaaS names | Cloudflare, Datadog, Traefik, Hetzner, Oracle Cloud Always Free, Rank Math, EDD, imgproxy, etc. |
| Hardware class (not serials) | e.g. "HP EliteDesk mini PC with 60 GB RAM", "23 GB VPS" |

### Always redact or replace

| Sensitive | Replace with |
|-----------|----------------|
| API keys, tokens, salts, passwords, signing keys | Remove entirely; show placeholder env var **names** only (e.g. `IMGPROXY_KEY`, `DD_API_KEY`) |
| Private hostnames, internal DNS, home IPs, WAN IPs | `home-server`, `db-host`, or omit |
| Full private IP addresses | Partial mask: `172.18.x.x`, `10.0.x.x` |
| SSH usernames, server nicknames tied to identity | `the host`, `origin server` |
| Datadog monitor IDs, org-specific URLs with tokens | Describe the monitor in prose; show query **shape**, not live IDs |
| Customer/order data, download filenames that reveal products | `product-file.zip`, generic descriptions |
| Email addresses (except public author contact already on About page) | Omit |
| Employer-internal systems, client names, ticket numbers | Generalize ("a previous employer", "a SaaS platform") |
| Unreleased security details | Describe the class of issue without exploit steps |

### Use example.com for illustrative URLs

When showing URL patterns, redirects, or imgproxy paths **in code blocks**, prefer generics:

- Apex/www redirects: `example.com`, `www.example.com`
- Image subdomain in config examples: `img.example.com`
- Media CDN placeholder: `media.example.com`

In **prose** (opening context), link the real public site `joyofexploringtheworld.com`. In **technical examples**, use `example.com` unless the real hostname is required for clarity (e.g. showing an actual `curl` against a public endpoint).

### Truncate noisy log lines

Bot URLs, long signed imgproxy paths, and stack traces: show a **representative truncated** line with `…` — never paste full signed URLs or paths that include secrets.

**Bad (leaks signature material):**

```
/insecure/HASH_HERE/rs:fill:800:600/plain/local:///uploads/photo.jpg
```

**Good:**

```
/…/image.avif%201250w,%20https:/img.example.com/…/other-image.avif%20300w
```

### Config snippets

- Copy structure from the issue summary or companion repo; strip env-specific values.
- Docker network names like `wordpress_app-network` are fine (project-scoped, not secret).
- Never paste `.env` contents.

---

## Post file format

### Location and slug

- Path: `content/posts/<slug>.md`
- Slug: lowercase kebab-case derived from the title (e.g. `Fixing Robots.txt Unreachable` → `fixing-robots-txt-unreachable-traefik-docker.md`)
- Check existing filenames to avoid duplicates or near-duplicates.

### Frontmatter (required)

```yaml
---
title: "Human-Readable Title in Title Case"
date: 2026-07-01T10:00:00Z
draft: true
description: "One sentence for SEO/social — what happened and what the reader learns."
tags: ["WordPress", "Docker", "Traefik"]
---
```

- `date`: ISO 8601 UTC. Use today's date unless the user specifies the incident date.
- `draft: true` by default; set `draft: false` only when asked.
- `tags`: 3–7 tags from the project's vocabulary (see below). Use existing tag strings when possible.
- Do **not** add a top-level `#` heading in the body — Hugo uses `title` as the page heading.

### Body structure

Follow this outline unless the topic clearly fits a different shape (e.g. pure architecture overview):

1. **Opening paragraph** — Who "we" are, what site/stack, what problem in one or two sentences. Link [joyofexploringtheworld.com](https://joyofexploringtheworld.com/) once.
2. **Symptom / context** — What alerted or broke; tables work well for alert counts vs impact.
3. **Root cause** — Clear explanation; numbered lists for multiple contributing factors.
4. **The fix** — Concrete steps with fenced code blocks (`yaml`, `bash`, `apache`, `json`, `hcl` as appropriate).
5. **Lessons or "What you can do"** — Actionable checklist for the reader.
6. **See also** — Pipe-separated internal links to related posts: `[Title](/posts/slug/)`
7. **CTA shortcode** on its own line at the end:

```markdown
{{< cta >}}
```

The CTA renders a standard footer pointing readers to the travel blog and the companion GitHub repo. Include it on every new post unless the user says otherwise.

### Writing style

- First person plural: **we**, **our** — collaborative ops voice.
- Direct and practical; explain jargon briefly.
- Prefer short `##` sections over long walls of text.
- Use tables for comparisons (symptom vs impact, before vs after).
- British spelling is fine (`optimise`, `behaviour`) — match nearby posts.
- No engagement bait; no filler conclusions.

### Common tag vocabulary

`WordPress`, `Docker`, `Traefik`, `Cloudflare`, `Datadog`, `monitoring`, `SEO`, `imgproxy`, `DevOps`, `incident`, `WP-CLI`, `MariaDB`, `Redis`, `Terraform`, `Oracle Cloud`, `IPSec`, `hybrid`, `Google Search Console`, `Apache`, `self-hosted`, `Hetzner`, `security`

Pick tags that help readers find the post; do not tag every technology mentioned.

---

## Stack context (for accuracy, not for copy-paste)

Use this when interpreting issue summaries. Do not dump the full stack into every post.

```
Internet → Cloudflare (CDN/APO/WAF) → Traefik v3 → 2× WordPress (Docker)
  → MariaDB, Redis object cache
Sidecars: imgproxy (signed URLs, image subdomain), wp-cron sidecar, backup container, Datadog agent
Also: CrowdSec, Rank Math SEO, EDD for digital downloads
Hybrid expansion: Oracle Always Free VM (edge) + home EliteDesk over IPSec (DB/batch/standby)
Infra as code: Terraform for Cloudflare; monitors scripted to Datadog
Companion config repo: github.com/luismsousa/wordpress-docker-stack
```

Only include stack detail relevant to the issue. Link to [Running a WordPress Travel Blog on a Budget VPS](/posts/wordpress-docker-compose-production-stack/) when the whole stack matters.

---

## Internal linking

Before finishing, search `content/posts/` for related topics and add a **See also** line. Common hubs:

| Topic | Post slug |
|-------|-----------|
| Full stack overview | `wordpress-docker-compose-production-stack` |
| Traefik incidents | `why-our-site-went-down-for-an-hour`, `rank-math-sitemap-not-loading-traefik`, `fixing-robots-txt-unreachable-traefik-docker` |
| Datadog | `datadog-apache-404-wordpress-docker`, `datadog-imgproxy-bot-alerts-not-outages` |
| imgproxy | `self-hosted-wordpress-imgproxy`, `when-image-crop-error-isnt-about-the-image` |
| WP-CLI / automation | `bulk-wp-cli-guardrails-three-reboots` |
| Hybrid / Oracle | `hybrid-wordpress-oracle-elitedesk-ipsec` |
| SEO | `seo-housekeeping-focus-keywords-sitemaps` |

Use relative paths: `/posts/<slug>/`

---

## Checklist before handing off

- [ ] No secrets, tokens, full private IPs, or identifiable private hostnames
- [ ] Opening links the public travel blog once; examples use `example.com` where appropriate
- [ ] Frontmatter complete (`title`, `date`, `draft`, `description`, `tags`)
- [ ] No duplicate `#` title in body
- [ ] Code blocks have language tags and are copy-paste safe
- [ ] "See also" links to at least one existing post
- [ ] `{{< cta >}}` at the end
- [ ] Filename slug is unique and kebab-case
- [ ] User has **not** been auto-committed to unless they asked

---

## Example: turning a summary into a post

**User input (raw):**

> Datadog paged us at 3am. imgproxy 403 rate spiked to 12%. Turns out bots were requesting entire srcset strings as one URL. Had two monitors for the same thing. Fixed by removing warn threshold and clamp_min 100 on denominator. Monitor ID 12345678. IMGPROXY_SALT=abc123realvalue

**Agent output (sanitized excerpt):**

```markdown
---
title: "When Datadog Alerts Are Bots, Not Outages (imgproxy srcset Noise)"
date: 2026-06-13T12:00:00Z
draft: true
description: "Overnight email floods from imgproxy 403 monitors flapping on malformed bot URLs — and how we tuned Datadog to alert on real outages only."
tags: ["Datadog", "WordPress", "imgproxy", "monitoring", "Traefik"]
---

Nothing wakes you up like a Datadog email at 03:00 — especially when the site is healthy…
```

(Full reference: `content/posts/datadog-imgproxy-bot-alerts-not-outages.md`)

---

## License note

Blog content is [CC BY-NC-ND 4.0](./CONTENT-LICENSE.md). Code/config snippets in posts are illustrative; the MIT-licensed repo code is separate. Do not paste proprietary third-party code verbatim.
