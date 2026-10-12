class_name Game
extends Node3D
## Match controller. The "host" is the authority: it rolls the wind, simulates every shot and
## judges the result. Offline that is the local player. Online it is a headless referee server
## (--server) that runs one Game per room ("Room_<id>", server_only) and seats the first two
## players as X and O; a client's own Game renames itself to the same "Room_<id>" while inside a
## room, so RPC paths match. Everyone else only replays what the host broadcasts, so nobody can
## cheat the physics and nobody can disagree about the outcome.

signal room_changed            ## server: who is in the room / whether a match runs changed
signal room_empty              ## server: the last player left
signal player_left(peer: int)  ## server: a player left this room (peer id)

enum Mode { BOT, LOCAL, ONLINE }
enum Phase { IDLE, AIMING, FLYING, RESULT, OVER }

const RESULT_PAUSE := 1.6
const BOT_THINK := 2.0
const MAX_SHOT_LAG := 0.5   ## s: how far back a client may date its shot (it sees the turn late)
const GLYPH := {1: "X", 2: "O"}
## Launch sound per ammo type: normal, erase, steer, freeze (files in assets/audio/).
const LAUNCH_SFX := ["launch", "launch_erase", "launch_steer", "launch_freeze"]
const NOTICE_START := "Chọn vị trí. Căn gió. Bắn."
const AMMO_NOTICES := [NOTICE_START,
	"Đạn tẩy: bắn trúng dấu của đối thủ để xóa nó.",
	"Đạn đuổi: sau khi bắn, di chuột để kéo rocket tới ô muốn trúng.",
	"Đạn băng: trúng bàn cờ là bàn đứng yên ngay tại tư thế đó trong %d lượt."]

var mode := Mode.BOT
var phase := Phase.IDLE
var is_host := true
var server_only := false   ## headless referee room: runs the match but has no player
var room_id := 0
var room_name := ""
var lobby: Lobby           ## client side
var my_team := 1
var team := 1
var difficulty := Rules.DIFF_HARD
var env := Rules.calm_env()   ## this turn's conditions: wind, gravity, tilt or tumble, time
var board_time := 0.0         ## the board's clock: a tumbling board's pose is a function of it
var time_left := Rules.TURN_TIME
var winner := 0
var board := PackedByteArray()
var mark_count := 0
var names := {1: Loc.t("Đội X"), 2: Loc.t("Đội O")}
var notice := Loc.t(NOTICE_START)
var last_cell := Vector2i(-1, -1)
var win_cells: Array[Vector2i] = []

var world: World
var rig: FpsRig
var ui: Ui
var sfx: Sfx
var obstacles: Array[Dictionary] = []
var _shot_tau0 := 0.0          ## client: board-clock time the current shot left the barrel
var _shot_slave := false       ## client: board clock is slaved to the rocket's flight
var _bot_plan: Dictionary = {}
var _auto_plan: Dictionary = {}
var _auto_next := 0.0

var _rocket: Rocket
var _rng := RandomNumberGenerator.new()
var _turn_age := 0.0
var _result_in := 0.0
var _pending: Dictionary = {}
var _flight_left := 0.0
var _autoplay := false
var _last_tick := -1
var _auto_fired := false
var _no_pause := false
var _next_capture_try := 0   ## web: earliest tick (ms) for the next pointer-lock attempt
var _no_mouse := false   ## test only: never capture the mouse (a real mouse would steer the camera)
var _force_tilt := Vector2(INF, INF)   ## test only (--tilt=lean,twist)
var selected_ammo := Rules.AMMO_NORMAL
var _used := _fresh_used()   ## team -> [ammo] = special spent this match
var _pending_ammo := Rules.AMMO_NORMAL
var _last_ammo := Rules.AMMO_NORMAL
var _last_blast := ""
var _frozen_left := 0          ## authority: turns of freeze still to come
var skins := {1: Skins.defaults(), 2: Skins.defaults()}   ## team -> loadout (marks, blasts, trails)
var _live: Dictionary = {}              ## authority: guided flight in progress
var _steer_target := Vector3.ZERO       ## authority: world point the guided rocket chases
var _steer_live := false                ## every peer: a guided rocket is in the air
var _live_acc := 0.0
var _live_send := 0.0
var _steer_send := 0.0
var _auto_target := Vector3(INF, INF, INF)
var _slots := {1: 0, 2: 0}        ## server: team -> peer id
var _slot_names := {1: "", 2: ""}
var _slot_skins := {1: Skins.defaults(), 2: Skins.defaults()}
var _reserved := {}               ## server: peers told to join but not yet seated
var _room_label := ""           ## client: name of the room we are in


func _ready() -> void:
	_rng.randomize()
	obstacles = Rules.make_obstacles()
	board.resize(Rules.N * Rules.N)
	if server_only:
		my_team = 0   # a referee room controls no team, and needs no scene, camera or sound
		return
	world = World.new()
	world.name = "World"
	add_child(world)
	rig = FpsRig.new()
	rig.name = "Rig"
	add_child(rig)
	rig.fire_requested.connect(_on_fire_requested)
	rig.ammo_selected.connect(_on_ammo_selected)
	sfx = Sfx.new()
	sfx.name = "Sfx"
	add_child(sfx)
	Net.joined_host.connect(_on_joined_host)
	Net.join_failed.connect(_on_join_failed)
	Net.host_lost.connect(_on_host_lost)


