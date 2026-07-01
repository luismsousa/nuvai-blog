#!/usr/bin/env bash
# Regenerate blog post charts from Datadog. Loads keys from .cursor/mcp.json when present.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
VENV="$ROOT/scripts/generate-post-charts/.venv"
REQ="$ROOT/scripts/generate-post-charts/requirements.txt"
SCRIPT="$ROOT/scripts/generate-post-charts/generate_post_charts.py"
MCP="$ROOT/.cursor/mcp.json"

if [[ ! -d "$VENV" ]]; then
  python3 -m venv "$VENV"
  "$VENV/bin/pip" install -q -r "$REQ"
fi

export DD_SITE="${DD_SITE:-datadoghq.eu}"

if [[ -z "${DD_API_KEY:-}" && -f "$MCP" ]]; then
  eval "$(
    python3 - <<'PY'
import json, shlex
from pathlib import Path
mcp = json.loads(Path(".cursor/mcp.json").read_text())
h = mcp.get("mcpServers", {}).get("datadog", {}).get("headers", {})
for k in ("DD_API_KEY", "DD_APPLICATION_KEY"):
    v = h.get(k, "")
    if v:
        print(f"export {k}={shlex.quote(v)}")
PY
  )"
fi

if [[ -z "${DD_API_KEY:-}" ]]; then
  echo "DD_API_KEY required (export it or add datadog headers to .cursor/mcp.json)" >&2
  exit 1
fi

cd "$ROOT"
exec "$VENV/bin/python" "$SCRIPT"
