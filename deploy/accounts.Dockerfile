FROM python:3.12-alpine
# Chỉ dùng thư viện chuẩn (sqlite3, hashlib.scrypt), không cần pip install.
RUN adduser -D -u 10002 accounts && mkdir -p /data && chown accounts /data
COPY accounts.py /app/accounts.py
USER accounts
ENV RC_DB=/data/accounts.db PORT=8000 PYTHONUNBUFFERED=1
EXPOSE 8000
HEALTHCHECK --interval=30s --timeout=3s CMD wget -qO- http://127.0.0.1:8000/health >/dev/null 2>&1 || exit 1
CMD ["python", "-I", "/app/accounts.py"]
