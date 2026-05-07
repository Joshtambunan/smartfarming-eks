# 🌱 SmartFarming System on AWS EKS
> Final Project – AWS Cloud Administration – IT-Del 2026

Smart farming services on Kubernetes with secure AWS access and IaC automation using Terraform.

---

## 📁 Struktur Repository

```
smartfarming-eks/
├── docs/                          # Dokumentasi lengkap
│   ├── architecture.md            # Diagram dan penjelasan arsitektur
│   ├── dr-runbook.md              # Prosedur Disaster Recovery
│   └── irsa-guide.md             # Panduan setup IRSA
├── services/                      # Source code semua service
│   ├── storage-service/           # Service upload/download file ke S3
│   ├── farm-data-service/         # Service CRUD data IoT sensor + RDS
│   └── frontend-service/          # Dashboard UI visualisasi data
├── k8s/                           # Kubernetes manifests
│   ├── storage/                   # Manifest untuk storage-service
│   ├── farm-data/                 # Manifest untuk farm-data-service
│   └── frontend/                  # Manifest untuk frontend-service
├── terraform/                     # Infrastructure as Code
│   ├── modules/                   # Terraform modules (eks, irsa, s3, rds, ecr, vpc)
│   ├── main.tf                    # Root module
│   ├── variables.tf               # Input variables
│   ├── outputs.tf                 # Output values
│   └── backend.tf                 # Remote state config
├── scripts/                       # Helper scripts
│   └── restore/                   # DR restore scripts
├── docker-compose.yml             # Local development environment
└── .gitignore
```

---

## 🗺️ Roadmap Pengerjaan

### FASE 0 – Persiapan Tools
### FASE 1 – Development & Test Lokal
### FASE 2 – AWS Infrastructure dengan Terraform
### FASE 3 – Build, Push ECR & Deploy ke EKS
### FASE 4 – Disaster Recovery & Backup
### FASE 5 – Cost Tagging & Budget Alert
### FASE 6 – Dokumentasi & Finalisasi

Lihat detail setiap fase di bawah ini.

---

## ⚙️ FASE 0 — Persiapan Tools

### Tujuan
Memastikan semua tools terinstall sebelum mulai coding.

### Tools yang dibutuhkan

| Tool | Fungsi | Install |
|---|---|---|
| Docker Desktop | Build dan run container | https://docs.docker.com/get-docker/ |
| MicroK8s / Minikube | Kubernetes lokal | `sudo snap install microk8s --classic` |
| kubectl | CLI untuk Kubernetes | https://kubernetes.io/docs/tasks/tools/ |
| Terraform | Infrastructure as Code | https://developer.hashicorp.com/terraform/install |
| AWS CLI v2 | CLI untuk AWS | https://aws.amazon.com/cli/ |
| Python 3.11+ | Runtime backend service | https://python.org |
| Git | Version control | https://git-scm.com |

### Langkah-langkah

```bash
# 1. Clone repository ini
git clone https://github.com/USERNAME/smartfarming-eks.git
cd smartfarming-eks

# 2. Verifikasi semua tools terinstall
docker --version
kubectl version --client
terraform version
aws --version
python3 --version

# 3. Configure AWS CLI
aws configure
# Masukkan: AWS Access Key, Secret Key, Region (ap-southeast-1), output format (json)

# 4. Verifikasi AWS CLI terhubung
aws sts get-caller-identity
```

---

## 💻 FASE 1 — Development & Test Lokal

### Tujuan
Membangun semua service dan memastikan semuanya jalan di lokal sebelum deploy ke AWS.
Ini menghemat AWS credit karena debugging dilakukan di lokal.

### Step 1.1 — Jalankan environment lokal dengan Docker Compose

```bash
# Dari root project
docker-compose up --build

# Verifikasi semua service running
docker-compose ps
```

**Endpoint yang tersedia setelah up:**
- storage-service  → http://localhost:8001/docs
- farm-data-service → http://localhost:8002/docs
- frontend-service  → http://localhost:3000

