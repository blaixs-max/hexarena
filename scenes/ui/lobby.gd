extends Control

enum State { MAIN, MP_MENU, JOIN_INPUT, LOBBY_ROOM, CONNECTING, ERROR }

var state: State = State.MAIN

@onready var main_panel: Control = $Panels/MainPanel
@onready var mp_panel: Control = $Panels/MPPanel
@onready var join_panel: Control = $Panels/JoinPanel
@onready var room_panel: Control = $Panels/RoomPanel
@onready var connecting_panel: Control = $Panels/ConnectingPanel

@onready var title_label: Label = $Header/Title
@onready var subtitle_label: Label = $Header/Subtitle

@onready var quick_match_btn: Button = $Panels/MainPanel/VBox/QuickMatch
@onready var multiplayer_btn: Button = $Panels/MainPanel/VBox/Multiplayer
@onready var profile_btn: Button = $Panels/MainPanel/VBox/Profile
@onready var settings_btn: Button = $Panels/MainPanel/VBox/Settings
@onready var quit_btn: Button = $Panels/MainPanel/VBox/Quit

@onready var play_friends_btn: Button = $Panels/MPPanel/VBox/PlayFriends
@onready var quick_match_mp_btn: Button = $Panels/MPPanel/VBox/QuickMatchMP
@onready var custom_match_btn: Button = $Panels/MPPanel/VBox/CustomMatch
@onready var mp_back_btn: Button = $Panels/MPPanel/VBox/Back
@onready var online_server_btn: Button = $Panels/MPPanel/VBox/OnlineServer

@onready var host_btn: Button = $Panels/JoinPanel/VBox/HostRoom
@onready var rooms_container: VBoxContainer = $Panels/JoinPanel/VBox/RoomsScroll/RoomsList
@onready var rooms_empty: Label = $Panels/JoinPanel/VBox/RoomsScroll/RoomsList/EmptyHint
@onready var manual_toggle: Button = $Panels/JoinPanel/VBox/ManualToggle
@onready var manual_box: HBoxContainer = $Panels/JoinPanel/VBox/ManualBox
@onready var ip_field: LineEdit = $Panels/JoinPanel/VBox/ManualBox/IPField
@onready var join_btn: Button = $Panels/JoinPanel/VBox/ManualBox/JoinRoom
@onready var join_back_btn: Button = $Panels/JoinPanel/VBox/Back
@onready var join_status: Label = $Panels/JoinPanel/VBox/Status

@onready var room_code_label: Label = $Panels/RoomPanel/Inner/RoomHeader/RoomCode
@onready var room_ip_label: Label = $Panels/RoomPanel/Inner/RoomHeader/RoomIP
@onready var home_slots: HBoxContainer = $Panels/RoomPanel/Inner/Teams/HomeTeam/Slots
@onready var away_slots: HBoxContainer = $Panels/RoomPanel/Inner/Teams/AwayTeam/Slots
@onready var start_match_btn: Button = $Panels/RoomPanel/Inner/Actions/StartMatch
@onready var leave_room_btn: Button = $Panels/RoomPanel/Inner/Actions/Leave

@onready var connecting_status: Label = $Panels/ConnectingPanel/VBox/Status

const COLOR_HOME := Color(0.92, 0.41, 0.18)
const COLOR_AWAY := Color(0.27, 0.55, 0.94)
const COLOR_GOLD := Color(0.95, 0.78, 0.22)
const COLOR_TEXT_DIM := Color(0.65, 0.7, 0.85, 1)
const COLOR_TEXT := Color(0.92, 0.94, 0.98, 1)

func _ready() -> void:
	if "--server" in OS.get_cmdline_args():
		_start_dedicated()
		return
	quick_match_btn.pressed.connect(_on_quick_match)
	multiplayer_btn.pressed.connect(func(): _set_state(State.MP_MENU))
	profile_btn.pressed.connect(_on_coming_soon.bind("Profil"))
	settings_btn.pressed.connect(_on_coming_soon.bind("Ayarlar"))
	quit_btn.pressed.connect(_on_quit)
	play_friends_btn.pressed.connect(func(): _set_state(State.JOIN_INPUT))
	quick_match_mp_btn.pressed.connect(_on_coming_soon.bind("Hızlı Eşleş"))
	custom_match_btn.pressed.connect(_on_coming_soon.bind("Özel Maç"))
	mp_back_btn.pressed.connect(func(): _set_state(State.MAIN))
	online_server_btn.pressed.connect(_on_online_server)
	host_btn.pressed.connect(_on_host)
	join_btn.pressed.connect(_on_join)
	join_back_btn.pressed.connect(func(): _set_state(State.MP_MENU))
	manual_toggle.pressed.connect(_toggle_manual)
	start_match_btn.pressed.connect(_on_start_match)
	leave_room_btn.pressed.connect(_on_leave_room)
	Network.lobby_changed.connect(_refresh_room)
	Network.joined_lobby.connect(_on_joined_lobby)
	Network.connect_failed.connect(_on_connect_failed)
	Network.left_lobby.connect(_on_left_lobby)
	Network.rooms_updated.connect(_refresh_room_list)
	ip_field.text = "127.0.0.1"
	manual_box.visible = false
	if Network.is_online():
		_set_state(State.LOBBY_ROOM)
	else:
		_set_state(State.MAIN)

