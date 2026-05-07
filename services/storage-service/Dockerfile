# ============================================================
# Dockerfile – storage-service
# Menggunakan python:3.11-slim sebagai base image (lebih kecil).
# Container berjalan sebagai non-root user (keamanan).
# ============================================================

FROM python:3.11-slim

# Metadata image
LABEL project="smartfarming"
LABEL service="storage-service"
LABEL maintainer="IT-Del 2026"

# Set working directory
WORKDIR /app

# Install dependencies lebih dulu (layer caching – lebih efisien)
COPY app/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy source code
COPY app/ .

# Buat user non-root untuk keamanan (jangan pakai root di container)
RUN addgroup --system appgroup && \
    adduser --system --ingroup appgroup appuser
USER appuser

# Expose port service
EXPOSE 8001

# Jalankan aplikasi
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8001"]
