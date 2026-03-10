#!/usr/bin/env bash
set -euo pipefail

# Security audit: verify infrastructure security posture
# Usage: ./security-audit.sh

PROJECT_ID="${GCP_PROJECT_ID:-litellm-489602}"
REGION="${GCP_REGION:-europe-west9}"
ORG_NAME="${ORG_NAME:-lugnicca}"

PASS=0
FAIL=0
WARN=0

check() {
  local name="$1"
  local status="$2"
  local detail="${3:-}"

  case "$status" in
    PASS)
      echo "  ✓ $name"
      PASS=$((PASS + 1))
      ;;
    FAIL)
      echo "  ✗ $name"
      [[ -n "$detail" ]] && echo "    → $detail"
      FAIL=$((FAIL + 1))
      ;;
    WARN)
      echo "  ⚠ $name"
      [[ -n "$detail" ]] && echo "    → $detail"
      WARN=$((WARN + 1))
      ;;
  esac
}

echo "=== Lugnicca Security Audit ==="
echo "Project: $PROJECT_ID"
echo "Region:  $REGION"
echo ""

# Check 1: Cloud SQL has no public IP
echo "[1/7] Cloud SQL Private IP"
SQL_INSTANCE="${ORG_NAME}-litellm-db"
PUBLIC_IP=$(gcloud sql instances describe "$SQL_INSTANCE" \
  --project="$PROJECT_ID" \
  --format="value(ipAddresses[].type)" 2>/dev/null || echo "NOT_FOUND")

if [[ "$PUBLIC_IP" == "NOT_FOUND" ]]; then
  check "Cloud SQL instance exists" "WARN" "Instance not found — not yet deployed?"
elif echo "$PUBLIC_IP" | grep -q "PRIMARY"; then
  check "Cloud SQL private IP only" "FAIL" "Public IP detected"
else
  check "Cloud SQL private IP only" "PASS"
fi

# Check 2: Secrets in Secret Manager
echo ""
echo "[2/7] Secret Manager"
for secret in "${ORG_NAME}-litellm-master-key" "${ORG_NAME}-litellm-salt-key" "${ORG_NAME}-openrouter-key"; do
  EXISTS=$(gcloud secrets describe "$secret" \
    --project="$PROJECT_ID" \
    --format="value(name)" 2>/dev/null || echo "NOT_FOUND")
  if [[ "$EXISTS" == "NOT_FOUND" ]]; then
    check "Secret: $secret" "WARN" "Not found in Secret Manager — not yet deployed?"
  else
    check "Secret: $secret" "PASS"
  fi
done

# Check 3: Cloud Run service account (not default)
echo ""
echo "[3/7] Cloud Run Service Account"
SA=$(gcloud run services describe "${ORG_NAME}-litellm-gateway" \
  --project="$PROJECT_ID" \
  --region="$REGION" \
  --format="value(spec.template.spec.serviceAccountName)" 2>/dev/null || echo "NOT_FOUND")

if [[ "$SA" == "NOT_FOUND" ]]; then
  check "Cloud Run service account" "WARN" "Service not found — not yet deployed?"
elif echo "$SA" | grep -q "compute@developer"; then
  check "Dedicated service account" "FAIL" "Using default compute SA"
else
  check "Dedicated service account" "PASS"
fi

# Check 4: VPC Connector
echo ""
echo "[4/7] VPC Connector"
CONNECTOR=$(gcloud compute networks vpc-access connectors describe "${ORG_NAME}-connector" \
  --project="$PROJECT_ID" \
  --region="$REGION" \
  --format="value(name)" 2>/dev/null || echo "NOT_FOUND")

if [[ "$CONNECTOR" == "NOT_FOUND" ]]; then
  check "VPC connector exists" "WARN" "Not found — not yet deployed?"
else
  check "VPC connector exists" "PASS"
fi

# Check 5: OpenRouter ZDR
echo ""
echo "[5/7] OpenRouter ZDR Configuration"
CONFIG_FILE="$(dirname "$0")/../litellm-config.yaml"
if [[ -f "$CONFIG_FILE" ]]; then
  if grep -q "data_collection.*deny" "$CONFIG_FILE"; then
    check "OpenRouter ZDR (data_collection: deny)" "PASS"
  else
    check "OpenRouter ZDR (data_collection: deny)" "FAIL" "ZDR not configured in litellm-config.yaml"
  fi
else
  check "Config file exists" "WARN" "litellm-config.yaml not found"
fi

# Check 6: No hardcoded secrets in config
echo ""
echo "[6/7] No Hardcoded Secrets"
if [[ -f "$CONFIG_FILE" ]]; then
  if grep -qE "sk-[a-zA-Z0-9]{20,}" "$CONFIG_FILE"; then
    check "No hardcoded API keys" "FAIL" "Found hardcoded key in config"
  else
    check "No hardcoded API keys" "PASS"
  fi

  if grep -q "os.environ/" "$CONFIG_FILE"; then
    check "Secrets via environment variables" "PASS"
  else
    check "Secrets via environment variables" "WARN" "No os.environ/ references found"
  fi
fi

# Check 7: Guardrails configured
echo ""
echo "[7/7] Guardrails"
if [[ -f "$CONFIG_FILE" ]]; then
  if grep -q "guardrails:" "$CONFIG_FILE" || grep -q "guardrail_list" "$CONFIG_FILE"; then
    check "Presidio guardrails configured" "PASS"
  else
    check "Presidio guardrails configured" "FAIL" "No guardrails in config"
  fi
fi

# Summary
echo ""
echo "=== Summary ==="
echo "  Passed:   $PASS"
echo "  Failed:   $FAIL"
echo "  Warnings: $WARN"
echo ""

if [[ $FAIL -gt 0 ]]; then
  echo "RESULT: FAILED — $FAIL issue(s) require attention"
  exit 1
else
  echo "RESULT: PASSED (with $WARN warning(s))"
fi
