#!/bin/bash
# ============================================================
# scripts/restore/restore-s3.sh
# Script untuk restore file S3 dari versi lama
#
# Usage:
#   bash scripts/restore/restore-s3.sh <filename> <version-id>
#
# Contoh:
#   bash scripts/restore/restore-s3.sh data-sensor.csv abc123xyz
# ============================================================

set -euo pipefail

FILENAME=${1:-""}
VERSION_ID=${2:-""}
BUCKET_NAME=${S3_BUCKET_NAME:-"smartfarming-storage-GANTI_INI"}

if [[ -z "$FILENAME" || -z "$VERSION_ID" ]]; then
  echo "❌ Usage: bash restore-s3.sh <filename> <version-id>"
  echo "   Contoh: bash restore-s3.sh sensor-data.csv abc123"
  exit 1
fi

echo "🔄 Memulai restore S3..."
echo "   Bucket  : $BUCKET_NAME"
echo "   File    : $FILENAME"
echo "   Version : $VERSION_ID"
echo ""

START_TIME=$(date +%s)

# Restore dengan copy object ke versi terbaru
aws s3api copy-object \
  --bucket "$BUCKET_NAME" \
  --copy-source "${BUCKET_NAME}/${FILENAME}?versionId=${VERSION_ID}" \
  --key "$FILENAME"

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

echo ""
echo "✅ Restore berhasil dalam ${DURATION} detik"
echo "   File '$FILENAME' telah dikembalikan ke versi $VERSION_ID"

# Verifikasi
echo ""
echo "🔍 Verifikasi file..."
aws s3api head-object \
  --bucket "$BUCKET_NAME" \
  --key "$FILENAME" \
  --query '{Size: ContentLength, LastModified: LastModified}'

echo ""
echo "📊 Catat hasil ini di docs/dr-runbook.md:"
echo "   Skenario : S3 file restore"
echo "   Durasi   : ${DURATION} detik"
echo "   RPO      : Cek timestamp versi vs saat ini"
