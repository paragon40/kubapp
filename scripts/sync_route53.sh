#!/bin/bash
set -euo pipefail

DOMAIN="${DOMAIN:-rundailytest.online}"
ENV="${ENV:-dev}"
ING_FILE="${INGRESS_FILE:-gitops/ingress/$ENV/values.yaml}"

if [[ ! -f "$ING_FILE" ]]; then
  echo "❌ Ingress file not found: $ING_FILE"
  exit 1
fi

echo "===================================="
echo "Route53 Auto-Provision + Sync"
echo "DOMAIN: $DOMAIN"
echo "===================================="

# -------------------------------
# 1. Get ALB from ingress
# -------------------------------
echo "Checking ingress.."
kubectl get ingress kubapp-${ENV}-alb -n "$ENV" >/dev/null

echo "Fetching ALB..."

ALB=""

for i in {1..30}; do
  ALB=$(kubectl get ingress kubapp-${ENV}-alb -n "$ENV" \
    -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)

  if [[ -n "$ALB" ]]; then
    echo "ALB ready: $ALB"
    break
  fi

  echo "ALB not ready yet ($i/30)"
  sleep 10
done

if [[ -z "$ALB" ]]; then
  echo "❌ ALB never became ready"
  kubectl describe ingress kubapp-${ENV}-alb -n "$ENV" || true
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

ZONE_EXISTS=false

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
  ZONE_EXISTS=true
fi

# -------------------------------
# 3b. Show Namecheap nameservers ONLY on NEW ZONE
# -------------------------------
if [[ "$ZONE_EXISTS" == false ]]; then
  echo ""
  echo "===================================="
  echo "NAMECHEAP DELEGATION (ONE-TIME ONLY)"
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
  echo "👉 Required ONLY ONCE per domain"
  echo "===================================="
  echo ""
fi

# -------------------------------
# 4. Define services (GitOps truth)
# -------------------------------
mapfile -t SERVICES < <(yq e '.services[].name' "$ING_FILE")

# -------------------------------
# 5. Root domain (FIXED: ALIAS A record)
# -------------------------------
echo "Updating root domain..."

ALB_ZONE_ID=$(aws elbv2 describe-load-balancers \
  --query "LoadBalancers[?DNSName=='$ALB'].CanonicalHostedZoneId" \
  --output text)

aws route53 change-resource-record-sets \
  --hosted-zone-id "$ZONE_ID" \
  --change-batch "{
    \"Changes\": [{
      \"Action\": \"UPSERT\",
      \"ResourceRecordSet\": {
        \"Name\": \"$DOMAIN\",
        \"Type\": \"A\",
        \"AliasTarget\": {
          \"HostedZoneId\": \"$ALB_ZONE_ID\",
          \"DNSName\": \"$ALB\",
          \"EvaluateTargetHealth\": false
        }
      }
    }]
  }"

# -------------------------------
# 6. Subdomains (CNAME → ALB)
# -------------------------------
echo "Updating service subdomains..."

for svc in "${SERVICES[@]}"; do
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
