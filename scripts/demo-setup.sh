#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Demo Setup Script
# Creates teams, users, model aliases — then you demo everything in the UIs
# Usage: ./scripts/demo-setup.sh
# Prerequisites: gateway running (docker compose up), .env configured
# =============================================================================

GATEWAY_URL="${GATEWAY_URL:-http://localhost:4000}"
MASTER_KEY="${MASTER_KEY:?MASTER_KEY is required — export MASTER_KEY=sk-...}"
DEFAULT_PASSWORD="demo1234"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

ok()   { echo -e "  ${GREEN}✓${NC} $1"; }
fail() { echo -e "  ${RED}✗${NC} $1"; }
info() { echo -e "  ${CYAN}→${NC} $1"; }
header() { echo -e "\n${BOLD}${YELLOW}═══ $1 ═══${NC}\n"; }

api() {
  local method="$1" path="$2" data="${3:-}"
  if [[ -n "$data" ]]; then
    curl -s -X "$method" "$GATEWAY_URL$path" \
      -H "Authorization: Bearer $MASTER_KEY" \
      -H "Content-Type: application/json" \
      -d "$data"
  else
    curl -s -X "$method" "$GATEWAY_URL$path" \
      -H "Authorization: Bearer $MASTER_KEY"
  fi
}

# =============================================================================
# 1. Health Check
# =============================================================================
header "1. Health Check"

if curl -s -f "$GATEWAY_URL/health/liveliness" > /dev/null 2>&1; then
  ok "Gateway is healthy at $GATEWAY_URL"
else
  fail "Gateway is not responding at $GATEWAY_URL"
  echo "    Run: docker compose -f docker-compose.local.yml up -d"
  exit 1
fi

# =============================================================================
# 2. Create Model Aliases
# =============================================================================
header "2. Create Model Aliases"

info "Creating demo/smart (Qwen3.5 35B-A3B MoE)..."
api POST "/model/new" '{
  "model_name": "demo/smart",
  "litellm_params": {
    "model": "openrouter/qwen/qwen3.5-35b-a3b",
    "api_key": "os.environ/OPENROUTER_API_KEY",
    "extra_body": {"provider": {"data_collection": "deny"}}
  },
  "model_info": {
    "description": "Qwen3.5 35B-A3B MoE via OpenRouter (ZDR)"
  }
}' > /dev/null && ok "demo/smart created" || fail "demo/smart failed"

info "Creating demo/cheap (Gemini 2.5 Flash)..."
api POST "/model/new" '{
  "model_name": "demo/cheap",
  "litellm_params": {
    "model": "openrouter/google/gemini-2.5-flash",
    "api_key": "os.environ/OPENROUTER_API_KEY",
    "extra_body": {"provider": {"data_collection": "deny"}}
  },
  "model_info": {
    "description": "Gemini 2.5 Flash via OpenRouter (ZDR)"
  }
}' > /dev/null && ok "demo/cheap created" || fail "demo/cheap failed"

# =============================================================================
# 3. Create Teams
# =============================================================================
header "3. Create Teams"

info "Creating team: engineering (budget \$200/month)..."
ENG_TEAM=$(api POST "/team/new" '{
  "team_alias": "engineering",
  "max_budget": 200,
  "budget_duration": "30d",
  "models": ["demo/smart", "demo/cheap", "openrouter/*"]
}')
ENG_TEAM_ID=$(echo "$ENG_TEAM" | grep -o '"team_id":"[^"]*"' | head -1 | cut -d'"' -f4)
if [[ -n "$ENG_TEAM_ID" ]]; then
  ok "engineering (id: $ENG_TEAM_ID)"
else
  fail "engineering creation failed"
  echo "    $ENG_TEAM"
fi

info "Creating team: data-science (budget \$100/month)..."
DS_TEAM=$(api POST "/team/new" '{
  "team_alias": "data-science",
  "max_budget": 100,
  "budget_duration": "30d",
  "models": ["demo/smart", "demo/cheap"]
}')
DS_TEAM_ID=$(echo "$DS_TEAM" | grep -o '"team_id":"[^"]*"' | head -1 | cut -d'"' -f4)
if [[ -n "$DS_TEAM_ID" ]]; then
  ok "data-science (id: $DS_TEAM_ID)"
else
  fail "data-science creation failed"
  echo "    $DS_TEAM"
fi