func _set_state(s: State) -> void:
	state = s
	main_panel.visible = (s == State.MAIN)
	mp_panel.visible = (s == State.MP_MENU)
	join_panel.visible = (s == State.JOIN_INPUT)
	room_panel.visible = (s == State.LOBBY_ROOM)
	connecting_panel.visible = (s == State.CONNECTING)
	if s == State.LOBBY_ROOM:
		_refresh_room()
	if s == State.JOIN_INPUT:
		join_status.text = ""
		_refresh_room_list()

func _on_quick_match() -> void:
	Network.leave()
	get_tree().change_scene_to_file("res://scenes/match/match.tscn")

func _on_online_server() -> void:
	if Network.join_dedicated_server(Network.public_server_ip):
		connecting_status.text = "Sunucuya bağlanılıyor: %s..." % Network.public_server_ip
		_set_state(State.CONNECTING)
	else:
		connecting_status.text = "Sunucuya bağlantı başarısız"

func _start_dedicated() -> void:
	print("[Server] Dedicated server mode starting...")
	if Network.start_dedicated_server():
		print("[Server] Listening — clients can connect")
		get_tree().change_scene_to_file.call_deferred("res://scenes/match/match.tscn")
	else:
		push_error("[Server] Failed to start dedicated server")
		get_tree().quit()

func _on_quit() -> void:
	get_tree().quit()

func _on_coming_soon(label: String) -> void:
	if join_status:
		join_status.text = "%s — yakında" % label
	connecting_status.text = "%s yakında geliyor" % label

func _on_host() -> void:
	if Network.host_game():
		_set_state(State.LOBBY_ROOM)
	else:
		join_status.text = "Host başarısız (port dolu olabilir)"

func _on_join() -> void:
	var ip: String = ip_field.text.strip_edges()
	if ip == "":
		ip = "127.0.0.1"
	if Network.join_game(ip):
		connecting_status.text = "Bağlanılıyor: %s..." % ip
		_set_state(State.CONNECTING)
	else:
		join_status.text = "Bağlantı başarısız"

func _on_joined_lobby() -> void:
	if Network.connecting_to_dedicated:
		get_tree().change_scene_to_file.call_deferred("res://scenes/match/match.tscn")
		return
	_set_state(State.LOBBY_ROOM)

func _on_connect_failed() -> void:
	connecting_status.text = "Bağlantı başarısız"
	await get_tree().create_timer(1.4).timeout
	_set_state(State.JOIN_INPUT)

func _on_left_lobby() -> void:
	_set_state(State.MAIN)

func _toggle_manual() -> void:
	manual_box.visible = not manual_box.visible
	manual_toggle.text = "▲ Manuel IP gizle" if manual_box.visible else "▼ Manuel IP gir"

func _refresh_room_list() -> void:
	if state != State.JOIN_INPUT:
		return
	for c in rooms_container.get_children():
		if c.name == "EmptyHint":
			continue
		c.queue_free()
	var rooms: Array = Network.discovered_rooms.values()
	rooms_empty.visible = rooms.is_empty()
	for r in rooms:
		var row := _make_room_row(r)
		rooms_container.add_child(row)
		rooms_container.move_child(rooms_empty, rooms_container.get_child_count() - 1)

