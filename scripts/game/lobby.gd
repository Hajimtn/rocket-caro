class_name Lobby
extends Node
## Room directory, always at /root/Main/Lobby on every peer.
## Server: owns one Game node ("Room_<id>") per room and keeps them alive while someone is
## inside. Client: asks for the room list, creates or joins rooms, and hands the chosen room id
## to its Game, which renames itself to "Room_<id>" so the RPC paths match the server's.

signal rooms_updated(list: Array)
signal notice(message: String)

const MAX_ROOMS := 64

var is_server := false
var game: Game   ## client side

var _rooms: Dictionary = {}       ## id -> Game (server)
var _peer_room: Dictionary = {}   ## peer id -> room id (server)
var _next_id := 1


# --- server -----------------------------------------------------------------------------------

func start_server(port: int) -> bool:
	var err := Net.serve(port)
	if err != OK:
		print("[RC] cannot listen on port %d (error %d). Is another server already running?" % [port, err])
		return false
	is_server = true
	multiplayer.peer_connected.connect(func(id: int) -> void: _send_list(id))
	multiplayer.peer_disconnected.connect(_on_peer_out)
	print("[RC] referee server listening on ws://0.0.0.0:%d" % port)
	return true


func _on_peer_out(id: int) -> void:
	var room: Game = _rooms.get(_peer_room.get(id, 0))
	_peer_room.erase(id)
	if room != null:
		room.on_peer_gone(id)
	_push_all()


func _make_room(room_name: String, difficulty: int) -> Game:
	var room := Game.new()
	room.server_only = true
	room.mode = Game.Mode.ONLINE
	room.room_id = _next_id
	room.room_name = room_name
	room.difficulty = clampi(difficulty, 0, Rules.DIFF_INSANE)
	room.name = "Room_%d" % _next_id
	_next_id += 1
	room.room_changed.connect(_push_all)
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
	print("[RC] room %d created: %s [%s]" % [room.room_id, room_name, Rules.DIFF_NAMES[room.difficulty]])
	return room


func _enter(peer: int, room: Game) -> void:
	room.reserve(peer)
	_peer_room[peer] = room.room_id
	lobby_joined.rpc_id(peer, room.room_id)
	_push_all()


func _list() -> Array:
	var out: Array = []
	for id: int in _rooms:
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
	if room == null:
		lobby_error.rpc_id(id, "Phòng không còn tồn tại.")
		_send_list(id)
	elif room.is_full():
		lobby_error.rpc_id(id, "Phòng đã đủ 2 người.")
		_send_list(id)
	else:
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
		if not _rooms[room_id].is_full():
			_enter(id, _rooms[room_id])
			return
	srv_create("", player_name, difficulty)


# --- client -----------------------------------------------------------------------------------

func request_list() -> void:
	srv_list.rpc_id(1)


func request_create(room_name: String) -> void:
	srv_create.rpc_id(1, room_name, Net.player_name, Prefs.difficulty)


func request_join(room_id: int) -> void:
	srv_join.rpc_id(1, room_id)


func request_quick() -> void:
	srv_quick.rpc_id(1, Net.player_name, Prefs.difficulty)


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
