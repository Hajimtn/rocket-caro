class_name TouchControls
extends Control
## On-screen controls for phones and tablets: drag anywhere to aim, a big FIRE button and a
## ZOOM toggle. Multi-touch, so one thumb can keep aiming while the other fires. Godot's own
## GUI only sees the first finger (mouse emulation), so this reads the raw touches instead.

signal look(relative: Vector2)
signal fire
signal zoom

const FIRE_R := 72.0
const ZOOM_R := 44.0
const ACCENT := Color("e9f48b")

var blockers: Array[Control] = []   ## a touch that starts on one of these belongs to it (buttons, ammo bar)
var can_fire := false               ## your turn: the FIRE button is lit
var zoomed := false
var _look_finger := -1
var _fire_finger := -1


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visibility_changed.connect(func() -> void:
		_look_finger = -1
		_fire_finger = -1)


func _fire_center() -> Vector2:
	return Vector2(size.x - 150.0, size.y - 220.0)


func _zoom_center() -> Vector2:
	return _fire_center() + Vector2(-125.0, -95.0)


func set_state(fire_ok: bool, is_zoomed: bool) -> void:
	if fire_ok != can_fire or is_zoomed != zoomed:
		can_fire = fire_ok
		zoomed = is_zoomed
		queue_redraw()


func _blocked(p: Vector2) -> bool:
	for c in blockers:
		if is_instance_valid(c) and c.is_visible_in_tree() and c.get_global_rect().has_point(p):
			return true
	return false


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	if event is InputEventScreenTouch:
		var t: InputEventScreenTouch = event
		if t.pressed:
			if t.position.distance_to(_fire_center()) <= FIRE_R * 1.15:
				_fire_finger = t.index
				fire.emit()
				queue_redraw()
			elif t.position.distance_to(_zoom_center()) <= ZOOM_R * 1.25:
				zoom.emit()
			elif _look_finger == -1 and not _blocked(t.position):
				_look_finger = t.index
		else:
			if t.index == _look_finger:
				_look_finger = -1
			if t.index == _fire_finger:
				_fire_finger = -1
				queue_redraw()
	elif event is InputEventScreenDrag:
		var d: InputEventScreenDrag = event
		if d.index == _look_finger:
			look.emit(d.relative)


func _draw() -> void:
	var font := get_theme_default_font()
	var fc := _fire_center()
	var lit := can_fire
	var fill := ACCENT if lit else Color(1, 1, 1, 0.12)
	fill.a = (0.95 if _fire_finger != -1 else 0.78) if lit else 0.12
	draw_circle(fc, FIRE_R, fill)
	draw_arc(fc, FIRE_R, 0.0, TAU, 48, Color(1, 1, 1, 0.5 if lit else 0.2), 3.0)
	var label := Loc.t("BẮN")
	draw_string(font, fc + Vector2(-FIRE_R, 9), label, HORIZONTAL_ALIGNMENT_CENTER, FIRE_R * 2.0, 26,
		Color("20382c") if lit else Color(1, 1, 1, 0.45))
	var zc := _zoom_center()
	draw_circle(zc, ZOOM_R, Color(ACCENT, 0.85) if zoomed else Color(0.075, 0.173, 0.196, 0.7))
	draw_arc(zc, ZOOM_R, 0.0, TAU, 40, Color(1, 1, 1, 0.45), 2.0)
	# a little magnifier
	var ink := Color("20382c") if zoomed else Color(1, 1, 1, 0.85)
	draw_arc(zc + Vector2(-4, -4), 12.0, 0.0, TAU, 24, ink, 3.0)
	draw_line(zc + Vector2(5, 5), zc + Vector2(15, 15), ink, 4.0)
