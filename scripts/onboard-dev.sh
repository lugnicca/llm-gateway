#!/usr/bin/env bash
set -euo pipefail

# Full developer onboarding: create key + configure Claude Code + JetBrains instructions
# Usage: ./onboard-dev.sh --user "john@company.com" --team "engineering" --budget 100

GATEWAY_URL="${GATEWAY_URL:-http://localhost:4000}"
MASTER_KEY="${MASTER_KEY:?MASTER_KEY is required}"

USER=""
TEAM=""
BUDGET=""
MODELS="prod/*,openrouter/*,local/*"

while [[ $# -gt 0 ]]; do
  case $1 in
    --user) USER="$2"; shift 2 ;;
    --team) TEAM="$2"; shift 2 ;;
    --budget) BUDGET="$2"; shift 2 ;;
    --models) MODELS="$2"; shift 2 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

if [[ -z "$USER" ]]; then
  echo "Error: --user is required"
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== Developer Onboarding ==="
echo "User:    $USER"
echo "Team:    ${TEAM:-default}"
echo "Gateway: $GATEWAY_URL"
echo ""

# Step 1: Create key
echo "--- Step 1: Creating API key ---"
ARGS="--user $USER"
[[ -n "$TEAM" ]] && ARGS="$ARGS --team $TEAM"
[[ -n "$BUDGET" ]] && ARGS="$ARGS --budget $BUDGET"
[[ -n "$MODELS" ]] && ARGS="$ARGS --models $MODELS"

OUTPUT=$(GATEWAY_URL="$GATEWAY_URL" MASTER_KEY="$MASTER_KEY" "$SCRIPT_DIR/create-user-key.sh" $ARGS)
echo "$OUTPUT"
KEY=$(echo "$OUTPUT" | grep "Key:" | awk '{print $2}')

if [[ -z "$KEY" ]]; then
  echo "Error: Failed to create key"
  exit 1
fi

# Step 2: Claude Code configuration
echo ""
echo "--- Step 2: Claude Code Configuration ---"
echo ""
echo "Add to your Claude Code settings (~/.claude/settings.json):"
echo ""
cat <<EOF
{
  "env": {
    "ANTHROPIC_BASE_URL": "$GATEWAY_URL",
    "ANTHROPIC_API_KEY": "$KEY"
  }
}
EOF

# Step 3: JetBrains AI instructions
echo ""
echo "--- Step 3: JetBrains AI Assistant ---"
echo ""
echo "In JetBrains IDE:"
echo "  1. Settings → Tools → AI Assistant → Custom Provider"
echo "  2. Provider URL: $GATEWAY_URL"
echo "  3. API Key: $KEY"
echo "  4. Model: prod/claude-sonnet (or any available model)"
echo ""
echo "See docs/JETBRAINS-SETUP.md for detailed instructions."
echo ""
echo "=== Onboarding Complete ==="
