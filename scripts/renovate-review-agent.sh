#!/usr/bin/env bash
# Run on miniagent (via n8n SSH) to review and merge safe Renovate PRs with Cursor Agent CLI.
set -euo pipefail

REPO="${REPO:-/Users/luissousa/code/nuvai-blog}"
GITHUB_OWNER="${GITHUB_OWNER:-luismsousa}"
GITHUB_REPO="${GITHUB_REPO:-nuvai-blog}"
CONFIG_FILE="${CONFIG_FILE:-$REPO/.cursor/automation/renovate-review/config.json}"
BOOTSTRAP_FILE="${BOOTSTRAP_FILE:-$REPO/.cursor/automation/renovate-review/bootstrap.env}"

export PATH="/opt/homebrew/bin:/usr/local/bin:${HOME}/.local/bin:${HOME}/.cursor/bin:${PATH:-/usr/bin:/bin:/usr/sbin:/sbin}"

if [[ ! -d "$REPO" ]]; then
  echo "Repository not found: $REPO" >&2
  exit 1
fi

if [[ -f "$BOOTSTRAP_FILE" ]]; then
  # shellcheck disable=SC1090
  set -a
  source "$BOOTSTRAP_FILE"
  set +a
fi

ensure_pass_cli_session() {
  if command -v pass-cli >/dev/null 2>&1 && pass-cli test >/dev/null 2>&1; then
    return 0
  fi

  if [[ -z "${PROTON_PASS_PERSONAL_ACCESS_TOKEN:-}" ]]; then
    return 1
  fi

  export PROTON_PASS_KEY_PROVIDER="${PROTON_PASS_KEY_PROVIDER:-fs}"
  pass-cli login >/dev/null 2>&1 || true
  pass-cli test >/dev/null 2>&1
}

default_keychain_path() {
  if [[ -n "${KEYCHAIN_PATH:-}" && -f "${KEYCHAIN_PATH}" ]]; then
    printf '%s' "${KEYCHAIN_PATH}"
    return 0
  fi

  for candidate in \
    "${HOME}/Library/Keychains/login.keychain-db" \
    "${HOME}/Library/Keychains/login.keychain"; do
    if [[ -f "$candidate" ]]; then
      printf '%s' "$candidate"
      return 0
    fi
  done

  return 1
}

unlock_login_keychain() {
  local keychain password

  keychain="$(default_keychain_path || true)"
  if [[ -z "$keychain" ]]; then
    echo "Login keychain not found. Set KEYCHAIN_PATH in config.json if it is non-default." >&2
    return 1
  fi

  password="${KEYCHAIN_PASSWORD_BOOTSTRAP:-${KEYCHAIN_PASSWORD:-}}"
  if [[ -z "$password" ]]; then
    echo "KEYCHAIN_PASSWORD_BOOTSTRAP is required for headless SSH runs on macOS." >&2
    echo "Run scripts/setup-renovate-bootstrap.sh on miniagent or add bootstrap.env." >&2
    return 1
  fi

  security unlock-keychain -p "$password" "$keychain"
  security set-keychain-settings -t 3600 -l "$keychain"
}

if ! ensure_pass_cli_session; then
  unlock_login_keychain
  ensure_pass_cli_session || {
    echo "pass-cli session unavailable after keychain unlock." >&2
    echo "Check bootstrap.env or set PROTON_PASS_PERSONAL_ACCESS_TOKEN." >&2
    exit 1
  }
fi

if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "Missing config: $CONFIG_FILE" >&2
  echo "Copy .cursor/automation/renovate-review/config.json.example (or use config.template.json with pass-cli inject)." >&2
  exit 1
fi

CONFIG_ENV="$(python3 - "$CONFIG_FILE" <<'PY'
import json, os, shlex, subprocess, sys

PASS_CLI = os.environ.get("PASS_CLI_BIN", "pass-cli")

def resolve(value: str) -> str:
    value = value.strip()
    if not value:
        return ""
    if not value.startswith("pass://"):
        return value
    try:
        return subprocess.check_output(
            [PASS_CLI, "item", "view", value],
            text=True,
            stderr=subprocess.PIPE,
        ).strip()
    except FileNotFoundError:
        raise SystemExit(
            "pass-cli not found. Install with: brew install proton-pass-cli"
        )
    except subprocess.CalledProcessError as exc:
        detail = (exc.stderr or exc.stdout or str(exc)).strip()
        raise SystemExit(f"Failed to resolve {value}: {detail}")

