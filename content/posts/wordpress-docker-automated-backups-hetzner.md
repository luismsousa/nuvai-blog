---
title: "Automated WordPress Backups to Hetzner with Docker (Zero Plugins)"
date: 2026-03-07T12:08:00Z
draft: false
description: "Daily automated backups of WordPress and MariaDB to a Hetzner Storage Box using Docker, offen/docker-volume-backup, and SFTP—no plugins required."
tags: ["WordPress", "Docker", "backup", "Hetzner", "MariaDB", "disaster-recovery"]
---

We run a travel blog at [joyofexploringtheworld.com](https://joyofexploringtheworld.com/) on a single VPS with Docker Compose. Managed backup plugins add overhead, cost money, and only back up what WordPress can see. We wanted to back up everything—volumes, configs, database—automatically, with offsite copies. Here's how we did it with zero WordPress plugins.

## The backup service

We use [offen/docker-volume-backup](https://github.com/offen/docker-volume-backup) as a sidecar container in our Docker Compose stack. It runs on a cron schedule, tars up the mounted volumes, and ships the archive to a remote Hetzner Storage Box via SFTP.

```yaml
# docker-compose.yml — backup service
backup:
  image: offen/docker-volume-backup:v2
  restart: always
  env_file: ./backup.env
  volumes:
    - wordpress:/backup/wordpress:ro
    - db:/backup/db:ro
    - ./config:/backup/host-config/config:ro
    - ./.env:/backup/host-config/env-wordpress:ro
    - ./.env-traefik:/backup/host-config/env-traefik:ro
    - ./wp-content/mu-plugins:/backup/host-config/mu-plugins:ro
    - /var/run/docker.sock:/var/run/docker.sock:ro
    - /path/to/local/backups:/archive
    - ./config/backup-ssh-key:/run/secrets/backup-ssh-key:ro
```

The `backup.env` file controls the schedule and remote destination:

```bash
BACKUP_CRON_EXPRESSION=0 2 * * *
BACKUP_RETENTION_DAYS=7

SSH_HOST=your-subaccount.your-storagebox.de
SSH_PORT=23
SSH_USER=your-subaccount
SSH_REMOTE_PATH=/home/backups/
SSH_IDENTITY_FILE_PATH=/run/secrets/backup-ssh-key
```

## Pre-backup database dump

The backup tool can stop containers for consistency, but we also want a logical SQL dump inside the archive. We use a Docker label on the `db` service to run `mariadb-dump` just before the backup starts:

```yaml
# docker-compose.yml — db service labels
db:
  image: mariadb:latest
  labels:
    - docker-volume-backup.stop-during-backup=true
    - "docker-volume-backup.archive-pre=/bin/sh -c 'mariadb-dump --all-databases -uroot -p\"$$MARIADB_ROOT_PASSWORD\" > /var/lib/mysql/all-databases.sql'"
```

This `archive-pre` hook runs inside the running `db` container, so you get a fresh SQL dump in `/var/lib/mysql/` right before the volume is archived. The dump file rides along in the tar archive alongside the raw MariaDB data files—belt and braces.

## What gets backed up

| Data | Source | Archive path |
|------|--------|--------------|
| WordPress core, plugins, themes, uploads | Docker volume `wordpress` | `/backup/wordpress/` |
| MariaDB data files + SQL dump | Docker volume `db` | `/backup/db/` |
| Apache, Traefik, Datadog, MariaDB configs | `./config/` | `/backup/host-config/config/` |
| Let's Encrypt certificates | `./config/letsencrypt/` | `/backup/host-config/config/letsencrypt/` |
| WordPress and Traefik env files | `./.env`, `./.env-traefik` | `/backup/host-config/` |
| MU-plugins | `./wp-content/mu-plugins/` | `/backup/host-config/mu-plugins/` |

## The backup lifecycle

1. The `archive-pre` hook runs `mariadb-dump` inside the running `db` container
2. WordPress and DB containers are stopped for filesystem consistency
3. A tar.gz archive is created from all mounted volumes
4. Containers are restarted
5. The archive is saved locally
6. The archive is uploaded via SFTP to the Hetzner Storage Box
7. Archives older than 7 days are pruned from both locations

## Restoring from backup

For a restore on the same server:

```bash
# List available local backups
ls -lh /path/to/local/backups/backup-*.tar.gz

# Or fetch from Hetzner if local is gone
sftp -P 23 -i ./config/backup-ssh-key \
  your-subaccount@your-subaccount.your-storagebox.de:/home/backups/
```

For a full disaster recovery on a fresh server, the steps are: install Docker, download the backup from Hetzner, extract config files, restore Docker volumes, and bring the stack up. We keep a detailed [RECOVERY.md](https://github.com/luismsousa/wordpress-docker-stack/blob/main/RECOVERY.md) in the companion repo with the full procedure.

## What you can do

1. Add `offen/docker-volume-backup` as a sidecar to your Docker Compose stack.
2. Use `archive-pre` labels for a pre-backup database dump.
3. Ship archives to a remote location (Hetzner Storage Box, S3, etc.) via SFTP or other protocols.
4. Set a retention policy so old backups are pruned automatically.
5. Write a `RECOVERY.md` and test the restore procedure before you need it.

The full backup config, docker-compose.yml, and RECOVERY.md are in the [companion repo](https://github.com/luismsousa/wordpress-docker-stack).

**See also**: [Running a WordPress Travel Blog on a Budget VPS: The Full Stack](/posts/wordpress-docker-compose-production-stack/) | [How We Sped Up Our Travel Blog](/posts/how-we-sped-up-our-travel-blog/)

{{< cta >}}
