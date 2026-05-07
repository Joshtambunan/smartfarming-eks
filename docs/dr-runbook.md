# Disaster Recovery Runbook – SmartFarming EKS
**Project**: SmartFarming – IT Del 2026  
**Target RPO**: ≤ 1 jam | **Target RTO**: ≤ 4 jam

---

## 📋 Daftar Isi
1. Skenario Bencana
2. Prosedur Restore S3
3. Prosedur Restore RDS
4. Update Kubernetes Setelah Restore
5. Catatan Hasil DR Test

---

## 1. Skenario Bencana yang Dicakup

| Skenario | Kemungkinan | Dampak | Prosedur |
|---|---|---|---|
| File S3 terhapus tidak sengaja | Sedang | Tinggi | Restore dari S3 versioning |
| Data RDS korup atau terhapus | Rendah | Sangat Tinggi | RDS point-in-time recovery |
| EKS node down semua | Rendah | Tinggi | Deploy ulang pod ke node baru |
| Region AWS down | Sangat Rendah | Kritis | Failover ke backup region |

---

## 2. Prosedur Restore S3

### Tujuan
Memulihkan file yang terhapus atau versi lama dari S3 menggunakan S3 Versioning.

### Prasyarat
- AWS CLI terinstall dan ter-konfigurasi dengan kredensial yang tepat
- S3 Versioning sudah diaktifkan (dikonfigurasi via Terraform)

### Langkah-langkah

**Step 1: Identifikasi file yang perlu di-restore**
```bash
# List semua versi file di bucket
aws s3api list-object-versions \
  --bucket smartfarming-storage-NAMAKALIAN \
  --prefix nama-file-yang-hilang.txt

# Output akan menampilkan VersionId dan IsLatest untuk setiap versi
```

**Step 2: Identifikasi versi yang benar**
```bash
# Lihat detail versi tertentu
aws s3api get-object \
  --bucket smartfarming-storage-NAMAKALIAN \
  --key nama-file.txt \
  --version-id "VERSION_ID_YANG_DIPILIH" \
  /tmp/preview-restore.txt

cat /tmp/preview-restore.txt  # Verifikasi isinya benar
```

**Step 3: Restore versi lama**
```bash
# Jalankan script restore
bash scripts/restore/restore-s3.sh nama-file.txt VERSION_ID_YANG_DIPILIH

# Atau manual:
aws s3api copy-object \
  --bucket smartfarming-storage-NAMAKALIAN \
  --copy-source "smartfarming-storage-NAMAKALIAN/nama-file.txt?versionId=VERSION_ID" \
  --key nama-file.txt
```

**Step 4: Verifikasi**
```bash
# Cek file sudah tersedia
aws s3api head-object \
  --bucket smartfarming-storage-NAMAKALIAN \
  --key nama-file.txt

# Test download via API
curl http://storage-service:8001/download/nama-file.txt
```

**Estimasi waktu**: 5–15 menit

---

## 3. Prosedur Restore RDS Point-in-Time

### Tujuan
Memulihkan database ke kondisi tertentu menggunakan RDS automated backup.

### Prasyarat
- RDS automated backup diaktifkan (7 hari dev, 30 hari prod) – dikonfigurasi Terraform
- Akses AWS CLI dengan permission `rds:RestoreDBInstanceToPointInTime`

### Langkah-langkah

**Step 1: Identifikasi waktu restore yang diinginkan**
```bash
# Lihat window backup yang tersedia
aws rds describe-db-instances \
  --db-instance-identifier smartfarming-db-dev \
  --query 'DBInstances[0].{
    Earliest: RestoreWindow.EarliestTime,
    Latest: RestoreWindow.LatestTime,
    BackupRetentionDays: BackupRetentionPeriod
  }'
```

**Step 2: Restore ke instance baru**
```bash
# Restore ke waktu tertentu (format ISO 8601)
aws rds restore-db-instance-to-point-in-time \
  --source-db-instance-identifier smartfarming-db-dev \
  --target-db-instance-identifier smartfarming-db-restored \
  --restore-time "2026-05-01T10:00:00Z" \
  --db-instance-class db.t3.micro \
  --no-multi-az \
  --tags Key=Project,Value=smartfarming Key=Environment,Value=dev Key=Purpose,Value=dr-restore
```

