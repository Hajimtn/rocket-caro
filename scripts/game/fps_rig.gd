class_name FpsRig
extends Node3D
## The local player's body: first-person camera, procedural rocket launcher, movement
## and aiming input. It only asks the match controller to fire; it never decides anything.

signal fire_requested(origin: Vector3, direction: Vector3)
signal ammo_selected(index: int)

const LOOK_SENS := 0.0017
const LOOK_SENS_ZOOM := 0.00055
const TOUCH_SENS := 0.0022        ## rad per dragged pixel (a finger covers less ground than a mouse)
const FOV_NORMAL := 61.0
const FOV_ZOOM := 22.6
const PITCH_MIN := -0.35
const PITCH_MAX := 1.2
const REST_POS := Vector3(0.3, -0.27, -0.55)

var team := 1
var yaw := 0.0
var start_pitch := 0.4   ## set per turn by reset_for_turn so the whole board is in view
var pitch := start_pitch
var menu_mode := false   ## idle sway behind the menus
var azimuth := 0.0       ## where the body stands round the board (Rules.shooter_azimuth); it faces the middle
var _was_captured := false
var _look_ok_at := 0   ## ticks (ms) before which mouse look is ignored
var _menu_t := 0.0
var zoom := false
var active := false     ## accepts look/fire input
var cam: Camera3D
var launcher: Node3D



func _ready() -> void:
	cam = Camera3D.new()
	cam.fov = FOV_NORMAL
	cam.near = 0.05
	cam.far = 1200.0
	add_child(cam)
	cam.current = true
	_build_launcher()
	reset_for_turn(1)


## Puts the player back on their start spot, facing the middle of the board. The pitch is the
## average of the angles to the board's bottom and top edge, which keeps all of it on screen
## even when it leans.
func reset_for_turn(for_team: int, xf: Transform3D = Transform3D(Basis.IDENTITY, Rules.BOARD_ORIGIN), start_z: float = Rules.START_Z_FAR, at_azimuth: float = NAN) -> void:
	team = for_team
	yaw = 0.0
	azimuth = at_azimuth if not is_nan(at_azimuth) else (0.0 if team == 1 else PI)
	position = Vector3(start_z * sin(azimuth), Rules.EYE_HEIGHT, start_z * cos(azimuth))
	var bottom := xf.origin
	var top := xf * Vector3(0.0, Rules.BOARD_SIZE, 0.0)
	var a_bottom := atan2(bottom.y - position.y, Vector2(bottom.x - position.x, bottom.z - position.z).length())
	var a_top := atan2(top.y - position.y, Vector2(top.x - position.x, top.z - position.z).length())
	start_pitch = clampf(0.5 * (a_bottom + a_top), PITCH_MIN, PITCH_MAX)
	pitch = start_pitch
	set_zoom(false)
	_apply()


## Carries the player round the board (very hard): the body keeps facing the middle, and the
## player's own mouse look stays on top of that.
func ride(at_azimuth: float, radius: float) -> void:
	azimuth = at_azimuth
	position = Vector3(radius * sin(azimuth), Rules.EYE_HEIGHT, radius * cos(azimuth))


func set_zoom(on: bool) -> void:
	zoom = on
	cam.fov = FOV_ZOOM if on else FOV_NORMAL
	launcher.visible = not on and not menu_mode


func aim_direction() -> Vector3:
	return -cam.global_transform.basis.z


## Where the crosshair line (ignoring wind and gravity) meets the board, as fractional
## (row, col); Vector2(-1, -1) when it never does.
func aim_on_board(xf: Transform3D) -> Vector2:
	var p := aim_world_point(xf)
	return Rules.board_cell_float(p, xf) if p.is_finite() else Vector2(-1, -1)


## World point where the crosshair line meets the board face; INF if it never does.
func aim_world_point(xf: Transform3D) -> Vector3:
	return Rules.plane_hit(global_position, aim_direction(), xf)


