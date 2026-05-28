#!/usr/bin/env bash
set -euo pipefail

: "${DISCORD_WEBHOOK_URL:?missing DISCORD_WEBHOOK_URL}"

# ── Status labels ─────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# With emoji — used in the embed title only
status_overall="$("$SCRIPT_DIR/status-label.sh" "${OVERALL_STATUS:-unknown}")"

# Text-only — used inside the code block table so columns align correctly
status_text() { printf '%s' "${1:-unknown}"; }
status_tests="$(status_text    "${TESTS_RESULT:-unknown}")"
status_quality="$(status_text  "${QUALITY_RESULT:-unknown}")"
status_security="$(status_text "${SECURITY_RESULT:-unknown}")"
status_migration="$(status_text "${MIGRATION_RESULT:-skipped}")"
status_cd="$(status_text       "${CD_RESULT:-unknown}")"

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
run_url="$(json_escape "${RUN_URL:-}")"
short_sha="${COMMIT_SHA:0:7}"

col=14

table_line() {
  local label="$1"
  local value="$2"
  printf "%-${col}s %s\n" "${label}" "${value}"
}

table="$(cat <<EOF
$(table_line "Repository"   "${REPO:-unknown}")
$(table_line "Branch"       "${BRANCH:-main}")
$(table_line "Commit"       "${short_sha}")
$(table_line "Tests"        "${status_tests}")
$(table_line "Quality"      "${status_quality}")
$(table_line "Security"     "${status_security}")
$(table_line "DB migration" "${status_migration}")
$(table_line "CD"           "${status_cd}")
$(table_line "Image tag"    "${IMAGE_TAG:-}")
EOF
)"

description="$(json_escape "\`\`\`
${table}
\`\`\`")"

# ── Build embed payload ───────────────────────────────────────────────────────
payload="$(cat <<EOF
{
  "content": "@everyone",
  "embeds": [
    {
      "title": "${status_overall} - ${service}",
      "url": "${run_url}",
      "color": ${color},
      "description": "${description}",
      "footer": { "text": "CI/CD Result" }
    }
  ],
  "allowed_mentions": {
    "parse": ["everyone"]
  }
}
EOF
)"

echo "=== Sending to Discord ==="
http_code=$(curl -sS -o /tmp/discord_response.txt -w "%{http_code}" \
  -X POST \
  -H "Content-Type: application/json" \
  -d "$payload" \
  "$DISCORD_WEBHOOK_URL")

echo "HTTP status: $http_code"
echo "Response body: $(cat /tmp/discord_response.txt)"

[ "$http_code" -ge 200 ] && [ "$http_code" -lt 300 ] || { echo "::error::Discord webhook returned $http_code"; exit 1; }
