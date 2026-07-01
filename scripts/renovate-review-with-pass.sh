#!/usr/bin/env bash
# Wrapper that resolves pass:// secrets via Proton Pass CLI, then runs the review agent.
set -euo pipefail

REPO="${REPO:-/Users/luissousa/code/nuvai-blog}"
SECRETS_ENV="${SECRETS_ENV:-$REPO/.cursor/automation/renovate-review/secrets.env}"
PASS_CLI="${PASS_CLI_BIN:-pass-cli}"

export PATH="/opt/homebrew/bin:/usr/local/bin:${HOME}/.local/bin:${PATH:-/usr/bin:/bin:/usr/sbin:/sbin}"

if ! command -v "$PASS_CLI" >/dev/null 2>&1; then
  echo "pass-cli not found. Install with: brew install proton-pass-cli" >&2
  exit 1
fi

if [[ ! -f "$SECRETS_ENV" ]]; then
  echo "Missing secrets env: $SECRETS_ENV" >&2
  echo "Copy secrets.env.example and replace pass:// URIs with your vault/item/field paths." >&2
  exit 1
fi

exec "$PASS_CLI" run --env-file "$SECRETS_ENV" -- \
  bash "$REPO/scripts/renovate-review-agent.sh"