cfg = json.load(open(sys.argv[1]))
required = ("CURSOR_API_KEY", "GITHUB_TOKEN")
optional = ("KEYCHAIN_PASSWORD", "KEYCHAIN_PATH")

for key in required:
    raw = os.environ.get(key, "").strip() or cfg.get(key, "").strip()
    value = resolve(raw)
    if not value:
        raise SystemExit(f"config is missing {key}")
    print(f"export {key}={shlex.quote(value)}")

for key in optional:
    raw = os.environ.get(key, "").strip() or cfg.get(key, "").strip()
    if not raw:
        continue
    value = resolve(raw) if raw.startswith("pass://") else raw
    if value:
        print(f"export {key}={shlex.quote(value)}")
PY
)" || {
  echo "$CONFIG_ENV" >&2
  exit 1
}

# shellcheck disable=SC1090
eval "$CONFIG_ENV"

export GH_TOKEN="${GITHUB_TOKEN}"

AGENT_BIN="${CURSOR_AGENT_BIN:-}"
if [[ -z "$AGENT_BIN" || ! -x "$AGENT_BIN" ]]; then
  if [[ -x "${HOME}/.local/bin/agent" ]]; then
    AGENT_BIN="${HOME}/.local/bin/agent"
  elif [[ -x "${HOME}/.cursor/bin/agent" ]]; then
    AGENT_BIN="${HOME}/.cursor/bin/agent"
  else
    AGENT_BIN="$(find "${HOME}/.local/share/cursor-agent/versions" -maxdepth 2 -name cursor-agent -type f 2>/dev/null | sort -r | head -1 || true)"
  fi
fi

if [[ -z "$AGENT_BIN" || ! -x "$AGENT_BIN" ]]; then
  echo "Cursor agent CLI not found. Install with: curl https://cursor.com/install -fsS | bash" >&2
  exit 1
fi

cd "$REPO"

git fetch origin --prune

OPEN_RENOVATE_COUNT="$(
  gh pr list \
    --repo "${GITHUB_OWNER}/${GITHUB_REPO}" \
    --state open \
    --json number,headRefName \
    --jq '[.[] | select(.headRefName | startswith("renovate/"))] | length'
)"

if [[ "$OPEN_RENOVATE_COUNT" == "0" ]]; then
  echo "No open Renovate PRs for ${GITHUB_OWNER}/${GITHUB_REPO}."
  exit 0
fi

echo "Found ${OPEN_RENOVATE_COUNT} open Renovate PR(s). Starting Cursor agent review..."

PROMPT=$(cat <<EOF
You are operating headlessly on miniagent for ${GITHUB_OWNER}/${GITHUB_REPO} (clone at ${REPO}).

Read AGENTS.md first for repo conventions.

## Goal
Review every open Renovate PR (branches renovate/*), merge routine dependency rollouts. This Hugo static site deploys via Cloudflare Pages — merging to main triggers deploy automatically.

## Workflow
1. List open renovate/* PRs:
   gh pr list --repo ${GITHUB_OWNER}/${GITHUB_REPO} --state open --json number,headRefName,title,labels
2. For each PR, inspect the diff, Renovate labels, and CI:
   gh pr view <n> && gh pr checks <n> && gh pr diff <n>
3. Merge PRs that match the "merge confidently" rules below (squash):
   gh pr merge <n> --squash --delete-branch
4. Skip merge only for items in "escalate to human" below. Comment briefly on those PRs and mention @luismsousa.
5. Do not push to main, commit locally, or edit repo files — merge via GitHub only.

## Merge confidently (default yes)
- patch and digest bumps: GitHub Actions, Hugo, Wrangler, git submodule theme pins
- minor bumps for CI tooling and build dependencies
- Single-purpose diffs that match the PR title (version pin changes only)

CI: merge when required checks pass or failures are clearly unrelated/flaky. Do not skip solely because checks are still pending — wait briefly and re-check once.

## Escalate to human (skip merge, comment @luismsousa)
- major Hugo version bumps
- major theme submodule updates with breaking layout or asset changes
- Required CI failures clearly caused by the upgrade
- Diffs with surprise changes unrelated to the stated Renovate update

## Output
Print a concise summary: merged PRs (number + one line), skipped PRs (number + reason).
EOF
)

"$AGENT_BIN" --api-key "$CURSOR_API_KEY" -p --force --output-format text "$PROMPT"
