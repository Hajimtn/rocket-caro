class_name Rules
extends RefCounted
## Pure game rules shared by every peer: board geometry, ballistics, win check, bot brain.
## A cell is addressed as Vector2i(row, col); row 0 is the top row, col 0 the left column
## as seen from team 1's side of the board.

const N := 15                      ## board is N x N cells
const CELL := 6.5                  ## world units per cell
const BOARD_SIZE := N * CELL
const BOARD_HALF := BOARD_SIZE * 0.5
const BOARD_BOTTOM := 8.0
const BOARD_TOP := BOARD_BOTTOM + BOARD_SIZE
const BOARD_MID_Y := BOARD_BOTTOM + BOARD_HALF
const GRAVITY := 5.0
const SPEED := 100.0
const TURN_TIME := 15.0
const EYE_HEIGHT := 5.0
const START_Z_FAR := 160.0    ## distance from the board where players stand, fixed (every level but insane)
const START_Z_NEAR := 100.0   ## insane: the board is closer, but it tumbles
const WIN_LEN := 5
const MAX_WIND := 8.0
const FLIGHT_LIMIT := 5.0
const SIM_DT := 1.0 / 240.0
const PATH_HZ := 60.0
const PATH_STRIDE := 4
const AMMO_NORMAL := 0
const AMMO_ERASE := 1   ## wipes an opponent's mark
const AMMO_STEER := 2   ## steered by the shooter's crosshair while it flies
const STEER_GAIN := 5.0       ## 1/s: how hard the rocket pulls toward the crosshair point
const STEER_ACCEL := 45.0     ## u/s^2: maximum sideways pull (gravity is 5, wind up to 8)
const DIFF_NORMAL := 0      ## no wind, no gravity
const DIFF_HARD := 1        ## + wind and gravity
const DIFF_VERY_HARD := 2   ## + the board leans and twists every turn, and the player is spun round and round
const DIFF_INSANE := 3      ## wind + gravity + a board that tumbles and spins non-stop, fast (the player does not spin)
const DIFF_NAMES := ["Bình thường", "Khó", "Rất khó", "Siêu khó"]
const DIFF_DESC := [
	"Không gió, không trọng lực: rocket bay thẳng.",
	"Có gió và trọng lực làm rocket lệch.",
	"Thêm độ dốc: bàn cờ nghiêng và xoay đổi mỗi lượt, còn bạn bị xoay vòng 360° trong lúc ngắm. Dễ gây chóng mặt.",
	"Bàn cờ lật và quay liên tục rất nhanh: phải bắn đón đầu. Dễ gây chóng mặt.",
]
const MAX_LEAN_AWAY := 0.80   ## rad (about 46 degrees): board top leaning away from the shooter
const MAX_LEAN_TOWARD := 0.40 ## rad: leaning toward the shooter fills the screen, so keep it milder
const MIN_LEAN := 0.30        ## rad: never (nearly) flat, or the hard part would be invisible
const MAX_TWIST := 0.60       ## rad: board turned about the vertical axis
const MIN_TWIST := 0.15
const TILT_ANIM := 0.8        ## seconds the board takes to swing to its new angle
const FLIP_MIN := 0.7         ## insane: rad/s the board somersaults about its horizontal axis
const FLIP_MAX := 1.2
const SPIN_MIN := 1.2         ## insane: rad/s it spins about the vertical axis
const SPIN_MAX := 2.0
const PLAYER_SPIN_MIN := 0.7  ## very hard: rad/s the player is spun round and round (360 degrees)
const PLAYER_SPIN_MAX := 1.1
const BOARD_ORIGIN := Vector3(0.0, BOARD_BOTTOM, 0.0)   ## the board hinges on its bottom edge
const DIRS: Array[Vector2i] = [Vector2i(0, 1), Vector2i(1, 0), Vector2i(1, 1), Vector2i(1, -1)]


