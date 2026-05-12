extends RigidBody2D
class_name Player

signal stamina_changed(value: float, max_value: float)

@export var input_peer_id: int = 0  # 0 = AI, >0 = client peer that sends input

@export var team := 0
@export var move_force := 1700.0
@export var walk_speed := 320.0
@export var sprint_speed := 480.0
@export var sprint_threshold := 0.85
@export var max_stamina := 100.0
@export var stamina_drain := 26.0
@export var stamina_regen := 20.0
@export var min_stamina_to_sprint := 6.0
@export var kick_impulse_min := 200.0
@export var kick_impulse_max := 1100.0
@export var ball_touch_radius := 30.0
@export var label_text := "P"
@export var ai_controlled := true
@export var carry_distance := 36.0
@export var dribble_lerp := 14.0
@export var carry_speed_factor := 0.95

@export var bump_velocity_weight := 1.4
@export var bump_facing_weight := 70.0
@export var bump_min_impulse := 35.0
@export var bump_max_impulse := 700.0
@export var bump_self_recoil := 0.40
@export var bump_sprint_multiplier := 1.55
@export var bump_same_team_factor := 0.55
@export var bump_cooldown := 0.18

@export var color_home := Color(0.92, 0.41, 0.18)
@export var color_away := Color(0.27, 0.55, 0.94)
@export var ring_user_controlled := Color(1, 1, 0.2, 1)

@onready var body_shape: CollisionShape2D = $Shape
@onready var visual: Node2D = $Visual
@onready var body_poly: Polygon2D = $Visual/TeamRing
@onready var face_bg: Polygon2D = $Visual/FaceBg
@onready var face: Node2D = $Visual/Face
@onready var ring: Node2D = $Visual/Ring
@onready var stamina_ring: Polygon2D = $Visual/StaminaRing
@onready var outline: Polygon2D = $Visual/Outline
@onready var foot_l: Polygon2D = $Visual/FootL
@onready var foot_r: Polygon2D = $Visual/FootR
@onready var shadow: Node2D = $Shadow
@onready var label: Label = $Visual/Label

const FACE_PALETTES := [
	{"skin": Color(0.97, 0.82, 0.65), "hair": Color(0.18, 0.12, 0.06), "style": 0, "beard": false},
	{"skin": Color(0.94, 0.74, 0.55), "hair": Color(0.65, 0.32, 0.12), "style": 1, "beard": false},
	{"skin": Color(0.92, 0.78, 0.62), "hair": Color(0.92, 0.78, 0.32), "style": 2, "beard": false},
	{"skin": Color(0.62, 0.42, 0.30), "hair": Color(0.10, 0.08, 0.06), "style": 0, "beard": true},
	{"skin": Color(0.86, 0.68, 0.52), "hair": Color(0.50, 0.32, 0.18), "style": 1, "beard": true},
	{"skin": Color(0.97, 0.85, 0.70), "hair": Color(0.78, 0.50, 0.20), "style": 2, "beard": false},
]

var _foot_phase := 0.0
var _bob_t := 0.0
var _kick_punch_t := 0.0
var _bump_until := 0.0

var input_vector := Vector2.ZERO
var aim_vector := Vector2.RIGHT
var _ball: Ball = null
var _is_user := false
var _facing := Vector2.RIGHT
var stamina := 100.0
var _is_sprinting := false
var external_sprint_pressed := false
var keyboard_sprint_pressed := false
@export var radius := 22.0

func _ready() -> void:
	add_to_group("player")
	if team == MatchState.TEAM_HOME:
		add_to_group("team_home")
	else:
		add_to_group("team_away")
	gravity_scale = 0.0
	linear_damp = 4.5
	angular_damp = 8.0
	collision_layer = 1 << 1
	collision_mask = (1 << 0) | (1 << 1) | (1 << 2)
	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(_on_body_contact)
	stamina = max_stamina
	stamina_changed.emit(stamina, max_stamina)
	if Network.is_online() and not multiplayer.is_server():
		freeze = true
	_apply_visual()

func _is_authority() -> bool:
	return (not Network.is_online()) or multiplayer.is_server()

func bind_ball(b: Ball) -> void:
	_ball = b

func set_user_controlled(on: bool) -> void:
	_is_user = on
	_apply_visual()

func is_user() -> bool:
	return _is_user

func set_input(move: Vector2) -> void:
	input_vector = move.limit_length(1.0)

