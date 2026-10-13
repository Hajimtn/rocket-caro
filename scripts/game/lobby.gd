class_name Lobby
extends Node
## Room directory and matchmaking, always at /root/Main/Lobby on every peer.
## Server: owns one Game node ("Room_<id>") per room and keeps them alive while someone is
## inside; pairs up players looking for a match; knows who is logged in. Client: asks for the
## room list, creates or joins rooms, looks for matches, and hands the chosen room id to its
## Game, which renames itself to "Room_<id>" so the RPC paths match the server's.
##
## Accounts: a client sends the token it got from the accounts service; the server checks the
## signature with RC_AUTH_SECRET, so a player's name and identity cannot be faked. Matches found
## by matchmaking between two accounts are rated: the result goes to the accounts service
## (RC_AUTH_URL), which updates both Elo ratings. Without RC_AUTH_SECRET (a LAN server)
## everybody is a guest and nothing is rated.

signal rooms_updated(list: Array)
signal notice(message: String)
signal authed(ok: bool, reason: String)          ## client: the server's verdict on our token
signal search_changed(on: bool, waiting: int)    ## client: looking for a match (and how many others are)
signal rating_changed(before: int, after: int)   ## client: our rating after a rated match

const MAX_ROOMS := 64
const PAIR_EVERY := 1.0       ## s between matchmaking passes
const RATING_WINDOW := 100.0  ## Elo gap accepted at once...
const WINDOW_GROWTH := 25.0   ## ...widening by this much per second of waiting

var is_server := false
var game: Game   ## client side

var _rooms: Dictionary = {}       ## id -> Game (server)
var _peer_room: Dictionary = {}   ## peer id -> room id (server)
var _next_id := 1
var _accounts: Dictionary = {}    ## server: peer id -> {uid, name, rating}
var _queue: Array[Dictionary] = []   ## server: {peer, uid, rating, diff, since}
var _pair_in := 0.0
var _secret := ""
var _auth_url := ""


# --- server -----------------------------------------------------------------------------------

func start_server(port: int) -> bool:
	var err := Net.serve(port)
	if err != OK:
		print("[RC] cannot listen on port %d (error %d). Is another server already running?" % [port, err])
		return false
	is_server = true
	_secret = OS.get_environment("RC_AUTH_SECRET")
	_auth_url = OS.get_environment("RC_AUTH_URL")
	multiplayer.peer_connected.connect(func(id: int) -> void: _send_list(id))
	multiplayer.peer_disconnected.connect(_on_peer_out)
	print("[RC] referee server listening on ws://0.0.0.0:%d (accounts %s)" % [port, "on" if _secret != "" else "off"])
	return true


func _process(delta: float) -> void:
	if not is_server or _queue.is_empty():
		return
	_pair_in -= delta
	if _pair_in <= 0.0:
		_pair_in = PAIR_EVERY
		_pair()


func _on_peer_out(id: int) -> void:
	_unqueue(id)
	_accounts.erase(id)
	var room: Game = _rooms.get(_peer_room.get(id, 0))
	_peer_room.erase(id)
	if room != null:
		room.on_peer_gone(id)
	_push_all()


## Who is behind a peer: {uid, name, rating}, or {} for a guest.
func account(peer: int) -> Dictionary:
	return _accounts.get(peer, {})


func _make_room(room_name: String, difficulty: int, ranked: bool = false) -> Game:
	var room := Game.new()
	room.server_only = true
	room.mode = Game.Mode.ONLINE
	room.room_id = _next_id
	room.room_name = room_name
	room.ranked = ranked
	room.lobby = self
	room.difficulty = clampi(difficulty, 0, Rules.DIFF_INSANE)
	room.name = "Room_%d" % _next_id
	_next_id += 1
	room.room_changed.connect(_push_all)
	room.match_result.connect(func(winner: int) -> void: _report(room, winner))
	room.player_left.connect(func(peer: int) -> void:
		_peer_room.erase(peer)
		if multiplayer.get_peers().has(peer):
			_send_list(peer))
	room.room_empty.connect(func() -> void:
		print("[RC] room %d closed" % room.room_id)
		_rooms.erase(room.room_id)
		room.queue_free()
		_push_all())
	_rooms[room.room_id] = room
	get_parent().add_child(room)
	print("[RC] room %d created: %s [%s]%s" % [room.room_id, room_name, Rules.DIFF_NAMES[room.difficulty], " ranked" if ranked else ""])
	return room