### Step 1.2 — Test storage-service

```bash
# Upload file
curl -X POST "http://localhost:8001/upload" \
  -F "file=@test.txt"

# List file
curl http://localhost:8001/files

# Download file
curl http://localhost:8001/download/test.txt -o downloaded.txt
```

### Step 1.3 — Test farm-data-service

```bash
# Tambah data sensor
curl -X POST "http://localhost:8002/sensors" \
  -H "Content-Type: application/json" \
  -d '{"sensor_id": "sensor-01", "type": "temperature", "value": 28.5, "unit": "celsius"}'

# Lihat semua data sensor
curl http://localhost:8002/sensors

# Jalankan IoT simulator (generate data otomatis)
curl -X POST http://localhost:8002/simulator/start
```

### Step 1.4 — Test di MicroK8s Lokal

```bash
# Enable addons yang dibutuhkan
microk8s enable dns storage registry

# Apply semua manifest
kubectl apply -f k8s/storage/
kubectl apply -f k8s/farm-data/
kubectl apply -f k8s/frontend/

# Cek pod running
kubectl get pods -A

# Port forward untuk test
kubectl port-forward svc/storage-service 8001:8001 -n storage
```

---

## ☁️ FASE 2 — AWS Infrastructure dengan Terraform

### Tujuan
Membuat seluruh infrastruktur AWS secara otomatis menggunakan Terraform.
Tidak boleh ada resource yang dibuat manual di console AWS.

### Urutan resource yang dibuat Terraform:
1. **VPC** – network isolasi untuk semua resource
2. **ECR** – repository untuk Docker images
3. **EKS Cluster** – managed Kubernetes
4. **OIDC Provider** – jembatan antara EKS dan IAM (syarat IRSA)
5. **S3 Bucket** – storage untuk storage-service
6. **RDS PostgreSQL** – database untuk farm-data-service
7. **IAM Roles (IRSA)** – akses AWS per service account

### Step 2.1 — Setup Terraform Backend (Remote State)

```bash
# Buat S3 bucket untuk menyimpan terraform state (lakukan manual SEKALI)
aws s3 mb s3://smartfarming-tfstate-NAMAKALIAN --region ap-southeast-1

# Buat DynamoDB table untuk state locking
aws dynamodb create-table \
  --table-name smartfarming-tfstate-lock \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region ap-southeast-1
```

### Step 2.2 — Edit variables.tf

```bash
cd terraform
# Edit file variables.tf, sesuaikan:
# - aws_region
# - project_name
# - your_name / NIM untuk resource naming
```

### Step 2.3 — Deploy Infrastructure

```bash
cd terraform

# Download providers
terraform init

# Preview resource yang akan dibuat
terraform plan

# Deploy (ketik 'yes' saat diminta)
terraform apply

# Catat output penting:
# - eks_cluster_name
# - ecr_repository_urls
# - s3_bucket_name
# - rds_endpoint
```

### Step 2.4 — Connect kubectl ke EKS

```bash
# Update kubeconfig
aws eks update-kubeconfig \
  --name smartfarming-eks \
  --region ap-southeast-1

# Verifikasi
kubectl get nodes
```

### Step 2.5 — Verifikasi IRSA (M1 ✅)

```bash
# Deploy test pod untuk verifikasi IRSA
kubectl apply -f k8s/test-irsa-pod.yaml

# Masuk ke pod dan test assume role
kubectl exec -it test-pod -n storage -- aws sts get-caller-identity

# Harus muncul ARN role storage-service, bukan node role
```

---

## 🚀 FASE 3 — Build, Push ECR & Deploy ke EKS

### Tujuan
Build Docker image, push ke ECR, dan deploy semua service ke EKS.

### Step 3.1 — Login ke ECR