func kick() -> void:
	var tw := create_tween()
	tw.tween_property(launcher, "position:z", REST_POS.z + 0.12, 0.05)
	tw.tween_property(launcher, "position:z", REST_POS.z, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


func _apply() -> void:
	rotation = Vector3(0.0, azimuth - yaw, 0.0)
	cam.rotation.x = pitch


## While menus are up the camera drifts slowly across the arena instead of sitting still.
func set_menu_mode(on: bool) -> void:
	if on == menu_mode:
		return
	menu_mode = on
	launcher.visible = not on and not zoom
	if not on:
		yaw = 0.0
		pitch = start_pitch
		_apply()


func _process(delta: float) -> void:
	# Grabbing the mouse can deliver one huge bogus motion event; skip the first instant.
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if captured and not _was_captured:
		_look_ok_at = Time.get_ticks_msec() + 200
	_was_captured = captured
	if menu_mode:
		_menu_t += delta
		yaw = sin(_menu_t * 0.2) * 0.2
		pitch = start_pitch
		_apply()
		return
	if active:
		var turn := 0.6 * delta
		if Input.is_physical_key_pressed(KEY_LEFT):
			yaw -= turn
		if Input.is_physical_key_pressed(KEY_RIGHT):
			yaw += turn
		if Input.is_physical_key_pressed(KEY_UP):
			pitch += 0.5 * delta
		if Input.is_physical_key_pressed(KEY_DOWN):
			pitch -= 0.5 * delta
		pitch = clampf(pitch, PITCH_MIN, PITCH_MAX)
	_apply()


func _unhandled_input(event: InputEvent) -> void:
	# Touches arrive as touches (see TouchControls) and again as fake mouse events; only the
	# first kind counts, or every tap would try to grab the mouse.
	if not active or event.device == InputEvent.DEVICE_ID_EMULATION:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if Time.get_ticks_msec() < _look_ok_at:
			return
		var mm: InputEventMouseMotion = event
		var s := (LOOK_SENS_ZOOM if zoom else LOOK_SENS) * Prefs.sensitivity
		var rel := mm.relative.limit_length(150.0)   # one wild event must not spin the view
		yaw += rel.x * s
		pitch = clampf(pitch - rel.y * s, PITCH_MIN, PITCH_MAX)
	elif event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
				_request_fire()
			else:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			set_zoom(mb.pressed)
	elif event is InputEventKey:
		var k: InputEventKey = event
		if k.pressed and not k.echo:
			if k.physical_keycode == KEY_Z:
				set_zoom(not zoom)
			elif k.physical_keycode == KEY_SPACE:
				_request_fire()
			elif k.physical_keycode >= KEY_1 and k.physical_keycode < KEY_1 + Rules.AMMO_COUNT:
				ammo_selected.emit(k.physical_keycode - KEY_1)


## A finger dragged across the screen (touch controls).
func touch_look(relative: Vector2) -> void:
	if not active:
		return
	var s := TOUCH_SENS * (LOOK_SENS_ZOOM / LOOK_SENS if zoom else 1.0) * Prefs.sensitivity
	var rel := relative.limit_length(200.0)
	yaw += rel.x * s
	pitch = clampf(pitch - rel.y * s, PITCH_MIN, PITCH_MAX)


func request_fire() -> void:
	if active:
		_request_fire()


func _request_fire() -> void:
	fire_requested.emit(global_position, aim_direction())


func _build_launcher() -> void:
	launcher = Node3D.new()
	launcher.position = REST_POS
	launcher.scale = Vector3.ONE * 0.55
	cam.add_child(launcher)
	var body_col := Color("394e4e")
	var dark := Color("202f32")
	var accent := Color("dce690")
	var tube := CylinderMesh.new()
	tube.top_radius = 0.11
	tube.bottom_radius = 0.11
	tube.height = 1.5
	_add_part(tube, body_col, Vector3(0, 0, -0.35), Vector3(90, 0, 0))
	var muzzle := CylinderMesh.new()
	muzzle.top_radius = 0.15
	muzzle.bottom_radius = 0.15
	muzzle.height = 0.14
	_add_part(muzzle, dark, Vector3(0, 0, -1.08), Vector3(90, 0, 0))
	var flare := CylinderMesh.new()
	flare.top_radius = 0.18
	flare.bottom_radius = 0.11
	flare.height = 0.3
	_add_part(flare, dark, Vector3(0, 0, 0.5), Vector3(90, 0, 0))
	var band := CylinderMesh.new()
	band.top_radius = 0.118
	band.bottom_radius = 0.118
	band.height = 0.08
	_add_part(band, accent, Vector3(0, 0, -0.55), Vector3(90, 0, 0))
	var sight := BoxMesh.new()
	sight.size = Vector3(0.04, 0.1, 0.18)
	_add_part(sight, dark, Vector3(0, 0.15, -0.4), Vector3.ZERO)
	var grip := BoxMesh.new()
	grip.size = Vector3(0.09, 0.3, 0.12)
	_add_part(grip, Color("be956e"), Vector3(0, -0.22, 0.0), Vector3(12, 0, 0))
	var hand := BoxMesh.new()
	hand.size = Vector3(0.14, 0.14, 0.3)
	_add_part(hand, Color("be956e"), Vector3(0, -0.14, -0.55), Vector3.ZERO)


func _add_part(mesh: Mesh, color: Color, pos: Vector3, rot_deg: Vector3) -> void:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.7
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	launcher.add_child(mi)