static func make_obstacles() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for side in [-1, 1]:
		for i in 7:
			out.append({
				"x": (i - 3) * 14.0,
				"z": side * (42.0 + (i % 3) * 13.0),
				"r": 4.0 if i % 2 == 1 else 3.0,
				"tree": i % 2 == 1,
			})
	return out


## No wind, no gravity, flat board: the baseline every difficulty builds on.
## spin/omega/theta0/t0 describe a tumbling board: its two angles at board-clock time tau are
## theta0 + omega * (tau - t0) (x = flip about the horizontal axis, y = spin about the vertical).
static func calm_env() -> Dictionary:
	return {"wind": 0.0, "gravity": 0.0, "tilt": Vector2.ZERO, "spin": false,
		"omega": Vector2.ZERO, "theta0": Vector2.ZERO, "t0": 0.0, "time": TURN_TIME,
		"start_z": START_Z_FAR, "yaw_rate": 0.0}


## Rolls the conditions for one turn. Everything a shot depends on lives in this dictionary, so
## the authority can broadcast it and every peer (and the bot) sees exactly the same physics.
## shooter is the team (1 or 2) whose turn it is: a static lean is chosen relative to them.
## prev/now keep a tumbling board continuous: the new angles start where the old ones were.
static func roll_env(difficulty: int, rng: RandomNumberGenerator, shooter: int = 1, prev: Dictionary = {}, now: float = 0.0) -> Dictionary:
	var env := calm_env()
	if difficulty >= DIFF_HARD:
		env["wind"] = rng.randf_range(-MAX_WIND, MAX_WIND)
		env["gravity"] = GRAVITY
	if difficulty == DIFF_VERY_HARD:
		var toward := rng.randf() < 0.4
		var lean := rng.randf_range(MIN_LEAN, MAX_LEAN_TOWARD) if toward else -rng.randf_range(MIN_LEAN, MAX_LEAN_AWAY)
		env["tilt"] = Vector2(
			lean * (1.0 if shooter == 1 else -1.0),   # +x leans the top toward +z, i.e. toward team 1
			(1.0 if rng.randf() < 0.5 else -1.0) * rng.randf_range(MIN_TWIST, MAX_TWIST))
		# The player cannot walk, but is turned round and round on the spot.
		env["yaw_rate"] = (1.0 if rng.randf() < 0.5 else -1.0) * rng.randf_range(PLAYER_SPIN_MIN, PLAYER_SPIN_MAX)
	if difficulty >= DIFF_INSANE:
		env["spin"] = true
		env["start_z"] = START_Z_NEAR
		env["omega"] = Vector2(
			(1.0 if rng.randf() < 0.5 else -1.0) * rng.randf_range(FLIP_MIN, FLIP_MAX),
			(1.0 if rng.randf() < 0.5 else -1.0) * rng.randf_range(SPIN_MIN, SPIN_MAX))
		env["t0"] = now
		env["theta0"] = board_angles(prev, now) if prev.get("spin", false) else Vector2(rng.randf_range(0.0, TAU), rng.randf_range(0.0, TAU))
	return env


## How far the wind alone pushes a rocket sideways after T seconds.
static func wind_push(env: Dictionary, t: float) -> float:
	return 0.5 * float(env["wind"]) * t * t


# --- the (possibly tilted or tumbling) board -----------------------------------------------

## Orientation of the board: x = its "right", y = its "up", z = its face normal.
## tilt.x leans the top toward +z (team 1) when positive; tilt.y turns it about the vertical axis.
static func board_basis(tilt: Vector2) -> Basis:
	return Basis(Vector3.UP, tilt.y) * Basis(Vector3.RIGHT, tilt.x)


## The tumbling board's two angles at board-clock time tau.
static func board_angles(env: Dictionary, tau: float) -> Vector2:
	return (env["theta0"] as Vector2) + (env["omega"] as Vector2) * (tau - float(env["t0"]))