func _enter(peer: int, room: Game) -> void:
	room.reserve(peer)
	_peer_room[peer] = room.room_id
	lobby_joined.rpc_id(peer, room.room_id)
	_push_all()


## Matchmade rooms are private: they never show up in the list.
func _list() -> Array:
	var out: Array = []
	for id: int in _rooms:
		if not _rooms[id].ranked:
			out.append(_rooms[id].room_info())
	return out


func _send_list(peer: int) -> void:
	lobby_rooms.rpc_id(peer, _list())


## Everyone who is not inside a room sees the directory update live.
func _push_all() -> void:
	var list := _list()
	for peer in multiplayer.get_peers():
		if not _peer_room.has(peer):
			lobby_rooms.rpc_id(peer, list)


@rpc("any_peer", "call_remote", "reliable")
func srv_list() -> void:
	if is_server:
		_send_list(multiplayer.get_remote_sender_id())


@rpc("any_peer", "call_remote", "reliable")
func srv_create(room_name: String, player_name: String, difficulty: int) -> void:
	if not is_server:
		return
	var id := multiplayer.get_remote_sender_id()
	if _peer_room.has(id):
		return
	_unqueue(id)
	if _rooms.size() >= MAX_ROOMS:
		lobby_error.rpc_id(id, "Máy chủ đã đủ số phòng tối đa.")
		return
	var clean := room_name.strip_edges().substr(0, 24)   # may stay empty: clients label it "Room #id"
	_enter(id, _make_room(clean, difficulty))


@rpc("any_peer", "call_remote", "reliable")
func srv_join(room_id: int) -> void:
	if not is_server:
		return
	var id := multiplayer.get_remote_sender_id()
	if _peer_room.has(id):
		return
	var room: Game = _rooms.get(room_id)
	if room == null or room.ranked:
		lobby_error.rpc_id(id, "Phòng không còn tồn tại.")
		_send_list(id)
	elif room.is_full():
		lobby_error.rpc_id(id, "Phòng đã đủ 2 người.")
		_send_list(id)
	else:
		_unqueue(id)
		_enter(id, room)


## Join the room that has been waiting longest for an opponent, or open a new one.
@rpc("any_peer", "call_remote", "reliable")
func srv_quick(player_name: String, difficulty: int) -> void:
	if not is_server:
		return
	var id := multiplayer.get_remote_sender_id()
	if _peer_room.has(id):
		return
	for room_id: int in _rooms:
		if not _rooms[room_id].ranked and not _rooms[room_id].is_full():
			_enter(id, _rooms[room_id])
			return
	srv_create("", player_name, difficulty)


# --- server: accounts and matchmaking ---------------------------------------------------------

@rpc("any_peer", "call_remote", "reliable")
func srv_auth(token: String) -> void:
	if not is_server:
		return
	var id := multiplayer.get_remote_sender_id()
	if _secret == "":
		lobby_authed.rpc_id(id, false, "disabled")
		return
	var acc := _verify(token)
	if acc.is_empty():
		lobby_authed.rpc_id(id, false, "invalid")
		return
	_accounts[id] = acc
	lobby_authed.rpc_id(id, true, "")
	_fetch_rating(id, int(acc["uid"]))


