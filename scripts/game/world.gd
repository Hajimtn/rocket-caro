class_name World
extends Node3D
## Everything static in the arena: sky, two grassy banks, the giant board, scenery and
## obstacles, plus the data texture that drives the board shader. All geometry is built from
## primitives so the game runs without any imported art.

var _img: Image
var _tex: ImageTexture
var _mat: ShaderMaterial
var _pivot: Node3D
var _obstacle_root: Node3D
var _tilt_shown := Vector2.ZERO
var _tilt_known := true   ## false after a tumbling spell: the next static tilt must snap, not tween
var _spin_on := false
var _tilt_tween: Tween
var _posts: Array[MeshInstance3D] = []


func _ready() -> void:
	_build_environment()
	_build_ground()
	_build_scenery()
	_build_board()
	set_obstacles(Rules.make_obstacles())


# --- board data ---------------------------------------------------------------------------

func clear_board() -> void:
	_img.fill(Color(0, 0, 0, 1))
	_tex.update(_img)
	_mat.set_shader_parameter("last_cell", Vector2(-1, -1))


func set_cell(r: int, c: int, value: int) -> void:
	_img.set_pixel(c, r, Color(value / 255.0, 0, 0, 1))
	_tex.update(_img)


func set_last(r: int, c: int) -> void:
	_mat.set_shader_parameter("last_cell", Vector2(c, r))


func mark_win(cells: Array[Vector2i], team: int) -> void:
	for cell in cells:
		_img.set_pixel(cell.y, cell.x, Color((team | 4) / 255.0, 0, 0, 1))
	_tex.update(_img)


# --- effects ------------------------------------------------------------------------------