```bash
# Ganti ACCOUNT_ID dan REGION sesuai milikmu
aws ecr get-login-password --region ap-southeast-1 | \
  docker login --username AWS \
  --password-stdin ACCOUNT_ID.dkr.ecr.ap-southeast-1.amazonaws.com
```

### Step 3.2 — Build dan Push storage-service (M2 ✅)

```bash
cd services/storage-service

# Build image, tag dengan git commit ID
GIT_COMMIT=$(git rev-parse --short HEAD)
ECR_URL=ACCOUNT_ID.dkr.ecr.ap-southeast-1.amazonaws.com/smartfarming-storage

docker build -t $ECR_URL:$GIT_COMMIT .
docker push $ECR_URL:$GIT_COMMIT

# Update image tag di deployment manifest
sed -i "s|IMAGE_TAG|$GIT_COMMIT|g" ../../k8s/storage/deployment.yaml

# Deploy ke EKS
kubectl apply -f ../../k8s/storage/
kubectl rollout status deployment/storage-service -n storage

# Test upload file ke S3 (harus berhasil dengan IAM role, bukan static key)
kubectl port-forward svc/storage-service 8001:8001 -n storage &
curl -X POST http://localhost:8001/upload -F "file=@../../scripts/test.txt"
```

### Step 3.3 — Build dan Push farm-data-service (M3 ✅)

```bash
cd services/farm-data-service

GIT_COMMIT=$(git rev-parse --short HEAD)
ECR_URL=ACCOUNT_ID.dkr.ecr.ap-southeast-1.amazonaws.com/smartfarming-farmdata

docker build -t $ECR_URL:$GIT_COMMIT .
docker push $ECR_URL:$GIT_COMMIT

sed -i "s|IMAGE_TAG|$GIT_COMMIT|g" ../../k8s/farm-data/deployment.yaml
kubectl apply -f ../../k8s/farm-data/
kubectl rollout status deployment/farm-data-service -n farm-data

# Test CRUD ke RDS
kubectl port-forward svc/farm-data-service 8002:8002 -n farm-data &
curl -X POST http://localhost:8002/sensors \
  -H "Content-Type: application/json" \
  -d '{"sensor_id":"s01","type":"temperature","value":28.5,"unit":"celsius"}'
```

### Step 3.4 — Build dan Push frontend-service

```bash
cd services/frontend-service

GIT_COMMIT=$(git rev-parse --short HEAD)
ECR_URL=ACCOUNT_ID.dkr.ecr.ap-southeast-1.amazonaws.com/smartfarming-frontend

docker build -t $ECR_URL:$GIT_COMMIT .
docker push $ECR_URL:$GIT_COMMIT

sed -i "s|IMAGE_TAG|$GIT_COMMIT|g" ../../k8s/frontend/deployment.yaml
kubectl apply -f ../../k8s/frontend/
kubectl rollout status deployment/frontend-service -n frontend

# Akses dashboard
kubectl port-forward svc/frontend-service 3000:3000 -n frontend &
open http://localhost:3000
```

### Step 3.5 — Verifikasi HPA berjalan

```bash
kubectl get hpa -A
# Semua service harus punya HPA aktif
```

---

## 🛡️ FASE 4 — Disaster Recovery & Backup

### Tujuan
Memastikan data tidak hilang dan sistem bisa dipulihkan dalam RPO ≤ 1 jam / RTO ≤ 4 jam.

### Step 4.1 — Verifikasi S3 Versioning aktif

```bash
aws s3api get-bucket-versioning \
  --bucket smartfarming-storage-NAMAKALIAN
# Harus return: {"Status": "Enabled"}
```

### Step 4.2 — Restore S3 Object (simulasi DR)

```bash
# Lihat versi file yang tersedia
aws s3api list-object-versions \
  --bucket smartfarming-storage-NAMAKALIAN \
  --prefix namafile.txt

# Restore versi lama
bash scripts/restore/restore-s3.sh namafile.txt VERSION_ID
```

