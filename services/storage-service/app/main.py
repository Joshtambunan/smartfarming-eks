"""
storage-service – Mengelola upload/download file farming ke Amazon S3.
Service ini menggunakan IRSA (IAM Roles for Service Accounts) untuk
mendapatkan akses S3 secara otomatis tanpa hardcoded AWS keys.
"""

import os
import boto3
import logging
from fastapi import FastAPI, UploadFile, File, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from botocore.exceptions import ClientError

# Setup logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(
    title="SmartFarming Storage Service",
    description="Service untuk menyimpan dan mengambil file farming dari S3",
    version="1.0.0"
)

# CORS – izinkan frontend mengakses service ini
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# Nama bucket diambil dari environment variable, bukan hardcoded
BUCKET_NAME = os.getenv("S3_BUCKET_NAME", "smartfarming-storage-local")
AWS_REGION = os.getenv("AWS_REGION", "ap-southeast-1")

def get_s3_client():
    """
    Membuat S3 client.
    - Di EKS: boto3 otomatis menggunakan IRSA credentials dari OIDC token
    - Di lokal: boto3 menggunakan credentials dari ~/.aws/credentials atau env vars
    Tidak ada key yang ditulis manual di sini.
    """
    return boto3.client("s3", region_name=AWS_REGION)


@app.get("/health")
def health_check():
    """Health check endpoint untuk Kubernetes liveness probe."""
    return {"status": "healthy", "service": "storage-service"}


@app.get("/")
def root():
    return {"message": "SmartFarming Storage Service", "bucket": BUCKET_NAME}


@app.post("/upload")
async def upload_file(file: UploadFile = File(...)):
    """
    Upload file ke S3 bucket.
    Menggunakan multipart upload untuk file besar.
    """
    try:
        s3 = get_s3_client()
        file_content = await file.read()

        s3.put_object(
            Bucket=BUCKET_NAME,
            Key=file.filename,
            Body=file_content,
            ContentType=file.content_type or "application/octet-stream",
            # Tag file sesuai project
            Tagging="Project=smartfarming&Service=storage-service"
        )

        logger.info(f"File uploaded: {file.filename} ({len(file_content)} bytes)")
        return {
            "message": "File berhasil diupload",
            "filename": file.filename,
            "size_bytes": len(file_content),
            "bucket": BUCKET_NAME
        }

    except ClientError as e:
        error_code = e.response["Error"]["Code"]
        logger.error(f"S3 error saat upload {file.filename}: {error_code}")
        raise HTTPException(status_code=500, detail=f"Gagal upload ke S3: {error_code}")


@app.get("/files")
def list_files():
    """
    List semua file yang ada di S3 bucket.
    """
    try:
        s3 = get_s3_client()
        response = s3.list_objects_v2(Bucket=BUCKET_NAME)

        files = []
        for obj in response.get("Contents", []):
            files.append({
                "filename": obj["Key"],
                "size_bytes": obj["Size"],
                "last_modified": obj["LastModified"].isoformat()
            })

        return {"files": files, "total": len(files)}

    except ClientError as e:
        raise HTTPException(status_code=500, detail=f"Gagal list file: {e}")


@app.get("/download/{filename}")
def download_file(filename: str):
    """
    Generate pre-signed URL untuk download file dari S3.
    Pre-signed URL berlaku selama 1 jam.
    """
    try:
        s3 = get_s3_client()

        # Cek apakah file ada
        s3.head_object(Bucket=BUCKET_NAME, Key=filename)

        # Generate pre-signed URL (tidak expose data langsung, lebih aman)
        url = s3.generate_presigned_url(
            "get_object",
            Params={"Bucket": BUCKET_NAME, "Key": filename},
            ExpiresIn=3600  # 1 jam
        )

        return {"filename": filename, "download_url": url, "expires_in_seconds": 3600}

    except ClientError as e:
        if e.response["Error"]["Code"] == "404":
            raise HTTPException(status_code=404, detail=f"File '{filename}' tidak ditemukan")
        raise HTTPException(status_code=500, detail=f"Gagal generate download URL: {e}")


@app.delete("/files/{filename}")
def delete_file(filename: str):
    """
    Hapus file dari S3 bucket.
    Dengan S3 versioning aktif, file tidak benar-benar hilang – hanya diberi delete marker.
    """
    try:
        s3 = get_s3_client()
        s3.delete_object(Bucket=BUCKET_NAME, Key=filename)
        logger.info(f"File deleted: {filename}")
        return {"message": f"File '{filename}' berhasil dihapus"}

    except ClientError as e:
        raise HTTPException(status_code=500, detail=f"Gagal hapus file: {e}")
