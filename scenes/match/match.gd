extends Node2D

const PlayerScene := preload("res://scenes/player/player.tscn")
const BallScene := preload("res://scenes/ball/ball.tscn")
const AIBrainScript := preload("res://scripts/ai/ai_brain.gd")

@onready var pitch: Pitch = $Pitch
@onready var hud: CanvasLayer = $HUD
@onready var joystick: VirtualJoystick = $HUD/Joystick
@onready var kick_button: KickButton = $HUD/RightCluster/KickButton
@onready var power_kick_button: KickButton = $HUD/RightCluster/PowerKickButton
@onready var camera: Camera2D = $Camera2D
@onready var players_root: Node2D = $Players
@onready var ball_container: Node2D = $BallContainer
@onready var player_spawner: MultiplayerSpawner = $PlayerSpawner
@onready var ball_spawner: MultiplayerSpawner = $BallSpawner

var ball: Ball
var home_players: Array[Player] = []
var away_players: Array[Player] = []
var user_player: Player

const HOME_LABELS := ["1", "6", "V"]
const AWAY_LABELS := ["FY", "5", "o)"]
const MAX_KICK_CHARGE := 0.6
const MIN_KICK_POWER := 0.22
const SHOOT_AIM_ASSIST_CONE := 0.65
const SHOOT_AIM_ASSIST_STRENGTH := 0.28

var _kick_charge_start := -1.0
var _pending_kickoff_team := -1
var _freeze_positions_active := false
var _is_online := false
var _is_authority := true

func _ready() -> void:
	_is_online = Network.is_online()
	_is_authority = (not _is_online) or Network.is_host()
	if _is_online and Network.is_host():
		Network.set_room_state("OYUNDA")
		if Network.is_dedicated:
			multiplayer.peer_connected.connect(_on_dedicated_peer_connected)
			multiplayer.peer_disconnected.connect(_on_dedicated_peer_disconnected)
		_setup_dedicated_hud_visibility()
	pitch.goal_triggered.connect(_on_goal)
	MatchState.match_ended.connect(_on_match_ended)
	MatchState.kickoff_ended.connect(_on_kickoff_ended)
	kick_button.kick_requested.connect(_on_shoot_request)
	if power_kick_button:
		power_kick_button.kick_requested.connect(_on_kick_request)
	if _is_authority:
		_setup_authority()
	else:
		_setup_client()

func _setup_authority() -> void:
	MatchState.reset_match()
	_spawn_ball()
	if ball:
		ball.owner_changed.connect(_on_ball_owner_changed)
	_spawn_team(MatchState.TEAM_HOME)
	_spawn_team(MatchState.TEAM_AWAY)
	_assign_user_control()
	_position_for_kickoff(MatchState.TEAM_HOME)
	MatchState.start_match()

func _setup_client() -> void:
	player_spawner.spawned.connect(_on_player_spawned)
	ball_spawner.spawned.connect(_on_ball_spawned)

func _on_player_spawned(p: Node) -> void:
	if not (p is Player):
		return
	var pl: Player = p as Player
	if pl.team == MatchState.TEAM_HOME:
		home_players.append(pl)
	else:
		away_players.append(pl)
	if ball and is_instance_valid(ball):
		pl.bind_ball(ball)
	if pl.input_peer_id == Network.get_my_id():
		user_player = pl
		pl.set_user_controlled(true)

func _on_ball_spawned(b: Node) -> void:
	if not (b is Ball):
		return
	ball = b as Ball
	for p in home_players:
		p.bind_ball(ball)
	for p in away_players:
		p.bind_ball(ball)

func _process(_d: float) -> void:
	if _is_authority:
		_force_freeze_positions()
		_apply_kickoff_freeze()
		if not MatchState.running:
			_freeze_after_match_end()
			return
	if _is_online and not _is_authority:
		_rebind_user_player_if_needed()
	if user_player and is_instance_valid(user_player):
		var input: Vector2 = _compose_input_vector()
		if MatchState.awaiting_kickoff_pass and user_player.team != MatchState.current_kicker:
			input = Vector2.ZERO
		if _is_online and not _is_authority:
			user_player.rpc_id(1, "remote_set_input", input)
		else:
			user_player.set_input(input)
	_handle_kick_keyboard()

