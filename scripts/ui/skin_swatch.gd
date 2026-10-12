class_name SkinSwatch
extends Control
## Small drawn preview of one skin (Skins catalogue), shown on the skin picker buttons.

const TEAM_X := Color("ff8a6e")
const TEAM_O := Color("6cbcff")

var kind := "board"
var skin: Dictionary = {}


func _init(skin_kind: String = "board", skin_id: String = "") -> void:
	kind = skin_kind
	skin = Skins.find(kind, skin_id)
	custom_minimum_size = Vector2(96, 44)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	match kind:
		"board":
			_draw_board(r)
		"mark":
			_draw_marks(r)
		"blast":
			_draw_blast(r)
		_:
			_draw_trail(r)


func _draw_board(r: Rect2) -> void:
	draw_rect(r, skin["frame"])
	var inner := r.grow(-4.0)
	var paper: Color = skin["paper"]
	paper.a = 1.0
	draw_rect(inner, paper)
	if skin["pattern"] == 1:
		var y := inner.position.y + 3.0
		while y + 2.0 < inner.end.y:
			draw_line(Vector2(inner.position.x, y), Vector2(inner.end.x, y + 2.0), paper.darkened(0.12), 1.0)
			y += 6.5
	var n := 6
	for i in range(1, n):
		var x := inner.position.x + inner.size.x * i / n
		var y := inner.position.y + inner.size.y * i / n
		var col: Color = skin["major"] if i == 3 else skin["minor"]
		var w := 2.0 if i == 3 else 1.0
		if skin["pattern"] == 3 and i == 3:
			draw_line(Vector2(x, inner.position.y), Vector2(x, inner.end.y), Color(col, 0.35), 6.0)
			draw_line(Vector2(inner.position.x, y), Vector2(inner.end.x, y), Color(col, 0.35), 6.0)
		draw_line(Vector2(x, inner.position.y), Vector2(x, inner.end.y), col, w)
		draw_line(Vector2(inner.position.x, y), Vector2(inner.end.x, y), col, w)
	_glyph(1, inner.position + inner.size * Vector2(0.25, 0.32), 9.0, skin["x"])
	_glyph(2, inner.position + inner.size * Vector2(0.75, 0.68), 9.0, skin["o"])


func _draw_marks(r: Rect2) -> void:
	draw_rect(r, Color(0.85, 0.88, 0.75))
	_glyph(1, r.position + r.size * Vector2(0.3, 0.5), 15.0, TEAM_X.darkened(0.15))
	_glyph(2, r.position + r.size * Vector2(0.7, 0.5), 15.0, TEAM_O.darkened(0.25))


## One mark of the current mark skin (or classic X/O when drawing a board preview).
func _glyph(team: int, c: Vector2, s: float, col: Color) -> void:
	var style: int = skin["style"] if kind == "mark" else 0
	match style:
		1:
			var pts := PackedVector2Array()
			for i in 10:
				var a := -PI * 0.5 + i * PI / 5.0
				pts.append(c + Vector2(cos(a), sin(a)) * (s if i % 2 == 0 else s * 0.45))
			draw_colored_polygon(pts, col)
		2:
			var pts := PackedVector2Array()
			for i in 40:
				var t := TAU * i / 40.0
				var p := Vector2(16.0 * pow(sin(t), 3), -(13.0 * cos(t) - 5.0 * cos(2.0 * t) - 2.0 * cos(3.0 * t) - cos(4.0 * t)))
				pts.append(c + p * s / 17.0)
			draw_colored_polygon(pts, col)
		3:
			var d := PackedVector2Array([c + Vector2(0, -s), c + Vector2(s, 0), c + Vector2(0, s), c + Vector2(-s, 0), c + Vector2(0, -s)])
			draw_polyline(d, col, 2.5)
			var g := s * 0.4
			draw_colored_polygon(PackedVector2Array([c + Vector2(0, -g), c + Vector2(g, 0), c + Vector2(0, g), c + Vector2(-g, 0)]), col)
		_:
			if team == 1:
				var k := s * 0.75
				draw_line(c + Vector2(-k, -k), c + Vector2(k, k), col, 3.0)
				draw_line(c + Vector2(-k, k), c + Vector2(k, -k), col, 3.0)
			else:
				draw_arc(c, s * 0.75, 0.0, TAU, 24, col, 3.0)


func _draw_blast(r: Rect2) -> void:
	draw_rect(r, Color(0.08, 0.16, 0.19))
	var c := r.get_center()
	var colors: Array = skin["colors"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in 26:
		var a := rng.randf() * TAU
		var d := rng.randf_range(3.0, 22.0)
		var k := d / 22.0
		var col: Color = Color.from_hsv(rng.randf(), 0.7, 1.0) if skin["rainbow"] else (colors[0] as Color).lerp(colors[1], k)
		col.a = 1.0 - k * 0.5
		var p := c + Vector2(cos(a), sin(a) * 0.8) * d
		if skin["shape"] == "flake":
			draw_set_transform(p, a, Vector2.ONE)
			draw_rect(Rect2(-3, -1.5, 6, 3), col)
			draw_set_transform(Vector2.ZERO)
		else:
			draw_circle(p, 3.2 - k * 1.5, col)


func _draw_trail(r: Rect2) -> void:
	draw_rect(r, Color(0.43, 0.62, 0.7))
	var colors: Array = skin["colors"]
	var y := r.get_center().y
	for i in 12:
		var k := float(i) / 11.0   # 0 at the rocket, 1 at the oldest puff
		var x := r.end.x - 16.0 - k * (r.size.x - 22.0)
		var col: Color = Color.from_hsv(k, 0.75, 1.0) if skin["rainbow"] else (colors[0] as Color).lerp(colors[colors.size() - 1], k)
		col.a = 1.0 - k * 0.8
		var rad := (3.0 + k * 4.0) * float(skin["size"])
		if skin["shape"] == "flake":
			draw_rect(Rect2(x - 2, y - 2 + sin(i * 1.7) * 6.0, 4, 4), col)
		else:
			draw_circle(Vector2(x, y + sin(i * 0.9) * 2.0), rad, col)
	# the rocket itself
	draw_rect(Rect2(r.end.x - 15.0, y - 2.5, 11.0, 5.0), Color("dfe6d0"))
	draw_colored_polygon(PackedVector2Array([Vector2(r.end.x - 4.0, y - 2.5), Vector2(r.end.x, y), Vector2(r.end.x - 4.0, y + 2.5)]), Color("c44836"))
