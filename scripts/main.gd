extends Node
## Entry point. Always creates the "Lobby" (room directory). With --server it runs the headless
## referee and nothing else; otherwise it also builds the match controller ("Game") and the UI.


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("--lang=") or a.begins_with("--diff=") or a == "--nowarn" or a.begins_with("--skin="):
			Prefs.test_mode = true
		if a.begins_with("--lang="):
			Prefs.language = a.get_slice("=", 1) if a.get_slice("=", 1) in Loc.LANGS else "vi"   # test only: not saved
		elif a.begins_with("--skin="):   # test only: board,mark,blast,trail ids
			var ids := a.get_slice("=", 1).split(",")
			var want := {}
			for i in mini(ids.size(), Skins.KINDS.size()):
				want[Skins.KINDS[i]] = ids[i]
			Prefs.skins = Skins.sanitize(want)
		elif a == "--nowarn":
			Prefs.hide_warning = true   # test only: not saved
	var lobby := Lobby.new()
	lobby.name = "Lobby"
	add_child(lobby)

	if "--server" in args:
		var port := Net.PORT
		for a in args:
			if a.begins_with("--port="):
				port = int(a.get_slice("=", 1))
			elif a.begins_with("--autoquit="):
				get_tree().create_timer(float(a.get_slice("=", 1))).timeout.connect(func() -> void: get_tree().quit())
		if not lobby.start_server(port):
			get_tree().quit(1)
		return

	var game := Game.new()
	game.name = "Game"
	game.lobby = lobby
	lobby.game = game
	add_child(game)
	var ui := Ui.new()
	ui.name = "Ui"
	add_child(ui)
	game.bind_ui(ui)
	game.run_cli(args)
