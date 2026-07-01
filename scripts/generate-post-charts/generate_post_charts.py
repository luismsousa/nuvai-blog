#!/usr/bin/env python3
"""Generate blog post charts from Datadog metrics.

Reads DD_API_KEY, DD_APPLICATION_KEY (optional for metrics), and DD_SITE
(default datadoghq.eu) from the environment.

Usage:
  pip install -r scripts/generate-post-charts/requirements.txt
  export DD_API_KEY=... DD_APPLICATION_KEY=... DD_SITE=datadoghq.eu
  python scripts/generate-post-charts/generate_post_charts.py
"""

from __future__ import annotations

import json
import os
import sys
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import matplotlib.dates as mdates
import matplotlib.pyplot as plt
import matplotlib.ticker as mticker
import requests

REPO_ROOT = Path(__file__).resolve().parents[2]
OUTPUT_ROOT = REPO_ROOT / "static" / "images" / "posts"

# Datadog-ish palette (blog-friendly on light background)
COLOR_403 = "#E5A009"
COLOR_404 = "#D33043"
COLOR_PUBLIC = "#4B66EA"
COLOR_ADMIN = "#632CA6"
COLOR_MUTED = "#6A737D"
COLOR_GRID = "#E1E4E8"

# Incident window referenced in the posts (UTC)
APO_PURGE = datetime(2026, 7, 1, 12, 0, tzinfo=timezone.utc)
CHART_FROM = datetime(2026, 6, 25, 0, 0, tzinfo=timezone.utc)
CHART_TO = datetime(2026, 7, 2, 0, 0, tzinfo=timezone.utc)
TRIAGE_FROM = datetime(2026, 6, 30, 0, 0, tzinfo=timezone.utc)
TRIAGE_TO = datetime(2026, 7, 1, 23, 59, tzinfo=timezone.utc)


@dataclass
class Series:
    label: str
    points: list[tuple[datetime, float]]
    color: str


class DatadogClient:
    def __init__(self) -> None:
        self.api_key = os.environ.get("DD_API_KEY", "")
        self.app_key = os.environ.get("DD_APPLICATION_KEY", "")
        self.site = os.environ.get("DD_SITE", "datadoghq.eu")
        if not self.api_key:
            raise SystemExit(
                "DD_API_KEY is required. Export it or load from .cursor/mcp.json locally."
            )
        self.base = f"https://api.{self.site}"
        self.headers = {"DD-API-KEY": self.api_key}
        if self.app_key:
            self.headers["DD-APPLICATION-KEY"] = self.app_key

    def query_timeseries(
        self, query: str, start: datetime, end: datetime
    ) -> list[tuple[datetime, float]]:
        params = {
            "from": int(start.timestamp()),
            "to": int(end.timestamp()),
            "query": query,
        }
        resp = requests.get(
            f"{self.base}/api/v1/query",
            headers=self.headers,
            params=params,
            timeout=60,
        )
        resp.raise_for_status()
        payload = resp.json()
        series_list = payload.get("series") or []
        if not series_list:
            return []
        pointlist = series_list[0].get("pointlist") or []
        points: list[tuple[datetime, float]] = []
        for ts_ms, value in pointlist:
            if value is None:
                continue
            points.append(
                (datetime.fromtimestamp(ts_ms / 1000, tz=timezone.utc), float(value))
            )
        return points

    def query_scalar_sum(
        self, query: str, start: datetime, end: datetime
    ) -> float:
        points = self.query_timeseries(query, start, end)
        return sum(v for _, v in points)

    def count_logs(self, filter_query: str, start: datetime, end: datetime) -> int:
        if not self.app_key:
            return 0
        body = {
            "filter": {
                "query": filter_query,
                "from": start.isoformat(),
                "to": end.isoformat(),
            },
            "compute": [{"aggregation": "count", "type": "total"}],
        }
        resp = requests.post(
            f"{self.base}/api/v2/logs/analytics/aggregate",
            headers={**self.headers, "Content-Type": "application/json"},
            json=body,
            timeout=60,
        )
        if resp.status_code == 403:
            return 0
        resp.raise_for_status()
        data = resp.json()
        buckets = data.get("data", {}).get("buckets") or []
        if not buckets:
            return 0
        return int(buckets[0].get("computes", {}).get("c0", 0))