func bind_ui(u: Ui) -> void:
	ui = u
	ui.bot_requested.connect(func() -> void: _start_offline(Mode.BOT))
	ui.local_requested.connect(func() -> void: _start_offline(Mode.LOCAL))
	ui.join_requested.connect(_join)
	ui.pause_requested.connect(_pause)
	ui.resume_requested.connect(_resume)
	ui.leave_requested.connect(func() -> void:
		if mode == Mode.ONLINE and room_id != 0:
			leave_room("")
		else:
			_leave(""))
	ui.disconnect_requested.connect(func() -> void: _leave(""))
	ui.create_room_requested.connect(func(n: String) -> void: lobby.request_create(n))
	ui.join_room_requested.connect(func(id: int) -> void: lobby.request_join(id))
	ui.quick_join_requested.connect(func() -> void: lobby.request_quick())
	ui.refresh_rooms_requested.connect(func() -> void: lobby.request_list())
	lobby.rooms_updated.connect(ui.set_room_list)
	lobby.notice.connect(ui.set_rooms_status)
	ui.rematch_requested.connect(func() -> void:
		if mode == Mode.ONLINE:
			srv_rematch.rpc_id(1)
		else:
			_auth_begin_match())
	ui.skins_changed.connect(func() -> void: world.set_board_skin(Prefs.skins["board"]))
	ui.look_dragged.connect(rig.touch_look)
	ui.fire_pressed.connect(rig.request_fire)
	ui.zoom_pressed.connect(func() -> void:
		if rig.active:
			rig.set_zoom(not rig.zoom))
	ui.ammo_tapped.connect(_on_ammo_selected)


## Developer shortcuts for scripted multi-process tests (pass after `--`).
func run_cli(args: PackedStringArray) -> void:
	for a in args:
		if a.begins_with("--tilt="):
			_force_tilt = Vector2(float(a.get_slice("=", 1).get_slice(",", 0)), float(a.get_slice("=", 1).get_slice(",", 1)))
		if a.begins_with("--diff="):
			Prefs.difficulty = clampi(int(a.get_slice("=", 1)), 0, Rules.DIFF_INSANE)   # test only: not saved
	for a in args:
		if a == "--autoplay":
			_autoplay = true
		elif a.begins_with("--card="):
			ui.debug_card(a.get_slice("=", 1))
		elif a == "--nomouse":
			_no_mouse = true
		elif a == "--touch":
			ui.force_touch_mode()
		elif a == "--nopause":
			_no_pause = true
		elif a == "--bot":
			_start_offline(Mode.BOT)
		elif a == "--autobot":
			_autoplay = true
			_start_offline(Mode.BOT)
		elif a.begins_with("--autojoin="):
			_autoplay = true
			_join(a.get_slice("=", 1))
		elif a.begins_with("--shot="):
			var spec := a.get_slice("=", 1)   # path@seconds
			var secs := float(spec.get_slice("@", 1)) if "@" in spec else 6.0
			get_tree().create_timer(secs).timeout.connect(func() -> void:
				get_viewport().get_texture().get_image().save_png(spec.get_slice("@", 0)))
		elif a.begins_with("--autoquit="):
			get_tree().create_timer(float(a.get_slice("=", 1))).timeout.connect(func() -> void: get_tree().quit())


# --- session flow -----------------------------------------------------------------------------

func _local_controls(t: int) -> bool:
	match mode:
		Mode.BOT:
			return t == 1
		Mode.LOCAL:
			return true
	return t == my_team


func _view_team(t: int) -> int:
	return t if mode == Mode.LOCAL else my_team


func _start_offline(m: Mode) -> void:
	Net.close()
	mode = m
	is_host = true
	my_team = 1
	names = {1: Loc.t("Bạn"), 2: "Bot"} if m == Mode.BOT else {1: Loc.t("Đội X"), 2: Loc.t("Đội O")}
	difficulty = Prefs.difficulty
	# Two players on one machine share one loadout; the bot dresses up at random.
	skins = {1: Prefs.skins.duplicate(), 2: Skins.random(_rng) if m == Mode.BOT else Prefs.skins.duplicate()}
	_auth_begin_match()


func _join(address: String) -> void:
	var err := Net.connect_to(address)
	if err != OK:
		ui.set_join_status(Loc.t("Không kết nối được tới %s (lỗi %d).") % [address, err])
		return
	mode = Mode.ONLINE
	is_host = false
	my_team = 0
	phase = Phase.IDLE
	ui.set_join_status(Loc.t("Đang kết nối tới %s…") % address)


func _on_joined_host() -> void:
	ui.show_rooms()
	lobby.request_list()
	if _autoplay:
		lobby.request_quick()


## Client: the lobby sent us to a room. Take the room's node name so RPCs line up, then sit down.
func enter_room(id: int) -> void:
	room_id = id
	name = "Room_%d" % id
	my_team = 0
	srv_hello.rpc_id(1, Net.player_name, Prefs.skins)


## Client: back to the room list without dropping the connection.
func leave_room(message: String) -> void:
	if room_id != 0:
		srv_leave.rpc_id(1)
		room_id = 0
		name = "Game"
	get_tree().paused = false
	_clear_match()
	phase = Phase.IDLE
	my_team = 0
	ui.show_rooms()
	if message != "":
		ui.set_rooms_status(message)
	lobby.request_list()


func _on_join_failed() -> void:
	Net.close()
	ui.show_join()
	ui.set_join_status(Loc.t("Kết nối thất bại. Kiểm tra địa chỉ máy chủ và mạng của bạn, rồi thử lại."))


func _on_host_lost() -> void:
	_leave(Loc.t("Mất kết nối tới máy chủ."))


func _leave(message: String) -> void:
	if room_id != 0:
		room_id = 0
		name = "Game"
	get_tree().paused = false
	Net.close()
	_clear_match()
	phase = Phase.IDLE
	mode = Mode.BOT
	is_host = true
	ui.show_menu(message)