## {uid, name, rating} from a token signed by the accounts service, or {} if it is not genuine
## or has expired. (Same format as backend/accounts.py.)
func _verify(token: String) -> Dictionary:
	var parts := token.split(".")
	if parts.size() != 2 or token.length() > 1024:
		return {}
	var crypto := Crypto.new()
	var want := crypto.hmac_digest(HashingContext.HASH_SHA256, _secret.to_utf8_buffer(), parts[0].to_utf8_buffer()).hex_encode()
	if want.length() != parts[1].length() or not crypto.constant_time_compare(want.to_utf8_buffer(), parts[1].to_utf8_buffer()):
		return {}
	var data = JSON.parse_string(Marshalls.base64_to_utf8(parts[0]))
	if not data is Dictionary or float(data.get("exp", 0)) < Time.get_unix_time_from_system():
		return {}
	return {"uid": int(data.get("uid", 0)), "name": str(data.get("name", "")).substr(0, 16), "rating": 1000}


## The rating is not in the token (it changes); ask the accounts service for it.
func _fetch_rating(peer: int, uid: int) -> void:
	_internal(HTTPClient.METHOD_GET, "/internal/user/%d" % uid, null, func(code: int, data: Dictionary) -> void:
		if code == 200 and _accounts.has(peer) and int(_accounts[peer]["uid"]) == uid:
			_accounts[peer]["rating"] = int(data["user"]["rating"])
			for q in _queue:
				if q["peer"] == peer:
					q["rating"] = _accounts[peer]["rating"])


@rpc("any_peer", "call_remote", "reliable")
func srv_find(difficulty: int) -> void:
	if not is_server:
		return
	var id := multiplayer.get_remote_sender_id()
	if _peer_room.has(id):
		return
	_unqueue(id)
	var acc := account(id)
	_queue.append({"peer": id, "uid": int(acc.get("uid", 0)), "rating": float(acc.get("rating", 1000)),
		"diff": clampi(difficulty, 0, Rules.DIFF_INSANE), "since": Time.get_ticks_msec() / 1000.0})
	_pair_in = 0.0   # try at once
	_tell_queue()


@rpc("any_peer", "call_remote", "reliable")
func srv_cancel_find() -> void:
	if is_server:
		var id := multiplayer.get_remote_sender_id()
		_unqueue(id)
		lobby_search.rpc_id(id, false, 0)
		_tell_queue()


func _unqueue(peer: int) -> void:
	for i in range(_queue.size() - 1, -1, -1):
		if _queue[i]["peer"] == peer:
			_queue.remove_at(i)


## Pairs players looking for the same difficulty, closest ratings first. Whoever has waited
## longest is served first, and the longer they wait the bigger the rating gap they accept.
## Two tabs of the same account are never paired with each other.
func _pair() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var paired := true
	while paired:
		paired = false
		for i in _queue.size():
			var a: Dictionary = _queue[i]
			var window := RATING_WINDOW + WINDOW_GROWTH * (now - float(a["since"]))
			var best := -1
			var best_gap := INF
			for j in _queue.size():
				var b: Dictionary = _queue[j]
				if j == i or b["diff"] != a["diff"] or (a["uid"] != 0 and a["uid"] == b["uid"]):
					continue
				var gap := absf(float(a["rating"]) - float(b["rating"]))
				if gap <= window and gap < best_gap:
					best = j
					best_gap = gap
			if best >= 0:
				var b: Dictionary = _queue[best]
				_unqueue(a["peer"])
				_unqueue(b["peer"])
				_start_match(a, b)
				paired = true
				break
	_tell_queue()


func _start_match(a: Dictionary, b: Dictionary) -> void:
	if _rooms.size() >= MAX_ROOMS:
		for p in [a, b]:
			lobby_search.rpc_id(p["peer"], false, 0)
			lobby_error.rpc_id(p["peer"], "Máy chủ đã đủ số phòng tối đa.")
		return
	var room := _make_room("", a["diff"], true)
	for p in [a, b]:
		lobby_search.rpc_id(p["peer"], false, 0)
		_enter(p["peer"], room)


