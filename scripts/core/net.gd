extends Node
## Networking over WebSocket so browsers and desktop builds can share one room.
## A headless "referee" server (godot --headless -- --server) owns the match; players connect
## to ws://<server>:24571. Registered as the "Net" autoload.

signal joined_host      ## client: connection to the server is up
signal join_failed      ## client: could not reach the server
signal host_lost        ## client: the server went away

const PORT := 24571

var player_name := ""
var last_address := "127.0.0.1"


func _ready() -> void:
	var user := OS.get_environment("USER")
	if user != "":
		player_name = user.substr(0, 16)
	if player_name == "":
		player_name = Loc.t("Người chơi")
	if Prefs.player_name != "":
		player_name = Prefs.player_name
	if Prefs.address != "":
		last_address = Prefs.address
	multiplayer.connected_to_server.connect(func() -> void: joined_host.emit())
	multiplayer.connection_failed.connect(func() -> void: join_failed.emit())
	multiplayer.server_disconnected.connect(func() -> void: host_lost.emit())


func is_online() -> bool:
	var peer := multiplayer.multiplayer_peer
	return peer != null and not (peer is OfflineMultiplayerPeer) \
		and peer.get_connection_status() != MultiplayerPeer.CONNECTION_DISCONNECTED


func serve(port: int = PORT) -> Error:
	close()
	var peer := WebSocketMultiplayerPeer.new()
	var err := peer.create_server(port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	return OK


func connect_to(address: String, port: int = PORT) -> Error:
	close()
	last_address = address
	Prefs.address = address
	Prefs.save()
	var url := address
	if not "://" in address:
		var host := address
		if ":" not in host:
			if not OS.has_feature("web"):
				host += ":%d" % port
			elif _page("port") != "":
				host += ":" + _page("port")   # on the web the game socket goes through the page's own port...
			# ...and a page on the default port (https://domain/) needs none: wss://domain
		url = "%s://%s" % ["wss" if _page("protocol") == "https:" else "ws", host]
	var peer := WebSocketMultiplayerPeer.new()
	var err := peer.create_client(url)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	return OK


func close() -> void:
	var peer := multiplayer.multiplayer_peer
	if peer != null and not (peer is OfflineMultiplayerPeer):
		peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()


## On the web the server is whoever served the page (host:port); on desktop, the last address used.
func default_address() -> String:
	if on_itch():
		return last_address if "://" in last_address else ""   # itch has no game server of its own
	if OS.has_feature("web") and _page("host") != "":
		return _page("host")
	return last_address


## True when the web build is running inside an itch.io page (a static host with no game server).
func on_itch() -> bool:
	var h := _page("hostname")
	return h.ends_with("itch.zone") or h.ends_with("itch.io")


func _page(prop: String) -> String:
	if not OS.has_feature("web"):
		return ""
	var v: Variant = JavaScriptBridge.eval("window.location.%s" % prop)
	return str(v) if v != null else ""


## Private IPv4 addresses of this machine, for telling a friend where to connect.
func local_addresses() -> PackedStringArray:
	var out := PackedStringArray()
	for a: String in IP.get_local_addresses():
		if a.count(".") == 3 and not a.begins_with("127.") and not a.begins_with("169.254."):
			out.append(a)
	return out