func _compose_input_vector() -> Vector2:
	var stick: Vector2 = joystick.get_vector()
	var kbd: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if kbd.length_squared() > 0.001:
		var sprint: bool = Input.is_action_pressed("sprint")
		return kbd.normalized() * (1.0 if sprint else 0.7)
	return stick

func _handle_kick_keyboard() -> void:
	if Input.is_action_just_pressed("kick"):
		_kick_charge_start = Time.get_ticks_msec() / 1000.0
		if kick_button and kick_button.has_method("external_charge_start"):
			kick_button.external_charge_start()
	elif Input.is_action_just_released("kick") and _kick_charge_start >= 0.0:
		var t: float = clamp((Time.get_ticks_msec() / 1000.0 - _kick_charge_start) / MAX_KICK_CHARGE, 0.0, 1.0)
		var power: float = lerp(MIN_KICK_POWER, 1.0, t)
		_on_shoot_request(power)
		_kick_charge_start = -1.0
		if kick_button and kick_button.has_method("external_charge_release"):
			kick_button.external_charge_release()
	if InputMap.has_action("pass") and Input.is_action_just_pressed("pass"):
		_on_kick_request(0.55)

func _apply_kickoff_freeze() -> void:
	if not MatchState.awaiting_kickoff_pass:
		return
	var kicker: int = MatchState.current_kicker
	var home_pos: Array = pitch.home_positions(kicker)
	var away_pos: Array = pitch.away_positions(kicker)
	var kicker_arr: Array[Player] = home_players if kicker == MatchState.TEAM_HOME else away_players
	var opposing_arr: Array[Player] = away_players if kicker == MatchState.TEAM_HOME else home_players
	var opposing_positions: Array = away_pos if kicker == MatchState.TEAM_HOME else home_pos
	var kicker_positions: Array = home_pos if kicker == MatchState.TEAM_HOME else away_pos
	for i in opposing_arr.size():
		var p: Player = opposing_arr[i]
		if is_instance_valid(p) and i < opposing_positions.size():
			p.global_position = opposing_positions[i]
			p.linear_velocity = Vector2.ZERO
			p.angular_velocity = 0.0
	for i in kicker_arr.size():
		var p: Player = kicker_arr[i]
		if is_instance_valid(p) and i < kicker_positions.size():
			p.global_position = kicker_positions[i]
			p.linear_velocity = Vector2.ZERO
			p.angular_velocity = 0.0
	if kicker_arr.size() > 0 and ball and is_instance_valid(ball):
		var striker: Player = kicker_arr[0]
		if is_instance_valid(striker) and ball.owner_player != striker:
			ball.acquire(striker)

func _force_freeze_positions() -> void:
	if not _freeze_positions_active:
		return
	if _pending_kickoff_team < 0:
		_freeze_positions_active = false
		return
	if not MatchState.is_frozen():
		_freeze_positions_active = false
		return
	var kicker: int = _pending_kickoff_team
	var home_pos: Array = pitch.home_positions(kicker)
	var away_pos: Array = pitch.away_positions(kicker)
	for i in home_players.size():
		if is_instance_valid(home_players[i]):
			home_players[i].global_position = home_pos[i]
			home_players[i].linear_velocity = Vector2.ZERO
			home_players[i].angular_velocity = 0.0
	for i in away_players.size():
		if is_instance_valid(away_players[i]):
			away_players[i].global_position = away_pos[i]
			away_players[i].linear_velocity = Vector2.ZERO
			away_players[i].angular_velocity = 0.0
	if ball and is_instance_valid(ball):
		ball.global_position = pitch.ball_spawn()
		ball.linear_velocity = Vector2.ZERO
		ball.angular_velocity = 0.0
		if ball.owner_player != null:
			ball.release(0.0)

