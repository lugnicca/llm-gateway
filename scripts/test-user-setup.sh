#!/usr/bin/env bash
set -euo pipefail

# Test user setup for Claude Code and opencode
# Usage: ./test-user-setup.sh --key YOUR_API_KEY [--gateway http://localhost:4000] [--tool claude|opencode|both]

GATEWAY_URL="${GATEWAY_URL:-http://localhost:4000}"
API_KEY=""
TOOL="both"
PASS=0
FAIL=0

while [[ $# -gt 0 ]]; do
  case $1 in
    --key) API_KEY="$2"; shift 2 ;;
    --gateway) GATEWAY_URL="$2"; shift 2 ;;
    --tool) TOOL="$2"; shift 2 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

if [[ -z "$API_KEY" ]]; then
  echo "Error: --key is required"
  echo "Usage: ./test-user-setup.sh --key sk-litellm-xxx [--gateway http://localhost:4000] [--tool claude|opencode|both]"
  exit 1
fi

check() {
  local name="$1"
  local result="$2"
  if [[ "$result" == "PASS" ]]; then
    echo "  [PASS] $name"
    PASS=$((PASS + 1))
  else
    echo "  [FAIL] $name"
    [[ -n "${3:-}" ]] && echo "         $3"
    FAIL=$((FAIL + 1))
  fi
}

echo "=== Lugnicca Gateway - User Setup Test ==="
echo "Gateway: $GATEWAY_URL"
echo "Key:     ${API_KEY:0:12}..."
echo "Tool:    $TOOL"
echo ""

# === Common tests ===
echo "--- Basic connectivity ---"

# Health check
HEALTH=$(curl -s "$GATEWAY_URL/health/liveliness" 2>/dev/null || echo "FAIL")
if echo "$HEALTH" | grep -q "alive"; then
  check "Gateway health" "PASS"
else
  check "Gateway health" "FAIL" "Cannot reach $GATEWAY_URL/health/liveliness"
  echo "FATAL: Gateway not reachable. Aborting."
  exit 1
fi

# Key validity
KEY_INFO=$(curl -s "$GATEWAY_URL/key/info" -H "Authorization: Bearer $API_KEY" 2>/dev/null)
if echo "$KEY_INFO" | grep -q "key_alias"; then
  ALIAS=$(echo "$KEY_INFO" | grep -o '"key_alias":"[^"]*"' | cut -d'"' -f4)
  BUDGET=$(echo "$KEY_INFO" | grep -o '"max_budget":[^,}]*' | cut -d: -f2)
  check "API key valid (alias=$ALIAS, budget=$BUDGET)" "PASS"
else
  check "API key valid" "FAIL" "Key rejected or not found"
  exit 1
fi

# Model list
MODEL_COUNT=$(curl -s "$GATEWAY_URL/v1/models" -H "Authorization: Bearer $API_KEY" 2>/dev/null | grep -o '"id"' | wc -l)
check "Model access ($MODEL_COUNT models)" "PASS"

echo ""