info "Creating team: stagiaires (budget \$10/month)..."
INTERN_TEAM=$(api POST "/team/new" '{
  "team_alias": "stagiaires",
  "max_budget": 10,
  "budget_duration": "30d",
  "models": ["demo/cheap"]
}')
INTERN_TEAM_ID=$(echo "$INTERN_TEAM" | grep -o '"team_id":"[^"]*"' | head -1 | cut -d'"' -f4)
if [[ -n "$INTERN_TEAM_ID" ]]; then
  ok "stagiaires (id: $INTERN_TEAM_ID)"
else
  fail "stagiaires creation failed"
  echo "    $INTERN_TEAM"
fi

info "Creating team: automation (budget \$50/month, MCP: jira+gitlab)..."
AUTO_TEAM=$(api POST "/team/new" '{
  "team_alias": "automation",
  "max_budget": 50,
  "budget_duration": "30d",
  "models": ["demo/smart", "demo/cheap"],
  "metadata": {"mcp_servers": ["jira", "gitlab"]}
}')
AUTO_TEAM_ID=$(echo "$AUTO_TEAM" | grep -o '"team_id":"[^"]*"' | head -1 | cut -d'"' -f4)
if [[ -n "$AUTO_TEAM_ID" ]]; then
  ok "automation (id: $AUTO_TEAM_ID)"
else
  fail "automation creation failed"
  echo "    $AUTO_TEAM"
fi

info "Creating team: power-users (budget \$500/month, all models)..."
POWER_TEAM=$(api POST "/team/new" '{
  "team_alias": "power-users",
  "max_budget": 500,
  "budget_duration": "30d",
  "models": ["demo/smart", "demo/cheap", "openrouter/*"]
}')
POWER_TEAM_ID=$(echo "$POWER_TEAM" | grep -o '"team_id":"[^"]*"' | head -1 | cut -d'"' -f4)
if [[ -n "$POWER_TEAM_ID" ]]; then
  ok "power-users (id: $POWER_TEAM_ID)"
else
  fail "power-users creation failed"
  echo "    $POWER_TEAM"
fi

# =============================================================================
# 4. Create Users
# =============================================================================
header "4. Create Users"

create_user() {
  local email="$1" role="$2" budget="$3"
  local resp
  resp=$(api POST "/user/new" "{
    \"user_email\": \"$email\",
    \"user_role\": \"$role\",
    \"max_budget\": $budget,
    \"budget_duration\": \"30d\"
  }")
  local user_id
  user_id=$(echo "$resp" | grep -o '"user_id":"[^"]*"' | head -1 | cut -d'"' -f4)
  if [[ -n "$user_id" ]]; then
    ok "$email ($role, \$$budget/month) → id: $user_id" >&2
    echo "$user_id"
  else
    fail "$email creation failed" >&2
    echo "$resp" >&2
    echo ""
  fi
}

info "Creating users..."
ALICE_UID=$(create_user "alice@company.com" "internal_user" 100)
ARTHUR_UID=$(create_user "arthur@company.com" "internal_user" 50)
BOB_UID=$(create_user "bob@company.com" "internal_user" 80)
BEA_UID=$(create_user "bea@company.com" "internal_user" 20)
CAROL_UID=$(create_user "carol@company.com" "internal_user" 5)
CLEMENT_UID=$(create_user "clement@company.com" "internal_user" 5)
ADMIN_UID=$(create_user "admin@company.com" "proxy_admin" 300)

# =============================================================================
# 5. Create User Keys
# =============================================================================
header "5. Create User Keys"

create_key() {
  local user_id="$1" team_id="$2" budget="$3" alias="$4"

  local resp
  resp=$(api POST "/key/generate" "{
    \"user_id\": \"$user_id\",
    \"team_id\": \"$team_id\",
    \"key_alias\": \"$alias\",
    \"max_budget\": $budget,
    \"budget_duration\": \"30d\"
  }")

  local key
  key=$(echo "$resp" | grep -o '"key":"[^"]*"' | head -1 | cut -d'"' -f4)

  if [[ -n "$key" ]]; then
    ok "$alias → \$$budget/month → $key" >&2
    echo "$key"
  else
    fail "$alias key creation failed" >&2
    echo "$resp" >&2
    echo ""
  fi
}

info "Engineering keys..."
ALICE_KEY=$(create_key "$ALICE_UID" "$ENG_TEAM_ID" 100 "alice")
ARTHUR_KEY=$(create_key "$ARTHUR_UID" "$ENG_TEAM_ID" 50 "arthur")