**Step 3: Tunggu instance restored siap**
```bash
# Monitor status restore (bisa 15–45 menit)
aws rds wait db-instance-available \
  --db-instance-identifier smartfarming-db-restored

echo "✅ RDS instance restored dan available"
```

**Step 4: Ambil endpoint baru**
```bash
NEW_ENDPOINT=$(aws rds describe-db-instances \
  --db-instance-identifier smartfarming-db-restored \
  --query 'DBInstances[0].Endpoint.Address' \
  --output text)
echo "New endpoint: $NEW_ENDPOINT"
```

**Step 5: Update Kubernetes ConfigMap dengan endpoint baru**
```bash
# Update configmap farm-data-service
kubectl create configmap farm-data-config \
  --from-literal=DB_HOST=$NEW_ENDPOINT \
  --from-literal=DB_PORT=5432 \
  --from-literal=DB_NAME=smartfarming \
  --from-literal=DB_USER=farmuser \
  --from-literal=AWS_REGION=ap-southeast-1 \
  -n farm-data \
  --dry-run=client -o yaml | kubectl apply -f -

# Restart pod agar ambil konfigurasi baru
kubectl rollout restart deployment/farm-data-service -n farm-data

# Tunggu pod ready
kubectl rollout status deployment/farm-data-service -n farm-data
```

**Step 6: Verifikasi**
```bash
# Test koneksi ke DB
kubectl port-forward svc/farm-data-service 8002:8002 -n farm-data &
curl http://localhost:8002/health
curl http://localhost:8002/sensors?limit=5
```

**Step 7: Cleanup instance lama (setelah yakin restore berhasil)**
```bash
# Hapus instance lama jika sudah tidak dibutuhkan
aws rds delete-db-instance \
  --db-instance-identifier smartfarming-db-dev \
  --skip-final-snapshot

# Rename restored instance menjadi nama asli (opsional)
aws rds modify-db-instance \
  --db-instance-identifier smartfarming-db-restored \
  --new-db-instance-identifier smartfarming-db-dev \
  --apply-immediately
```

**Estimasi waktu**: 30–90 menit

---

## 4. Update Kubernetes Setelah Restore

Setelah restore (S3 atau RDS), lakukan langkah berikut untuk memastikan semua pod menggunakan konfigurasi terbaru:

```bash
# 1. Restart semua deployment
kubectl rollout restart deployment/storage-service -n storage
kubectl rollout restart deployment/farm-data-service -n farm-data
kubectl rollout restart deployment/frontend-service -n frontend

# 2. Tunggu semua pod ready
kubectl rollout status deployment/storage-service -n storage
kubectl rollout status deployment/farm-data-service -n farm-data
kubectl rollout status deployment/frontend-service -n frontend

# 3. Verifikasi semua pod running
kubectl get pods -A | grep smartfarming

# 4. Test endpoint semua service
kubectl port-forward svc/storage-service 8001:8001 -n storage &
kubectl port-forward svc/farm-data-service 8002:8002 -n farm-data &
kubectl port-forward svc/frontend-service 3000:3000 -n frontend &

curl http://localhost:8001/health
curl http://localhost:8002/health
curl http://localhost:3000
```

---

## 5. Catatan Hasil DR Test

Isi tabel ini setelah setiap DR drill:

| Tanggal | Skenario | Waktu Mulai | Waktu Selesai | Durasi | RPO Tercapai? | RTO Tercapai? | Catatan |
|---|---|---|---|---|---|---|---|
| YYYY-MM-DD | S3 file restore | HH:MM | HH:MM | X menit | ✅/❌ | ✅/❌ | |
| YYYY-MM-DD | RDS point-in-time | HH:MM | HH:MM | X menit | ✅/❌ | ✅/❌ | |

**Target**: RPO ≤ 60 menit | RTO ≤ 240 menit

---

*Dokumen ini harus diperbarui setiap kali ada perubahan infrastruktur.*  
*DR drill dijadwalkan setiap kuartal.*