func _spawn_ball() -> void:
	ball = BallScene.instantiate() as Ball
	ball_container.add_child(ball, true)
	ball.global_position = pitch.ball_spawn()

func _spawn_team(team: int) -> void:
	var positions: Array = pitch.home_positions(MatchState.TEAM_HOME) if team == MatchState.TEAM_HOME else pitch.away_positions(MatchState.TEAM_AWAY)
	var labels: Array = HOME_LABELS if team == MatchState.TEAM_HOME else AWAY_LABELS
	for i in 3:
		var p: Player = PlayerScene.instantiate() as Player
		p.team = team
		p.label_text = labels[i]
		p.input_peer_id = _peer_for_slot(team, i)
		players_root.add_child(p, true)
		p.global_position = positions[i]
		p.bind_ball(ball)
		if team == MatchState.TEAM_HOME:
			home_players.append(p)
		else:
			away_players.append(p)

func _peer_for_slot(team: int, slot: int) -> int:
	if not _is_online:
		if team == MatchState.TEAM_HOME and slot == 0:
			return 1
		return 0
	var peers: Array = Network.connected_peers.duplicate()
	if Network.is_dedicated:
		peers.erase(1)
	peers.sort()
	var slot_index: int = slot * 2 + (0 if team == MatchState.TEAM_HOME else 1)
	if slot_index < peers.size():
		return int(peers[slot_index])
	return 0

func _assign_user_control() -> void:
	var my_id: int = 1 if not _is_online else Network.get_my_id()
	for p in home_players:
		if p.input_peer_id == my_id:
			user_player = p
			user_player.set_user_controlled(true)
			break
	if user_player == null:
		for p in away_players:
			if p.input_peer_id == my_id:
				user_player = p
				user_player.set_user_controlled(true)
				break
	for p in home_players + away_players:
		if p.input_peer_id == 0:
			_attach_ai(p, p.team, _ai_role_for(p))

func _ai_role_for(p: Player) -> int:
	var arr: Array[Player] = home_players if p.team == MatchState.TEAM_HOME else away_players
	var idx: int = arr.find(p)
	return [0, 1, 2][idx] if idx >= 0 and idx < 3 else 1

func _attach_ai(p: Player, team: int, role: int) -> void:
	var brain := Node.new()
	brain.set_script(AIBrainScript)
	p.add_child(brain)
	var own_goal: Vector2 = Vector2(-840, 0) if team == MatchState.TEAM_HOME else Vector2(840, 0)
	var enemy_goal: Vector2 = Vector2(840, 0) if team == MatchState.TEAM_HOME else Vector2(-840, 0)
	(brain as AIBrain).setup(p, ball, own_goal, enemy_goal, role)

func _position_for_kickoff(kicker_team: int) -> void:
	var home_pos: Array = pitch.home_positions(kicker_team)
	var away_pos: Array = pitch.away_positions(kicker_team)
	for i in home_players.size():
		home_players[i].global_position = home_pos[i]
		home_players[i].linear_velocity = Vector2.ZERO
	for i in away_players.size():
		away_players[i].global_position = away_pos[i]
		away_players[i].linear_velocity = Vector2.ZERO
	if ball and is_instance_valid(ball):
		ball.reset_to(pitch.ball_spawn())

func _on_goal(scoring_team: int) -> void:
	if not _is_authority:
		return
	MatchState.register_goal(scoring_team)
	if not MatchState.running:
		return
	_pending_kickoff_team = MatchState.current_kicker
	_freeze_positions_active = true

func _on_kick_request(power: float) -> void:
	if user_player == null or not is_instance_valid(user_player):
		return
	if _is_online and not _is_authority:
		user_player.rpc_id(1, "remote_kick", power)
	else:
		user_player.kick(power)