func spawn_explosion(pos: Vector3, scale_factor: float = 1.0, ammo: int = Rules.AMMO_NORMAL) -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var ball := SphereMesh.new()
	ball.radius = 0.35
	ball.height = 0.7
	ball.radial_segments = 8
	ball.rings = 4
	ball.material = mat
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
	match ammo:
		Rules.AMMO_ERASE:
			ramp.colors = PackedColorArray([Color(0.9, 0.8, 1, 1), Color(0.65, 0.42, 1, 0.85), Color(0.2, 0.1, 0.3, 0)])
		Rules.AMMO_STEER:
			ramp.colors = PackedColorArray([Color(0.8, 1, 1, 1), Color(0.22, 0.84, 1, 0.85), Color(0.1, 0.2, 0.3, 0)])
		_:
			ramp.colors = PackedColorArray([Color(1, 0.95, 0.5, 1), Color(1, 0.45, 0.12, 0.85), Color(0.25, 0.25, 0.25, 0)])
	var p := CPUParticles3D.new()
	p.mesh = ball
	p.color_ramp = ramp
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = 56
	p.lifetime = 0.9
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = 4.0 * scale_factor
	p.initial_velocity_max = 15.0 * scale_factor
	p.gravity = Vector3(0, -4, 0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.8 * scale_factor
	add_child(p)
	p.global_position = pos
	p.emitting = true
	var light := OmniLight3D.new()
	light.light_color = Color(1, 0.7, 0.3)
	light.omni_range = 40.0
	light.light_energy = 6.0
	add_child(light)
	light.global_position = pos
	var tw := create_tween()
	tw.tween_property(light, "light_energy", 0.0, 0.5)
	tw.tween_callback(light.queue_free)
	get_tree().create_timer(1.6).timeout.connect(p.queue_free)


# --- construction ---------------------------------------------------------------------------

func _std(color: Color, roughness: float = 1.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	return m


func _add_mesh(mesh: Mesh, color: Color, pos: Vector3, rot_deg: Vector3 = Vector3.ZERO, parent: Node = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _std(color)
	mi.position = pos
	mi.rotation_degrees = rot_deg
	(parent if parent != null else self).add_child(mi)
	return mi


func _build_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("6f9fb2")
	sky_mat.sky_horizon_color = Color("d0dfbf")
	sky_mat.ground_horizon_color = Color("b7c9b0")
	sky_mat.ground_bottom_color = Color("294f59")
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color("c3d6c3")
	env.fog_density = 0.0016
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, 35, 0)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 260.0
	add_child(sun)


func _build_ground() -> void:
	for side in [-1, 1]:
		var bank := PlaneMesh.new()
		bank.size = Vector2(560, 320)
		_add_mesh(bank, Color("52784e") if side == 1 else Color("587c62"), Vector3(0, 0, side * 185.0))
	var strip := PlaneMesh.new()
	strip.size = Vector2(420, 50)
	var water := _add_mesh(strip, Color("2c5560"), Vector3(0, -0.4, 0))
	(water.material_override as StandardMaterial3D).roughness = 0.15
	(water.material_override as StandardMaterial3D).metallic = 0.3


func _build_scenery() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for side in [-1, 1]:
		for i in 10:
			var h := rng.randf_range(40.0, 85.0)
			var cone := CylinderMesh.new()
			cone.top_radius = 0.0
			cone.bottom_radius = rng.randf_range(28.0, 50.0)
			cone.height = h
			cone.radial_segments = 6
			cone.rings = 1
			_add_mesh(cone, Color("607e77").lerp(Color("8aa59a"), rng.randf()),
				Vector3(-300.0 + i * 66.0 + rng.randf_range(-14, 14), h * 0.5 - 2.0, side * rng.randf_range(345.0, 390.0)))


func _build_board() -> void:
	_img = Image.create(Rules.N, Rules.N, false, Image.FORMAT_R8)
	_tex = ImageTexture.create_from_image(_img)
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/board.gdshader")
	_mat.set_shader_parameter("cells", _tex)
	_mat.set_shader_parameter("grid_size", float(Rules.N))
	# Everything that makes up the physical board hangs off a pivot on its bottom edge, so a
	# harder difficulty can lean and twist the whole thing.
	_pivot = Node3D.new()
	_pivot.name = "BoardPivot"
	_pivot.position = Rules.BOARD_ORIGIN
	add_child(_pivot)
	var quad := QuadMesh.new()
	quad.size = Vector2(Rules.BOARD_SIZE, Rules.BOARD_SIZE)
	var board := MeshInstance3D.new()
	board.name = "Board"
	board.mesh = quad
	board.material_override = _mat
	board.position = Vector3(0, Rules.BOARD_HALF, 0)
	board.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_pivot.add_child(board)
	var frame_col := Color("1c3036")
	var bar_h := BoxMesh.new()
	var edge := Rules.BOARD_HALF + 0.8
	bar_h.size = Vector3(Rules.BOARD_SIZE + 4.0, 1.6, 1.4)
	var bar_v := BoxMesh.new()
	bar_v.size = Vector3(1.6, Rules.BOARD_SIZE, 1.4)
	_add_mesh(bar_h, frame_col, Vector3(0, Rules.BOARD_SIZE + 0.8, 0), Vector3.ZERO, _pivot)
	_add_mesh(bar_h, frame_col, Vector3(0, -0.8, 0), Vector3.ZERO, _pivot)
	_add_mesh(bar_v, frame_col, Vector3(-edge, Rules.BOARD_HALF, 0), Vector3.ZERO, _pivot)
	_add_mesh(bar_v, frame_col, Vector3(edge, Rules.BOARD_HALF, 0), Vector3.ZERO, _pivot)
	var post := BoxMesh.new()
	post.size = Vector3(3, Rules.BOARD_BOTTOM + 2.0, 3)
	_posts.append(_add_mesh(post, frame_col, Vector3(-edge, -Rules.BOARD_BOTTOM * 0.5 - 0.4, 0), Vector3.ZERO, _pivot))
	_posts.append(_add_mesh(post, frame_col, Vector3(edge, -Rules.BOARD_BOTTOM * 0.5 - 0.4, 0), Vector3.ZERO, _pivot))


## Swings the board to a new lean/twist (see Rules.board_basis).
func set_tilt(tilt: Vector2, animate: bool = true) -> void:
	if _tilt_tween != null:
		_tilt_tween.kill()
		_tilt_tween = null
	if not animate or not _tilt_known or tilt.is_equal_approx(_tilt_shown):
		_show_tilt(tilt)
		return
	var from := _tilt_shown
	_tilt_tween = create_tween()
	_tilt_tween.tween_method(func(k: float) -> void: _show_tilt(from.lerp(tilt, k)), 0.0, 1.0, Rules.TILT_ANIM) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)


func _show_tilt(tilt: Vector2) -> void:
	_tilt_shown = tilt
	_tilt_known = true
	_pivot.transform = Transform3D(Rules.board_basis(tilt), Rules.BOARD_ORIGIN)


## Puts the board in an exact pose (a tumbling board is re-posed every frame).
func set_pose(xf: Transform3D) -> void:
	_pivot.transform = xf


## A tumbling board floats free of the ground, so its support posts are hidden.
func set_spin_mode(on: bool) -> void:
	if on == _spin_on:
		return   # called every turn: only act when the mode really changes
	_spin_on = on
	if _tilt_tween != null:
		_tilt_tween.kill()
		_tilt_tween = null
	for p in _posts:
		p.visible = not on
	if on:
		_tilt_known = false   # the pose is driven by set_pose from here on


## Replaces every tree and rock (insane mode reshuffles them each turn).
func set_obstacles(list: Array[Dictionary]) -> void:
	if _obstacle_root != null:
		_obstacle_root.queue_free()
	_obstacle_root = Node3D.new()
	_obstacle_root.name = "Obstacles"
	add_child(_obstacle_root)
	_build_obstacle_meshes(list)


func _build_obstacle_meshes(list: Array[Dictionary]) -> void:
	var rock_col := Color("657778")
	var trunk_col := Color("665844")
	var leaf_col := Color("345e48")
	for o in list:
		var x: float = o["x"]
		var z: float = o["z"]
		if o["tree"]:
			var trunk := CylinderMesh.new()
			trunk.top_radius = 0.6
			trunk.bottom_radius = 0.9
			trunk.height = 8.0
			trunk.radial_segments = 8
			_add_mesh(trunk, trunk_col, Vector3(x, 4.0, z), Vector3.ZERO, _obstacle_root)
			var leaves := CylinderMesh.new()
			leaves.top_radius = 0.0
			leaves.bottom_radius = 4.5
			leaves.height = 11.0
			leaves.radial_segments = 8
			_add_mesh(leaves, leaf_col, Vector3(x, 12.0, z), Vector3.ZERO, _obstacle_root)
		else:
			var rock := SphereMesh.new()
			rock.radius = o["r"]
			rock.height = o["r"] * 2.0
			rock.radial_segments = 10
			rock.rings = 5
			_add_mesh(rock, rock_col, Vector3(x, 3.0, z), Vector3.ZERO, _obstacle_root)
