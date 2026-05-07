# Panduan IRSA – IAM Roles for Service Accounts

## Apa itu IRSA?

IRSA adalah mekanisme keamanan yang memungkinkan pod Kubernetes mendapatkan
akses ke layanan AWS **tanpa menyimpan AWS Access Key** di mana pun.

## Kenapa IRSA Penting?

Tanpa IRSA (cara yang SALAH):
```yaml
# JANGAN LAKUKAN INI! ❌
env:
  - name: AWS_ACCESS_KEY_ID
    value: "AKIAIOSFODNN7EXAMPLE"        # Berbahaya jika ter-commit ke Git
  - name: AWS_SECRET_ACCESS_KEY
    value: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
```

Dengan IRSA (cara yang BENAR):
```yaml
# Cukup anotasi Service Account ✅
metadata:
  annotations:
    eks.amazonaws.com/role-arn: "arn:aws:iam::123456789:role/storage-service-role"
```

## Cara Kerja IRSA

```
Pod → pakai Kubernetes Service Account
   ↓
EKS inject OIDC token ke pod (di /var/run/secrets/)
   ↓
AWS SDK baca token otomatis
   ↓
SDK kirim token ke AWS STS (AssumeRoleWithWebIdentity)
   ↓
STS validasi token via OIDC provider EKS
   ↓
STS return temporary credentials (berlaku 1 jam)
   ↓
Pod gunakan temporary credentials untuk akses S3/RDS/dll
```

## Verifikasi IRSA Berjalan

```bash
# Exec ke dalam pod
kubectl exec -it <pod-name> -n storage -- sh

# Di dalam pod, cek identity
aws sts get-caller-identity

# Output yang benar (harus muncul role storage-service, BUKAN node role):
# {
#   "UserId": "AROAXXX:botocore-session-xxx",
#   "Account": "123456789012",
#   "Arn": "arn:aws:sts::123456789012:assumed-role/smartfarming-storage-service-role/..."
# }
```

## Troubleshooting IRSA

**Problem**: Pod tidak bisa akses S3, error "Access Denied"

Cek urutan ini:
1. Apakah ServiceAccount punya annotation `eks.amazonaws.com/role-arn`?
2. Apakah role ARN di annotation cocok dengan role yang dibuat Terraform?
3. Apakah trust policy IAM role membolehkan namespace + SA yang benar?
4. Apakah OIDC provider sudah didaftarkan di IAM? (`aws iam list-open-id-connect-providers`)
5. Apakah IAM policy role membolehkan aksi yang dibutuhkan (s3:PutObject, dll)?

```bash
# Debug: lihat token yang diinjek ke pod
kubectl exec -it <pod-name> -n storage -- \
  cat /var/run/secrets/eks.amazonaws.com/serviceaccount/token
```
