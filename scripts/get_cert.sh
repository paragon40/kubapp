#!/usr/bin/env bash
set -euo pipefail

DOMAIN="${1:-${DOMAIN:-}}"

if [[ -z "$DOMAIN" ]]; then
  echo "Usage: $0 <domain>"
  exit 1
fi

echo " Collecting ALL ACM domains in AWS account..."
echo "------------------------------------------------"

CERT_ARNS=$(aws acm list-certificates \
  --query "CertificateSummaryList[].CertificateArn" \
  --output text)

ALL_DOMAINS=()

# -----------------------------
# STEP 1: COLLECT ALL DOMAINS
# -----------------------------
for arn in $CERT_ARNS; do
  DOMAINS=$(aws acm describe-certificate \
    --certificate-arn "$arn" \
    --query "Certificate.SubjectAlternativeNames" \
    --output text)

  for d in $DOMAINS; do
    ALL_DOMAINS+=("$d")
  done
done

# -----------------------------
# STEP 2: PRINT ALL DOMAINS
# -----------------------------
echo "All domains found in ACM:"
for d in "${ALL_DOMAINS[@]}"; do
  echo " - $d"
done

echo "------------------------------------------------"

# -----------------------------
# STEP 3: CHECK INPUT DOMAIN
# -----------------------------
FOUND=""

for arn in $CERT_ARNS; do
  DOMAINS=$(aws acm describe-certificate \
    --certificate-arn "$arn" \
    --query "Certificate.SubjectAlternativeNames" \
    --output text)

  for d in $DOMAINS; do
    if [[ "$d" == "$DOMAIN" ]]; then
      FOUND="$arn"
      break 2
    fi
  done
done

# -----------------------------
# STEP 4: RESULT
# -----------------------------
if [[ -z "$FOUND" ]]; then
  echo "❌ DOMAIN NOT FOUND IN ACM: $DOMAIN"
  exit 1
fi

echo "✅ DOMAIN EXISTS IN ACM: $DOMAIN"
echo "CERTIFICATE ARN:"
echo "CERT_ARN=$FOUND"
# export CERT_ARN="$FOUND"
