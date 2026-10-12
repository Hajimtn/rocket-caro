extends SceneTree
## Touch controls, driven with fake touches in a real bot match:
##   godot --headless --path . --script tools/test_touch.gd -- --bot --nowarn --nopause --diff=1

var _fails := 0
var _main: Node


## Untyped on purpose: naming Game/Ui here would compile them before the autoloads (Net,
## Prefs) exist, which fails under --script.
func _initialize() -> void:
	create_timer(20.0).timeout.connect(func() -> void:
		print("FAIL: timed out")
		quit(1))
	_start.call_deferred()


func _start() -> void:
	_main = load("res://scenes/main.tscn").instantiate()
	root.add_child(_main)
	_run()


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout


## Real touches come in window pixels and are scaled to the game's 1280-wide canvas; the
## headless window is tiny, so convert the canvas points the test thinks in.
func _to_window(pos: Vector2) -> Vector2:
	return root.get_final_transform() * pos


func _touch(index: int, pos: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = index
	e.position = _to_window(pos)
	e.pressed = pressed
	Input.parse_input_event(e)


func _drag(index: int, pos: Vector2, rel: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = index
	e.position = _to_window(pos)
	e.relative = root.get_final_transform().basis_xform(rel)
	Input.parse_input_event(e)


func _check(ok: bool, what: String) -> void:
	if not ok:
		_fails += 1
		print("FAIL: ", what)


func _run() -> void:
	await _wait(2.5)   # the bot match has started and it is our turn
	var game = _main.get_node("Game")
	var ui = _main.get_node("Ui")
	var rig = game.rig
	_check(game.phase == game.Phase.AIMING and game.team == 1, "our turn to aim")

	# One finger aims...
	var yaw0: float = rig.yaw
	var pitch0: float = rig.pitch
	_touch(0, Vector2(500, 300), true)
	await process_frame
	_check(ui.touch_mode, "a touch switches to touch mode")
	_drag(0, Vector2(600, 280), Vector2(100, -20))
	await process_frame
	_check(rig.yaw > yaw0 + 0.1, "dragging right turns right (yaw %.3f -> %.3f)" % [yaw0, rig.yaw])
	_check(rig.pitch > pitch0, "dragging up looks up")
	_check(Input.mouse_mode != Input.MOUSE_MODE_CAPTURED, "touch never grabs the mouse")

	# ...an ammo slot can be tapped (first finger lifts, a tap is emulated as a click)...
	_touch(0, Vector2(600, 280), false)
	await process_frame

	# ...and a second finger fires while the first keeps aiming.
	_touch(0, Vector2(500, 300), true)
	await process_frame
	var fire_at: Vector2 = ui._touch._fire_center()
	_touch(1, fire_at, true)
	await process_frame
	_touch(1, fire_at, false)
	_drag(0, Vector2(510, 300), Vector2(10, 0))   # aiming finger is unaffected by the FIRE press
	await process_frame
	_check(game.phase == game.Phase.FLYING, "the FIRE button fires (phase %d)" % game.phase)
	_touch(0, Vector2(510, 300), false)

	print("RESULT: ", "FAIL" if _fails > 0 else "OK")
	quit(_fails)