info "Data-science keys..."
BOB_KEY=$(create_key "$BOB_UID" "$DS_TEAM_ID" 80 "bob")
BEA_KEY=$(create_key "$BEA_UID" "$DS_TEAM_ID" 20 "bea")

info "Stagiaires keys..."
CAROL_KEY=$(create_key "$CAROL_UID" "$INTERN_TEAM_ID" 5 "carol")
CLEMENT_KEY=$(create_key "$CLEMENT_UID" "$INTERN_TEAM_ID" 5 "clement")

info "Automation keys (n8n)..."
N8N_SMART_KEY=$(create_key "$ADMIN_UID" "$AUTO_TEAM_ID" 30 "n8n-smart")
N8N_CHEAP_KEY=$(create_key "$ADMIN_UID" "$AUTO_TEAM_ID" 20 "n8n-cheap")

info "Power user key..."
ADMIN_KEY=$(create_key "$ADMIN_UID" "$POWER_TEAM_ID" 300 "admin")

# =============================================================================
# 6. Set User Passwords
# =============================================================================
header "6. Set User Passwords"

set_password() {
  local user_id="$1" email="$2"
  local resp
  resp=$(api POST "/user/update" "{\"user_id\": \"$user_id\", \"password\": \"$DEFAULT_PASSWORD\"}")
  if echo "$resp" | grep -q '"user_id"'; then
    ok "$email → password set" >&2
  else
    fail "$email password failed" >&2
    echo "$resp" >&2
  fi
}

set_password "$ALICE_UID" "alice@company.com"
set_password "$ARTHUR_UID" "arthur@company.com"
set_password "$BOB_UID" "bob@company.com"
set_password "$BEA_UID" "bea@company.com"
set_password "$CAROL_UID" "carol@company.com"
set_password "$CLEMENT_UID" "clement@company.com"
set_password "$ADMIN_UID" "admin@company.com"

# =============================================================================
# Summary
# =============================================================================
header "Setup Complete"

echo -e "${BOLD}Models:${NC}"
echo "  demo/smart     → Qwen3.5 35B-A3B MoE (OpenRouter, ZDR)"
echo "  demo/cheap     → Gemini 2.5 Flash (OpenRouter, ZDR)"
echo "  openrouter/*   → Any OpenRouter model (wildcard, ZDR)"
echo ""
echo -e "${BOLD}Teams:${NC}"
echo "  engineering   → \$200/month, models: demo/smart + demo/cheap + openrouter/*"
echo "  data-science  → \$100/month, models: demo/smart + demo/cheap"
echo "  stagiaires    → \$10/month,  models: demo/cheap only"
echo "  automation    → \$50/month,  models: demo/smart + demo/cheap, MCP: jira + gitlab"
echo "  power-users   → \$500/month, models: all + openrouter/*"
echo ""
echo -e "${BOLD}Users & Keys:${NC}"
echo "  alice      → engineering   \$100/month  key: $ALICE_KEY"
echo "  arthur     → engineering   \$50/month   key: $ARTHUR_KEY"
echo "  bob        → data-science  \$80/month   key: $BOB_KEY"
echo "  bea        → data-science  \$20/month   key: $BEA_KEY"
echo "  carol      → stagiaires    \$5/month    key: $CAROL_KEY"
echo "  clement    → stagiaires    \$5/month    key: $CLEMENT_KEY"
echo "  n8n-smart  → automation    \$30/month   key: $N8N_SMART_KEY"
echo "  n8n-cheap  → automation    \$20/month   key: $N8N_CHEAP_KEY"
echo "  admin      → power-users   \$300/month  key: $ADMIN_KEY"
echo ""
echo -e "${BOLD}UI Login (all passwords: $DEFAULT_PASSWORD):${NC}"
echo "  alice@company.com    (internal_user)"
echo "  arthur@company.com   (internal_user)"
echo "  bob@company.com      (internal_user)"
echo "  bea@company.com      (internal_user)"
echo "  carol@company.com    (internal_user)"
echo "  clement@company.com  (internal_user)"
echo "  admin@company.com    (proxy_admin)"
echo ""
echo -e "${BOLD}Next steps:${NC}"
echo "  1. Login at $GATEWAY_URL/ui with email + password"
echo "  2. Configure Cline: Base URL=$GATEWAY_URL, API Key=(key above)"
echo "  3. Configure Junie: Same Base URL + API Key in JetBrains settings"
echo "  4. Configure n8n:   Use n8n-smart or n8n-cheap key as API key"