### Step 4.3 — Restore RDS Point-in-Time

```bash
# Lihat window backup yang tersedia
aws rds describe-db-instances \
  --db-instance-identifier smartfarming-db \
  --query 'DBInstances[0].{EarliestRestoreTime:RestoreWindow.EarliestTime}'

# Jalankan restore
bash scripts/restore/restore-rds.sh "2026-05-01T10:00:00Z"

# Setelah restore, update Kubernetes secret RDS endpoint
kubectl create secret generic rds-config \
  --from-literal=host=NEW_RDS_ENDPOINT \
  --from-literal=port=5432 \
  -n farm-data --dry-run=client -o yaml | kubectl apply -f -

# Restart pod agar koneksi diperbarui
kubectl rollout restart deployment/farm-data-service -n farm-data
```

### Step 4.4 — Catat hasil DR Test

Isi tabel di `docs/dr-runbook.md`:
- Waktu mulai restore
- Waktu selesai restore
- Total durasi (harus ≤ RTO 4 jam)
- Data hilang maksimal (harus ≤ RPO 1 jam)

---

## 💰 FASE 5 — Cost Tagging & Budget Alert (M5 ✅)

### Tujuan
Memastikan semua resource AWS ter-tag dan ada alert jika cost melebihi batas.

### Step 5.1 — Verifikasi Tag di semua resource

```bash
# Cek tag di EKS
aws eks describe-cluster --name smartfarming-eks \
  --query 'cluster.tags'

# Cek tag di S3
aws s3api get-bucket-tagging \
  --bucket smartfarming-storage-NAMAKALIAN

# Cek tag di RDS
aws rds describe-db-instances \
  --db-instance-identifier smartfarming-db \
  --query 'DBInstances[0].TagList'
```

Tags yang harus ada di setiap resource:
```
Project     = smartfarming
Environment = dev
Service     = storage-service / farm-data-service / frontend-service
Owner       = NAMA_KALIAN
CostCenter  = CC-AGRI-01
```

### Step 5.2 — Setup AWS Budget (via Terraform, sudah otomatis)

Cek budget di console: https://console.aws.amazon.com/billing/home#/budgets

Alert akan dikirim ke email saat cost mencapai 50%, 80%, dan 100%.

### Step 5.3 — Review Cost Explorer

```bash
# Buka Cost Explorer di console AWS
# Filter by tag: Project = smartfarming
# Lihat breakdown per service
```

---

## 📄 FASE 6 — Dokumentasi & Finalisasi

### Checklist sebelum submit

- [ ] Semua service berjalan di EKS
- [ ] IRSA terkonfigurasi benar (tidak ada static key)
- [ ] HPA aktif untuk semua service
- [ ] S3 versioning enabled
- [ ] RDS backup enabled
- [ ] DR restore test berhasil dan dicatat di runbook
- [ ] Semua resource ter-tag dengan benar
- [ ] AWS Budget alerts aktif
- [ ] README lengkap
- [ ] Tidak ada secret/key yang ter-commit ke Git
- [ ] `terraform destroy` bisa dijalankan bersih (cleanup)

### Cleanup setelah demo (PENTING – hemat credit)

```bash
cd terraform
terraform destroy
# Ketik 'yes' untuk destroy semua resource
```

---

## 🔐 Security Rules (WAJIB DIPATUHI)

1. **JANGAN PERNAH** commit AWS Access Key ke Git
2. **JANGAN PERNAH** taruh password database di manifest YAML
3. IRSA adalah satu-satunya cara pod mengakses AWS
4. Setiap service hanya bisa akses resource miliknya sendiri
5. Container harus run sebagai non-root user
6. Tambahkan `.gitignore` yang mencakup `.env`, `*.pem`, `terraform.tfvars`

---

## 👥 Tim & Kontak

| Nama | NIM | Role |
|---|---|---|
| [Nama] | [NIM] | Developer |

**Institut Teknologi Del – 2026**
