#!/bin/bash
# ============================================================
# scripts/restore/restore-rds.sh
# Script untuk restore RDS ke point-in-time
#
# Usage:
#   bash scripts/restore/restore-rds.sh "2026-05-01T10:00:00Z"
# ============================================================

set -euo pipefail

RESTORE_TIME=${1:-""}
SOURCE_DB=${SOURCE_DB_ID:-"smartfarming-db-dev"}
TARGET_DB="smartfarming-db-restored-$(date +%Y%m%d%H%M)"
DB_CLASS=${DB_CLASS:-"db.t3.micro"}
REGION=${AWS_REGION:-"ap-southeast-1"}

if [[ -z "$RESTORE_TIME" ]]; then
  echo "❌ Usage: bash restore-rds.sh '<ISO8601_datetime>'"
  echo "   Contoh: bash restore-rds.sh '2026-05-01T10:00:00Z'"
  echo ""
  echo "   Cek window yang tersedia:"
  echo "   aws rds describe-db-instances --db-instance-identifier $SOURCE_DB --query 'DBInstances[0].RestoreWindow'"
  exit 1
fi

echo "🔄 Memulai RDS Point-in-Time Recovery..."
echo "   Source DB    : $SOURCE_DB"
echo "   Target DB    : $TARGET_DB"
echo "   Restore Time : $RESTORE_TIME"
echo "   DB Class     : $DB_CLASS"
echo ""

START_TIME=$(date +%s)

# Jalankan restore
aws rds restore-db-instance-to-point-in-time \
  --source-db-instance-identifier "$SOURCE_DB" \
  --target-db-instance-identifier "$TARGET_DB" \
  --restore-time "$RESTORE_TIME" \
  --db-instance-class "$DB_CLASS" \
  --no-multi-az \
  --region "$REGION" \
  --tags \
    Key=Project,Value=smartfarming \
    Key=Environment,Value=dev \
    Key=Purpose,Value=dr-restore \
    Key=RestoreTime,Value="$(echo $RESTORE_TIME | tr ':' '-')"

echo "⏳ Menunggu instance siap (bisa 15-45 menit)..."
aws rds wait db-instance-available \
  --db-instance-identifier "$TARGET_DB" \
  --region "$REGION"

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

# Ambil endpoint baru
NEW_ENDPOINT=$(aws rds describe-db-instances \
  --db-instance-identifier "$TARGET_DB" \
  --region "$REGION" \
  --query 'DBInstances[0].Endpoint.Address' \
  --output text)

echo ""
echo "✅ RDS restore berhasil dalam $((DURATION / 60)) menit $((DURATION % 60)) detik"
echo "   New endpoint: $NEW_ENDPOINT"
echo ""
echo "📋 Langkah selanjutnya:"
echo "   1. Update Kubernetes ConfigMap:"
echo "      kubectl create configmap farm-data-config \\"
echo "        --from-literal=DB_HOST=$NEW_ENDPOINT \\"
echo "        --from-literal=DB_PORT=5432 \\"
echo "        --from-literal=DB_NAME=smartfarming \\"
echo "        --from-literal=DB_USER=farmuser \\"
echo "        --from-literal=AWS_REGION=$REGION \\"
echo "        -n farm-data --dry-run=client -o yaml | kubectl apply -f -"
echo ""
echo "   2. Restart farm-data-service:"
echo "      kubectl rollout restart deployment/farm-data-service -n farm-data"
echo ""
echo "   3. Verifikasi:"
echo "      kubectl rollout status deployment/farm-data-service -n farm-data"
echo ""
echo "📊 Catat hasil ini di docs/dr-runbook.md:"
echo "   Skenario : RDS point-in-time recovery"
echo "   Durasi   : $((DURATION / 60)) menit"
echo "   Target DB: $TARGET_DB"
