class_name Minimap
extends Control
## Whole-board overview. Columns are mirrored for the player on the far side so it always
## matches what they see through their own camera.

const SIDE := 150.0
const PX := SIDE / Rules.N   ## pixels per cell

var board := PackedByteArray()
var last := Vector2i(-1, -1)
var win_cells: Array[Vector2i] = []
var flip := false
var aim := Vector2(-1, -1)   ## fractional (row, col) the crosshair points at


func _init() -> void:
	custom_minimum_size = Vector2(Rules.N * PX, Rules.N * PX)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _col(c: int) -> int:
	return Rules.N - 1 - c if flip else c


func _draw() -> void:
	var s := Rules.N * PX
	draw_rect(Rect2(0, 0, s, s), Color("163239"))
	for i in range(0, Rules.N + 1, 5):
		draw_line(Vector2(i * PX, 0), Vector2(i * PX, s), Color("33554f"))
		draw_line(Vector2(0, i * PX), Vector2(s, i * PX), Color("33554f"))
	for i in board.size():
		var v := board[i]
		if v == 0:
			continue
		var r := i / Rules.N
		var c := i % Rules.N
		draw_rect(Rect2(_col(c) * PX, r * PX, PX, PX), Color("fa8b6f") if v == 1 else Color("78beed"))
	for cell in win_cells:
		draw_rect(Rect2(_col(cell.y) * PX - 1, cell.x * PX - 1, PX + 2, PX + 2), Color("e9f48b"), false, 1.0)
	if last.x >= 0:
		draw_rect(Rect2(_col(last.y) * PX - 2, last.x * PX - 2, PX + 4, PX + 4), Color("e9f48b"), false, 1.0)
	if aim.x >= 0.0 and aim.x < Rules.N and aim.y >= 0.0 and aim.y < Rules.N:
		var cx := (Rules.N - aim.y if flip else aim.y) * PX
		draw_circle(Vector2(cx, aim.x * PX), 2.5, Color(1, 1, 1, 0.9))
	draw_rect(Rect2(0, 0, s, s), Color("71958a"), false, 1.0)
