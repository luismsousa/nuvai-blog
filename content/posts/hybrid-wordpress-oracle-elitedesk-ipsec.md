---
title: "Hybrid WordPress: Free Oracle VM + Home EliteDesk over IPSec"
date: 2026-06-13T13:00:00Z
draft: false
description: "Splitting MariaDB, batch jobs, and warm standby onto a 60 GB home server while keeping Traefik and WordPress on Oracle Always Free — with IPSec, R2, and Cloudflare Tunnel."
tags: ["WordPress", "Docker", "Oracle Cloud", "IPSec", "hybrid", "Cloudflare"]
---

Running everything on one free-tier cloud VM works until it does not. Ours did not: on [joyofexploringtheworld.com](https://joyofexploringtheworld.com/), block editor REST storms, bulk SEO automation, MariaDB, ~100 GB of media, imgproxy, and backups all competed for four vCPUs and 23 GB RAM on a single Oracle instance.

The cheapest upgrade path was not another €5 VPS. It was hardware we already owned — **HP EliteDesk mini PCs with 60 GB RAM** — connected to Oracle over **Always Free IPSec** via a home gateway that supports site-to-site VPN.

This post summarises the hybrid architecture we planned and started implementing.

## The constraint

| Layer | Config | Risk under load |
|-------|--------|-----------------|
| WordPress × 2 | 4 Apache workers × 1536M PHP each | 8 concurrent admin/REST requests fleet-wide |
| MariaDB | 2 GB InnoDB buffer on same VM | Competes with PHP |
| Redis, Traefik, imgproxy, Datadog, CrowdSec | ~3 GB more | Background work stacks |
| Media | Large library on local disk | Disk I/O + huge backup tarballs |

Software fixes helped (admin round-robin routing, [batch guardrails](/posts/bulk-wp-cli-guardrails-three-reboots/), REST cache for anonymous users, Jetpack re-entry guard). The next win is **separating state and batch work** from the public edge.

## Target architecture

```
                 Cloudflare (APO + CDN + WAF)
                           │
              ┌────────────┴────────────┐
              │   Oracle VM (edge)      │
              │ Traefik, WP×2, Redis    │
              │ imgproxy, CrowdSec      │
              └────────────┬────────────┘
                           │ IPSec (private)
              ┌────────────┴────────────┐
              │ Home LAN — EliteDesk    │
              │ MariaDB, wp-cron, batch │
              │ warm standby WP (idle)  │
              │ cloudflared (Tunnel)    │
              └────────────┬────────────┘
                           │
              ┌────────────┴────────────┐
              │ Cloudflare R2 (media)     │
              │ Offsite backup storage    │
              └─────────────────────────┘
```

**Normal operation:** visitors hit Oracle; WordPress talks to MariaDB on the EliteDesk over IPSec; Redis stays on Oracle next to PHP.

**Failover:** Cloudflare Tunnel exposes standby WordPress + imgproxy at home without opening ports; media still served from R2.

## Why IPSec over WireGuard

Oracle provides **50 free site-to-site IPSec tunnels**. With a home router that supports IPSec, it is the long-term fabric:

| | Oracle IPSec + home gateway | WireGuard point-to-point |
|--|---------------------------|--------------------------|
| Cost | Free | Free |
| Routing | Whole subnets (VCN ↔ LAN) | Usually two peers |
| Where it runs | Gateway hardware / kernel | Extra process on Oracle VM |
| Scaling | Add home services on LAN | Extra tunnels per service |

WireGuard remains a fine **fallback** if Oracle’s IPSec docs and IKE parameters fight you. IPSec is the target for DB + standby on the same LAN.

Typical layout:

```
Oracle VCN (10.0.0.0/24)
  └── WordPress VM (10.0.0.x) ──IPSec──► Home LAN (192.168.x.0/24)
                                            └── EliteDesk (192.168.x.x)
                                                  MariaDB :3306
```

**Firewall:** allow TCP 3306 from the Oracle VCN subnet → EliteDesk IP only. Never port-forward MariaDB to the internet.

Latency between cloud and home in the same country is usually **5–15 ms** — fine for MariaDB. Keep Redis on Oracle; object cache should sit next to production PHP, not across the tunnel.

## Service placement matrix

### EliteDesk (always)

- **MariaDB primary** — 8–16 GB `innodb_buffer_pool_size` on a 60 GB host
- **wp-cron + wp-batch.sh** — all bulk WP-CLI / agent maintenance
- **Backups** — dump locally, push to offsite storage
- **Warm standby WordPress** (Phase 4) — idle until failover
- **cloudflared** — Cloudflare Tunnel for standby origin

### Oracle (production edge)

- **Traefik + TLS** — static IP, Cloudflare origin
- **WordPress × 2** — `WORDPRESS_DB_HOST` → EliteDesk LAN IP
- **Redis** — low latency to WP
- **imgproxy** — reads R2 after media migration
- **CrowdSec + Datadog** — tied to live Traefik logs

### Do not duplicate on standby

| Service | Why skip |
|---------|----------|
| CrowdSec | Production edge only; Cloudflare WAF covers DR |
| Full Traefik | Tunnel terminates TLS at Cloudflare |
| Media on disk | R2 is shared store |
| Production Redis | Cold cache on failover is acceptable |

## Phase 2: MariaDB migration

1. Stand up MariaDB on EliteDesk with tuned `innodb_buffer_pool_size` (start at 8G).
2. Maintenance window: `mariadb-dump` on Oracle → restore on EliteDesk.
3. Point Oracle `WORDPRESS_DB_HOST` at EliteDesk IP; stop Oracle `db` service.
4. Move `wp-cron` and all `./scripts/wp-batch.sh` execution to EliteDesk.
5. Keep Oracle DB volume **7 days** for rollback.

Grant MySQL access only from the Oracle subnet:

```sql
CREATE USER IF NOT EXISTS 'wordpress'@'10.0.0.%' IDENTIFIED BY '<strong-password>';
GRANT ALL ON wordpress.* TO 'wordpress'@'10.0.0.%';
```

## Phase 3: Cloudflare R2 + imgproxy

A large media library on disk makes backups slow and standby painful. Move **Media Library** images to R2; keep **EDD protected downloads** (`uploads/edd/`) off public buckets — they rely on token validation and `.htaccess` 403.

We chose **[Advanced Media Offloader](https://wordpress.org/plugins/advanced-media-offloader/)** over WP Offload Media: native R2, free core + `wp advmo offload` for bulk migration via our guarded WP-CLI wrapper, credentials in `wp-config.php`.

imgproxy today reads a local Docker volume via `local://` paths. After R2, update the mu-plugin to pass through `https://media.example.com/...` as HTTPS sources and add the host to `IMGPROXY_ALLOWED_SOURCES`. Cloudflare still caches imgproxy output at the image subdomain — R2 is hit on cache miss only.

## Phase 4: Warm standby + Cloudflare Tunnel

Standby stack on EliteDesk (minimal):

- WordPress × 1 → local MariaDB
- imgproxy → same R2 config
- cloudflared → Tunnel to Cloudflare

Failover options:

- **Free (manual):** swap Cloudflare origin from Oracle IP to Tunnel hostname in Terraform (~30–60 min RTO)
- **Paid (~$5/mo):** Cloudflare Load Balancing with health checks on `/health.php`

IPSec and Tunnel solve **different** problems: IPSec is private Oracle ↔ home; Tunnel is public Cloudflare ↔ home without opening ports.

## What we deliberately avoided

| Idea | Why defer |
|------|-----------|
| Third WP replica on same Oracle VM | Same RAM ceiling |
| Raise MaxRequestWorkers without raising container mem_limit | OOM cycle |
| Docker Swarm multi-host WP without object storage | Shared volume does not cross hosts cleanly |
| Production solely from home ISP | Power/uptime risk — fine for worker/DR, not primary origin |

## If you only do one thing

**Move MariaDB + batch/cron to the EliteDesk over IPSec.** Highest impact, ~£0 incremental cost, frees Oracle CPU/RAM for HTTP and stops batch jobs from causing cloud VM reboots.

We keep a living runbook in our [WordPress Docker stack repo](https://github.com/luismsousa/wordpress-docker-stack) with full checklists, network tables, imgproxy migration steps, and agent ownership (home vs Oracle) on each side of the tunnel.

Hybrid does not mean complex for its own sake. It means putting **interruptible heavy work** and **durable state** where RAM is cheap, and keeping the **reliable public IP** where Cloudflare expects it.