@rpc("any_peer", "call_remote", "unreliable_ordered")
func remote_set_input(move: Vector2) -> void:
	if Network.is_online() and not multiplayer.is_server():
		return
	if Network.is_online():
		var sender: int = multiplayer.get_remote_sender_id()
		if sender != input_peer_id:
			return
	input_vector = move.limit_length(1.0)

@rpc("any_peer", "call_remote", "reliable")
func remote_kick(power: float) -> void:
	if Network.is_online() and not multiplayer.is_server():
		return
	if Network.is_online():
		var sender: int = multiplayer.get_remote_sender_id()
		if sender != input_peer_id:
			return
	kick(power)

@rpc("any_peer", "call_remote", "reliable")
func remote_kick_directed(dir: Vector2, power: float) -> void:
	if Network.is_online() and not multiplayer.is_server():
		return
	if Network.is_online():
		var sender: int = multiplayer.get_remote_sender_id()
		if sender != input_peer_id:
			return
	kick_directed(dir, power)

func _apply_visual() -> void:
	if body_poly == null:
		return
	var col: Color = color_home if team == MatchState.TEAM_HOME else color_away
	body_poly.color = col
	if label:
		label.text = label_text
	if ring:
		ring.visible = _is_user
	if stamina_ring:
		stamina_ring.visible = false
	if outline:
		outline.visible = false
	if foot_l:
		foot_l.visible = false
	if foot_r:
		foot_r.visible = false
	if face and face.has_method("_build"):
		var seed: int = abs(label_text.hash()) % FACE_PALETTES.size()
		var pal: Dictionary = FACE_PALETTES[seed]
		face.skin_color = pal.skin
		face.hair_color = pal.hair
		face.hair_style = pal.style
		face.has_beard = pal.beard
		if face_bg:
			face_bg.color = pal.skin
		face._build()

func _animate_visual(delta: float, input_mag: float) -> void:
	var v_speed: float = linear_velocity.length()
	_foot_phase += delta * (8.0 + v_speed * 0.04)
	var step_amp: float = clamp(v_speed / sprint_speed, 0.0, 1.0)
	var swing: float = sin(_foot_phase) * 18.0 * step_amp
	var perp: Vector2 = Vector2(-_facing.y, _facing.x)
	if foot_l:
		var pl: Vector2 = perp * (10.0) + _facing * swing
		foot_l.position = visual.transform.affine_inverse().basis_xform(pl)
		foot_l.modulate.a = 0.85 if step_amp > 0.05 else 0.0
	if foot_r:
		var pr: Vector2 = perp * (-10.0) + _facing * (-swing)
		foot_r.position = visual.transform.affine_inverse().basis_xform(pr)
		foot_r.modulate.a = 0.85 if step_amp > 0.05 else 0.0
	_bob_t += delta * (3.0 + v_speed * 0.02)
	var bob: float = (1.0 - step_amp) * sin(_bob_t * 1.4) * 0.04
	var squash: Vector2 = Vector2.ONE
	if _kick_punch_t > 0.0:
		_kick_punch_t = max(0.0, _kick_punch_t - delta)
		var k: float = _kick_punch_t / 0.18
		squash = Vector2(1.0 + 0.20 * k, 1.0 - 0.18 * k)
	var stam_t: float = clamp(stamina / max_stamina, 0.0, 1.0)
	visual.scale = Vector2(squash.x, squash.y) * (1.0 + bob)
	if shadow:
		shadow.scale = Vector2(squash.x, squash.y) * (1.0 - bob * 0.4)
	if stamina_ring and _is_user:
		var col_g: Color = Color(0.4, 1.0, 0.5, 0.85)
		var col_y: Color = Color(1.0, 0.9, 0.3, 0.85)
		var col_r: Color = Color(1.0, 0.35, 0.3, 0.9)
		var c: Color
		if stam_t > 0.55:
			c = col_y.lerp(col_g, (stam_t - 0.55) / 0.45)
		else:
			c = col_r.lerp(col_y, stam_t / 0.55)
		stamina_ring.color = c

func is_sprinting() -> bool:
	return _is_sprinting

