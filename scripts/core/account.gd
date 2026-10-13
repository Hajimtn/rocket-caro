extends Node
## The player's (optional) account: sign up / log in with the accounts service (backend/
## accounts.py) to get a rating and a name nobody else can take. The service hands out a signed
## token, kept in Prefs, which the game server checks by itself. Registered as the "Account"
## autoload; playing without one (as a guest) keeps working everywhere.

signal changed                 ## logged in, logged out, or the stats were refreshed
signal failed(message: String) ## a register/login attempt did not work (message is ready to show)

## What the service's error codes mean to the player.
const ERRORS := {
	"bad_name": "Tên đăng nhập 3–16 ký tự, chỉ gồm chữ không dấu, số, dấu _ hoặc dấu chấm.",
	"bad_password": "Mật khẩu cần từ 6 đến 72 ký tự.",
	"taken": "Tên này đã có người dùng.",
	"bad_login": "Sai tên đăng nhập hoặc mật khẩu.",
	"too_many": "Thử quá nhiều lần. Đợi vài phút rồi thử lại.",
}

var token := ""
var user: Dictionary = {}   ## {id, name, rating, wins, losses, draws}; empty when logged out
var busy := false
var api_override := ""      ## test only (--api=URL)


func _ready() -> void:
	token = Prefs.token
	if token != "":
		user = _from_token(token)   # show the name at once; the stats arrive with refresh()
		refresh()


func logged_in() -> bool:
	return token != "" and not user.is_empty()


## The service lives next to the game server: same origin as the page on the web (no CORS),
## the public server everywhere else (itch.io, desktop builds).
func api_base() -> String:
	if api_override != "":
		return api_override
	if OS.has_feature("web") and not Net.on_itch():
		var origin = JavaScriptBridge.eval("window.location.origin")
		if origin != null and str(origin).begins_with("http"):
			return str(origin)
	return Net.PUBLIC_SERVER.replace("wss://", "https://").replace("ws://", "http://")


func register(name: String, password: String) -> void:
	_send(HTTPClient.METHOD_POST, "/api/register", {"name": name.strip_edges(), "password": password}, _on_logged_in)


func login(name: String, password: String) -> void:
	_send(HTTPClient.METHOD_POST, "/api/login", {"name": name.strip_edges(), "password": password}, _on_logged_in)


func logout() -> void:
	token = ""
	user = {}
	Prefs.token = ""
	Prefs.save()
	changed.emit()


## Re-reads the rating and record (after a match, or at start-up).
func refresh() -> void:
	if token == "":
		return
	_send(HTTPClient.METHOD_GET, "/api/me", null, func(code: int, data: Dictionary) -> void:
		if code == 200:
			user = data.get("user", {})
			changed.emit()
		elif code == 401:
			logout()   # expired or no longer valid: back to playing as a guest
		# anything else (offline, server down): keep what we have
	)


func _on_logged_in(code: int, data: Dictionary) -> void:
	if code == 200 and data.has("token"):
		token = data["token"]
		user = data.get("user", {})
		Prefs.token = token
		Prefs.save()
		changed.emit()
		return
	var why: String = data.get("error", "")
	failed.emit(Loc.t(ERRORS[why]) if ERRORS.has(why) else Loc.t("Không kết nối được tới máy chủ tài khoản."))


## The name inside a token, readable without asking the server (it is only signed, not secret).
func _from_token(t: String) -> Dictionary:
	var data = JSON.parse_string(Marshalls.base64_to_utf8(t.get_slice(".", 0)))
	if data is Dictionary and data.has("name"):
		return {"id": int(data.get("uid", 0)), "name": str(data["name"]), "rating": 0, "wins": 0, "losses": 0, "draws": 0}
	return {}


func _send(method: int, path: String, body: Variant, done: Callable) -> void:
	busy = true
	var http := HTTPRequest.new()
	http.timeout = 12.0
	add_child(http)
	http.request_completed.connect(func(_result: int, code: int, _headers: PackedStringArray, raw: PackedByteArray) -> void:
		http.queue_free()
		busy = false
		var data = JSON.parse_string(raw.get_string_from_utf8()) if raw.size() > 0 else null
		done.call(code, data if data is Dictionary else {}))
	var headers := PackedStringArray(["Content-Type: application/json"])
	if token != "":
		headers.append("Authorization: Bearer " + token)
	var err := http.request(api_base() + path, headers, method, JSON.stringify(body) if body != null else "")
	if err != OK:
		http.queue_free()
		busy = false
		done.call(0, {})
