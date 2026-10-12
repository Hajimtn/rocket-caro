class_name Rocket
extends Node3D
## Visual rocket that replays a path precomputed by the authority (Rules.simulate_shot).

signal landed(pos: Vector3)

var ammo := Rules.AMMO_NORMAL   ## set before add_child: tints the nose cone
var _live := false
var _live_target := Vector3.ZERO
var _path := PackedVector3Array()
var _t := 0.0
var _running := false
var _body: Node3D
var _trail: CPUParticles3D


func _ready() -> void:
	_body = Node3D.new()
	add_child(_body)
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color("dfe6d0")
	steel.metallic = 0.4
	steel.roughness = 0.4
	var red := StandardMaterial3D.new()
	red.albedo_color = [Color("c44836"), Color("a56bff"), Color("37d6ff")][ammo]
	if ammo != Rules.AMMO_NORMAL:
		red.emission_enabled = true
		red.emission = red.albedo_color
		red.emission_energy_multiplier = 1.5
	var glow := StandardMaterial3D.new()
	glow.albedo_color = Color("ffd36b")
	glow.emission_enabled = true
	glow.emission = Color("ff9d2e")
	glow.emission_energy_multiplier = 3.0
	glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var tube := CylinderMesh.new()
	tube.top_radius = 0.25
	tube.bottom_radius = 0.25
	tube.height = 1.4
	tube.radial_segments = 10
	tube.material = steel
	_part(tube, Vector3(0, 0, 0), Vector3(90, 0, 0))
	var nose := CylinderMesh.new()
	nose.top_radius = 0.0
	nose.bottom_radius = 0.25
	nose.height = 0.55
	nose.radial_segments = 10
	nose.material = red
	_part(nose, Vector3(0, 0, -0.97), Vector3(-90, 0, 0))
	var flame := SphereMesh.new()
	flame.radius = 0.3
	flame.height = 0.9
	flame.radial_segments = 8
	flame.rings = 4
	flame.material = glow
	_part(flame, Vector3(0, 0, 0.8), Vector3(90, 0, 0))

	var smoke_mat := StandardMaterial3D.new()
	smoke_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smoke_mat.vertex_color_use_as_albedo = true
	smoke_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var puff := SphereMesh.new()
	puff.radius = 0.22
	puff.height = 0.44
	puff.radial_segments = 6
	puff.rings = 3
	puff.material = smoke_mat
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 1.0])
	ramp.colors = PackedColorArray([Color(1, 0.95, 0.75, 0.9), Color(0.8, 0.85, 0.85, 0.0)])
	_trail = CPUParticles3D.new()
	_trail.mesh = puff
	_trail.color_ramp = ramp
	_trail.amount = 90
	_trail.lifetime = 1.1
	_trail.local_coords = false
	_trail.direction = Vector3.BACK
	_trail.spread = 25.0
	_trail.initial_velocity_min = 0.3
	_trail.initial_velocity_max = 1.2
	_trail.gravity = Vector3.ZERO
	_trail.scale_amount_min = 0.7
	_trail.scale_amount_max = 1.4
	_trail.emitting = false
	add_child(_trail)


func _part(mesh: Mesh, pos: Vector3, rot_deg: Vector3) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_body.add_child(mi)


func launch(path: PackedVector3Array) -> void:
	_path = path
	_t = 0.0
	_running = path.size() >= 2
	position = path[0]
	_trail.emitting = false
	if not _running:
		_finish()


## Live (guided) flight: the authority streams positions instead of a precomputed path.
func begin_live(start: Vector3) -> void:
	_live = true
	_live_target = start
	_path = PackedVector3Array([start])
	position = start


func push_live(pos: Vector3) -> void:
	_live_target = pos


func end_live(pos: Vector3) -> void:
	if _live:
		_live = false
		position = pos
		_finish()


## Seconds of flight played so far (path mode); the board clock follows this.
func elapsed() -> float:
	return _t / Rules.PATH_HZ


func is_live() -> bool:
	return _live


func _process(delta: float) -> void:
	if _live:
		var before := position
		position = position.lerp(_live_target, 1.0 - exp(-24.0 * delta))
		var dir := position - before
		if dir.length_squared() > 0.0001:
			look_at(position + dir, Vector3.UP if absf(dir.normalized().y) < 0.99 else Vector3.RIGHT)
		if not _trail.emitting and position.distance_to(_path[0]) > 6.0:
			_trail.emitting = true
		return
	if not _running:
		return
	_t += delta * Rules.PATH_HZ
	var i := int(_t)
	if i >= _path.size() - 1:
		position = _path[_path.size() - 1]
		_finish()
		return
	position = _path[i].lerp(_path[i + 1], _t - i)
	# Keep the smoke out of the shooter's face: it only starts once the rocket is clear.
	if not _trail.emitting and position.distance_to(_path[0]) > 6.0:
		_trail.emitting = true
	var dir := _path[i + 1] - _path[i]
	if dir.length_squared() > 0.0001:
		look_at(position + dir, Vector3.UP if absf(dir.normalized().y) < 0.99 else Vector3.RIGHT)


func _finish() -> void:
	_running = false
	_body.visible = false
	_trail.emitting = false
	landed.emit(position)
	get_tree().create_timer(1.3).timeout.connect(queue_free)
