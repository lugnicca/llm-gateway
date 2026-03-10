#!/usr/bin/env bash
set -euo pipefail

# Create a virtual key for a user
# Usage: ./create-user-key.sh --user "john@company.com" --team "engineering" --budget 50 --models "prod/*,sandbox/*"

GATEWAY_URL="${GATEWAY_URL:-http://localhost:4000}"
MASTER_KEY="${MASTER_KEY:?MASTER_KEY is required}"

USER=""
TEAM=""
BUDGET=""
MODELS=""
KEY_ALIAS=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --user) USER="$2"; shift 2 ;;
    --team) TEAM="$2"; shift 2 ;;
    --budget) BUDGET="$2"; shift 2 ;;
    --models) MODELS="$2"; shift 2 ;;
    --alias) KEY_ALIAS="$2"; shift 2 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

if [[ -z "$USER" ]]; then
  echo "Error: --user is required"
  exit 1
fi

# Extract username from email for alias (alice@company.com -> alice)
DEFAULT_ALIAS="${USER%%@*}"

# Build request body
BODY=$(cat <<EOF
{
  "user_id": "$USER",
  "team_id": "${TEAM:-default}",
  "key_alias": "${KEY_ALIAS:-$DEFAULT_ALIAS}",
  "max_budget": ${BUDGET:-null},
  "models": [$(echo "$MODELS" | sed 's/,/","/g' | sed 's/^/"/' | sed 's/$/"/' | sed 's/""/null/')]
}
EOF
)

# Handle empty models
if [[ -z "$MODELS" ]]; then
  BODY=$(cat <<EOF
{
  "user_id": "$USER",
  "team_id": "${TEAM:-default}",
  "key_alias": "${KEY_ALIAS:-$DEFAULT_ALIAS}",
  "max_budget": ${BUDGET:-null}
}
EOF
)
fi

echo "Creating key for user: $USER (team: ${TEAM:-default})"

RESPONSE=$(curl -s -X POST "$GATEWAY_URL/key/generate" \
  -H "Authorization: Bearer $MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d "$BODY")

KEY=$(echo "$RESPONSE" | grep -o '"key":"[^"]*"' | head -1 | cut -d'"' -f4)

if [[ -n "$KEY" ]]; then
  echo "Key created successfully!"
  echo "  User:   $USER"
  echo "  Team:   ${TEAM:-default}"
  echo "  Budget: ${BUDGET:-unlimited}"
  echo "  Key:    $KEY"
  echo ""
  echo "Configure Claude Code:"
  echo "  export ANTHROPIC_BASE_URL=$GATEWAY_URL"
  echo "  export ANTHROPIC_API_KEY=$KEY"
else
  echo "Error creating key:"
  echo "$RESPONSE"
  exit 1
fi
