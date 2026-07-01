#!/usr/bin/env bash
set -euo pipefail

PRODUCTION_URL="https://blog.nuvai.cloud"

git submodule update --init --recursive

if [ "${CF_PAGES_BRANCH:-}" = "main" ] || [ -z "${CF_PAGES:-}" ]; then
  BASE_URL="$PRODUCTION_URL"
else
  BASE_URL="${CF_PAGES_URL:-$PRODUCTION_URL}"
fi

hugo --gc --minify --baseURL "$BASE_URL"
