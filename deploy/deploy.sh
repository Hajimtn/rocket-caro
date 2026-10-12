#!/usr/bin/env bash
#
# Deploy super-caro.kembabies.io.vn lên VPS <VPS_IP> (cùng pattern với
# kembabies và caro-tournament: host Nginx giữ 80/443 + certbot, app chạy Docker
# bind 127.0.0.1, ảnh dựng ngay trên VPS).
#
# Bản web được export Ở MÁY NÀY (cần Godot + export template web), rồi đẩy lên.
# Trên VPS chỉ còn: nginx phục vụ file tĩnh, và Godot headless chạy trọng tài từ
# chính file .pck đó.
#
# Dùng:  ./deploy/deploy.sh            test luật, export, đẩy lên, khởi động lại
#        ./deploy/deploy.sh logs       xem log (trọng tài + nginx)
#        ./deploy/deploy.sh ps         trạng thái container
#        ./deploy/deploy.sh restart
set -euo pipefail

VPS="${VPS_USER:-deploy}@${VPS_HOST:-<VPS_IP>}"
REMOTE=${REMOTE_BASE:-/home/deploy/kembabies}/super-caro
SITE=super-caro.kembabies.io.vn
PORT=8792

LOCAL="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAGE="$LOCAL/build/deploy"
GODOT=${GODOT:-$(command -v godot || echo /Applications/Godot.app/Contents/MacOS/Godot)}

die() { echo "!! $*" >&2; exit 1; }
dc() { ssh ${2:+-t} "$VPS" "cd '$REMOTE' && docker compose $1"; }

cmd_deploy() {
  [ -x "$GODOT" ] || die "Không thấy Godot ($GODOT). Đặt biến GODOT=/đường/dẫn/Godot."

  # Chặn lỗi ở máy mình còn hơn để server mới chết giữa chừng.
  echo "==> Test luật"
  "$GODOT" --headless --path "$LOCAL" --script tools/test_rules.gd 2>&1 | tail -1 | grep -q "RESULT: OK" \
    || die "tools/test_rules.gd không qua. Chạy tay để xem lỗi."

  echo "==> Export bản web"
  rm -rf "$STAGE"
  mkdir -p "$STAGE/site"
  "$GODOT" --headless --path "$LOCAL" --export-release Web "$STAGE/site/index.html" >/dev/null 2>&1 || true
  for f in index.html index.js index.wasm index.pck; do
    [ -s "$STAGE/site/$f" ] || die "Export thiếu $f (đã cài export template Web cho Godot chưa?)"
  done
  cp "$LOCAL"/deploy/{docker-compose.yml,web.Dockerfile,game.Dockerfile,nginx.conf} "$STAGE/"

  echo "==> rsync lên $VPS:$REMOTE"
  ssh "$VPS" "mkdir -p '$REMOTE'"
  # --stats chứ không phải --info=stats1: macOS ship openrsync (tương thích
  # rsync 2.6.9), không hiểu cờ --info của rsync 3.x.
  rsync -az --delete --stats "$STAGE/" "$VPS:$REMOTE/" | grep -E "^(Number of files|Total transferred)" || true

  echo "==> Build + up"
  dc "up -d --build --remove-orphans"
  dc "ps"

  echo "==> Kiểm tra từ trong VPS"
  # Trang tĩnh trả 200, và yêu cầu WebSocket được trọng tài nhận (101).
  ssh "$VPS" "sleep 2; \
    printf '   trang web: '; curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:$PORT/; \
    printf '   websocket: '; curl -s -o /dev/null -w '%{http_code}\n' --max-time 3 --http1.1 \
      -H 'Connection: Upgrade' -H 'Upgrade: websocket' -H 'Sec-WebSocket-Version: 13' \
      -H 'Sec-WebSocket-Key: cm9ja2V0LWNhcm8tdGVzdA==' http://127.0.0.1:$PORT/ || true"

  ssh "$VPS" "docker image prune -f >/dev/null"
  cat <<MSG

Xong.  https://$SITE
Lần đầu cần vhost + HTTPS trên host Nginx (cần sudo), xem deploy/super-caro.kembabies.io.vn.conf.

  ./deploy/deploy.sh ps       trạng thái container
  ./deploy/deploy.sh logs     xem log
MSG
}

case "${1:-deploy}" in
  deploy)  cmd_deploy ;;
  logs)    dc "logs -f --tail=100" t ;;
  ps)      dc "ps" ;;
  restart) dc "restart" ;;
  *) die "Không hiểu lệnh '$1'. Dùng: deploy | logs | ps | restart" ;;
esac