## Pose of the board at board-clock time tau. The frame's origin is the middle of the bottom
## edge, x runs along the bottom edge, y is "up the board", z is the face normal. A static
## tilt hinges on that edge; a tumbling board turns about its own centre.
static func board_xform(env: Dictionary, tau: float) -> Transform3D:
	if env["spin"]:
		var b := board_basis(board_angles(env, tau))
		return Transform3D(b, Vector3(0.0, BOARD_MID_Y, 0.0) - b.y * BOARD_HALF)
	return Transform3D(board_basis(env["tilt"]), BOARD_ORIGIN)


## World point -> board coordinates (u across, v up from the bottom edge, w off the face).
static func to_local(p: Vector3, xf: Transform3D) -> Vector3:
	return xf.affine_inverse() * p


static func cell_world(r: int, c: int, xf: Transform3D) -> Vector3:
	return xf * Vector3(-BOARD_HALF + (c + 0.5) * CELL, BOARD_SIZE - (r + 0.5) * CELL, 0.0)


## Where a straight line from origin along dir meets the board face (world point);
## Vector3(INF, INF, INF) if it never does.
static func plane_hit(origin: Vector3, dir: Vector3, xf: Transform3D) -> Vector3:
	var n := xf.basis.z
	var denom := dir.dot(n)
	if absf(denom) < 0.001:
		return Vector3(INF, INF, INF)
	var t := -(origin - xf.origin).dot(n) / denom
	if t <= 0.0:
		return Vector3(INF, INF, INF)
	return origin + dir * t


## Fractional (row, col) of a world point on the board, for the minimap.
static func board_cell_float(p: Vector3, xf: Transform3D) -> Vector2:
	var l := to_local(p, xf)
	return Vector2((BOARD_SIZE - l.y) / CELL, (l.x + BOARD_HALF) / CELL)


## Cell under board coordinates (u, v), or Vector2i(-1, -1) when off the board.
static func cell_at(u: float, v: float) -> Vector2i:
	if u < -BOARD_HALF or u >= BOARD_HALF or v <= 0.0 or v > BOARD_SIZE:
		return Vector2i(-1, -1)
	return Vector2i(int(floor((BOARD_SIZE - v) / CELL)), int(floor((u + BOARD_HALF) / CELL)))


static func _in_bounds(r: int, c: int) -> bool:
	return r >= 0 and r < N and c >= 0 and c < N


## Cells of the winning line through (r, c) for team t, or an empty array.
static func win_line(board: PackedByteArray, r: int, c: int, t: int) -> Array[Vector2i]:
	for d in DIRS:
		var line: Array[Vector2i] = [Vector2i(r, c)]
		for s in [-1, 1]:
			for k in range(1, WIN_LEN):
				var rr: int = r + d.x * k * s
				var cc: int = c + d.y * k * s
				if not _in_bounds(rr, cc) or board[rr * N + cc] != t:
					break
				line.append(Vector2i(rr, cc))
		if line.size() >= WIN_LEN:
			return line
	var none: Array[Vector2i] = []
	return none


static func hit_obstacle(o: Dictionary, p: Vector3) -> bool:
	if o["tree"]:
		return absf(p.x - o["x"]) < 4.0 and absf(p.z - o["z"]) < 2.0 and p.y < 14.0
	return Vector3(o["x"], 3.0, o["z"]).distance_to(p) < o["r"]


## tau0 is the board-clock time at launch; the board's pose at any moment of the flight is
## board_xform(env, tau0 + t).
static func begin_flight(origin: Vector3, dir: Vector3, tau0: float = 0.0) -> Dictionary:
	return {"pos": origin, "vel": dir.normalized() * SPEED, "t": 0.0, "tau0": tau0}


