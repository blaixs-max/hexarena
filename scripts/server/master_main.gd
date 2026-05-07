extends Node

## Dedicated WebSocket Master Server entry point.
##
## Usage (local dev):
##   godot --headless --path . scenes/server/master_main.tscn
##
## Usage (Oracle Cloud / production):
##   godot --headless --path /opt/hexarena scenes/server/master_main.tscn -- --port 7777
##
## Configuration via CLI args:
##   --port <number>   WebSocket server port (default 7777)
##
## Production deploy:
## - Reverse proxy (Caddy/Nginx) ile TLS termination yap
## - wss:// üzerinden serve et (Cloudflare Tunnel ile otomatik)

const DEFAULT_PORT := 7777
const MatchScene := preload("res://scenes/match/match.tscn")

func _ready() -> void:
	var port: int = _parse_port_arg()
	print("[MasterServer] Booting HexArena dedicated server...")
	print("[MasterServer] WebSocket port: %d" % port)
	if not Network.start_dedicated_server(port, true):
		push_error("[MasterServer] Failed to start. Exiting.")
		get_tree().quit(1)
		return
	print("[MasterServer] Server up. Waiting for clients on port %d..." % port)
	# Mevcut match flow'u kullan: match.tscn dedicated mode'da çalışır
	var match_node: Node = MatchScene.instantiate()
	get_tree().root.call_deferred("add_child", match_node)
	# Bu node'u tree'den çıkar (artık sadece match aktif)
	queue_free()

func _parse_port_arg() -> int:
	var args: PackedStringArray = OS.get_cmdline_args()
	for i in args.size():
		if args[i] == "--port" and i + 1 < args.size():
			return int(args[i + 1])
	return DEFAULT_PORT
