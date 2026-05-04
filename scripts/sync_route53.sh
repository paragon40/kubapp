#!/bin/bash
set -euo pipefail

DOMAIN="${DOMAIN:-rundailytest.online}"
ENV="${ENV:-dev}"
ING_FILE="${INGRESS_FILE:-gitops/ingress/dev/values.yaml}"

echo "===================================="
echo "Route53 Auto-Provision + Sync"
echo "DOMAIN: $DOMAIN"
echo "===================================="

# -------------------------------
# 1. Get ALB from ingress
# -------------------------------
echo "Fetching ALB..."

ALB=$(kubectl get ingress kubapp-${ENV}-alb -n "$ENV" \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

if [[ -z "$ALB" ]]; then
  echo "❌ ALB not ready yet. Exit."
  exit 1
fi

echo "ALB: $ALB"

# -------------------------------
# 2. Check hosted zone
# -------------------------------
echo "Checking hosted zone..."

ZONE_ID=$(aws route53 list-hosted-zones-by-name \
  --dns-name "$DOMAIN" \
  --query "HostedZones[?Name=='${DOMAIN}.'].Id" \
  --output text 2>/dev/null | sed 's|/hostedzone/||')

# -------------------------------
# 3. CREATE ZONE if missing
# -------------------------------
if [[ -z "$ZONE_ID" || "$ZONE_ID" == "None" ]]; then
  echo "Hosted zone not found → creating..."

  CREATE_OUTPUT=$(aws route53 create-hosted-zone \
    --name "$DOMAIN" \
    --caller-reference "$(date +%s)-kubapp")

  ZONE_ID=$(echo "$CREATE_OUTPUT" | jq -r '.HostedZone.Id' | sed 's|/hostedzone/||')

  echo "Created hosted zone: $ZONE_ID"
else
  echo "Existing zone found: $ZONE_ID"
  exit 0
fi

# -------------------------------
# 3b. Show Namecheap nameservers (ONE-TIME SETUP)
# -------------------------------
echo ""
echo "===================================="
echo "NAMECHEAP DELEGATION"
echo "===================================="

NS=$(aws route53 get-hosted-zone \
  --id "$ZONE_ID" \
  --query "DelegationSet.NameServers[]" \
  --output text)

for ns in $NS; do
  echo "$ns"
done

echo ""
echo "👉 Paste these into Namecheap → Custom DNS"
echo "👉 This is REQUIRED ONLY ONCE per domain"
echo "===================================="
echo ""

# -------------------------------
# 4. Define services (your GitOps truth)
# -------------------------------
SERVICES=$(yq e '.services[].name' "$ING_FILE")

# -------------------------------
# 5. Root domain
# -------------------------------
echo "Updating root domain..."

aws route53 change-resource-record-sets \
  --hosted-zone-id "$ZONE_ID" \
  --change-batch "{
    \"Changes\": [{
      \"Action\": \"UPSERT\",
      \"ResourceRecordSet\": {
        \"Name\": \"$DOMAIN\",
        \"Type\": \"CNAME\",
        \"TTL\": 60,
        \"ResourceRecords\": [{\"Value\": \"$ALB\"}]
      }
    }]
  }"

# -------------------------------
# 6. Subdomains (explicit routing)
# -------------------------------
echo "Updating service subdomains..."

for svc in $SERVICES; do
  FQDN="$svc.$DOMAIN"

  echo "→ $FQDN"

  aws route53 change-resource-record-sets \
    --hosted-zone-id "$ZONE_ID" \
    --change-batch "{
      \"Changes\": [{
        \"Action\": \"UPSERT\",
        \"ResourceRecordSet\": {
          \"Name\": \"$FQDN\",
          \"Type\": \"CNAME\",
          \"TTL\": 60,
          \"ResourceRecords\": [{\"Value\": \"$ALB\"}]
        }
      }]
    }"
done

echo "===================================="
echo "DNS FULL SYNC COMPLETE"
echo "===================================="