func _make_room_row(room) -> Control:
	var row := PanelContainer.new()
	row.custom_minimum_size = Vector2(0, 70)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.10, 0.16, 0.92)
	sb.border_width_left = 2
	sb.border_width_top = 2
	sb.border_width_right = 2
	sb.border_width_bottom = 2
	sb.border_color = Color(0.25, 0.32, 0.45, 1)
	sb.set_corner_radius_all(14)
	row.add_theme_stylebox_override("panel", sb)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	row.add_child(hb)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(info)
	var name_lbl := Label.new()
	name_lbl.text = room.name
	name_lbl.add_theme_font_size_override("font_size", 22)
	name_lbl.add_theme_color_override("font_color", COLOR_GOLD)
	info.add_child(name_lbl)
	var detail := Label.new()
	var state_color := Color(0.4, 0.95, 0.5, 1) if room.state == "BEKLIYOR" else Color(0.95, 0.7, 0.4, 1)
	detail.text = "%d / %d  •  %s  •  %s" % [room.player_count, room.max_players, room.state, room.ip]
	detail.add_theme_font_size_override("font_size", 16)
	detail.add_theme_color_override("font_color", state_color)
	info.add_child(detail)
	var join_btn_dyn := Button.new()
	join_btn_dyn.custom_minimum_size = Vector2(120, 50)
	join_btn_dyn.text = "KATIL"
	var sb_btn := StyleBoxFlat.new()
	sb_btn.bg_color = Color(0.96, 0.62, 0.20, 1)
	sb_btn.set_corner_radius_all(14)
	join_btn_dyn.add_theme_stylebox_override("normal", sb_btn)
	join_btn_dyn.add_theme_color_override("font_color", Color.WHITE)
	join_btn_dyn.add_theme_font_size_override("font_size", 18)
	join_btn_dyn.disabled = (room.state != "BEKLIYOR" or room.player_count >= room.max_players)
	join_btn_dyn.pressed.connect(func(): _join_specific_room(room))
	hb.add_child(join_btn_dyn)
	return row

func _join_specific_room(room) -> void:
	if Network.join_game(room.ip, room.port):
		connecting_status.text = "Bağlanılıyor: %s..." % room.name
		_set_state(State.CONNECTING)

func _on_leave_room() -> void:
	Network.leave()

func _on_start_match() -> void:
	if not Network.is_host():
		return
	rpc("_remote_start_match")
	_remote_start_match()

@rpc("authority", "call_local", "reliable")
func _remote_start_match() -> void:
	get_tree().change_scene_to_file("res://scenes/match/match.tscn")

func _refresh_room() -> void:
	if state != State.LOBBY_ROOM:
		return
	if Network.is_host():
		room_code_label.text = "ODA AÇIK"
		room_ip_label.text = "Senin IP'in: %s  •  Port: %d" % [_local_ip_hint(), Network.DEFAULT_PORT]
	else:
		room_code_label.text = "ODADASIN"
		room_ip_label.text = "Host'un başlatması bekleniyor"
	_build_team_slots(home_slots, MatchState.TEAM_HOME)
	_build_team_slots(away_slots, MatchState.TEAM_AWAY)
	start_match_btn.visible = Network.is_host()
	start_match_btn.disabled = Network.connected_peers.size() < 1

func _local_ip_hint() -> String:
	for ip in IP.get_local_addresses():
		if ip.begins_with("192.168.") or ip.begins_with("10.") or ip.begins_with("172."):
			return ip
	return "lokal"

func _build_team_slots(container: HBoxContainer, team: int) -> void:
	for c in container.get_children():
		c.queue_free()
	var col: Color = COLOR_HOME if team == MatchState.TEAM_HOME else COLOR_AWAY
	var peers: Array = Network.connected_peers.duplicate()
	peers.sort()
	for slot in 3:
		var slot_index: int = slot * 2 + (0 if team == MatchState.TEAM_HOME else 1)
		var card := _make_slot_card(col, slot_index, peers)
		container.add_child(card)

func _make_slot_card(team_color: Color, slot_index: int, peers: Array) -> Control:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(160, 200)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.09, 0.13, 0.92)
	sb.border_width_left = 3
	sb.border_width_top = 3
	sb.border_width_right = 3
	sb.border_width_bottom = 3
	sb.border_color = team_color
	sb.set_corner_radius_all(16)
	sb.shadow_color = Color(0, 0, 0, 0.4)
	sb.shadow_size = 8
	sb.shadow_offset = Vector2(0, 4)
	card.add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 12)
	card.add_child(v)
	var dot := Panel.new()
	dot.custom_minimum_size = Vector2(60, 60)
	dot.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var sb_dot := StyleBoxFlat.new()
	sb_dot.bg_color = team_color
	sb_dot.set_corner_radius_all(30)
	dot.add_theme_stylebox_override("panel", sb_dot)
	v.add_child(dot)
	var name_label := Label.new()
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 22)
	name_label.add_theme_color_override("font_color", COLOR_TEXT)
	v.add_child(name_label)
	var status_label := Label.new()
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_font_size_override("font_size", 16)
	status_label.add_theme_color_override("font_color", COLOR_TEXT_DIM)
	v.add_child(status_label)
	if slot_index < peers.size():
		var peer_id: int = int(peers[slot_index])
		var is_me: bool = peer_id == Network.get_my_id()
		name_label.text = "Host" if peer_id == 1 else "Player %d" % peer_id
		if is_me:
			name_label.text += " (sen)"
			name_label.add_theme_color_override("font_color", COLOR_GOLD)
		status_label.text = "HAZIR"
		status_label.add_theme_color_override("font_color", Color(0.4, 0.95, 0.5, 1))
	else:
		name_label.text = "BOT"
		status_label.text = "boş slot"
	return card