def apply_style() -> None:
    plt.rcParams.update(
        {
            "figure.facecolor": "white",
            "axes.facecolor": "white",
            "axes.edgecolor": COLOR_GRID,
            "axes.labelcolor": "#24292F",
            "axes.titlecolor": "#24292F",
            "text.color": "#24292F",
            "xtick.color": COLOR_MUTED,
            "ytick.color": COLOR_MUTED,
            "grid.color": COLOR_GRID,
            "grid.linestyle": "-",
            "grid.linewidth": 0.6,
            "font.size": 11,
            "axes.titlesize": 13,
            "axes.titleweight": "bold",
            "legend.frameon": False,
            "savefig.bbox": "tight",
            "savefig.pad_inches": 0.15,
        }
    )


def save_fig(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    plt.savefig(path, dpi=160)
    plt.close()
    print(f"  wrote {path.relative_to(REPO_ROOT)}")


def style_axes(ax: plt.Axes, *, ylabel: str, title: str) -> None:
    ax.set_title(title, loc="left", pad=12)
    ax.set_ylabel(ylabel)
    ax.grid(True, axis="y", alpha=0.9)
    ax.spines["top"].set_visible(False)
    ax.spines["right"].set_visible(False)
    ax.xaxis.set_major_formatter(mdates.DateFormatter("%d %b"))
    ax.xaxis.set_major_locator(mdates.DayLocator(interval=1))
    plt.setp(ax.get_xticklabels(), rotation=0, ha="center")


def plot_timeseries(
    series_list: list[Series],
    *,
    title: str,
    ylabel: str,
    output: Path,
    annotate: datetime | None = None,
    annotate_text: str | None = None,
    fill_between: bool = False,
) -> None:
    fig, ax = plt.subplots(figsize=(10, 4.2))
    for s in series_list:
        if not s.points:
            continue
        xs, ys = zip(*s.points)
        ax.plot(xs, ys, label=s.label, color=s.color, linewidth=2.2)
        if fill_between:
            ax.fill_between(xs, ys, alpha=0.12, color=s.color)
    if annotate and annotate_text:
        ax.axvline(annotate, color=COLOR_MUTED, linestyle="--", linewidth=1.2, alpha=0.8)
        ax.text(
            annotate,
            ax.get_ylim()[1] * 0.92,
            annotate_text,
            color=COLOR_MUTED,
            fontsize=10,
            ha="left",
            va="top",
            rotation=90,
        )
    style_axes(ax, ylabel=ylabel, title=title)
    ax.legend(loc="upper right")
    fig.autofmt_xdate()
    save_fig(output)


def plot_grouped_bars(
    categories: list[str],
    groups: list[tuple[str, list[float], str]],
    *,
    title: str,
    ylabel: str,
    output: Path,
    log_y: bool = False,
) -> None:
    fig, ax = plt.subplots(figsize=(8.5, 4.5))
    x = range(len(categories))
    width = 0.8 / max(len(groups), 1)
    for i, (label, values, color) in enumerate(groups):
        offsets = [pos + (i - (len(groups) - 1) / 2) * width for pos in x]
        ax.bar(offsets, values, width=width, label=label, color=color)
    ax.set_xticks(list(x))
    ax.set_xticklabels(categories)
    ax.set_ylabel(ylabel)
    ax.set_title(title, loc="left", pad=12)
    ax.grid(True, axis="y", alpha=0.9)
    ax.spines["top"].set_visible(False)
    ax.spines["right"].set_visible(False)
    if log_y:
        ax.set_yscale("log")
        ax.yaxis.set_major_formatter(mticker.ScalarFormatter())
        ax.yaxis.get_major_formatter().set_scientific(False)
    if len(groups) > 1:
        ax.legend(loc="upper right")
    save_fig(output)


def chart_triage_signal_comparison(dd: DatadogClient) -> None:
    log_errors = dd.count_logs("status:error env:production", TRIAGE_FROM, TRIAGE_TO)
    if log_errors == 0:
        # Fallback from the incident write-up when Logs aggregate needs App key.
        log_errors = 1

    imgproxy_404 = int(
        dd.query_scalar_sum(
            "sum:traefik.service.request.total{service:imgproxy_docker,code:404}.as_count()",
            TRIAGE_FROM,
            TRIAGE_TO,
        )
    )
    imgproxy_403 = int(
        dd.query_scalar_sum(
            "sum:traefik.service.request.total{service:imgproxy_docker,code:403}.as_count()",
            TRIAGE_FROM,
            TRIAGE_TO,
        )
    )

    plot_grouped_bars(
        ["Log index\n(status:error)", "imgproxy 403\n(Traefik)", "imgproxy 404\n(Traefik)"],
        [("24h count (production)", [log_errors, imgproxy_403, imgproxy_404], COLOR_PUBLIC)],
        title="Where the signal was during 24h triage",
        ylabel="Event count",
        output=OUTPUT_ROOT
        / "wordpress-incident-triage-apm-not-logs"
        / "triage-signal-comparison.png",
        log_y=True,
    )


def chart_imgproxy_403_vs_404(dd: DatadogClient, output_dir: Path, title_suffix: str) -> None:
    q403 = "sum:traefik.service.request.total{service:imgproxy_docker,code:403}.as_count()"
    q404 = "sum:traefik.service.request.total{service:imgproxy_docker,code:404}.as_count()"
    plot_timeseries(
        [
            Series("403 Invalid signature / bot noise", dd.query_timeseries(q403, CHART_FROM, CHART_TO), COLOR_403),
            Series("404 Source not allowed (stale HTML)", dd.query_timeseries(q404, CHART_FROM, CHART_TO), COLOR_404),
        ],
        title=f"imgproxy error responses at Traefik {title_suffix}",
        ylabel="Requests per interval",
        output=output_dir / "imgproxy-403-vs-404.png",
        annotate=APO_PURGE,
        annotate_text="APO purge",
    )


def chart_admin_vs_public_p95(dd: DatadogClient) -> None:
    q_public = "avg:traefik.service.request.duration.95percentile{service:wordpress_docker}"
    q_admin = "avg:traefik.service.request.duration.95percentile{service:wordpress-admin_docker}"
    public = dd.query_timeseries(q_public, CHART_FROM, CHART_TO)
    admin = dd.query_timeseries(q_admin, CHART_FROM, CHART_TO)

    fig, ax = plt.subplots(figsize=(10, 4.2))
    if public:
        xs, ys = zip(*public)
        ax.plot(xs, [y * 1000 for y in ys], label="Public (wordpress_docker)", color=COLOR_PUBLIC, linewidth=2.2)
    if admin:
        xs, ys = zip(*admin)
        ax.plot(xs, [y * 1000 for y in ys], label="Admin / REST (wordpress-admin_docker)", color=COLOR_ADMIN, linewidth=2.2)
    style_axes(ax, ylabel="p95 latency (ms)", title="WordPress Traefik p95 — public vs wp-admin")
    ax.legend(loc="upper right")
    fig.autofmt_xdate()
    save_fig(
        OUTPUT_ROOT
        / "wordpress-opcache-full-block-editor-slow"
        / "admin-vs-public-p95.png"
    )


def chart_opcache_before_after() -> None:
    """Static bars from in-container opcache_get_status() — no Datadog metric exists."""
    plot_grouped_bars(
        ["Free memory (MB)", "Max accelerated files"],
        [
            ("Before (image defaults won)", [0, 4000], COLOR_404),
            ("After (zz-opcache-production.ini)", [141, 10000], COLOR_PUBLIC),
        ],
        title="OPcache headroom before and after zz-opcache-production.ini",
        ylabel="Value",
        output=OUTPUT_ROOT
        / "wordpress-opcache-full-block-editor-slow"
        / "opcache-before-after.png",
    )


def write_manifest(manifest: dict[str, Any]) -> None:
    path = OUTPUT_ROOT / "manifest.json"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"  wrote {path.relative_to(REPO_ROOT)}")


