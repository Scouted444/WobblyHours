extends Node
## Networking + player registry (autoload "Net").
## Transport is plain ENet. Hosting opens the router port by itself (UPnP) and makes an invite code
## (Net.link, see scenes/net/connectivity.gd); friends paste the code to join, no VPN needed.
## Plain IPs (LAN, Radmin / Hamachi / Tailscale) still work in the join box.

signal player_joined(id: int)   # emitted on the server only
signal player_left(id: int)     # emitted on the server only
signal players_changed
signal disconnected(reason: String)
signal map_changed

const PORT := 24680
const MAX_PLAYERS := 16

var my_name := "Player"
var my_look := {}  # this player's customization (see scenes/player/look.gd)
var players := {}  # peer_id -> { "name": String }
var map := {}      # {"id": workshop map id or "", "mode": "sandbox" / "campaign"} chosen by the host
var mode := "sandbox"   # what the host picked on the main menu (sent to everyone in `map`)
var link: Connectivity  # router port, invite codes, LAN discovery
var quiet_fail := false # joining: trying several addresses, don't give up on the first failure

func _ready() -> void:
	link = Connectivity.new()
	link.name = "Link"
	add_child(link)
	my_look = Look.load_saved()
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)

# ------------------------------------------------------------------ connect
func host() -> bool:
	var peer := ENetMultiplayerPeer.new()
	if peer.create_server(PORT, MAX_PLAYERS) != OK:
		return false
	multiplayer.multiplayer_peer = peer
	players = {1: {"name": my_name, "look": Look.sanitize(my_look)}}
	map = {"id": Content.selected_map, "mode": mode}
	players_changed.emit()
	link.start_host()
	return true

func join(ip: String, port := PORT) -> bool:
	ip = ip.strip_edges()
	if ip.is_empty():
		return false
	var peer := ENetMultiplayerPeer.new()
	if peer.create_client(ip, port) != OK:
		return false
	multiplayer.multiplayer_peer = peer
	return true

func leave() -> void:
	link.stop_host()
	if multiplayer.multiplayer_peer != null:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	players.clear()
	map = {}

# ----------------------------------------------------------------- registry
func _on_connected() -> void:
	_register.rpc_id(1, my_name, my_look)

@rpc("any_peer", "call_remote", "reliable")
func _register(pname: String, look: Dictionary = {}) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	players[id] = {"name": pname.strip_edges().left(16), "look": Look.sanitize(look)}
	_sync_players.rpc(players)
	_set_map.rpc_id(id, map)
	player_joined.emit(id)

@rpc("authority", "call_remote", "reliable")
func _set_map(m: Dictionary) -> void:
	var id := str(m.get("id", ""))
	map = {"id": id if Look.is_model_id(id) else "", "mode": "campaign" if str(m.get("mode", "")) == "campaign" else "sandbox"}
	map_changed.emit()

## Campaign mode: no spawning, no free money; you earn cash doing jobs.
func is_campaign() -> bool:
	return str(map.get("mode", "sandbox")) == "campaign"

## Which peer has this model file (a player's character, or the host's map)?
func owner_of_model(id: String) -> int:
	for pid in players:
		if str(players[pid].get("look", {}).get("model", "")) == id:
			return int(pid)
	if str(map.get("id", "")) == id:
		return 1
	return 0

@rpc("authority", "call_local", "reliable")
func _sync_players(all_players: Dictionary) -> void:
	players = all_players
	players_changed.emit()

func _on_peer_disconnected(id: int) -> void:
	if multiplayer.is_server():
		players.erase(id)
		_sync_players.rpc(players)
		player_left.emit(id)

func _on_connection_failed() -> void:
	if quiet_fail:
		return   # main.gd moves on to the next address in the invite
	leave()
	disconnected.emit("Could not connect to that host")

func _on_server_disconnected() -> void:
	leave()
	disconnected.emit("The host closed the party")

## Change my look. Saves it, and tells everyone if we're in a party.
func set_my_look(look: Dictionary) -> void:
	my_look = Look.sanitize(look)
	Look.save(my_look)
	if multiplayer.multiplayer_peer != null and players.has(multiplayer.get_unique_id()):
		update_look.rpc_id(1, my_look)

@rpc("any_peer", "call_local", "reliable")
func update_look(look: Dictionary) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if id == 0:
		id = 1
	if players.has(id):
		players[id]["look"] = Look.sanitize(look)
		_sync_players.rpc(players)
