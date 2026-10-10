FROM python:3.12-slim
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
WORKDIR /app
COPY requirements.lock.txt .
RUN pip install --no-cache-dir --index-url https://pypi.tuna.tsinghua.edu.cn/simple -r requirements.lock.txt \
    && groupadd --gid 10001 keybox \
    && useradd --uid 10001 --gid 10001 --no-create-home keybox \
    && mkdir -p /data/backups && chown -R keybox:keybox /data
COPY keybox_backend ./keybox_backend
COPY migrations ./migrations
USER 10001:10001
EXPOSE 8000
CMD ["python", "-m", "uvicorn", "keybox_backend.app:app", "--host", "0.0.0.0", "--port", "8000", "--workers", "1", "--no-access-log", "--proxy-headers", "--forwarded-allow-ips", "*"]