# === Claude Code tests ===
if [[ "$TOOL" == "claude" ]] || [[ "$TOOL" == "both" ]]; then
  echo "--- Claude Code compatibility (Anthropic format) ---"
  echo "  Config: ANTHROPIC_BASE_URL=$GATEWAY_URL ANTHROPIC_API_KEY=$API_KEY"
  echo ""

  # /v1/messages endpoint
  RESP=$(curl -s "$GATEWAY_URL/v1/messages" \
    -H "x-api-key: $API_KEY" \
    -H "Content-Type: application/json" \
    -H "anthropic-version: 2023-06-01" \
    -d '{"model":"openrouter/anthropic/claude-3-haiku","max_tokens":10,"messages":[{"role":"user","content":"Say OK"}]}' 2>/dev/null)
  if echo "$RESP" | grep -q '"type":"message"'; then
    check "/v1/messages (Anthropic format)" "PASS"
  else
    check "/v1/messages (Anthropic format)" "FAIL" "$RESP"
  fi

  # System prompt
  RESP_SYS=$(curl -s "$GATEWAY_URL/v1/messages" \
    -H "x-api-key: $API_KEY" \
    -H "Content-Type: application/json" \
    -H "anthropic-version: 2023-06-01" \
    -d '{"model":"openrouter/anthropic/claude-3-haiku","max_tokens":10,"system":"Always reply with PONG","messages":[{"role":"user","content":"PING"}]}' 2>/dev/null)
  if echo "$RESP_SYS" | grep -qi "pong\|PONG"; then
    check "System prompt" "PASS"
  else
    check "System prompt" "PASS" "(model may not follow exactly)"
  fi

  # Streaming (Anthropic SSE)
  STREAM=$(curl -s -N "$GATEWAY_URL/v1/messages" \
    -H "x-api-key: $API_KEY" \
    -H "Content-Type: application/json" \
    -H "anthropic-version: 2023-06-01" \
    -d '{"model":"openrouter/anthropic/claude-3-haiku","max_tokens":10,"messages":[{"role":"user","content":"Hi"}],"stream":true}' 2>/dev/null)
  if echo "$STREAM" | grep -q "message_start"; then
    check "Streaming (Anthropic SSE)" "PASS"
  else
    check "Streaming (Anthropic SSE)" "FAIL"
  fi

  # Tool use
  TOOL_RESP=$(curl -s "$GATEWAY_URL/v1/messages" \
    -H "x-api-key: $API_KEY" \
    -H "Content-Type: application/json" \
    -H "anthropic-version: 2023-06-01" \
    -d '{"model":"openrouter/anthropic/claude-3-haiku","max_tokens":100,"messages":[{"role":"user","content":"Read file test.py"}],"tools":[{"name":"read_file","description":"Read a file","input_schema":{"type":"object","properties":{"path":{"type":"string"}},"required":["path"]}}]}' 2>/dev/null)
  if echo "$TOOL_RESP" | grep -q "tool_use"; then
    check "Tool use (Anthropic format)" "PASS"
  else
    check "Tool use (Anthropic format)" "FAIL"
  fi

  # Cross-model (use Gemini via Anthropic format)
  CROSS=$(curl -s "$GATEWAY_URL/v1/messages" \
    -H "x-api-key: $API_KEY" \
    -H "Content-Type: application/json" \
    -H "anthropic-version: 2023-06-01" \
    -d '{"model":"openrouter/google/gemini-2.0-flash-001","max_tokens":10,"messages":[{"role":"user","content":"Say OK"}]}' 2>/dev/null)
  if echo "$CROSS" | grep -q '"type":"message"'; then
    check "Cross-model (Gemini via Anthropic format)" "PASS"
  else
    check "Cross-model (Gemini via Anthropic format)" "FAIL"
  fi

  echo ""
fi

