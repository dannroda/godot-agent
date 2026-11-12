extends Node2D
## Fixture de run_scene con varias instancias (m11-50): sin args es el server; con --client se conecta
## a él. El puerto sale de GODOT_AGENT_FIXTURE_PORT (el check lo elige al azar).

var role := "solo"
var peer_count := 0
var connected := false
var user_dir := ""


func _ready() -> void:
	user_dir = OS.get_user_data_dir()
	var port := int(OS.get_environment("GODOT_AGENT_FIXTURE_PORT"))
	if port <= 0:
		return
	var peer := ENetMultiplayerPeer.new()
	if "--client" in OS.get_cmdline_user_args():
		role = "client"
		peer.create_client("127.0.0.1", port)
		multiplayer.connected_to_server.connect(func() -> void: connected = true)
		push_error("fixture client error")
	else:
		role = "server"
		peer.create_server(port)
		multiplayer.peer_connected.connect(func(id: int) -> void:
			# Un cliente que muere sin avisar se nota en ~2 s y no en los 30 de ENet.
			(multiplayer.multiplayer_peer as ENetMultiplayerPeer).get_peer(id).set_timeout(500, 1000, 2000)
			peer_count = multiplayer.get_peers().size())
		multiplayer.peer_disconnected.connect(func(_id: int) -> void: peer_count = multiplayer.get_peers().size())
	multiplayer.multiplayer_peer = peer