func _on_shoot_request(power: float) -> void:
	if user_player == null or not is_instance_valid(user_player):
		return
	if not user_player.can_kick():
		return
	var pos: Vector2 = user_player.global_position
	var enemy_goal: Vector2 = Vector2(840, 0) if user_player.team == MatchState.TEAM_HOME else Vector2(-840, 0)
	var facing: Vector2 = user_player.aim_dir()
	var to_goal_vec: Vector2 = enemy_goal - pos
	var final_dir: Vector2 = facing
	if to_goal_vec.length() > 0.001 and facing.length() > 0.001:
		var to_goal_n: Vector2 = to_goal_vec.normalized()
		if facing.dot(to_goal_n) > SHOOT_AIM_ASSIST_CONE:
			final_dir = facing.lerp(to_goal_n, SHOOT_AIM_ASSIST_STRENGTH).normalized()
	if _is_online and not _is_authority:
		user_player.rpc_id(1, "remote_kick_directed", final_dir, power)
	else:
		user_player.kick_directed(final_dir, power)

func _on_kickoff_ended() -> void:
	if not _is_authority:
		return
	MatchState.begin_awaiting_pass()
	_kickoff_safety_timeout()

func _kickoff_safety_timeout() -> void:
	await get_tree().create_timer(6.0).timeout
	if MatchState.awaiting_kickoff_pass:
		MatchState.mark_kickoff_pass_taken()

func _on_ball_owner_changed(new_owner: Node) -> void:
	if not MatchState.awaiting_kickoff_pass:
		return
	if new_owner == null:
		MatchState.mark_kickoff_pass_taken()

func _on_match_ended(_h: int, _a: int) -> void:
	if Network.is_dedicated:
		await get_tree().create_timer(4.0).timeout
		_dedicated_restart_match()
		return
	_freeze_after_match_end()

func _freeze_after_match_end() -> void:
	for arr in [home_players, away_players]:
		for p in arr:
			if is_instance_valid(p):
				p.set_input(Vector2.ZERO)
				p.linear_velocity = Vector2.ZERO
				p.angular_velocity = 0.0
	if ball and is_instance_valid(ball):
		ball.linear_velocity = Vector2.ZERO
		ball.angular_velocity = 0.0

func _dedicated_restart_match() -> void:
	get_tree().reload_current_scene()

func _setup_dedicated_hud_visibility() -> void:
	if not Network.is_dedicated:
		return
	if hud:
		hud.visible = false
	if camera:
		camera.zoom = Vector2(0.7, 0.7)

func _on_dedicated_peer_connected(peer_id: int) -> void:
	for arr in [home_players, away_players]:
		for p in arr:
			if not is_instance_valid(p):
				continue
			if p.input_peer_id == 0:
				_replace_ai_with_peer(p, peer_id)
				print("[Server] Peer %d → %s slot" % [peer_id, p.label_text])
				return
	print("[Server] Peer %d connected but no free slot — spectator" % peer_id)

func _on_dedicated_peer_disconnected(peer_id: int) -> void:
	for arr in [home_players, away_players]:
		for p in arr:
			if not is_instance_valid(p):
				continue
			if p.input_peer_id == peer_id:
				p.input_peer_id = 0
				_attach_ai(p, p.team, _ai_role_for(p))
				print("[Server] Peer %d left, %s → AI" % [peer_id, p.label_text])
				return

func _replace_ai_with_peer(p: Player, peer_id: int) -> void:
	for c in p.get_children():
		if c.get_script() == AIBrainScript:
			c.queue_free()
	p.input_peer_id = peer_id

func _rebind_user_player_if_needed() -> void:
	var my_id: int = Network.get_my_id()
	if user_player and is_instance_valid(user_player) and user_player.input_peer_id == my_id:
		return
	for arr in [home_players, away_players]:
		for p in arr:
			if is_instance_valid(p) and p.input_peer_id == my_id:
				if user_player and is_instance_valid(user_player) and user_player != p:
					user_player.set_user_controlled(false)
				user_player = p
				p.set_user_controlled(true)
				return