func _clear_match() -> void:
	if is_instance_valid(_rocket):
		_rocket.queue_free()
	board.fill(0)
	mark_count = 0
	winner = 0
	last_cell = Vector2i(-1, -1)
	win_cells.clear()
	_pending = {}
	if world != null:
		world.clear_board()


func _pause() -> void:
	if phase == Phase.IDLE or phase == Phase.OVER:
		return
	if mode != Mode.ONLINE:
		get_tree().paused = true
	ui.show_pause(mode == Mode.ONLINE)


func _resume() -> void:
	get_tree().paused = false
	ui.hide_overlay()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and not _autoplay and not _no_pause and not server_only and ui != null and not ui.overlay_open():
		_pause()


# --- authority: turns, shots, results --------------------------------------------------------------

func _bcast(method: StringName, args: Array) -> void:
	if server_only:
		for t in [1, 2]:
			if _slots[t] != 0:
				callv("rpc_id", [_slots[t], method] + args)
	callv(method, args)


func seated() -> int:
	return int(_slots[1] != 0) + int(_slots[2] != 0)


func is_full() -> bool:
	return seated() + _reserved.size() >= 2


func reserve(peer: int) -> void:
	_reserved[peer] = true


## What the room is called: its name, or "#id" when the creator left it blank.
func _room_title() -> String:
	return room_name if room_name != "" else "#%d" % room_id


func room_info() -> Dictionary:
	var who: Array = []
	for t in [1, 2]:
		if _slots[t] != 0:
			who.append(_slot_names[t])
	return {"id": room_id, "name": room_name, "count": seated() + _reserved.size(),
		"names": who, "playing": phase != Phase.IDLE, "diff": difficulty}


@rpc("any_peer", "call_remote", "reliable")
func srv_hello(guest_name: String, loadout: Dictionary) -> void:
	if not server_only:
		return
	var id := multiplayer.get_remote_sender_id()
	_reserved.erase(id)
	if id == _slots[1] or id == _slots[2]:
		return
	var t := 0
	for k in [1, 2]:
		if _slots[k] == 0:
			t = k
			break
	if t == 0:
		net_reject.rpc_id(id, "Phòng đã đủ 2 người chơi.")
		return
	_slots[t] = id
	_slot_names[t] = guest_name.strip_edges().substr(0, 16)
	if _slot_names[t] == "":
		_slot_names[t] = GLYPH[t]
	_slot_skins[t] = Skins.sanitize(loadout)
	_log("room %d: %s joined as team %d" % [room_id, _slot_names[t], t])
	net_assign.rpc_id(id, t)
	if _slots[3 - t] != 0:
		names = {1: _slot_names[1], 2: _slot_names[2]}
		skins = {1: _slot_skins[1], 2: _slot_skins[2]}
		_auth_begin_match()
	else:
		net_wait.rpc_id(id, "Phòng «%s». Bạn là đội %s. Đang chờ đối thủ vào phòng…", [_room_title(), GLYPH[t]])
	room_changed.emit()


@rpc("any_peer", "call_remote", "reliable")
func srv_rematch() -> void:
	if server_only and phase == Phase.OVER and _slots[1] != 0 and _slots[2] != 0:
		_auth_begin_match()
		room_changed.emit()


@rpc("any_peer", "call_remote", "reliable")
func srv_leave() -> void:
	if server_only:
		on_peer_gone(multiplayer.get_remote_sender_id())


func on_peer_gone(id: int) -> void:
	_reserved.erase(id)
	var gone := 0
	for k in [1, 2]:
		if _slots[k] == id:
			gone = k
			_slots[k] = 0
	if gone != 0:
		_log("room %d: team %d left" % [room_id, gone])
		_clear_match()
		phase = Phase.IDLE
		var other: int = _slots[3 - gone]
		if other != 0:
			net_wait.rpc_id(other, "Phòng «%s». Đối thủ đã thoát. Đang chờ người chơi mới…", [_room_title()])
		player_left.emit(id)
	if seated() == 0 and _reserved.is_empty():
		room_empty.emit()
	else:
		room_changed.emit()


@rpc("authority", "call_remote", "reliable")
func net_assign(t: int) -> void:
	my_team = t


@rpc("authority", "call_remote", "reliable")
func net_wait(template: String, args: Array) -> void:
	_clear_match()
	phase = Phase.IDLE
	get_tree().paused = false
	ui.show_waiting(Loc.t(template) % args)


@rpc("authority", "call_remote", "reliable")
func net_reject(message: String) -> void:
	leave_room(Loc.t(message))


func _auth_begin_match() -> void:
	_frozen_left = 0
	_bcast(&"net_new_match", [names[1], names[2], difficulty, skins])
	_auth_start_turn(1)


func _auth_start_turn(t: int) -> void:
	var frozen := _frozen_left
	_frozen_left = maxi(0, _frozen_left - 1)
	var rolled := Rules.roll_env(difficulty, _rng, t, env, board_time, frozen)
	if _force_tilt.is_finite():
		rolled["tilt"] = _force_tilt
	_bcast(&"net_turn", [t, rolled])


static func _fresh_used() -> Dictionary:
	var none := []
	none.resize(Rules.AMMO_COUNT)
	none.fill(false)
	return {1: none.duplicate(), 2: none.duplicate()}


## Whether team t may fire this ammo right now. The freeze rocket only exists on a tumbling
## board, and only while it is not already frozen.
func _ammo_ok(t: int, ammo: int) -> bool:
	if ammo == Rules.AMMO_NORMAL:
		return true
	if ammo < 0 or ammo >= Rules.AMMO_COUNT or _used[t][ammo]:
		return false
	if ammo == Rules.AMMO_FREEZE:
		return env["spin"] and int(env["frozen"]) == 0
	return true


