extends CanvasLayer

@onready var home_score_label: Label = $Top/Scoreboard/HomeScorePill/HomeScore
@onready var away_score_label: Label = $Top/Scoreboard/AwayScorePill/AwayScore
@onready var time_label: Label = $Top/Scoreboard/TimerBox/TimeLabel
@onready var center_msg: Label = $CenterMsg
@onready var flash: ColorRect = $Flash
@onready var stamina_bar: ProgressBar = $StaminaPanel/VBox/Bar
@onready var stamina_label: Label = $StaminaPanel/VBox/Label
@onready var joystick: VirtualJoystick = $Joystick
@onready var kick_button: KickButton = $RightCluster/KickButton
@onready var power_kick_button: KickButton = $RightCluster/PowerKickButton
@onready var sprint_button: SprintButton = $RightCluster/SprintButton
@onready var msg_shadow: Label = $CenterMsgShadow
@onready var edge_left: ColorRect = $EdgeLeft
@onready var edge_right: ColorRect = $EdgeRight
@onready var game_over_panel: Control = $GameOverPanel
@onready var go_result: Label = $GameOverPanel/Center/Panel/VBox/ResultLabel
@onready var go_score: Label = $GameOverPanel/Center/Panel/VBox/ScoreLabel
@onready var go_rematch: Button = $GameOverPanel/Center/Panel/VBox/Buttons/Rematch
@onready var go_menu: Button = $GameOverPanel/Center/Panel/VBox/Buttons/Menu

const GoalBurstScene := preload("res://scenes/fx/goal_burst.tscn")
const GOAL_SFX := preload("res://assets/audio/sfx/impactBell_heavy_000.ogg")
const GOAL_SFX2 := preload("res://assets/audio/sfx/impactBell_heavy_001.ogg")
const KICKOFF_SFX := preload("res://assets/audio/sfx/impactGlass_light_000.ogg")

var _msg_tween: Tween = null
var _bound_player: Node = null

const COLOR_HOME := Color(0.92, 0.41, 0.18)
const COLOR_AWAY := Color(0.27, 0.55, 0.94)

func _ready() -> void:
	MatchState.score_changed.connect(_on_score)
	MatchState.time_changed.connect(_on_time)
	MatchState.goal_scored.connect(_on_goal)
	MatchState.kickoff_started.connect(_on_kickoff_start)
	MatchState.awaiting_kickoff_pass_started.connect(_on_awaiting_pass)
	MatchState.awaiting_kickoff_pass_ended.connect(_on_pass_taken)
	MatchState.match_ended.connect(_on_end)
	_on_score(MatchState.home_score, MatchState.away_score)
	_on_time(MatchState.time_left)
	_clear_msg()
	flash.color = Color(1, 1, 1, 0)
	stamina_bar.max_value = 100.0
	stamina_bar.value = 100.0
	if sprint_button:
		sprint_button.sprint_pressed.connect(_on_sprint_pressed)
		sprint_button.sprint_released.connect(_on_sprint_released)
	if go_rematch:
		go_rematch.pressed.connect(_on_rematch)
	if go_menu:
		go_menu.pressed.connect(_on_main_menu)
	if game_over_panel:
		game_over_panel.visible = false

func _process(_d: float) -> void:
	if _bound_player == null:
		_bind_user_player()

func _bind_user_player() -> void:
	for p in get_tree().get_nodes_in_group("player"):
		if p.has_method("is_user") and p.is_user():
			_bound_player = p
			if p.has_signal("stamina_changed"):
				p.stamina_changed.connect(_on_stamina)
			return

func _on_stamina(value: float, max_value: float) -> void:
	stamina_bar.max_value = max_value
	stamina_bar.value = value
	stamina_label.text = "STAMINA  %d" % int(value)

func _on_sprint_pressed() -> void:
	var p: Node = _bound_player
	if p and is_instance_valid(p) and "external_sprint_pressed" in p:
		p.external_sprint_pressed = true

func _on_sprint_released() -> void:
	var p: Node = _bound_player
	if p and is_instance_valid(p) and "external_sprint_pressed" in p:
		p.external_sprint_pressed = false

func _on_score(home: int, away: int) -> void:
	home_score_label.text = "%d" % home
	away_score_label.text = "%d" % away

func _on_time(secs: float) -> void:
	var s: int = int(ceil(secs))
	time_label.text = "%d:%02d" % [s / 60, s % 60]

func _on_goal(team: int) -> void:
	var col: Color = COLOR_HOME if team == MatchState.TEAM_HOME else COLOR_AWAY
	_play_goal_animation(col)
	_play_flash(col)
	_play_edge(team, col)
	_play_burst(col)
	SFX.play(GOAL_SFX, 0.0, 1.0)
	await get_tree().create_timer(0.18).timeout
	SFX.play(GOAL_SFX2, -3.0, 1.05)

func _on_kickoff_start(kicker_team: int) -> void:
	SFX.play(KICKOFF_SFX, -3.0, 1.0)
	SFX.play_whistle_long()
	if MatchState.home_score == 0 and MatchState.away_score == 0:
		_show_msg("KICK OFF!", Color.WHITE, 1.2)

func _on_awaiting_pass(kicker_team: int) -> void:
	SFX.play_whistle_short()
	var col: Color = COLOR_HOME if kicker_team == MatchState.TEAM_HOME else COLOR_AWAY
	_show_msg("PASS TO START!", col, 2.5)