def main() -> int:
    apply_style()
    dd = DatadogClient()
    print("Generating charts from Datadog metrics…")

    chart_triage_signal_comparison(dd)

    triage_dir = OUTPUT_ROOT / "wordpress-incident-triage-apm-not-logs"
    apo_dir = OUTPUT_ROOT / "stale-cloudflare-apo-imgproxy-r2-migration"
    opcache_dir = OUTPUT_ROOT / "wordpress-opcache-full-block-editor-slow"

    chart_imgproxy_403_vs_404(dd, triage_dir, "(7d)")
    chart_imgproxy_403_vs_404(dd, apo_dir, "(7d — APO purge marked)")

    chart_admin_vs_public_p95(dd)
    chart_opcache_before_after()

    manifest = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "site": dd.site,
        "window": {"from": CHART_FROM.isoformat(), "to": CHART_TO.isoformat()},
        "charts": [
            "wordpress-incident-triage-apm-not-logs/triage-signal-comparison.png",
            "wordpress-incident-triage-apm-not-logs/imgproxy-403-vs-404.png",
            "stale-cloudflare-apo-imgproxy-r2-migration/imgproxy-403-vs-404.png",
            "wordpress-opcache-full-block-editor-slow/admin-vs-public-p95.png",
            "wordpress-opcache-full-block-editor-slow/opcache-before-after.png",
        ],
    }
    write_manifest(manifest)
    print("Done.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