func _on_ammo_selected(index: int) -> void:
	if phase != Phase.AIMING or not _local_controls(team):
		return
	if not _ammo_ok(team, index):
		return
	selected_ammo = index
	notice = Loc.t(AMMO_NOTICES[index])
	if index == Rules.AMMO_FREEZE:
		notice = notice % Rules.FREEZE_TURNS


func _on_fire_requested(origin: Vector3, dir: Vector3) -> void:
	if phase != Phase.AIMING or not _local_controls(team):
		return
	if _turn_age < Rules.TILT_ANIM and difficulty == Rules.DIFF_VERY_HARD:
		return   # wait for the board to finish swinging
	if is_host:
		_auth_fire(team, origin, dir, selected_ammo)
	else:
		srv_fire.rpc_id(1, origin, dir, selected_ammo, _turn_age)


## age: how far into the turn the client fired. A shooter circling the board fires from where
## they were at that moment, which the server can work out itself (Rules.shooter_pos).
@rpc("any_peer", "call_remote", "reliable")
func srv_fire(origin: Vector3, dir: Vector3, ammo: int, age: float) -> void:
	if not server_only:
		return
	var sender := multiplayer.get_remote_sender_id()
	var t := 1 if _slots[1] == sender else (2 if _slots[2] == sender else 0)
	if t != 0:
		_auth_fire(t, origin, dir, ammo, age)


@rpc("any_peer", "call_remote", "unreliable")
func srv_steer(point: Vector3) -> void:
	if not server_only:
		return
	var sender := multiplayer.get_remote_sender_id()
	if _slots[team] == sender and not _live.is_empty():
		_set_steer(point)


func _set_steer(point: Vector3) -> void:
	if point.is_finite():
		_steer_target = Vector3(clampf(point.x, -120.0, 120.0), clampf(point.y, -10.0, 160.0), clampf(point.z, -60.0, 60.0))


func _auth_fire(t: int, origin: Vector3, dir: Vector3, ammo: int = Rules.AMMO_NORMAL, age: float = -1.0) -> void:
	if phase != Phase.AIMING or t != team or dir.length() < 0.1 or not is_finite(dir.length()) or not origin.is_finite():
		return
	if not _ammo_ok(t, ammo):
		ammo = Rules.AMMO_NORMAL
	# Nobody can walk: the shot always leaves from where the rules put the player, whatever the
	# client sent. A client sees each turn a little late, so it may date its shot back a bit.
	var at := _turn_age if (age < 0.0 or not is_finite(age)) else clampf(age, _turn_age - MAX_SHOT_LAG, _turn_age)
	origin = Rules.shooter_pos(env, t, at)
	_pending_ammo = ammo
	if ammo == Rules.AMMO_STEER:
		_live = Rules.begin_flight(origin, dir, board_time)
		var aim := Rules.plane_hit(origin, dir, _xf())
		_steer_target = aim if aim.is_finite() else Rules.cell_world(Rules.N >> 1, Rules.N >> 1, _xf())
		_live_acc = 0.0
		_live_send = 0.0
		_bcast(&"net_shot", [t, ammo, PackedVector3Array([origin]), board_time])
		return
	var res := Rules.simulate_shot(origin, dir, env, board, obstacles, board_time)
	var path: PackedVector3Array = res["path"]
	_pending = res
	_flight_left = (path.size() - 1) / Rules.PATH_HZ + 0.05
	_bcast(&"net_shot", [t, ammo, path, board_time])


func _auth_finish_turn(res: Dictionary) -> void:
	var kind: String = res.get("kind", "timeout")
	var r: int = res.get("r", -1)
	var c: int = res.get("c", -1)
	var win := 0
	var flat := PackedInt32Array()
	if _pending_ammo == Rules.AMMO_ERASE and (kind == "placed" or kind == "occupied"):
		kind = "erased" if (kind == "occupied" and board[r * Rules.N + c] != team) else "erase_miss"
	elif _pending_ammo == Rules.AMMO_FREEZE and (kind == "placed" or kind == "occupied"):
		# The board stops exactly as it was when the rocket struck it; no mark is placed.
		kind = "frozen"
		_frozen_left = Rules.FREEZE_TURNS
		_bcast(&"net_freeze", [Rules.board_angles(env, float(res.get("tau", board_time)))])
	_live = {}
	_pending_ammo = Rules.AMMO_NORMAL
	if kind == "placed":
		board[r * Rules.N + c] = team
		var line := Rules.win_line(board, r, c, team)
		board[r * Rules.N + c] = 0
		if not line.is_empty():
			win = team
			for cell in line:
				flat.append(cell.x)
				flat.append(cell.y)
		elif mark_count + 1 >= Rules.N * Rules.N:
			win = 3
	_bcast(&"net_result", [team, kind, r, c, win, flat, res.get("pos", Vector3.ZERO)])


