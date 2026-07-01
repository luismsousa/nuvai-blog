#!/usr/bin/env bash
# One-time setup on miniagent (run from Screen Sharing or a local Terminal session).
# Creates bootstrap.env so headless SSH/n8n can unlock the login keychain before Proton Pass resolves secrets.
set -euo pipefail

REPO="${REPO:-/Users/luissousa/code/nuvai-blog}"
BOOTSTRAP_FILE="${BOOTSTRAP_FILE:-$REPO/.cursor/automation/renovate-review/bootstrap.env}"
KEYCHAIN_PASS_URI="${KEYCHAIN_PASS_URI:-pass://Homelab/KEYCHAIN_PASSWORD/password}"

export PATH="/opt/homebrew/bin:/usr/local/bin:${HOME}/.local/bin:${PATH:-/usr/bin:/bin:/usr/sbin:/sbin}"

if [[ -f "$BOOTSTRAP_FILE" ]]; then
  echo "bootstrap.env already exists: $BOOTSTRAP_FILE"
  exit 0
fi

if ! command -v pass-cli >/dev/null 2>&1; then
  echo "pass-cli not found. Install with: brew install proton-pass-cli" >&2
  exit 1
fi

if ! pass-cli test >/dev/null 2>&1; then
  echo "pass-cli is not authenticated. Run: pass-cli login" >&2
  exit 1
fi

KEYCHAIN_PASSWORD_BOOTSTRAP=""
if KEYCHAIN_PASSWORD_BOOTSTRAP="$(pass-cli item view "$KEYCHAIN_PASS_URI" 2>/dev/null)"; then
  echo "Using KEYCHAIN_PASSWORD from Proton Pass ($KEYCHAIN_PASS_URI)."
else
  read -rsp "macOS login password (unlocks keychain for headless SSH): " KEYCHAIN_PASSWORD_BOOTSTRAP
  echo
fi

if [[ -z "$KEYCHAIN_PASSWORD_BOOTSTRAP" ]]; then
  echo "No keychain password provided." >&2
  exit 1
fi

mkdir -p "$(dirname "$BOOTSTRAP_FILE")"
umask 077
printf 'KEYCHAIN_PASSWORD_BOOTSTRAP=%s\n' "$KEYCHAIN_PASSWORD_BOOTSTRAP" >"$BOOTSTRAP_FILE"
chmod 600 "$BOOTSTRAP_FILE"

echo "Wrote $BOOTSTRAP_FILE"
echo "Verify with: bash $REPO/scripts/renovate-review-agent.sh"