## Everyone still looking learns how many others are looking at their difficulty.
func _tell_queue() -> void:
	for q in _queue:
		var others := 0
		for o in _queue:
			if o["peer"] != q["peer"] and o["diff"] == q["diff"]:
				others += 1
		lobby_search.rpc_id(q["peer"], true, others)


## A matchmade game between two accounts ended (winner 1 = X, 2 = O, 3 = draw): rate it.
func _report(room: Game, winner: int) -> void:
	var uids := room.seat_uids()
	if not room.ranked or uids[1] == 0 or uids[2] == 0 or uids[1] == uids[2] or _auth_url == "":
		return
	var body := {"x_uid": uids[1], "o_uid": uids[2], "winner": 0 if winner == 3 else winner, "difficulty": room.difficulty}
	# The room may well be gone by the time the answer comes back (both players left).
	var room_id := room.room_id
	var peers := {1: room.seat_peer(1), 2: room.seat_peer(2)}
	_internal(HTTPClient.METHOD_POST, "/internal/match", body, func(code: int, data: Dictionary) -> void:
		if code != 200:
			print("[RC] could not rate room %d (HTTP %d)" % [room_id, code])
			return
		print("[RC] rated room %d: %s" % [room_id, data])
		for t in [1, 2]:
			var change: Dictionary = data["x" if t == 1 else "o"]
			for peer: int in _accounts:
				if int(_accounts[peer]["uid"]) == uids[t]:
					_accounts[peer]["rating"] = int(change["after"])
			if peers[t] != 0 and multiplayer.get_peers().has(peers[t]):
				lobby_rating.rpc_id(peers[t], int(change["before"]), int(change["after"])))


## A call to the accounts service on the private network (never seen by players).
func _internal(method: int, path: String, body: Variant, done: Callable) -> void:
	if _auth_url == "" or _secret == "":
		return
	var http := HTTPRequest.new()
	http.timeout = 10.0
	add_child(http)
	http.request_completed.connect(func(_r: int, code: int, _h: PackedStringArray, raw: PackedByteArray) -> void:
		http.queue_free()
		var data = JSON.parse_string(raw.get_string_from_utf8()) if raw.size() > 0 else null
		done.call(code, data if data is Dictionary else {}))
	var headers := PackedStringArray(["Content-Type: application/json", "X-Internal-Key: " + _secret])
	if http.request(_auth_url + path, headers, method, JSON.stringify(body) if body != null else "") != OK:
		http.queue_free()


# --- client -----------------------------------------------------------------------------------

func request_list() -> void:
	srv_list.rpc_id(1)


func request_create(room_name: String) -> void:
	srv_create.rpc_id(1, room_name, Net.player_name, Prefs.difficulty)


func request_join(room_id: int) -> void:
	srv_join.rpc_id(1, room_id)


func request_quick() -> void:
	srv_quick.rpc_id(1, Net.player_name, Prefs.difficulty)


func request_auth(token: String) -> void:
	srv_auth.rpc_id(1, token)


func request_find() -> void:
	srv_find.rpc_id(1, Prefs.difficulty)


func request_cancel_find() -> void:
	srv_cancel_find.rpc_id(1)


@rpc("authority", "call_remote", "reliable")
func lobby_rooms(list: Array) -> void:
	rooms_updated.emit(list)


@rpc("authority", "call_remote", "reliable")
func lobby_joined(room_id: int) -> void:
	if game != null:
		game.enter_room(room_id)


@rpc("authority", "call_remote", "reliable")
func lobby_error(message: String) -> void:
	notice.emit(Loc.t(message))


@rpc("authority", "call_remote", "reliable")
func lobby_authed(ok: bool, reason: String) -> void:
	authed.emit(ok, reason)


@rpc("authority", "call_remote", "reliable")
func lobby_search(on: bool, waiting: int) -> void:
	search_changed.emit(on, waiting)


@rpc("authority", "call_remote", "reliable")
func lobby_rating(before: int, after: int) -> void:
	rating_changed.emit(before, after)
