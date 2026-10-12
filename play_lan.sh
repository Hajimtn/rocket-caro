#!/bin/bash
# Starts everything needed to play Rocket Caro in the browser over the LAN:
#   - a web server for the exported game (HTTPS for other machines, HTTP for this one)
#   - the headless referee server that runs the matches (WebSocket, tunnelled through the same ports)
# Both players open the printed URL; the first to arrive is X, the second is O.
cd "$(dirname "$0")" || exit 1
GODOT="${GODOT:-/Users/manhtien/Downloads/Godot.app/Contents/MacOS/Godot}"
HTTP_PORT="${HTTP_PORT:-8060}"
HTTPS_PORT="${HTTPS_PORT:-8443}"

if [ "$1" = "--rebuild" ] || [ ! -f build/web/index.html ]; then
	echo "Exporting web build…"
	mkdir -p build/web
	"$GODOT" --headless --path . --export-release Web build/web/index.html >/dev/null 2>&1 || { echo "Export failed"; exit 1; }
fi

IP="$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || echo 127.0.0.1)"

# Self-signed certificate valid for this machine's current LAN IP (browsers need HTTPS to run Godot web builds).
CERT_DIR="build/cert"
CERT="$CERT_DIR/cert-$IP.pem"
KEY="$CERT_DIR/key-$IP.pem"
if [ ! -f "$CERT" ]; then
	mkdir -p "$CERT_DIR"
	cat > "$CERT_DIR/openssl.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = v3
prompt = no
[dn]
CN = Rocket Caro
[v3]
subjectAltName = IP:$IP,IP:127.0.0.1,DNS:localhost
CNF
	openssl req -x509 -newkey rsa:2048 -nodes -days 825 -keyout "$KEY" -out "$CERT" -config "$CERT_DIR/openssl.cnf" >/dev/null 2>&1 \
		|| { echo "Could not create certificate"; exit 1; }
fi

python3 tools/lan_server.py build/web "$HTTP_PORT" "$HTTPS_PORT" "$CERT" "$KEY" &
WEB_PID=$!
trap 'kill $WEB_PID 2>/dev/null' EXIT INT TERM

echo
echo "  Máy khác trong mạng:  https://$IP:$HTTPS_PORT"
echo "     (trình duyệt sẽ cảnh báo chứng chỉ tự ký: bấm Nâng cao → Tiếp tục truy cập; chỉ cần 1 lần)"
echo "  Chính máy này:        http://localhost:$HTTP_PORT"
echo "  Rồi bấm: Chơi mạng LAN → Vào phòng.   Ctrl+C để dừng."
echo
"$GODOT" --headless --path . -- --server
