extends RigidBody2D
class_name Ball

signal entered_goal(team_scoring: int)
signal owner_changed(new_owner: Node)

@export var radius := 10.0
@export var max_speed := 1300.0
@export var roll_damp := 1.2
@export var no_acquire_after_kick := 0.32

@export var spin_factor := 0.045
@export var kick_sfx_pool: Array[AudioStream]
@export var wall_sfx_pool: Array[AudioStream]
@export var wall_min_speed := 130.0

var _spawn_pos := Vector2.ZERO
var owner_player: Node = null
var _no_acquire_until := 0.0
var _spin_node: Node2D = null
var _last_wall_sfx := 0.0

func _ready() -> void:
	add_to_group("ball")
	gravity_scale = 0.0
	linear_damp = roll_damp
	angular_damp = 2.0
	collision_layer = 1 << 2
	collision_mask = (1 << 0) | (1 << 1) | (1 << 3)
	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(_on_body_contact)
	_spawn_pos = global_position
	_spin_node = get_node_or_null("Spin")
	if Network.is_online() and not multiplayer.is_server():
		freeze = true

func _is_authority() -> bool:
	return (not Network.is_online()) or multiplayer.is_server()

func can_be_acquired_by(p: Node) -> bool:
	if owner_player == p:
		return true
	var now: float = Time.get_ticks_msec() / 1000.0
	return now >= _no_acquire_until

func acquire(p: Node) -> void:
	if owner_player == p:
		return
	owner_player = p
	owner_changed.emit(p)

func release(no_acquire_seconds := 0.0) -> void:
	owner_player = null
	if no_acquire_seconds > 0.0:
		_no_acquire_until = Time.get_ticks_msec() / 1000.0 + no_acquire_seconds
	owner_changed.emit(null)

func kick(impulse: Vector2) -> void:
	release(no_acquire_after_kick)
	linear_velocity = Vector2.ZERO
	apply_central_impulse(impulse)
	_clamp_speed()
	if kick_sfx_pool and kick_sfx_pool.size() > 0:
		var power_t: float = clamp(impulse.length() / 720.0, 0.4, 1.2)
		SFX.play_random(kick_sfx_pool, lerp(-10.0, -2.0, power_t), 0.06)

func _on_body_contact(body: Node) -> void:
	if body == null:
		return
	if not (body is StaticBody2D):
		return
	var spd: float = linear_velocity.length()
	if spd < wall_min_speed:
		return
	var now: float = Time.get_ticks_msec() / 1000.0
	if now - _last_wall_sfx < 0.08:
		return
	_last_wall_sfx = now
	if wall_sfx_pool and wall_sfx_pool.size() > 0:
		SFX.play_random(wall_sfx_pool, -8.0, 0.1)

func _physics_process(delta: float) -> void:
	if not _is_authority():
		if _spin_node:
			var spd_c: float = linear_velocity.length()
			if spd_c > 1.0:
				_spin_node.rotation += spd_c * spin_factor * delta * (1.0 if linear_velocity.x >= 0.0 else -1.0)
		return
	if MatchState.is_frozen():
		linear_velocity = Vector2.ZERO
		angular_velocity = 0.0
	_clamp_speed()
	if _spin_node:
		var spd: float = linear_velocity.length()
		if spd > 1.0:
			var sign_dir: float = sign(linear_velocity.x) if abs(linear_velocity.x) > abs(linear_velocity.y) else sign(linear_velocity.y)
			if sign_dir == 0.0:
				sign_dir = 1.0
			_spin_node.rotation += spd * spin_factor * delta * sign_dir

func _clamp_speed() -> void:
	if linear_velocity.length() > max_speed:
		linear_velocity = linear_velocity.normalized() * max_speed

func reset_to(pos: Vector2) -> void:
	release(0.0)
	global_position = pos
	linear_velocity = Vector2.ZERO
	angular_velocity = 0.0
	_spawn_pos = pos
