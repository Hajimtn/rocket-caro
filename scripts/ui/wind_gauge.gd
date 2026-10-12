class_name WindGauge
extends Control
## The turn's conditions, drawn from the player's own point of view:
##  - wind: a right-pointing arrow always pushes the rocket toward the right edge of THEIR screen;
##  - gravity: always down;
##  - the board's lean (side view) and twist (top view). On a tumbling board these two icons
##    turn live, showing exactly where the board is in its flip and its spin.

const WIND_COL := Color("e9f48b")
const GRAV_COL := Color("ffad92")
const TILT_COL := Color("9ed5ff")
const TEXT_COL := Color("f5f2df")
const DIM_COL := Color(1, 1, 1, 0.18)
const WIND_W := 170.0
const GRAV_W := 96.0
const TILT_W := 160.0
const FULL := 62.0   ## arrow length at MAX_WIND

var wind := 0.0        ## m/s^2, positive = toward the right of the screen
var gravity := 0.0
var lean := 0.0        ## degrees, positive = the board's top leans toward the viewer
var twist := 0.0       ## degrees, positive = the board's right end swings toward the viewer
var show_tilt := false
var spin := false
var omega := Vector2.ZERO   ## rad/s: flip, spin


func _init() -> void:
	custom_minimum_size = Vector2(WIND_W + GRAV_W, 64)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_env(v: Dictionary) -> void:
	var changed := false
	for key: String in ["wind", "gravity", "lean", "twist"]:
		if not is_equal_approx(float(get(key)), float(v[key])):
			set(key, float(v[key]))
			changed = true
	if show_tilt != v["show_tilt"] or spin != v["spin"]:
		show_tilt = v["show_tilt"]
		spin = v["spin"]
		omega = v["omega"]
		custom_minimum_size.x = WIND_W + GRAV_W + (TILT_W if show_tilt else 0.0)
		changed = true
	if changed:
		queue_redraw()


func _arrow(from: Vector2, to: Vector2, col: Color) -> void:
	var dir := (to - from).normalized()
	var side := Vector2(-dir.y, dir.x)
	draw_line(from, to - dir * 6.0, col, 4.0)
	draw_colored_polygon(PackedVector2Array([to, to - dir * 12.0 + side * 7.0, to - dir * 12.0 - side * 7.0]), col)


func _draw() -> void:
	var font := get_theme_default_font()
	var cx := WIND_W * 0.5

	# wind
	draw_string(font, Vector2(0, 14), Loc.t("Gió  %.1f m/s²") % absf(wind), HORIZONTAL_ALIGNMENT_CENTER, WIND_W, 13, TEXT_COL)
	draw_line(Vector2(cx - FULL - 6, 38), Vector2(cx + FULL + 6, 38), DIM_COL, 2.0)
	draw_line(Vector2(cx, 33), Vector2(cx, 43), Color(1, 1, 1, 0.35), 2.0)
	if absf(wind) < 0.3:
		draw_circle(Vector2(cx, 38), 4.0, WIND_COL)
	else:
		var len := clampf(absf(wind) / Rules.MAX_WIND, 0.12, 1.0) * FULL
		_arrow(Vector2(cx, 38), Vector2(cx + signf(wind) * len, 38), WIND_COL)

	# gravity
	draw_line(Vector2(WIND_W, 6), Vector2(WIND_W, 58), Color(1, 1, 1, 0.15), 1.0)
	var gx := WIND_W + GRAV_W * 0.5
	draw_string(font, Vector2(WIND_W, 14), Loc.t("Trọng lực  %.1f") % gravity, HORIZONTAL_ALIGNMENT_CENTER, GRAV_W, 13, TEXT_COL)
	if gravity > 0.01:
		_arrow(Vector2(gx, 24), Vector2(gx, 56), GRAV_COL)
	else:
		draw_circle(Vector2(gx, 40), 4.0, GRAV_COL)

	# board lean (side view, you stand on the left) and twist (top view, you stand at the bottom)
	if show_tilt:
		var x0 := WIND_W + GRAV_W
		draw_line(Vector2(x0, 6), Vector2(x0, 58), Color(1, 1, 1, 0.15), 1.0)
		var head := Loc.t("Lật %.1f · Quay %.1f rad/s") % [absf(omega.x), absf(omega.y)] if spin \
			else Loc.t("Dốc %d° · Xoay %d°") % [roundi(lean), roundi(twist)]
		draw_string(font, Vector2(x0, 14), head, HORIZONTAL_ALIGNMENT_CENTER, TILT_W, 12, TEXT_COL)
		var sx := x0 + 48.0
		var pivot := Vector2(sx, 36.0) if spin else Vector2(sx, 56.0)   # a tumbling board turns about its middle
		draw_circle(Vector2(sx - 34.0, 56.0), 3.0, TEXT_COL)                         # you
		var l := deg_to_rad(lean)
		var arm := Vector2(-sin(l), -cos(l)) * (17.0 if spin else 34.0)
		draw_line(pivot - (arm if spin else Vector2.ZERO), pivot + arm, TILT_COL, 4.0)  # board
		var tc := Vector2(x0 + 112.0, 36.0)
		var t := deg_to_rad(twist)
		var half := Vector2(cos(t), sin(t)) * 20.0
		draw_line(tc - half, tc + half, TILT_COL, 4.0)
		draw_circle(Vector2(tc.x, 56.0), 3.0, TEXT_COL)                              # you
