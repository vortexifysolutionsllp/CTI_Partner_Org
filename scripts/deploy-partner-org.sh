#!/usr/bin/env bash
set -euo pipefail

TARGET_ORG="${1:?Usage: ./scripts/deploy-partner-org.sh <partner-org-alias>}"

echo "Deploying Partner Org app to: $TARGET_ORG"

sf org display --target-org "$TARGET_ORG" > /dev/null

sf project deploy start \
  --source-dir force-app \
  --target-org "$TARGET_ORG" \
  --wait 60

echo "Partner Org deployment completed."
