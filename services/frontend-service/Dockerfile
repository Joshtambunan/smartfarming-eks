# Frontend menggunakan nginx ringan untuk serve file statis
FROM nginx:alpine

LABEL project="smartfarming"
LABEL service="frontend-service"

# Copy file HTML ke direktori nginx
COPY app/ /usr/share/nginx/html/

# Config nginx sederhana
RUN echo 'server { \
  listen 3000; \
  location / { \
    root /usr/share/nginx/html; \
    index index.html; \
    try_files $uri $uri/ /index.html; \
  } \
}' > /etc/nginx/conf.d/default.conf

# Buat user non-root (nginx bisa jalan tanpa root untuk port > 1024)
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
RUN chown -R appuser:appgroup /usr/share/nginx/html /var/cache/nginx /var/run
USER appuser

EXPOSE 3000

CMD ["nginx", "-g", "daemon off;"]