## Test helper: aim like the bot would, sometimes with a special, via the normal fire path.
## Returns true once it has fired (a tumbling board may need a few tries to find a good moment).
func _autoplay_fire() -> bool:
	if _auto_plan.is_empty():
		var cell := Rules.bot_pick_target(board, mark_count, team, _rng)
		var ammo := Rules.AMMO_NORMAL
		if mark_count >= 2:
			if _ammo_ok(team, Rules.AMMO_ERASE):
				for i in board.size():
					if board[i] == 3 - team:
						cell = Vector2i(i / Rules.N, i % Rules.N)
						ammo = Rules.AMMO_ERASE
						break
			elif _ammo_ok(team, Rules.AMMO_FREEZE):
				ammo = Rules.AMMO_FREEZE
			elif _ammo_ok(team, Rules.AMMO_STEER):
				ammo = Rules.AMMO_STEER
		_auto_plan = {"cell": cell, "ammo": ammo}
	var cell: Vector2i = _auto_plan["cell"]
	var ammo: int = _auto_plan["ammo"]
	selected_ammo = ammo
	# Where the rules have us standing at this very moment (we may be circling the board).
	var origin := Rules.shooter_pos(env, team, _turn_age)
	if ammo == Rules.AMMO_STEER:
		# A guided shot starts off-line on purpose; the steering has to pull it onto the target.
		_auto_target = Rules.cell_world(cell.x, cell.y, _xf())
		_on_fire_requested(origin, (_auto_target - origin).normalized())
		return true
	var first := Vector3.ZERO
	for cand in Rules.aim_candidates(origin, cell, env, board_time):
		if first == Vector3.ZERO:
			first = cand["dir"]
		var probe := Rules.simulate_shot(origin, cand["dir"], env, board, obstacles, board_time)
		if _shot_does(probe, cell, ammo):
			_on_fire_requested(origin, cand["dir"])
			return true
	if _waits_for_moment() and time_left > 2.5:
		return false   # wait for a better moment
	if first == Vector3.ZERO:
		first = Rules.solve_aim_cell(origin, cell, env, board_time)["dir"]
	_on_fire_requested(origin, first)
	return true


## Picks, once per turn, what the bot wants to hit and with which ammo.
func _bot_make_plan(for_team: int) -> Dictionary:
	var cell := Rules.bot_pick_target(board, mark_count, for_team, _rng)
	if cell.x < 0:
		return {}
	var ammo := Rules.AMMO_NORMAL
	if not _used[for_team][Rules.AMMO_ERASE]:
		# Spend the eraser on an enemy run of four, unless the bot can simply win this turn.
		var threat := Rules.threat_cell(board, 3 - for_team)
		if threat.x >= 0:
			board[cell.x * Rules.N + cell.y] = for_team
			var wins := not Rules.win_line(board, cell.x, cell.y, for_team).is_empty()
			board[cell.x * Rules.N + cell.y] = 0
			if not wins:
				cell = threat
				ammo = Rules.AMMO_ERASE
	# Now and then, once the game is under way, the bot stops a tumbling board.
	if ammo == Rules.AMMO_NORMAL and mark_count >= 4 and _ammo_ok(for_team, Rules.AMMO_FREEZE) and _rng.randf() < 0.3:
		ammo = Rules.AMMO_FREEZE
	var spread := 0.6 if _rng.randf() < 0.08 else 0.22   # the odd sloppy shot keeps the bot beatable
	return {"cell": cell, "ammo": ammo, "next": 0.0,
		"jitter": Vector2(_rng.randf_range(-spread, spread), _rng.randf_range(-spread, spread)) * Rules.CELL}


## A simulated shot does what this ammo is for: a freeze rocket only has to hit the board.
func _shot_does(probe: Dictionary, cell: Vector2i, ammo: int) -> bool:
	if ammo == Rules.AMMO_FREEZE:
		return probe["kind"] == "placed" or probe["kind"] == "occupied"
	var expect := "occupied" if ammo == Rules.AMMO_ERASE else "placed"
	return probe["kind"] == expect and probe["r"] == cell.x and probe["c"] == cell.y


## A tumbling board, or a shooter circling a still one: the shot that works changes from moment
## to moment, so it pays to wait for a good one.
func _waits_for_moment() -> bool:
	return env["spin"] or float(env["orbit"]) != 0.0


## Called every frame once the bot has "thought" long enough. On a still board it aims, checks
## the shot by simulating it, and fires. When the good shot changes from moment to moment (a
## tumbling board, or the bot circling the board) it checks every ~0.1 s and waits for a moment
## when a shot really lands, firing a best guess only when time is nearly up.
func _auth_bot_fire(for_team: int) -> void:
	if _bot_plan.is_empty():
		_bot_plan = _bot_make_plan(for_team)
		if _bot_plan.is_empty():
			_auth_finish_turn({"kind": "timeout"})
			return
	var waits := _waits_for_moment()
	var now := Time.get_ticks_msec() / 1000.0
	if waits and now < float(_bot_plan["next"]):
		return
	_bot_plan["next"] = now + 0.1
	var cell: Vector2i = _bot_plan["cell"]
	var ammo: int = _bot_plan["ammo"]
	var jitter: Vector2 = _bot_plan["jitter"]
	var origin := Rules.shooter_pos(env, for_team, _turn_age)
	var guess := {}
	# On a still board, try a few nearby aim points so the bot can slip past trees and rocks.
	for attempt in (1 if waits else 6):
		var jit := jitter if attempt == 0 else Vector2(_rng.randf_range(-0.3, 0.3), _rng.randf_range(-0.3, 0.3)) * Rules.CELL
		for cand in Rules.aim_candidates(origin, cell, env, board_time, jit):
			if guess.is_empty():
				guess = cand
			var probe := Rules.simulate_shot(origin, cand["dir"], env, board, obstacles, board_time)
			if _shot_does(probe, cell, ammo):
				_auth_fire(for_team, origin, cand["dir"], ammo)
				return
	if waits and time_left > 2.5:
		return
	if guess.is_empty():
		guess = Rules.solve_aim_cell(origin, cell, env, board_time, jitter)
	_auth_fire(for_team, origin, guess["dir"], ammo)


# --- replicated events (run on every peer, including the host) ---------------------------------

