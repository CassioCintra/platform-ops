set -euo pipefail

if [ "$KEEP_RUNS" -lt 1 ]; then
  echo "keep-runs must be greater than zero"
  exit 1
fi

if [ -n "$WORKFLOW_ID" ]; then
  endpoint="/repos/$REPO/actions/workflows/$WORKFLOW_ID/runs?per_page=100"
else
  endpoint="/repos/$REPO/actions/runs?per_page=100"
fi

gh api --paginate "$endpoint" \
  --jq ".workflow_runs | sort_by(.created_at) | reverse | .[$KEEP_RUNS:][] | .id" \
| while read -r run_id; do
    if [ -n "$run_id" ]; then
      echo "Deleting workflow run $run_id"
      gh api -X DELETE "/repos/$REPO/actions/runs/$run_id"
    fi
  done