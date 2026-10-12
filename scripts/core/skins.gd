class_name Skins
extends RefCounted
## Cosmetic catalogue. A loadout is {board, mark, blast, trail} -> skin id (a String, so a
## future shop/account system can refer to skins by name). Ids that are unknown (an older or
## newer build, a tampered message) fall back to the first entry of their kind.
##  - board: how YOUR board looks. Local only: each player sees their own choice.
##  - mark:  the marks your team leaves on the board (same shape for both teams, team colours).
##  - blast: the explosion where your rockets land.
##  - trail: the smoke trail behind your rockets.
## mark, blast and trail are part of the match (both players see them), so they travel with it.

const KINDS: Array[String] = ["board", "mark", "blast", "trail"]
const KIND_NAMES := {"board": "Bàn cờ", "mark": "Dấu trên bàn", "blast": "Hiệu ứng nổ", "trail": "Vệt đường bay"}

## pattern: 0 plain, 1 wood grain, 2 chalk dust, 3 neon glow (see board.gdshader).
const BOARDS := [
	{"id": "paper", "name": "Giấy cổ", "paper": Color(0.847, 0.882, 0.733, 0.9), "minor": Color(0.663, 0.718, 0.604),
		"major": Color(0.443, 0.545, 0.467), "x": Color(0.769, 0.282, 0.212), "o": Color(0.157, 0.424, 0.612),
		"frame": Color("1c3036"), "pattern": 0},
	{"id": "chalk", "name": "Bảng phấn", "paper": Color(0.11, 0.23, 0.19, 0.96), "minor": Color(0.47, 0.56, 0.51),
		"major": Color(0.84, 0.88, 0.8), "x": Color(1.0, 0.62, 0.52), "o": Color(0.6, 0.84, 1.0),
		"frame": Color("6b4a2e"), "pattern": 2},
	{"id": "wood", "name": "Gỗ", "paper": Color(0.74, 0.55, 0.34, 1.0), "minor": Color(0.5, 0.33, 0.19),
		"major": Color(0.33, 0.2, 0.1), "x": Color(0.62, 0.1, 0.06), "o": Color(0.06, 0.22, 0.45),
		"frame": Color("3b2414"), "pattern": 1},
	{"id": "neon", "name": "Neon", "paper": Color(0.03, 0.04, 0.1, 0.92), "minor": Color(0.1, 0.36, 0.55),
		"major": Color(0.25, 0.95, 1.0), "x": Color(1.0, 0.3, 0.62), "o": Color(0.3, 0.95, 1.0),
		"frame": Color("15183a"), "pattern": 3},
]

## style: shape drawn by board.gdshader. 0 = X for team X and O for team O; the rest draw the
## same shape for both teams, told apart by colour.
const MARKS := [
	{"id": "classic", "name": "Cổ điển X/O", "style": 0},
	{"id": "star", "name": "Ngôi sao", "style": 1},
	{"id": "heart", "name": "Trái tim", "style": 2},
	{"id": "diamond", "name": "Kim cương", "style": 3},
]

## colors: the explosion's colour over its life (special ammo keeps its own colours so you can
## still tell what was fired). rainbow: each particle gets its own hue. shape: ball | flake.
const BLASTS := [
	{"id": "fire", "name": "Lửa", "colors": [Color(1, 0.95, 0.5, 1), Color(1, 0.45, 0.12, 0.85), Color(0.25, 0.25, 0.25, 0)],
		"amount": 56, "life": 0.9, "speed": 15.0, "gravity": -4.0, "shape": "ball", "rainbow": false, "light": Color(1, 0.7, 0.3)},
	{"id": "fireworks", "name": "Pháo hoa", "colors": [Color(1, 1, 1, 1), Color(1, 1, 1, 0.9), Color(1, 1, 1, 0)],
		"amount": 110, "life": 1.3, "speed": 24.0, "gravity": -9.0, "shape": "ball", "rainbow": true, "light": Color(1, 0.85, 1)},
	{"id": "confetti", "name": "Kim tuyến", "colors": [Color(1, 1, 1, 1), Color(1, 1, 1, 1), Color(1, 1, 1, 0)],
		"amount": 90, "life": 1.8, "speed": 12.0, "gravity": -3.0, "shape": "flake", "rainbow": true, "light": Color(1, 0.95, 0.8)},
	{"id": "plasma", "name": "Điện", "colors": [Color(1, 1, 1, 1), Color(0.35, 0.85, 1, 0.9), Color(0.1, 0.2, 0.6, 0)],
		"amount": 70, "life": 0.55, "speed": 26.0, "gravity": 0.0, "shape": "ball", "rainbow": false, "light": Color(0.4, 0.8, 1)},
]

## colors: a puff's colour over its life. rainbow: the hue cycles while the rocket flies.
const TRAILS := [
	{"id": "smoke", "name": "Khói", "colors": [Color(1, 0.95, 0.75, 0.9), Color(0.8, 0.85, 0.85, 0.0)],
		"life": 1.1, "size": 1.0, "shape": "ball", "rainbow": false, "amount": 90},
	{"id": "fire", "name": "Lửa", "colors": [Color(1, 0.95, 0.55, 1), Color(1, 0.42, 0.1, 0.8), Color(0.35, 0.08, 0.05, 0)],
		"life": 0.6, "size": 1.5, "shape": "ball", "rainbow": false, "amount": 120},
	{"id": "rainbow", "name": "Cầu vồng", "colors": [Color(1, 1, 1, 0.95), Color(1, 1, 1, 0.0)],
		"life": 1.4, "size": 1.2, "shape": "ball", "rainbow": true, "amount": 120},
	{"id": "sparkle", "name": "Lấp lánh", "colors": [Color(1, 1, 0.85, 1), Color(1, 0.8, 0.35, 0.9), Color(1, 0.7, 0.2, 0)],
		"life": 1.5, "size": 0.6, "shape": "flake", "rainbow": false, "amount": 140},
]


static func list(kind: String) -> Array:
	match kind:
		"board":
			return BOARDS
		"mark":
			return MARKS
		"blast":
			return BLASTS
	return TRAILS


static func index_of(kind: String, id: String) -> int:
	var all := list(kind)
	for i in all.size():
		if all[i]["id"] == id:
			return i
	return 0


static func find(kind: String, id: String) -> Dictionary:
	return list(kind)[index_of(kind, id)]


static func defaults() -> Dictionary:
	var out := {}
	for kind in KINDS:
		out[kind] = list(kind)[0]["id"]
	return out


## Any value (possibly from the network) -> a valid loadout.
static func sanitize(v: Variant) -> Dictionary:
	var out := defaults()
	if v is Dictionary:
		for kind in KINDS:
			var id := str((v as Dictionary).get(kind, ""))
			out[kind] = find(kind, id)["id"]
	return out


## A random loadout (the bot dresses up too).
static func random(rng: RandomNumberGenerator) -> Dictionary:
	var out := {}
	for kind in KINDS:
		var all := list(kind)
		out[kind] = all[rng.randi_range(0, all.size() - 1)]["id"]
	return out