@rpc("authority", "call_remote", "reliable")
func net_new_match(name_x: String, name_o: String, new_difficulty: int, new_skins: Dictionary) -> void:
	names = {1: name_x, 2: name_o}
	difficulty = new_difficulty
	skins = {1: Skins.sanitize(new_skins.get(1)), 2: Skins.sanitize(new_skins.get(2))}
	env = Rules.calm_env()
	board_time = 0.0
	_shot_slave = false
	_used = _fresh_used()
	_clear_match()
	if world != null:
		world.set_spin_mode(false)
		world.set_tilt(Vector2.ZERO, false)
		world.set_frozen(false, false)
		world.set_board_skin(Prefs.skins["board"])   # your own board, whatever the others chose
		world.set_mark_styles(skins[1]["mark"], skins[2]["mark"])
	phase = Phase.IDLE
	get_tree().paused = false
	if not server_only:
		ui.hide_overlay()
		ui.set_difficulty(difficulty)
		rig.reset_for_turn(_view_team(1), Transform3D(Basis.IDENTITY, Rules.BOARD_ORIGIN), _start_z_for(difficulty))
	_log("new match: %s vs %s [%s]" % [name_x, name_o, Rules.DIFF_NAMES[difficulty]])


## The board's pose right now (on a tumbling board it changes every frame).
func _start_z_for(level: int) -> float:
	return Rules.START_Z_NEAR if level >= Rules.DIFF_INSANE else Rules.START_Z_FAR


func _xf() -> Transform3D:
	return Rules.board_xform(env, board_time)


## Pose used to frame the camera at the start of a turn: a tumbling board is framed flat.
func _rest_xf() -> Transform3D:
	if env["spin"]:
		return Transform3D(Basis.IDENTITY, Rules.BOARD_ORIGIN)
	return _xf()


@rpc("authority", "call_remote", "reliable")
func net_turn(t: int, new_env: Dictionary) -> void:
	team = t
	env = new_env
	if env["spin"]:
		board_time = env["t0"]   # the authority's board clock at the start of this turn
		_shot_slave = false
	if world != null:
		world.set_spin_mode(env["spin"])
		world.set_frozen(int(env["frozen"]) > 0)
		if not env["spin"]:
			world.set_tilt(env["tilt"])
	time_left = env["time"]
	_turn_age = 0.0
	_last_tick = -1
	_auto_fired = false
	_auto_plan = {}
	_bot_plan = {}
	selected_ammo = Rules.AMMO_NORMAL
	_pending_ammo = Rules.AMMO_NORMAL
	_steer_live = false
	_live = {}
	phase = Phase.AIMING
	notice = Loc.t(NOTICE_START)
	var mine := _local_controls(t)
	if int(env["frozen"]) > 0:
		notice = Loc.t("Bàn cờ đang đóng băng: còn %d lượt.") % int(env["frozen"])
	elif mine and float(env["orbit"]) != 0.0:
		notice = Loc.t("Bạn đang đi vòng quanh bàn cờ! Chờ lúc thuận lợi rồi bắn.")
	if rig != null:
		# Everyone starts the turn facing the board (watchers too: nobody can walk to look around).
		# A shooter circling the board starts wherever the lap begins.
		var view := _view_team(t)
		rig.reset_for_turn(view, _rest_xf(), env["start_z"], Rules.shooter_azimuth(env, t, 0.0) if mine else NAN)
	_log("turn team=%d wind=%.2f tilt=(%.2f,%.2f) spin=%s omega=(%.2f,%.2f) orbit=%.2f frozen=%d" % [t, env["wind"], (env["tilt"] as Vector2).x, (env["tilt"] as Vector2).y, env["spin"], (env["omega"] as Vector2).x, (env["omega"] as Vector2).y, env["orbit"], env["frozen"]])


@rpc("authority", "call_remote", "reliable")
func net_shot(t: int, ammo: int, path: PackedVector3Array, tau: float) -> void:
	phase = Phase.FLYING
	_last_ammo = ammo
	_steer_live = ammo == Rules.AMMO_STEER
	if env["spin"]:
		# Pin the board clock to the moment of firing and then to the rocket's flight, so the
		# board is where the authority computed it to be when the rocket arrives.
		board_time = tau
		_shot_tau0 = tau
		_shot_slave = not _steer_live
	if ammo != Rules.AMMO_NORMAL:
		_used[t][ammo] = true
	_last_blast = skins[t]["blast"]
	var mine := _local_controls(t)
	notice = Loc.t("Đạn đuổi! Di chuột để lái rocket tới ô bạn muốn.") if (_steer_live and mine) else Loc.t("Rocket đang bay…")
	_log("shot team=%d ammo=%d points=%d" % [t, ammo, path.size()])
	if server_only:
		return
	if is_instance_valid(_rocket):
		_rocket.queue_free()
	_rocket = Rocket.new()
	_rocket.ammo = ammo
	_rocket.trail_id = skins[t]["trail"]
	add_child(_rocket)
	if _steer_live:
		_rocket.begin_live(path[0])
	elif path.size() >= 2:
		_rocket.launch(path)
	_rocket.landed.connect(_on_rocket_landed)
	_play(LAUNCH_SFX[ammo])
	if mine:
		rig.kick()
		ui.flash()


@rpc("authority", "call_remote", "unreliable")
func net_rocket(pos: Vector3, tau: float) -> void:
	if env["spin"]:
		board_time = tau
	if is_instance_valid(_rocket):
		_rocket.push_live(pos)


