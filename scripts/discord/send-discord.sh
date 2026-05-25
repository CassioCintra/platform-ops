#!/usr/bin/env bash
set -euo pipefail

: "${DISCORD_WEBHOOK_URL:?missing DISCORD_WEBHOOK_URL}"

# ── Status labels ─────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

status_tests="$("$SCRIPT_DIR/status-label.sh"    "${TESTS_RESULT:-unknown}")"
status_quality="$("$SCRIPT_DIR/status-label.sh"  "${QUALITY_RESULT:-unknown}")"
status_security="$("$SCRIPT_DIR/status-label.sh" "${SECURITY_RESULT:-unknown}")"
status_migration="$("$SCRIPT_DIR/status-label.sh" "${MIGRATION_RESULT:-skipped}")"
status_cd="$("$SCRIPT_DIR/status-label.sh"       "${CD_RESULT:-unknown}")"
status_overall="$("$SCRIPT_DIR/status-label.sh"  "${OVERALL_STATUS:-unknown}")"

# ── Embed color by overall status ─────────────────────────────────────────────
case "${OVERALL_STATUS:-unknown}" in
  success)   color=3066993  ;;  # green  #2ECC71
  failure)   color=15158332 ;;  # red    #E74C3C
  cancelled) color=16776960 ;;  # yellow #FFFF00
  *)         color=9807270  ;;  # grey   #95A5A6
esac

# ── Escape a string for JSON ──────────────────────────────────────────────────
json_escape() {
  printf '%s' "$1" \
    | sed 's/\\/\\\\/g' \
    | sed 's/"/\\"/g' \
    | sed ':a;N;$!ba;s/\n/\\n/g'
}

service="$(json_escape "${SERVICE_NAME:-unknown}")"
image_tag="$(json_escape "${IMAGE_TAG:-}")"
run_url="$(json_escape "${RUN_URL:-}")"
repo="$(json_escape "${REPO:-}")"
branch="$(json_escape "${BRANCH:-main}")"
commit="$(json_escape "${COMMIT_SHA:-}")"
short_sha="${COMMIT_SHA:0:7}"

# ── Build embed payload ───────────────────────────────────────────────────────
payload="$(cat <<EOF
{
  "content": null,
  "embeds": [
    {
      "title": "${status_overall} ${service}",
      "url": "${run_url}",
      "color": ${color},
      "fields": [
        { "name": "Repository",  "value": "${repo}",         "inline": true },
        { "name": "Branch",      "value": "\`${branch}\`",   "inline": true },
        { "name": "Commit",      "value": "\`${short_sha}\`","inline": true },
        { "name": "Tests",       "value": "${status_tests}",    "inline": true },
        { "name": "Quality",     "value": "${status_quality}",  "inline": true },
        { "name": "Security",    "value": "${status_security}", "inline": true },
        { "name": "DB migration","value": "${status_migration}","inline": true },
        { "name": "CD",          "value": "${status_cd}",       "inline": true },
        { "name": "Image tag",   "value": "\`${image_tag}\`",   "inline": true }
      ],
      "footer": { "text": "order-platform CI/CD" }
    }
  ],
  "allowed_mentions": { "parse": [] }
}
EOF
)"

curl -sS -o /dev/null -w "%{http_code}" \
  -X POST \
  -H "Content-Type: application/json" \
  -d "$payload" \
  "$DISCORD_WEBHOOK_URL"
