FROM nginx:1.27-alpine
COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY site/ /usr/share/nginx/html/
# Nén sẵn một lần lúc build: index.wasm ~39MB còn ~9MB. gzip_static gửi bản .gz
# cho trình duyệt nào nhận gzip, khỏi nén lại mỗi request.
RUN cd /usr/share/nginx/html && gzip -k -9 index.wasm index.pck index.js index.html \
    && chmod -R a+rX /usr/share/nginx/html
HEALTHCHECK --interval=30s --timeout=3s CMD wget -qO- http://127.0.0.1/ >/dev/null 2>&1 || exit 1