## A freeze rocket struck the tumbling board: it stops dead in the pose it had at that instant.
@rpc("authority", "call_remote", "reliable")
func net_freeze(theta: Vector2) -> void:
	env["omega"] = Vector2.ZERO
	env["theta0"] = theta
	env["frozen"] = Rules.FREEZE_TURNS
	_shot_slave = false
	if world != null:
		world.set_frozen(true)
	_log("freeze at (%.2f, %.2f)" % [theta.x, theta.y])


func _set_cell(r: int, c: int, value: int) -> void:
	if world != null:
		world.set_cell(r, c, value)


func _set_last(r: int, c: int) -> void:
	if world != null:
		world.set_last(r, c)


func _log(text: String) -> void:
	print("[RC r%d] %s" % [room_id, text])


func _play(sfx_name: String, volume_db: float = -6.0) -> void:
	if not server_only:
		sfx.play(sfx_name, volume_db)


func _on_rocket_landed(pos: Vector3) -> void:
	_shot_slave = false
	world.spawn_explosion(pos, 1.0 if pos.y > 1.0 else 0.6, _last_ammo, _last_blast)
	_play("boom", -4.0)


@rpc("authority", "call_remote", "reliable")
func net_result(t: int, kind: String, r: int, c: int, win: int, flat: PackedInt32Array, end_pos: Vector3) -> void:
	phase = Phase.RESULT
	_result_in = RESULT_PAUSE
	_steer_live = false
	_shot_slave = false
	if is_instance_valid(_rocket) and _rocket.is_live():
		_rocket.end_live(end_pos)
	match kind:
		"placed":
			board[r * Rules.N + c] = t
			mark_count += 1
			last_cell = Vector2i(r, c)
			_set_cell(r, c, t)
			_set_last(r, c)
			notice = Loc.t("Trúng ô %s!") % _cell_text(t, r, c)
			_play("mark")
		"erased":
			board[r * Rules.N + c] = 0
			mark_count -= 1
			last_cell = Vector2i(r, c)
			_set_cell(r, c, 0)
			_set_last(r, c)
			notice = Loc.t("Đạn tẩy xóa dấu ở ô %s!") % _cell_text(t, r, c)
			_play("mark")
		"frozen":
			notice = Loc.t("Đạn băng! Bàn cờ đóng băng trong %d lượt.") % Rules.FREEZE_TURNS
			_play("mark")
		"erase_miss":
			last_cell = Vector2i(r, c)
			_set_last(r, c)
			notice = Loc.t("Đạn tẩy không trúng dấu nào của đối thủ — mất lượt.")
			_play("block")
		"occupied":
			last_cell = Vector2i(r, c)
			_set_last(r, c)
			notice = Loc.t("Ô đã có dấu — mất lượt.")
			_play("block")
		"obstacle":
			notice = Loc.t("Rocket trúng vật cản — mất lượt.")
			_play("block")
		"timeout":
			notice = Loc.t("Hết giờ — mất lượt.")
			_play("block")
		_:
			notice = Loc.t("Bắn hụt — mất lượt.")
	_log("result team=%d kind=%s cell=(%d,%d) win=%d" % [t, kind, r, c, win])
	if win != 0:
		_finish_match(win, flat)


## "You win!" reads better than "You wins!", so the player's own name gets its own sentence.
func _win_text(t: int) -> String:
	return Loc.t("Bạn chiến thắng!") if names[t] == Loc.t("Bạn") else (Loc.t("%s chiến thắng!") % names[t])


## Cell coordinates as the shooter sees them (the far side of the board is mirrored).
func _cell_text(t: int, r: int, c: int) -> String:
	return "%d, %d" % [r + 1, (Rules.N - c) if _view_team(t) == 2 else c + 1]


func _finish_match(win: int, flat: PackedInt32Array) -> void:
	phase = Phase.OVER
	winner = win
	if server_only:
		return
	win_cells.clear()
	for i in range(0, flat.size(), 2):
		win_cells.append(Vector2i(flat[i], flat[i + 1]))
	if win != 3:
		world.mark_win(win_cells, win)
	var title := Loc.t("Hòa!") if win == 3 else _win_text(win)
	notice = title
	var sub := Loc.t("Bàn cờ đã đầy.") if win == 3 else Loc.t("5 dấu %s liên tiếp.") % GLYPH[win]
	var i_won := win != 3 and (mode == Mode.LOCAL or _local_controls(win))
	_play("win" if (win == 3 or i_won) else "lose")
	var can_rematch := true
	get_tree().create_timer(1.4).timeout.connect(func() -> void:
		if phase == Phase.OVER:
			ui.show_over(title, sub, can_rematch))


# --- per frame ---------------------------------------------------------------------------------

func _process(delta: float) -> void:
	if ui == null and not server_only:
		return
	board_time += delta
	if _shot_slave and is_instance_valid(_rocket):
		board_time = _shot_tau0 + _rocket.elapsed()
	if env["spin"] and world != null and phase != Phase.IDLE:
		world.set_pose(_xf())
	_tick(delta)
	_sync_input_and_hud()