## Advances a flight by one SIM_DT step. Returns {} while still airborne, otherwise
## {kind: placed|occupied|obstacle|miss, r, c, pos}. steer is a world point the rocket is
## pulled toward, or null for an unguided shot.
static func step_flight(f: Dictionary, env: Dictionary, board: PackedByteArray, obstacles: Array[Dictionary], steer: Variant = null) -> Dictionary:
	var old: Vector3 = f["pos"]
	var vel: Vector3 = f["vel"]
	if steer != null:
		var to: Vector3 = steer - old
		if to.length() > 3.0:
			var pull := ((to.normalized() * SPEED - vel) * STEER_GAIN).limit_length(STEER_ACCEL)
			vel += pull * SIM_DT
	vel.x += float(env["wind"]) * SIM_DT
	vel.y -= float(env["gravity"]) * SIM_DT
	var pos := old + vel * SIM_DT
	f["vel"] = vel
	f["pos"] = pos
	f["t"] = float(f["t"]) + SIM_DT
	var xf := board_xform(env, float(f["tau0"]) + float(f["t"]))
	var w_old := to_local(old, xf).z
	var w_new := to_local(pos, xf).z
	if w_old * w_new <= 0.0 and w_old != w_new:
		var hit := old + (pos - old) * (w_old / (w_old - w_new))
		var l := to_local(hit, xf)
		var cell := cell_at(l.x, l.y)
		if cell.x >= 0:
			f["pos"] = hit
			return {"kind": "occupied" if board[cell.x * N + cell.y] != 0 else "placed", "r": cell.x, "c": cell.y, "pos": hit}
	for o in obstacles:
		if hit_obstacle(o, pos):
			return {"kind": "obstacle", "r": -1, "c": -1, "pos": pos}
	if pos.y < 0.0 or float(f["t"]) > FLIGHT_LIMIT or absf(pos.z) > 420.0:
		return {"kind": "miss", "r": -1, "c": -1, "pos": pos}
	return {}


## Integrates an unguided rocket fired at board-clock time tau0 and returns
## {path: PackedVector3Array (60 Hz), kind, r, c, pos}.
static func simulate_shot(origin: Vector3, dir: Vector3, env: Dictionary, board: PackedByteArray, obstacles: Array[Dictionary], tau0: float = 0.0) -> Dictionary:
	var flight := begin_flight(origin, dir, tau0)
	var path := PackedVector3Array([origin])
	var step := 0
	while true:
		var res := step_flight(flight, env, board, obstacles)
		step += 1
		if not res.is_empty():
			path.append(res["pos"])
			res["path"] = path
			return res
		if step % PATH_STRIDE == 0:
			path.append(flight["pos"])
	return {}


## First opponent mark that belongs to a run of 4+ in a row (a threat worth erasing), or (-1, -1).
@warning_ignore("integer_division")
static func threat_cell(board: PackedByteArray, opponent: int) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_run := 3
	for i in N * N:
		if board[i] != opponent:
			continue
		var r := i / N
		var c := i % N
		for d in DIRS:
			var run := 1
			for s in [-1, 1]:
				for k in range(1, WIN_LEN):
					var rr: int = r + d.x * k * s
					var cc: int = c + d.y * k * s
					if not _in_bounds(rr, cc) or board[rr * N + cc] != opponent:
						break
					run += 1
			if run > best_run:
				best_run = run
				best = Vector2i(r, c)
	return best


## Direction and flight time that make a rocket fired from origin pass through the world point
## target, compensating gravity and wind. {dir: unit Vector3, time: seconds}
static func solve_aim_ex(origin: Vector3, target: Vector3, env: Dictionary) -> Dictionary:
	var d := target - origin
	var g: float = env["gravity"]
	var time := d.length() / SPEED
	var v := Vector3.ZERO
	for i in 14:
		v = Vector3((d.x - wind_push(env, time)) / time, (d.y + 0.5 * g * time * time) / time, d.z / time)
		time *= v.length() / SPEED
	v = Vector3((d.x - wind_push(env, time)) / time, (d.y + 0.5 * g * time * time) / time, d.z / time)
	return {"dir": v.normalized(), "time": time}


static func solve_aim(origin: Vector3, target: Vector3, env: Dictionary) -> Vector3:
	return solve_aim_ex(origin, target, env)["dir"]