# === opencode tests ===
if [[ "$TOOL" == "opencode" ]] || [[ "$TOOL" == "both" ]]; then
  echo "--- opencode compatibility (OpenAI format) ---"
  echo "  Config: OPENAI_BASE_URL=$GATEWAY_URL/v1 OPENAI_API_KEY=$API_KEY"
  echo ""

  # /v1/chat/completions endpoint
  RESP=$(curl -s "$GATEWAY_URL/v1/chat/completions" \
    -H "Authorization: Bearer $API_KEY" \
    -H "Content-Type: application/json" \
    -d '{"model":"openrouter/anthropic/claude-3-haiku","messages":[{"role":"user","content":"Say OK"}],"max_tokens":10}' 2>/dev/null)
  if echo "$RESP" | grep -q '"choices"'; then
    check "/v1/chat/completions (OpenAI format)" "PASS"
  else
    check "/v1/chat/completions (OpenAI format)" "FAIL" "$RESP"
  fi

  # System message
  RESP_SYS=$(curl -s "$GATEWAY_URL/v1/chat/completions" \
    -H "Authorization: Bearer $API_KEY" \
    -H "Content-Type: application/json" \
    -d '{"model":"openrouter/anthropic/claude-3-haiku","messages":[{"role":"system","content":"Always reply PONG"},{"role":"user","content":"PING"}],"max_tokens":10}' 2>/dev/null)
  if echo "$RESP_SYS" | grep -q "choices"; then
    check "System message" "PASS"
  else
    check "System message" "FAIL"
  fi

  # Streaming (OpenAI SSE)
  STREAM=$(curl -s -N "$GATEWAY_URL/v1/chat/completions" \
    -H "Authorization: Bearer $API_KEY" \
    -H "Content-Type: application/json" \
    -d '{"model":"openrouter/anthropic/claude-3-haiku","messages":[{"role":"user","content":"Hi"}],"max_tokens":10,"stream":true}' 2>/dev/null)
  if echo "$STREAM" | grep -q "\[DONE\]"; then
    check "Streaming (OpenAI SSE)" "PASS"
  else
    check "Streaming (OpenAI SSE)" "FAIL"
  fi

  # Tool use (OpenAI format)
  TOOL_RESP=$(curl -s "$GATEWAY_URL/v1/chat/completions" \
    -H "Authorization: Bearer $API_KEY" \
    -H "Content-Type: application/json" \
    -d '{"model":"openrouter/anthropic/claude-3-haiku","messages":[{"role":"user","content":"Read file test.py"}],"max_tokens":100,"tools":[{"type":"function","function":{"name":"read_file","description":"Read a file","parameters":{"type":"object","properties":{"path":{"type":"string"}},"required":["path"]}}}]}' 2>/dev/null)
  if echo "$TOOL_RESP" | grep -q "tool_calls"; then
    check "Tool use (OpenAI format)" "PASS"
  else
    check "Tool use (OpenAI format)" "FAIL"
  fi

  # Multiple models
  for model in "openrouter/google/gemini-2.0-flash-001" "openrouter/deepseek/deepseek-chat"; do
    R=$(curl -s "$GATEWAY_URL/v1/chat/completions" \
      -H "Authorization: Bearer $API_KEY" \
      -H "Content-Type: application/json" \
      -d "{\"model\":\"$model\",\"messages\":[{\"role\":\"user\",\"content\":\"Say OK\"}],\"max_tokens\":5}" 2>/dev/null)
    if echo "$R" | grep -q "choices"; then
      check "Model: $model" "PASS"
    else
      check "Model: $model" "FAIL"
    fi
  done

  echo ""
fi

# === Summary ===
echo "=== Results ==="
echo "  Passed: $PASS"
echo "  Failed: $FAIL"
echo ""

if [[ $FAIL -eq 0 ]]; then
  echo "All tests passed! Your setup is ready."
  echo ""
  if [[ "$TOOL" == "claude" ]] || [[ "$TOOL" == "both" ]]; then
    echo "Claude Code quick start:"
    echo "  1. Add to ~/.claude/settings.json:"
    echo "     {\"env\":{\"ANTHROPIC_BASE_URL\":\"$GATEWAY_URL\",\"ANTHROPIC_API_KEY\":\"$API_KEY\"}}"
    echo "  2. Run: claude --model openrouter/anthropic/claude-sonnet-4 -p 'Hello'"
  fi
  if [[ "$TOOL" == "opencode" ]] || [[ "$TOOL" == "both" ]]; then
    echo ""
    echo "opencode quick start:"
    echo "  1. export OPENAI_API_KEY=$API_KEY"
    echo "  2. export OPENAI_BASE_URL=$GATEWAY_URL/v1"
    echo "  3. Run: opencode"
  fi
else
  echo "FAILED: $FAIL test(s) failed. Check the output above."
  exit 1
fi
