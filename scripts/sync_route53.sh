#!/bin/bash
set -euo pipefail

# -------------------------------
# CONFIG
# -------------------------------
DOMAIN="${DOMAIN:-rundailytest.online}"
ENV="${ENV:-dev}"
ING_FILE="${INGRESS_FILE:-gitops/ingress/$ENV/values.yaml}"
AWS_REGION="${AWS_REGION:-$(aws configure get region)}"
CERT_ARN="${CERT_ARN:-}"

echo "===================================="
echo "Route53 Auto-Provision + Sync"
echo "DOMAIN: $DOMAIN"
echo "ENV: $ENV"
echo "AWS_REGION: $AWS_REGION"
echo "===================================="

# -------------------------------
# PRECHECKS
# -------------------------------
if [[ -z "$AWS_REGION" ]]; then
  echo "❌ AWS region not set"
  exit 1
fi

if [[ -z "$CERT_ARN" ]]; then
  echo "❌ CERT_ARN not provided"
  exit 1
fi

if [[ ! -f "$ING_FILE" ]]; then
  echo "❌ Ingress file not found: $ING_FILE"
  exit 1
fi

# -------------------------------
# CERT VALIDATION (HARD GUARANTEE)
# -------------------------------
echo "Validating ACM certificate..."

CERT_STATUS=$(aws acm describe-certificate \
  --region "$AWS_REGION" \
  --certificate-arn "$CERT_ARN" \
  --query "Certificate.Status" \
  --output text 2>/dev/null || true)

if [[ "$CERT_STATUS" != "ISSUED" ]]; then
  echo "❌ Certificate not valid in region or not issued: $CERT_ARN"
  exit 1
fi

echo "✅ Certificate OK"

# -------------------------------
# GET ALB FROM K8S
# -------------------------------
echo "Fetching ALB from ingress..."

ALB=""

for i in {1..15}; do
  ALB=$(kubectl get ingress kubapp-$ENV-alb -n "$ENV" \
    -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)

  if [[ -n "$ALB" ]]; then
    echo "✅ ALB ready: $ALB"
    break
  fi

  echo "⏳ Waiting for ALB ($i/15)"
  sleep 10
done

if [[ -z "$ALB" ]]; then
  echo "❌ ALB never became ready"
  kubectl describe ingress kubapp-$ENV-alb -n "$ENV" || true
  exit 1
fi

# -------------------------------
# VERIFY ALB EXISTS IN AWS
# -------------------------------
ALB_ARN=$(aws elbv2 describe-load-balancers \
  --region "$AWS_REGION" \
  --query "LoadBalancers[?DNSName=='$ALB'].LoadBalancerArn | [0]" \
  --output text)

if [[ -z "$ALB_ARN" || "$ALB_ARN" == "None" ]]; then
  echo "❌ ALB not found in AWS ELBv2 API"
  exit 1
fi

ALB_ZONE_ID=$(aws elbv2 describe-load-balancers \
  --region "$AWS_REGION" \
  --load-balancer-arns "$ALB_ARN" \
  --query "LoadBalancers[0].CanonicalHostedZoneId" \
  --output text)

echo "✅ ALB verified in AWS"

# -------------------------------
# HOSTED ZONE
# -------------------------------
echo "Checking Route53 hosted zone..."

ZONE_ID=$(aws route53 list-hosted-zones-by-name \
  --dns-name "$DOMAIN" \
  --query "HostedZones[?Name=='${DOMAIN}.'].Id" \
  --output text 2>/dev/null | sed 's|/hostedzone/||')

ZONE_EXISTS=false

if [[ -z "$ZONE_ID" || "$ZONE_ID" == "None" ]]; then
  echo "Creating hosted zone..."

  CREATE_OUTPUT=$(aws route53 create-hosted-zone \
    --name "$DOMAIN" \
    --caller-reference "$(date +%s)-kubapp")

  ZONE_ID=$(echo "$CREATE_OUTPUT" | jq -r '.HostedZone.Id' | sed 's|/hostedzone/||')

  echo "✅ Hosted zone created: $ZONE_ID"
else
  echo "✅ Existing zone: $ZONE_ID"
  ZONE_EXISTS=true
fi

# -------------------------------
# NAMECHEAP INFO (ONLY FIRST TIME)
# -------------------------------
if [[ "$ZONE_EXISTS" == false ]]; then
  echo ""
  echo "===================================="
  echo "NAMECHEAP DELEGATION (ONCE ONLY)"
  echo "===================================="

  aws route53 get-hosted-zone \
    --id "$ZONE_ID" \
    --query "DelegationSet.NameServers[]" \
    --output text

  echo ""
  echo "👉 Add these to Namecheap DNS"
  echo "===================================="
fi

# -------------------------------
# SERVICES FROM GITOPS
# -------------------------------
mapfile -t SERVICES < <(yq e '.services[].name' "$ING_FILE")

# -------------------------------
# ROOT DOMAIN
# -------------------------------
echo "Updating root domain..."

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
# SUBDOMAINS
# -------------------------------
echo "Updating subdomains..."

for svc in "${SERVICES[@]}"; do
  FQDN="$svc.$DOMAIN"

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

  echo "→ $FQDN updated"
done

echo "===================================="
echo "DNS SYNC COMPLETE"
echo "===================================="
