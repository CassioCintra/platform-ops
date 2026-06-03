#!/usr/bin/env bash
# Calculates the next semantic version tag based on conventional commits.
# Reads:  TAG_PREFIX (default "v"), DEFAULT_BUMP (default "patch")
# Writes: new_tag, changelog  →  $GITHUB_OUTPUT

set -euo pipefail

TAG_PREFIX="${TAG_PREFIX:-v}"
DEFAULT_BUMP="${DEFAULT_BUMP:-patch}"

# ── Last tag ──────────────────────────────────────────────────────────────────
LAST_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "${TAG_PREFIX}0.0.0")
CURRENT="${LAST_TAG#"${TAG_PREFIX}"}"
echo "Last tag: ${LAST_TAG}" >&2

# ── Commits since last tag ────────────────────────────────────────────────────
COMMITS=$(git log "${LAST_TAG}..HEAD" --pretty=format:"%s" 2>/dev/null || true)

# ── Parse conventional commits ────────────────────────────────────────────────
BUMP="$DEFAULT_BUMP"
FEAT_LOG=""
FIX_LOG=""
OTHER_LOG=""

while IFS= read -r msg; do
  [[ -z "$msg" ]] && continue

  if echo "$msg" | grep -qE '(^[a-z]+(\([^)]+\))?!:)|BREAKING CHANGE'; then
    BUMP="major"
  elif echo "$msg" | grep -qE '^feat(\([^)]+\))?:'; then
    [[ "$BUMP" != "major" ]] && BUMP="minor"
    FEAT_LOG+="- ${msg}\n"
  elif echo "$msg" | grep -qE '^fix(\([^)]+\))?:'; then
    FIX_LOG+="- ${msg}\n"
  else
    OTHER_LOG+="- ${msg}\n"
  fi
done <<< "$COMMITS"

echo "Bump type: ${BUMP}" >&2

# ── Compute new version ───────────────────────────────────────────────────────
IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT"
MAJOR="${MAJOR:-0}"; MINOR="${MINOR:-0}"; PATCH="${PATCH:-0}"

case "$BUMP" in
  major) MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0 ;;
  minor) MINOR=$((MINOR + 1)); PATCH=0 ;;
  *)     PATCH=$((PATCH + 1)) ;;
esac

NEW_TAG="${TAG_PREFIX}${MAJOR}.${MINOR}.${PATCH}"
echo "New tag: ${NEW_TAG}" >&2

# ── Build changelog ───────────────────────────────────────────────────────────
CHANGELOG=""
[[ -n "$FEAT_LOG" ]]  && CHANGELOG+="## Features\n${FEAT_LOG}\n"
[[ -n "$FIX_LOG" ]]   && CHANGELOG+="## Bug Fixes\n${FIX_LOG}\n"
[[ -n "$OTHER_LOG" ]] && CHANGELOG+="## Other Changes\n${OTHER_LOG}"
[[ -z "$CHANGELOG" ]] && CHANGELOG="Bump version to ${NEW_TAG}"

# ── Write to GITHUB_OUTPUT ────────────────────────────────────────────────────
{
  echo "new_tag=${NEW_TAG}"
  echo "changelog<<SEMVER_EOF"
  printf "%b\n" "$CHANGELOG"
  echo "SEMVER_EOF"
} >> "${GITHUB_OUTPUT}"
