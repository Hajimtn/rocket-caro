extends Node
## Player preferences, saved to user://settings.cfg (browser storage on the web build).
## Registered as the "Prefs" autoload; must load before "Net".

const PATH := "user://settings.cfg"

var player_name := ""
var address := ""
var sensitivity := 1.0   ## multiplier on mouse look
var volume := 0.8        ## 0..1 master volume
var test_mode := false      ## set by the --diff/--lang/--nowarn test flags: never write the settings file
var language := "vi"       ## "vi" or "en"
var hide_warning := false   ## skip the health-warning screen at start-up
var difficulty := Rules.DIFF_HARD   ## last chosen difficulty (offline games and rooms you create)
var skins := Skins.defaults()       ## chosen cosmetics, see Skins
var token := ""                     ## account login (see Account); empty when playing as a guest


func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) == OK:
		var saved := {}
		for kind in Skins.KINDS:
			saved[kind] = cfg.get_value("skins", kind, "")
		skins = Skins.sanitize(saved)
		player_name = str(cfg.get_value("player", "name", ""))
		address = str(cfg.get_value("net", "address", ""))
		sensitivity = clampf(float(cfg.get_value("input", "sensitivity", 1.0)), 0.3, 2.5)
		volume = clampf(float(cfg.get_value("audio", "volume", 0.8)), 0.0, 1.0)
		language = str(cfg.get_value("ui", "language", "vi"))
		if language not in Loc.LANGS:
			language = "vi"
		hide_warning = bool(cfg.get_value("ui", "hide_warning", false))
		token = str(cfg.get_value("account", "token", ""))
		difficulty = clampi(int(cfg.get_value("game", "difficulty", Rules.DIFF_HARD)), 0, Rules.DIFF_INSANE)
	apply_volume()


func apply_volume() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(volume) if volume > 0.001 else -80.0)


func save() -> void:
	if test_mode:
		return
	var cfg := ConfigFile.new()
	cfg.set_value("player", "name", player_name)
	cfg.set_value("net", "address", address)
	cfg.set_value("input", "sensitivity", sensitivity)
	cfg.set_value("audio", "volume", volume)
	cfg.set_value("game", "difficulty", difficulty)
	cfg.set_value("ui", "language", language)
	cfg.set_value("ui", "hide_warning", hide_warning)
	cfg.set_value("account", "token", token)
	for kind in Skins.KINDS:
		cfg.set_value("skins", kind, skins[kind])
	cfg.save(PATH)
