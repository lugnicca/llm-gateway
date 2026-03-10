#!/usr/bin/env bash
set -euo pipefail

# Rotate LiteLLM master key via GCP Secret Manager and redeploy Cloud Run
# Usage: ./rotate-master-key.sh

PROJECT_ID="${GCP_PROJECT_ID:-litellm-489602}"
REGION="${GCP_REGION:-europe-west9}"
ORG_NAME="${ORG_NAME:-lugnicca}"
SECRET_ID="${ORG_NAME}-litellm-master-key"
SERVICE_NAME="${ORG_NAME}-litellm-gateway"

echo "=== Master Key Rotation ==="
echo "Project: $PROJECT_ID"
echo "Region:  $REGION"
echo ""

# Generate new key
NEW_KEY="sk-litellm-$(openssl rand -hex 24)"
echo "Generated new master key"

# Add new secret version
echo "Updating Secret Manager..."
echo -n "$NEW_KEY" | gcloud secrets versions add "$SECRET_ID" \
  --project="$PROJECT_ID" \
  --data-file=-

echo "Secret updated"

# Disable old versions (keep last 2)
echo "Disabling old secret versions..."
OLD_VERSIONS=$(gcloud secrets versions list "$SECRET_ID" \
  --project="$PROJECT_ID" \
  --format="value(name)" \
  --filter="state=ENABLED" \
  --sort-by="~createTime" | tail -n +3)

for version in $OLD_VERSIONS; do
  echo "  Disabling version: $version"
  gcloud secrets versions disable "$version" \
    --secret="$SECRET_ID" \
    --project="$PROJECT_ID" \
    --quiet
done

# Redeploy Cloud Run to pick up new secret
echo ""
echo "Redeploying Cloud Run service..."
gcloud run services update "$SERVICE_NAME" \
  --project="$PROJECT_ID" \
  --region="$REGION" \
  --update-secrets="LITELLM_MASTER_KEY=${SECRET_ID}:latest"

echo ""
echo "=== Rotation Complete ==="
echo "New master key: $NEW_KEY"
echo ""
echo "IMPORTANT: Update all admin scripts with the new master key."
echo "User virtual keys are NOT affected by master key rotation."
