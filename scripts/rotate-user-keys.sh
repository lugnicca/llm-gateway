#!/usr/bin/env bash
set -euo pipefail

# Rotate virtual keys older than N days
# Usage: ./rotate-user-keys.sh [--days 90] [--dry-run]

GATEWAY_URL="${GATEWAY_URL:-http://localhost:4000}"
MASTER_KEY="${MASTER_KEY:?MASTER_KEY is required}"

MAX_AGE_DAYS=90
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --days) MAX_AGE_DAYS="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

echo "=== User Key Rotation ==="
echo "Max age: $MAX_AGE_DAYS days"
echo "Dry run: $DRY_RUN"
echo ""

# Get all keys
KEYS=$(curl -s -X GET "$GATEWAY_URL/key/list" \
  -H "Authorization: Bearer $MASTER_KEY")

CUTOFF_DATE=$(date -d "-${MAX_AGE_DAYS} days" +%Y-%m-%dT%H:%M:%S 2>/dev/null || \
  date -v-${MAX_AGE_DAYS}d +%Y-%m-%dT%H:%M:%S)

echo "Cutoff date: $CUTOFF_DATE"
echo ""

ROTATED=0
SKIPPED=0

echo "$KEYS" | python3 -c "
import json, sys
data = json.load(sys.stdin)
keys = data if isinstance(data, list) else data.get('keys', [])
for k in keys:
    print(f\"{k.get('token','')},{k.get('key_alias','')},{k.get('user_id','')},{k.get('created_at','')}\")
" 2>/dev/null | while IFS=',' read -r token alias user created; do
  if [[ -z "$created" ]] || [[ "$created" > "$CUTOFF_DATE" ]]; then
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  echo "Key: $alias (user: $user, created: $created)"

  if [[ "$DRY_RUN" == "true" ]]; then
    echo "  [DRY RUN] Would rotate"
  else
    # Delete old key
    curl -s -X POST "$GATEWAY_URL/key/delete" \
      -H "Authorization: Bearer $MASTER_KEY" \
      -H "Content-Type: application/json" \
      -d "{\"keys\":[\"$token\"]}" > /dev/null

    # Create new key with same settings
    curl -s -X POST "$GATEWAY_URL/key/generate" \
      -H "Authorization: Bearer $MASTER_KEY" \
      -H "Content-Type: application/json" \
      -d "{\"user_id\":\"$user\",\"key_alias\":\"$alias\"}" > /dev/null

    echo "  Rotated"
    ROTATED=$((ROTATED + 1))
  fi
done

echo ""
echo "=== Summary ==="
echo "  Rotated: $ROTATED"
echo "  Skipped: $SKIPPED"