func _on_pass_taken() -> void:
	if _msg_tween and _msg_tween.is_valid():
		_msg_tween.kill()
	_clear_msg()

func _on_end(home: int, away: int) -> void:
	if _msg_tween and _msg_tween.is_valid():
		_msg_tween.kill()
	_show_game_over_panel(home, away)
	_clear_msg()

func _show_game_over_panel(home: int, away: int) -> void:
	if not game_over_panel:
		return
	if joystick:
		joystick.visible = false
	if kick_button:
		kick_button.visible = false
	if power_kick_button:
		power_kick_button.visible = false
	if sprint_button:
		sprint_button.visible = false
	game_over_panel.visible = true
	game_over_panel.move_to_front()
	game_over_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	if home > away:
		go_result.text = "HOME WINS!"
		go_result.add_theme_color_override("font_color", COLOR_HOME)
	elif away > home:
		go_result.text = "AWAY WINS!"
		go_result.add_theme_color_override("font_color", COLOR_AWAY)
	else:
		go_result.text = "DRAW"
		go_result.add_theme_color_override("font_color", Color(0.95, 0.78, 0.22, 1))
	go_score.text = "%d  -  %d" % [home, away]

func _on_rematch() -> void:
	get_tree().reload_current_scene()

func _on_main_menu() -> void:
	Network.leave()
	get_tree().change_scene_to_file("res://scenes/ui/lobby.tscn")

func _play_goal_animation(col: Color) -> void:
	if _msg_tween and _msg_tween.is_valid():
		_msg_tween.kill()
	_set_msg_text("GOAL!", col, 220)
	center_msg.pivot_offset = center_msg.size * 0.5
	center_msg.scale = Vector2(0.05, 0.05)
	if msg_shadow:
		msg_shadow.pivot_offset = msg_shadow.size * 0.5
		msg_shadow.scale = Vector2(0.05, 0.05)
	_msg_tween = create_tween().set_parallel(true)
	_msg_tween.tween_property(center_msg, "scale", Vector2(1.45, 1.45), 0.30).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if msg_shadow:
		_msg_tween.tween_property(msg_shadow, "scale", Vector2(1.45, 1.45), 0.30).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_msg_tween.chain().tween_property(center_msg, "scale", Vector2(1.0, 1.0), 0.16)
	if msg_shadow:
		_msg_tween.parallel().tween_property(msg_shadow, "scale", Vector2(1.0, 1.0), 0.16)
	_msg_tween.chain().tween_interval(1.5)
	_msg_tween.tween_property(center_msg, "modulate:a", 0.0, 0.35)
	if msg_shadow:
		_msg_tween.parallel().tween_property(msg_shadow, "modulate:a", 0.0, 0.35)
	_msg_tween.chain().tween_callback(func():
		_set_msg_text("KICK OFF!", Color.WHITE, 110)
		_clear_msg_after(0.9))

func _play_flash(col: Color) -> void:
	flash.color = Color(col.r, col.g, col.b, 0.45)
	var f := create_tween()
	f.tween_property(flash, "color:a", 0.0, 0.55)

func _play_edge(team: int, col: Color) -> void:
	var bar: ColorRect = edge_right if team == MatchState.TEAM_HOME else edge_left
	if bar == null:
		return
	bar.color = Color(col.r, col.g, col.b, 0.85)
	var t := create_tween()
	t.tween_property(bar, "color:a", 0.0, 0.9)

func _play_burst(col: Color) -> void:
	var b := GoalBurstScene.instantiate()
	add_child(b)
	(b as Node2D).position = get_viewport().get_visible_rect().size * 0.5
	if b.has_method("setup_color"):
		b.setup_color(col)
	if b.has_method("play"):
		b.play()

func _show_msg(text: String, col: Color, hold_seconds: float) -> void:
	if _msg_tween and _msg_tween.is_valid():
		_msg_tween.kill()
	_set_msg_text(text, col, 110)
	_clear_msg_after(hold_seconds)

func _set_msg_text(text: String, col: Color, font_size: int) -> void:
	center_msg.text = text
	center_msg.modulate = col
	center_msg.scale = Vector2.ONE
	center_msg.add_theme_font_size_override("font_size", font_size)
	if msg_shadow:
		msg_shadow.text = text
		var s := center_msg.modulate
		msg_shadow.modulate = Color(0, 0, 0, 0.7)
		msg_shadow.scale = Vector2.ONE
		msg_shadow.add_theme_font_size_override("font_size", font_size)

func _clear_msg_after(hold_seconds: float) -> void:
	_msg_tween = create_tween()
	_msg_tween.tween_interval(hold_seconds)
	_msg_tween.tween_callback(_clear_msg)

func _clear_msg() -> void:
	center_msg.text = ""
	center_msg.scale = Vector2.ONE
	var c := center_msg.modulate
	c.a = 1.0
	center_msg.modulate = c
	if msg_shadow:
		msg_shadow.text = ""
		msg_shadow.scale = Vector2.ONE
		msg_shadow.modulate = Color(0, 0, 0, 0.7)

func _paint_dot(p: Panel, col: Color) -> void:
	if p == null:
		return
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(20)
	p.add_theme_stylebox_override("panel", sb)