## World point of a board cell (plus a board-plane offset) as it will be at board-clock time tau.
static func _cell_target(cell: Vector2i, env: Dictionary, tau: float, jitter: Vector2) -> Vector3:
	var xf := board_xform(env, tau)
	return cell_world(cell.x, cell.y, xf) + xf.basis.x * jitter.x + xf.basis.y * jitter.y


## Every way to hit a board cell with a rocket fired from origin at board-clock time tau0.
## A still board has one; a tumbling board has none, one or several, because the cell moves
## while the rocket flies: a solution is a flight time T such that the rocket aimed at where the
## cell will be at tau0 + T really takes T seconds to get there. Earliest first. Each entry is
## {dir, time} like solve_aim_ex. (A solution can still be spoiled if the board sweeps through
## the rocket's path earlier: the caller should simulate it.)
static func aim_candidates(origin: Vector3, cell: Vector2i, env: Dictionary, tau0: float, jitter: Vector2 = Vector2.ZERO) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not env["spin"]:
		out.append(solve_aim_ex(origin, _cell_target(cell, env, tau0, jitter), env))
		return out
	var prev_gap := 0.0
	var prev_t := 0.0
	var t := 0.25
	while t <= 2.6:
		var gap := float(solve_aim_ex(origin, _cell_target(cell, env, tau0 + t, jitter), env)["time"]) - t
		if prev_t > 0.0 and (gap < 0.0) != (prev_gap < 0.0):
			var lo := prev_t
			var hi := t
			var lo_neg := prev_gap < 0.0
			for k in 12:
				var mid := 0.5 * (lo + hi)
				var gm := float(solve_aim_ex(origin, _cell_target(cell, env, tau0 + mid, jitter), env)["time"]) - mid
				if (gm < 0.0) == lo_neg:
					lo = mid
				else:
					hi = mid
			var tm := 0.5 * (lo + hi)
			out.append(solve_aim_ex(origin, _cell_target(cell, env, tau0 + tm, jitter), env))
		prev_gap = gap
		prev_t = t
		t += 0.025
	return out


## First candidate from aim_candidates, or a rough guess when there is none.
static func solve_aim_cell(origin: Vector3, cell: Vector2i, env: Dictionary, tau0: float, jitter: Vector2 = Vector2.ZERO) -> Dictionary:
	var all := aim_candidates(origin, cell, env, tau0, jitter)
	if not all.is_empty():
		return all[0]
	return solve_aim_ex(origin, _cell_target(cell, env, tau0 + 1.0, jitter), env)


@warning_ignore("integer_division")
static func bot_pick_target(board: PackedByteArray, mark_count: int, me: int, rng: RandomNumberGenerator) -> Vector2i:
	if mark_count == 0:
		return Vector2i(N / 2, N / 2)
	var work := board.duplicate()
	var cand := {}
	for i in N * N:
		if work[i] == 0:
			continue
		var r := i / N
		var c := i % N
		for dr in range(-2, 3):
			for dc in range(-2, 3):
				if _in_bounds(r + dr, c + dc) and work[(r + dr) * N + c + dc] == 0:
					cand[(r + dr) * N + c + dc] = true
	var best := Vector2i(-1, -1)
	var best_score := -INF
	for key: int in cand:
		var r := key / N
		var c := key % N
		var val := rng.randf() * 0.4
		for t in [me, 3 - me]:
			work[key] = t
			if not win_line(work, r, c, t).is_empty():
				val += 10000.0 if t == me else 8000.0
			work[key] = 0
			for d in DIRS:
				var n := 0
				for s in [-1, 1]:
					for k in range(1, WIN_LEN):
						var rr: int = r + d.x * k * s
						var cc: int = c + d.y * k * s
						if not _in_bounds(rr, cc) or work[rr * N + cc] != t:
							break
						n += 1
				val += pow(4.0, n) * (1.0 if t == me else 1.1)
		if val > best_score:
			best_score = val
			best = Vector2i(r, c)
	return best