func _physics_process(delta: float) -> void:
	if not _is_authority():
		_animate_visual(delta, input_vector.length())
		return
	if MatchState.is_frozen():
		linear_velocity = Vector2.ZERO
		_release_if_owner()
		return
	var has_ball: bool = _ball != null and _ball.owner_player == self
	var input_mag: float = input_vector.length()
	var trying_sprint: bool = (input_mag > sprint_threshold) or external_sprint_pressed or keyboard_sprint_pressed
	var can_sprint: bool = stamina > min_stamina_to_sprint
	_is_sprinting = trying_sprint and can_sprint and input_mag > 0.05
	if _is_sprinting:
		stamina = max(0.0, stamina - stamina_drain * delta)
	else:
		stamina = min(max_stamina, stamina + stamina_regen * delta)
	stamina_changed.emit(stamina, max_stamina)

	if input_mag > 0.05:
		_facing = input_vector.normalized()
		var spd: float = sprint_speed if _is_sprinting else walk_speed
		if has_ball:
			spd *= carry_speed_factor
		var desired: Vector2 = _facing * spd
		var diff: Vector2 = desired - linear_velocity
		if diff.length_squared() > 0.0001:
			apply_central_force(diff.normalized() * move_force)
		if linear_velocity.length() > spd:
			linear_velocity = linear_velocity.normalized() * spd
	var rot_target: float = _facing.angle()
	visual.rotation = lerp_angle(visual.rotation, rot_target, 12.0 * delta)
	_try_acquire_ball()
	if _ball != null and _ball.owner_player == self:
		_dribble(delta)
	_animate_visual(delta, input_mag)

func _try_acquire_ball() -> void:
	if _ball == null:
		return
	if _ball.owner_player == self:
		return
	var d: float = global_position.distance_to(_ball.global_position)
	if d > ball_touch_radius + _ball.radius:
		return
	if not _ball.can_be_acquired_by(self):
		return
	_ball.acquire(self)

func _dribble(delta: float) -> void:
	var target: Vector2 = global_position + _facing * carry_distance
	var t: float = clamp(dribble_lerp * delta, 0.0, 1.0)
	_ball.global_position = _ball.global_position.lerp(target, t)
	_ball.linear_velocity = linear_velocity

func _release_if_owner() -> void:
	if _ball != null and _ball.owner_player == self:
		_ball.release(0.0)

func can_kick() -> bool:
	if _ball == null:
		return false
	if _ball.owner_player == self:
		return true
	return global_position.distance_to(_ball.global_position) <= ball_touch_radius + _ball.radius

func has_ball() -> bool:
	return _ball != null and _ball.owner_player == self

func kick(power: float) -> bool:
	if not can_kick():
		return false
	var dir: Vector2 = _facing
	if not has_ball():
		var to_ball: Vector2 = _ball.global_position - global_position
		if to_ball.length() > 0.001:
			dir = to_ball.normalized()
	if dir.length() < 0.001:
		dir = Vector2.RIGHT
	return _do_kick(dir, power)

func kick_directed(dir: Vector2, power: float) -> bool:
	if not can_kick():
		return false
	if dir.length() < 0.001:
		dir = _facing
		if dir.length() < 0.001:
			dir = Vector2.RIGHT
	dir = dir.normalized()
	_facing = dir
	return _do_kick(dir, power)

func _do_kick(dir: Vector2, power: float) -> bool:
	var impulse_mag: float = lerp(kick_impulse_min, kick_impulse_max, clamp(power, 0.0, 1.0))
	_ball.kick(dir * impulse_mag)
	_kick_punch_t = 0.18
	return true

func aim_dir() -> Vector2:
	return _facing

func _on_body_contact(other: Node) -> void:
	if not (other is Player) or other == self:
		return
	var now: float = Time.get_ticks_msec() / 1000.0
	if now < _bump_until:
		return
	_resolve_bump(other as Player)

func _resolve_bump(op: Player) -> void:
	var to_op: Vector2 = op.global_position - global_position
	var dist: float = to_op.length()
	if dist < 0.001:
		return
	to_op = to_op / dist
	var my_push_speed: float = max(0.0, linear_velocity.dot(to_op))
	var facing_align: float = max(0.0, _facing.dot(to_op))
	var sprint_mul: float = bump_sprint_multiplier if _is_sprinting else 1.0
	var raw: float = my_push_speed * bump_velocity_weight + facing_align * bump_facing_weight
	var impulse_mag: float = clamp(raw * sprint_mul, 0.0, bump_max_impulse)
	if op.team == team:
		impulse_mag *= bump_same_team_factor
	if impulse_mag < bump_min_impulse:
		return
	op.apply_central_impulse(to_op * impulse_mag)
	apply_central_impulse(-to_op * impulse_mag * bump_self_recoil)
	op.trigger_bump_anim()
	trigger_bump_anim()
	_bump_until = Time.get_ticks_msec() / 1000.0 + bump_cooldown
	op._bump_until = _bump_until

func trigger_bump_anim() -> void:
	_kick_punch_t = max(_kick_punch_t, 0.14)
