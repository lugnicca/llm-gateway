#!/usr/bin/env bash
set -euo pipefail

# Batch onboard users from CSV
# CSV format: user_email,team,budget,models
# Usage: ./batch-onboard.sh users.csv

GATEWAY_URL="${GATEWAY_URL:-http://localhost:4000}"
MASTER_KEY="${MASTER_KEY:?MASTER_KEY is required}"

CSV_FILE="${1:?Usage: $0 <csv-file>}"

if [[ ! -f "$CSV_FILE" ]]; then
  echo "Error: File not found: $CSV_FILE"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SUCCESS=0
FAILED=0

echo "=== Batch Onboarding ==="
echo "Gateway: $GATEWAY_URL"
echo ""

# Skip header line
tail -n +2 "$CSV_FILE" | while IFS=',' read -r user team budget models; do
  user=$(echo "$user" | xargs)
  team=$(echo "$team" | xargs)
  budget=$(echo "$budget" | xargs)
  models=$(echo "$models" | xargs)

  echo "Onboarding: $user (team: $team)"

  ARGS="--user $user"
  [[ -n "$team" ]] && ARGS="$ARGS --team $team"
  [[ -n "$budget" ]] && ARGS="$ARGS --budget $budget"
  [[ -n "$models" ]] && ARGS="$ARGS --models $models"

  if GATEWAY_URL="$GATEWAY_URL" MASTER_KEY="$MASTER_KEY" "$SCRIPT_DIR/create-user-key.sh" $ARGS; then
    SUCCESS=$((SUCCESS + 1))
  else
    FAILED=$((FAILED + 1))
    echo "  FAILED: $user"
  fi
  echo "---"
done

echo ""
echo "=== Summary ==="
echo "  Success: $SUCCESS"
echo "  Failed:  $FAILED"