func _tick(delta: float) -> void:
	match phase:
		Phase.AIMING:
			time_left = maxf(0.0, time_left - delta)
			_turn_age += delta
			var secs := ceili(time_left)
			if secs <= 5 and secs != _last_tick and _local_controls(team):
				_last_tick = secs
				_play("tick", -12.0)
			if _autoplay and not _auto_fired and _turn_age >= 1.0 and _local_controls(team) and Time.get_ticks_msec() / 1000.0 >= _auto_next:
				_auto_next = Time.get_ticks_msec() / 1000.0 + 0.1
				_auto_fired = _autoplay_fire()
			if not is_host:
				return
			if time_left <= 0.0:
				_auth_finish_turn({"kind": "timeout"})
			elif mode == Mode.BOT and team == 2 and _turn_age >= BOT_THINK:
				_auth_bot_fire(2)
		Phase.FLYING:
			if _steer_live and _local_controls(team):
				_steer_send += delta
				if _steer_send >= 1.0 / 30.0:
					_steer_send = 0.0
					if _autoplay and not _auto_plan.is_empty() and _auto_plan["ammo"] == Rules.AMMO_STEER:
						_auto_target = Rules.cell_world((_auto_plan["cell"] as Vector2i).x, (_auto_plan["cell"] as Vector2i).y, _xf())
					var point := _auto_target if _auto_target.is_finite() else rig.aim_world_point(_xf())
					if point.is_finite():
						if is_host:
							_set_steer(point)
						else:
							srv_steer.rpc_id(1, point)
			if is_host:
				if not _live.is_empty():
					_step_live(delta)
				else:
					_flight_left -= delta
					if _flight_left <= 0.0:
						_auth_finish_turn(_pending)
		Phase.RESULT:
			if is_host:
				_result_in -= delta
				if _result_in <= 0.0:
					_auth_start_turn(3 - team)


func _step_live(delta: float) -> void:
	_live_acc = minf(_live_acc + delta, 0.1)
	var res := {}
	while _live_acc >= Rules.SIM_DT and res.is_empty():
		_live_acc -= Rules.SIM_DT
		res = Rules.step_flight(_live, env, board, obstacles, _steer_target)
	if not res.is_empty():
		_auth_finish_turn(res)
		return
	_live_send += delta
	if _live_send >= 1.0 / 30.0:
		_live_send = 0.0
		_bcast(&"net_rocket", [_live["pos"], float(_live["tau0"]) + float(_live["t"])])


func _sync_input_and_hud() -> void:
	if server_only:
		return
	rig.set_menu_mode(phase == Phase.IDLE)
	# Very hard: the shooter rides round the board while aiming (and stops once the rocket is away).
	var riding := float(env["orbit"]) != 0.0 and _local_controls(team) and phase == Phase.AIMING
	if riding:
		rig.ride(Rules.shooter_azimuth(env, team, _turn_age), float(env["start_z"]))
	var overlay := ui.overlay_open()
	rig.active = not overlay and phase != Phase.IDLE
	# Touch screens aim with the on-screen controls, so the mouse is never grabbed there.
	var want := Input.MOUSE_MODE_VISIBLE if overlay or phase == Phase.IDLE or _no_mouse or ui.touch_mode else Input.MOUSE_MODE_CAPTURED
	if Input.mouse_mode != want:
		# A browser only grants pointer lock after a click, and an iframe (itch.io) may refuse it
		# outright, so on the web retry at a gentle pace; a click on the game also grabs the mouse.
		var now := Time.get_ticks_msec()
		if want != Input.MOUSE_MODE_CAPTURED or not OS.has_feature("web") or now >= _next_capture_try:
			_next_capture_try = now + 700
			Input.mouse_mode = want

	ui.set_hud_visible(phase != Phase.IDLE)
	if phase == Phase.IDLE:
		return
	var title: String
	if phase == Phase.OVER:
		title = Loc.t("Hòa!") if winner == 3 else _win_text(winner)
	else:
		title = (Loc.t("Lượt của bạn (%s)") % GLYPH[team]) if names[team] == Loc.t("Bạn") else (Loc.t("Lượt %s (%s)") % [names[team], GLYPH[team]])
	ui.set_hud(title, Ui.COL_X if team == 1 else Ui.COL_O,
		str(ceili(time_left)), phase == Phase.AIMING and time_left <= 5.0, notice)
	# Show everything from where the viewer stands. World +x is the RIGHT of team 1's screen but
	# the LEFT of team 2's, and a board leaning toward +z leans toward team 1 and away from
	# team 2; a shooter circling the board sees everything in between (azimuth a, 0 = team 1).
	var a := rig.azimuth
	var spin: bool = env["spin"]
	var angles: Vector2 = Rules.board_angles(env, board_time) if spin else env["tilt"]
	ui.set_env({
		"wind": float(env["wind"]) * cos(a),
		"gravity": env["gravity"],
		"lean": rad_to_deg(angles.x) * cos(a),
		"twist": rad_to_deg(wrapf(angles.y - a, -PI * 0.5, PI * 0.5)),
		"show_tilt": difficulty >= Rules.DIFF_VERY_HARD,
		"spin": spin,
		"omega": env["omega"],
		"frozen": int(env["frozen"]),
	})
	# Carried round the board? Say which way the board is if the player has looked away.
	var hint := ""
	if riding:
		var local := rig.cam.global_transform.affine_inverse() * (_xf() * Vector3(0.0, Rules.BOARD_HALF, 0.0))
		var ang := atan2(local.x, -local.z)
		if absf(ang) > 0.5:
			hint = Loc.t("Bàn ở bên phải  >>>") if ang > 0.0 else Loc.t("<<<  Bàn ở bên trái")
	ui.set_compass(hint)
	var mine := phase == Phase.AIMING and _local_controls(team)
	var usable := []
	for k in Rules.AMMO_COUNT:
		usable.append(_ammo_ok(team, k))
	ui.set_ammo(selected_ammo, usable, _used[team], mine, difficulty >= Rules.DIFF_INSANE)
	ui.set_touch_state(mine, rig.zoom)
	var mm := ui.minimap
	mm.board = board
	mm.last = last_cell
	mm.win_cells = win_cells
	mm.flip = cos(a) < 0.0   # seen from the far side the columns run the other way
	mm.aim = rig.aim_on_board(_xf())
	mm.queue_redraw()
