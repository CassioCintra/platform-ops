#!/usr/bin/env bash
set -euo pipefail

status="${1:-unknown}"

case "$status" in
  success)   echo "✅ success"   ;;
  failure)   echo "❌ failure"   ;;
  cancelled) echo "⚠️ cancelled" ;;
  skipped)   echo "⏭️ skipped"   ;;
  *)         echo "❔ unknown"   ;;
esac
