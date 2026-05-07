extends Node

signal lobby_changed
signal joined_lobby
signal left_lobby
signal connect_failed
signal match_starting
signal rooms_updated

const DEFAULT_PORT := 7777
const DISCOVERY_PORT := 7779
const DISCOVERY_PORTS := [7779, 7780, 7781, 7782, 7783]
const MAX_PLAYERS := 6
const BROADCAST_INTERVAL := 1.0
const ROOM_TIMEOUT := 3.5

enum Mode { OFFLINE, HOST, CLIENT }

class RoomInfo:
	var room_id: String
	var name: String
	var host_name: String
	var ip: String
	var port: int
	var player_count: int
	var max_players: int
	var state: String
	var last_seen: float

var mode := Mode.OFFLINE
var peer: ENetMultiplayerPeer = null
var local_name := "Player"
var connected_peers: Array[int] = []
var is_dedicated := false
var connecting_to_dedicated := false
var public_server_ip := "127.0.0.1"

var _broadcast_socket: PacketPeerUDP = null
var _discovery_socket: PacketPeerUDP = null
var _broadcast_timer := 0.0
var _room_state := "BEKLIYOR"
var _own_broadcast_id := ""

var discovered_rooms: Dictionary = {}

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	start_discovery()

func _process(delta: float) -> void:
	if mode == Mode.HOST and _broadcast_socket:
		_broadcast_timer -= delta
		if _broadcast_timer <= 0.0:
			_broadcast_timer = BROADCAST_INTERVAL
			_send_broadcast()
	if _discovery_socket:
		while _discovery_socket.get_available_packet_count() > 0:
			_read_one_discovery()
		_cleanup_stale_rooms()

func host_game(port: int = DEFAULT_PORT) -> bool:
	_close_existing()
	peer = ENetMultiplayerPeer.new()
	var err: int = peer.create_server(port, MAX_PLAYERS)
	if err != OK:
		push_error("Host failed: %d" % err)
		peer = null
		return false
	multiplayer.multiplayer_peer = peer
	mode = Mode.HOST
	connected_peers = [1]
	_own_broadcast_id = "%s:%d" % [_local_ip(), port]
	if not is_dedicated:
		_open_broadcast_socket()
	lobby_changed.emit()
	print("[Net] Hosting on port %d (dedicated=%s)" % [port, is_dedicated])
	return true

func start_dedicated_server(port: int = DEFAULT_PORT) -> bool:
	is_dedicated = true
	return host_game(port)

func join_game(ip: String, port: int = DEFAULT_PORT) -> bool:
	_close_existing()
	peer = ENetMultiplayerPeer.new()
	var err: int = peer.create_client(ip, port)
	if err != OK:
		push_error("Join failed: %d" % err)
		peer = null
		return false
	multiplayer.multiplayer_peer = peer
	mode = Mode.CLIENT
	print("[Net] Connecting to %s:%d" % [ip, port])
	return true

func join_dedicated_server(ip: String, port: int = DEFAULT_PORT) -> bool:
	connecting_to_dedicated = true
	return join_game(ip, port)

func leave() -> void:
	_close_existing()
	mode = Mode.OFFLINE
	is_dedicated = false
	connecting_to_dedicated = false
	connected_peers.clear()
	left_lobby.emit()

func is_online() -> bool:
	return mode != Mode.OFFLINE and multiplayer.multiplayer_peer != null

func is_host() -> bool:
	return mode == Mode.HOST

func is_client() -> bool:
	return mode == Mode.CLIENT

func get_my_id() -> int:
	if not is_online():
		return 0
	return multiplayer.get_unique_id()

func set_room_state(s: String) -> void:
	_room_state = s

func _close_existing() -> void:
	if peer:
		peer.close()
		peer = null
	multiplayer.multiplayer_peer = null
	if _broadcast_socket:
		_broadcast_socket.close()
		_broadcast_socket = null
	_own_broadcast_id = ""

func _open_broadcast_socket() -> void:
	_broadcast_socket = PacketPeerUDP.new()
	_broadcast_socket.set_broadcast_enabled(true)
	_broadcast_timer = 0.0

func start_discovery() -> bool:
	if _discovery_socket:
		return true
	for port in DISCOVERY_PORTS:
		var sock := PacketPeerUDP.new()
		sock.set_broadcast_enabled(true)
		var err: int = sock.bind(port)
		if err == OK:
			_discovery_socket = sock
			print("[Net] Discovery listening on port %d" % port)
			return true
		sock.close()
	push_warning("[Net] Tüm discovery portları dolu — manuel IP gerek")
	return false

func stop_discovery() -> void:
	if _discovery_socket:
		_discovery_socket.close()
		_discovery_socket = null

func _send_broadcast() -> void:
	if _broadcast_socket == null:
		return
	var data := {
		"v": 1,
		"name": "%s'in Odası" % local_name,
		"host_name": local_name,
		"port": DEFAULT_PORT,
		"players": connected_peers.size(),
		"max": MAX_PLAYERS,
		"state": _room_state,
		"id": _own_broadcast_id,
	}
	var bytes := JSON.stringify(data).to_utf8_buffer()
	for port in DISCOVERY_PORTS:
		_broadcast_socket.set_dest_address("255.255.255.255", port)
		_broadcast_socket.put_packet(bytes)
		_broadcast_socket.set_dest_address("127.0.0.1", port)
		_broadcast_socket.put_packet(bytes)

func _read_one_discovery() -> void:
	var bytes: PackedByteArray = _discovery_socket.get_packet()
	var sender_ip: String = _discovery_socket.get_packet_ip()
	var json_str: String = bytes.get_string_from_utf8()
	var json := JSON.new()
	if json.parse(json_str) != OK:
		return
	var data: Variant = json.data
	if not (data is Dictionary):
		return
	var port_val: int = int(data.get("port", DEFAULT_PORT))
	var room := RoomInfo.new()
	room.port = port_val
	room.room_id = "%s:%d" % [sender_ip, port_val]
	if mode == Mode.HOST and _own_broadcast_id == room.room_id:
		return
	room.name = str(data.get("name", "Oda"))
	room.host_name = str(data.get("host_name", "Host"))
	room.ip = sender_ip
	room.player_count = int(data.get("players", 1))
	room.max_players = int(data.get("max", MAX_PLAYERS))
	room.state = str(data.get("state", "BEKLIYOR"))
	room.last_seen = Time.get_ticks_msec() / 1000.0
	discovered_rooms[room.room_id] = room
	rooms_updated.emit()

func _cleanup_stale_rooms() -> void:
	var now: float = Time.get_ticks_msec() / 1000.0
	var changed: bool = false
	for id in discovered_rooms.keys():
		if now - (discovered_rooms[id] as RoomInfo).last_seen > ROOM_TIMEOUT:
			discovered_rooms.erase(id)
			changed = true
	if changed:
		rooms_updated.emit()

func _local_ip() -> String:
	for ip in IP.get_local_addresses():
		if ip.begins_with("192.168.") or ip.begins_with("10.") or ip.begins_with("172."):
			return ip
	return "127.0.0.1"

func _on_peer_connected(id: int) -> void:
	if not connected_peers.has(id):
		connected_peers.append(id)
	lobby_changed.emit()

func _on_peer_disconnected(id: int) -> void:
	connected_peers.erase(id)
	lobby_changed.emit()

func _on_connected_to_server() -> void:
	connected_peers = [1, multiplayer.get_unique_id()]
	joined_lobby.emit()
	lobby_changed.emit()

func _on_connection_failed() -> void:
	connect_failed.emit()
	leave()

func _on_server_disconnected() -> void:
	leave()
