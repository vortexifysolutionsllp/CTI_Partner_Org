#!/usr/bin/env bash
set -euo pipefail

TARGET_ORG="${1:?Usage: ./scripts/retrieve-partner-org.sh <partner-org-alias>}"

echo "Retrieving Partner Org source from: $TARGET_ORG"

sf org display --target-org "$TARGET_ORG" > /dev/null

sf project retrieve start \
  --source-dir force-app \
  --target-org "$TARGET_ORG" \
  --wait 60

echo "Partner Org retrieve completed."
