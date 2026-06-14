---
title: "Three Reboots in One Afternoon: Guardrails for Bulk WP-CLI on Docker WordPress"
date: 2026-06-13T11:00:00Z
draft: false
description: "260 parallel wpcli containers, 10–20 GB runaway PHP processes, and a Site Editor overlap — how we built batch-guard.sh and wp-batch.sh to stop host starvation."
tags: ["WordPress", "Docker", "WP-CLI", "DevOps", "SEO"]
---

An AI agent running Semrush SEO fixes is a wonderful thing — until your Oracle VM stops answering SSH and you reboot for the third time before lunch.

That happened on our travel blog ([joyofexploringtheworld.com](https://joyofexploringtheworld.com/)): a 23 GB RAM host running WordPress in Docker with two web replicas, MariaDB, Redis, Traefik, imgproxy, Datadog, CrowdSec, and a steady stream of `docker compose run --rm wpcli` invocations. The site was fine. The **host** was not.

## What the logs showed

| Signal | Count (one afternoon) |
|--------|----------------------|
| Ephemeral `wordpress-wpcli-run-*` containers | **260+** in one boot session |
| Kernel OOM kills of PHP | 3 (processes at **10–20 GB** RSS) |
| Apache cgroup OOM kills inside WordPress containers | 79 |
| `MaxRequestWorkers` saturation events | 9 |
| Host reboots | 3 |

The root cause was not Datadog, not Netdata, not Cloudflare. It was **unbounded parallel bulk work** overlapping with live wp-admin editing.

## Mistake 1: PHP memory limit ≠ container memory limit

The `wpcli` service had `PHP_MEMORY_LIMIT=512M` — but **no Docker `mem_limit`**. Each `docker compose run wpcli` loads full WordPress. When an agent looped dozens of separate `wp eval` calls, runaway scripts grew until the **kernel OOM killer** stepped in.

Fix:

```yaml
wpcli:
  image: wordpress:cli
  mem_limit: 768m
  mem_reservation: 128m
  # ...
```

Now a runaway script dies inside the container instead of consuming half the host.

## Mistake 2: one WP-CLI invocation per record

Category meta updates, content audits, verification curls — each as its own `docker compose run` — means:

- Cold WordPress bootstrap every time
- Parallel containers stacking on the host
- Redis/MariaDB cache churn on every write

Prefer **one** `eval-file` script with internal batching:

```php
foreach (array_chunk($term_ids, 5) as $batch) {
    foreach ($batch as $term_id) {
        // update term meta ...
    }
    sleep(2); // let MariaDB and object cache breathe
}
```

Run it through a wrapper, not raw compose:

```bash
./scripts/wp-batch.sh eval-file scripts/apply-category-descriptions.php
```

## Mistake 3: bulk work while the Site Editor is open

Around the first crash, `/wp-admin/site-editor.php` was active during an admin session while bulk WP-CLI ran in parallel. The block editor alone fires 30+ REST requests; bulk writes invalidate cache; Apache workers saturated; PHP hit 1536M per worker.

**Hard rule:** never overlap bulk maintenance with wp-admin / block editor sessions.

## The guardrail scripts

We added two bash scripts to our [WordPress Docker stack](https://github.com/luismsousa/wordpress-docker-stack).

### `batch-guard.sh` — pre-flight checks

```bash
./scripts/batch-guard.sh --status   # human-readable report
./scripts/batch-guard.sh            # exit 1 if unsafe
./scripts/batch-guard.sh --wait     # poll until safe (10 min timeout)
```

It checks:

- Host `MemAvailable` (default ≥ 4 GB)
- Load per CPU, swap usage
- Running `wpcli` containers (default: **zero** — one job at a time)
- Apache `BusyWorkers` on **both** WordPress replicas
- Recent kernel OOM events
- Recent wp-admin activity (last 5 minutes)
- Exclusive batch lock (`.batch-lock`)

### `wp-batch.sh` — guarded wrapper

```bash
./scripts/wp-batch.sh eval-file scripts/your-script.php
./scripts/wp-batch.sh --no-lock option get siteurl   # read-only only
```

Every bulk command runs the guard, acquires the lock, then `docker compose run --rm wpcli`. Quick read-only checks can skip the lock with `--no-lock`.

Emergency override for admin overlap (owner-approved only):

```bash
BATCH_GUARD_SKIP_ADMIN=1 ./scripts/wp-batch.sh eval-file scripts/...
```

## Agent-driven maintenance checklist

If you use Cursor, Claude, or any automation against production WordPress:

1. **Pre-flight:** `./scripts/batch-guard.sh --status`
2. **One bulk job at a time** — wait for the lock; do not launch parallel agent tasks
3. **One eval-file script** with batches of 5–10 + `sleep 2`, not N separate WP-CLI calls
4. **No Site Editor overlap** — batch-guard blocks when wp-admin was active in the last 5 minutes
5. **Minimal verification** — homepage + one archive after bulk changes, not a crawl of every URL
6. **Watch logs** during long jobs:

   ```bash
   docker compose logs -f --since=1m wordpress 2>&1 | grep -iE 'MaxRequestWorkers|memory|fatal'
   ```

7. **Stop if workers saturate** — resume off-hours

## What we learned about “helpful” automation

Agents default to the tool they know: `docker compose run wpcli` in a loop. That pattern is fine on a dev laptop. On a constrained production host sharing RAM with live traffic and a block editor, it is a **host-kill switch**.

The fix is not “never automate.” It is **centralise bulk work behind guardrails** and treat WP-CLI like a batch job system, not a REPL you spawn fifty times.

## After the guardrails

Post-reboot, the same host runs calmly at ~3 GB used with healthy Apache workers. Semrush fixes completed; the site stayed up; the difference was **how** maintenance ran, not **what** changed.

If you operate WordPress on a single VM with agents in the loop, steal the pattern: cap WP-CLI memory in Docker, pre-flight the host, one lock, one script, no admin overlap. Your future self (and your hosting bill) will thank you.
