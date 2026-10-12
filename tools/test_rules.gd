extends SceneTree
## Headless checks for Rules:  godot --headless --path . --script tools/test_rules.gd

func _init() -> void:
	var empty := PackedByteArray()
	empty.resize(Rules.N * Rules.N)
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var fails := 0
	var obstacles: Array[Dictionary] = Rules.make_obstacles()

	for diff in 4:
		var aimed := 0
		var guided := 0
		var no_obstacle := 0
		const RUNS := 150
		for i in RUNS:
			var shooter := 1 if i % 2 == 0 else 2
			var env := Rules.roll_env(diff, rng, shooter, {}, 0.0)
			var tau0 := rng.randf_range(0.0, 60.0)
			var cell := Vector2i(rng.randi_range(0, Rules.N - 1), rng.randi_range(0, Rules.N - 1))
			var origin := Vector3(rng.randf_range(-30, 30), 5, float(env["start_z"]) * (1.0 if shooter == 1 else -1.0))
			# unguided, aimed at where the cell will be; like the bot, try every solution and, if
			# the board is in the way, wait up to 3 s for a better moment
			var aim := Rules.solve_aim_cell(origin, cell, env, tau0)
			var hit := false
			var blocked := true
			for wait in 31:
				var fire_at := tau0 + wait * 0.1
				for cand in Rules.aim_candidates(origin, cell, env, fire_at):
					var res := Rules.simulate_shot(origin, cand["dir"], env, empty, obstacles, fire_at)
					if res["kind"] != "obstacle":
						blocked = false
					if res["kind"] == "placed" and res["r"] == cell.x and res["c"] == cell.y:
						hit = true
						aim = cand
						tau0 = fire_at
						break
				if hit or not env["spin"]:
					break
			if hit:
				aimed += 1
			if not blocked:
				no_obstacle += 1
			# guided from a rough direction, steering at the cell's predicted arrival position
			var arrive := Rules.cell_world(cell.x, cell.y, Rules.board_xform(env, tau0 + float(aim["time"])))
			var rough := (arrive + Vector3(rng.randf_range(-8, 8), rng.randf_range(-8, 8), 0) - origin).normalized()
			var f := Rules.begin_flight(origin, rough, tau0)
			var g := {}
			while g.is_empty():
				g = Rules.step_flight(f, env, empty, obstacles, arrive)
			if g["kind"] == "placed" and g["r"] == cell.x and g["c"] == cell.y:
				guided += 1
		print("%-12s aimed %3d/%d (blocked by obstacles %d)  guided %3d/%d" % [Rules.DIFF_NAMES[diff], aimed, RUNS, RUNS - no_obstacle, guided, RUNS])
		# Whenever nothing is in the way, aiming must be (nearly) exact, even at a tumbling board.
		if aimed < no_obstacle - 8:
			fails += 1
			print("  FAIL: aimed shots missed without an obstacle")
		# (a guided shot at a board that keeps spinning is only meaningful when the player keeps
		# steering, which this fixed-target test cannot do)
		if guided < RUNS * (0.3 if diff == Rules.DIFF_INSANE else 0.6):
			fails += 1
			print("  FAIL: guided accuracy too low")

	# Board maths: cell_world -> to_local -> cell_at round-trips for static and tumbling poses.
	var tumbling := Rules.roll_env(Rules.DIFF_INSANE, rng)
	for i in 200:
		var xf := Rules.board_xform(tumbling, rng.randf_range(0.0, 100.0)) if i % 2 == 0 \
			else Transform3D(Rules.board_basis(Vector2(rng.randf_range(-0.8, 0.8), rng.randf_range(-0.6, 0.6))), Rules.BOARD_ORIGIN)
		var cell := Vector2i(rng.randi_range(0, Rules.N - 1), rng.randi_range(0, Rules.N - 1))
		var l := Rules.to_local(Rules.cell_world(cell.x, cell.y, xf), xf)
		if Rules.cell_at(l.x, l.y) != cell or absf(l.z) > 0.001:
			fails += 1
			print("FAIL: round trip ", cell, " ", l)
			break

	# Environment per difficulty.
	var calm := Rules.roll_env(Rules.DIFF_NORMAL, rng)
	if calm["wind"] != 0.0 or calm["gravity"] != 0.0 or calm["tilt"] != Vector2.ZERO or calm["spin"]:
		fails += 1
		print("FAIL: normal must be calm")
	var hard := Rules.roll_env(Rules.DIFF_HARD, rng)
	if hard["gravity"] == 0.0 or hard["tilt"] != Vector2.ZERO or hard["spin"]:
		fails += 1
		print("FAIL: hard = wind + gravity, flat board")
	var very := Rules.roll_env(Rules.DIFF_VERY_HARD, rng)
	if absf((very["tilt"] as Vector2).x) < Rules.MIN_LEAN or very["spin"]:
		fails += 1
		print("FAIL: very hard = tilted, not tumbling")
	var a := Rules.roll_env(Rules.DIFF_INSANE, rng, 1, {}, 0.0)
	var b := Rules.roll_env(Rules.DIFF_INSANE, rng, 2, a, 7.0)
	if not a["spin"] or (a["omega"] as Vector2).length() < Rules.FLIP_MIN or a["tilt"] != Vector2.ZERO or a["gravity"] == 0.0:
		fails += 1
		print("FAIL: insane = wind + gravity + tumbling board")
	# The board must not jump when the next turn rolls new rates.
	if not (b["theta0"] as Vector2).is_equal_approx(Rules.board_angles(a, 7.0)):
		fails += 1
		print("FAIL: tumbling board is discontinuous between turns")
	# Insane tumbles the board; only very hard spins the player.
	if a["yaw_rate"] != 0.0 or very["yaw_rate"] == 0.0 or absf(float(very["yaw_rate"])) < Rules.PLAYER_SPIN_MIN:
		fails += 1
		print("FAIL: only very hard spins the player")
	if Rules.START_Z_NEAR - 69.0 < 20.0:
		fails += 1
		print("FAIL: a fixed player must stand clear of the tumbling board (radius ~69)")

	# Distance: fixed spots, far everywhere but insane.
	for d in 3:
		if Rules.roll_env(d, rng)["start_z"] != Rules.START_Z_FAR:
			fails += 1
			print("FAIL: levels below insane stand far from the board")
	if Rules.roll_env(Rules.DIFF_INSANE, rng)["start_z"] != Rules.START_Z_NEAR or Rules.START_Z_FAR <= Rules.START_Z_NEAR:
		fails += 1
		print("FAIL: insane stands near, the rest far")
	for d in [Rules.DIFF_NORMAL, Rules.DIFF_HARD]:
		if Rules.roll_env(d, rng)["yaw_rate"] != 0.0:
			fails += 1
			print("FAIL: no player spin below very hard")

	# Threat detection.
	var t := empty.duplicate()
	for k in 4:
		t[5 * Rules.N + 2 + k] = 1
	if Rules.threat_cell(t, 1).x != 5 or Rules.threat_cell(t, 2).x != -1:
		fails += 1
		print("FAIL: threat cell")

	print("RESULT: ", "FAIL" if fails > 0 else "OK")
	quit(fails)
