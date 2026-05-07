extends Node
class_name AIBrain

@export var defender_offset := 220.0
@export var support_offset := 280.0
@export var shoot_range := 640.0
@export var pass_lane_clearance := 38.0
@export var pass_lead_time := 0.32
@export var pass_min_distance := 140.0
@export var pass_max_distance := 720.0
@export var pass_score_advantage := 30.0
@export var dribble_kick_power := 0.55
@export var pass_min_power := 0.45
@export var pass_max_power := 0.85
@export var first_time_distance := 70.0
@export var first_time_recent_owner_secs := 0.45
@export var defender_intercept_range := 220.0
@export var kickoff_pass_delay := 1.6
@export var dribble_evade_range := 130.0
@export var dribble_evade_weight := 1.3
@export var support_avoid_range := 120.0
@export var support_avoid_weight := 0.7

var player: Player = null
var ball: Ball = null
var own_goal_pos: Vector2 = Vector2.ZERO
var enemy_goal_pos: Vector2 = Vector2.ZERO
var role := 0

var _kick_cooldown := 0.0
var _last_pass_target_id := 0

func setup(p: Player, b: Ball, own_goal: Vector2, enemy_goal: Vector2, p_role: int) -> void:
	player = p
	ball = b
	own_goal_pos = own_goal
	enemy_goal_pos = enemy_goal
	role = p_role

func _physics_process(delta: float) -> void:
	if player == null or not is_instance_valid(player):
		return
	if ball == null or not is_instance_valid(ball):
		return
	if not MatchState.running:
		player.set_input(Vector2.ZERO)
		return
	if MatchState.is_frozen():
		player.set_input(Vector2.ZERO)
		return
	_kick_cooldown = max(0.0, _kick_cooldown - delta)
	if MatchState.awaiting_kickoff_pass:
		_kickoff_behavior()
		return
	player.set_input(_decide_move())
	_decide_kick()

func _kickoff_behavior() -> void:
	if player.team != MatchState.current_kicker:
		player.set_input(Vector2.ZERO)
		return
	if role != 0:
		player.set_input(Vector2.ZERO)
		return
	if not player.has_ball():
		var to_ball: Vector2 = ball.global_position - player.global_position
		var d: float = to_ball.length()
		if d > 8.0:
			player.set_input(to_ball / d)
		else:
			player.set_input(Vector2.ZERO)
		return
	if _kick_cooldown > 0.0:
		player.set_input(Vector2.ZERO)
		return
	if MatchState.seconds_since_awaiting() < kickoff_pass_delay:
		player.set_input(Vector2.ZERO)
		return
	var target: Player = _find_pass_target()
	if target == null:
		target = _nearest_teammate()
	if target == null:
		var fwd: Vector2 = (enemy_goal_pos - player.global_position).normalized()
		player.kick_directed(fwd, 0.55)
		return
	var lead: Vector2 = target.global_position + target.linear_velocity * pass_lead_time
	var dir: Vector2 = (lead - player.global_position).normalized()
	var dist: float = player.global_position.distance_to(lead)
	var power: float = lerp(pass_min_power, pass_max_power, clamp(dist / pass_max_distance, 0.0, 1.0))
	player.kick_directed(dir, power)
	_kick_cooldown = 0.5

func _nearest_teammate() -> Player:
	var best: Player = null
	var best_d: float = INF
	for tm in _team_mates():
		if tm == player or not (tm is Player):
			continue
		var d: float = player.global_position.distance_to((tm as Player).global_position)
		if d < best_d:
			best_d = d
			best = tm as Player
	return best

func _decide_move() -> Vector2:
	var teammate_has_ball: bool = _team_has_ball()
	if player.has_ball():
		return _dribble_direction()
	if teammate_has_ball:
		return _support_run()
	return _chase_or_position()

func _dribble_direction() -> Vector2:
	var to_goal: Vector2 = enemy_goal_pos - player.global_position
	if to_goal.length() < 6.0:
		return Vector2.ZERO
	var goal_dir: Vector2 = to_goal.normalized()
	var nearest: Player = _nearest_enemy_to_self()
	if nearest == null:
		return goal_dir
	var to_enemy: Vector2 = nearest.global_position - player.global_position
	var dist: float = to_enemy.length()
	if dist > dribble_evade_range or dist < 0.001:
		return goal_dir
	var enemy_dir: Vector2 = to_enemy / dist
	var perp1: Vector2 = Vector2(-enemy_dir.y, enemy_dir.x)
	var perp2: Vector2 = Vector2(enemy_dir.y, -enemy_dir.x)
	var perp: Vector2 = perp1 if perp1.dot(goal_dir) > perp2.dot(goal_dir) else perp2
	var weight: float = clamp(1.0 - dist / dribble_evade_range, 0.0, 1.0)
	var combined: Vector2 = goal_dir + perp * weight * dribble_evade_weight
	if combined.length_squared() < 0.001:
		return goal_dir
	return combined.normalized()

func _nearest_enemy_to_self() -> Player:
	var best: Player = null
	var best_d: float = INF
	for e in _opponents():
		if not (e is Player):
			continue
		var d: float = player.global_position.distance_to((e as Player).global_position)
		if d < best_d:
			best_d = d
			best = e as Player
	return best

func _nearest_enemy_to_pos(p: Vector2) -> Player:
	var best: Player = null
	var best_d: float = INF
	for e in _opponents():
		if not (e is Player):
			continue
		var d: float = p.distance_to((e as Player).global_position)
		if d < best_d:
			best_d = d
			best = e as Player
	return best

func _team_has_ball() -> bool:
	if ball.owner_player == null:
		return false
	if not (ball.owner_player is Player):
		return false
	return (ball.owner_player as Player).team == player.team

func _support_run() -> Vector2:
	var ball_pos: Vector2 = ball.global_position
	var to_goal_dir: Vector2 = (enemy_goal_pos - ball_pos).normalized()
	var perp: Vector2 = Vector2(-to_goal_dir.y, to_goal_dir.x)
	var lateral: float = -1.0 if int(player.get_instance_id()) % 2 == 0 else 1.0
	var target: Vector2 = ball_pos
	match role:
		1:
			target = Vector2((ball_pos.x + own_goal_pos.x * 0.4) * 0.5, ball_pos.y * 0.4)
		2:
			target = ball_pos + to_goal_dir * support_offset * 0.4 + perp * 140.0 * lateral
		_:
			target = ball_pos + to_goal_dir * support_offset + perp * 90.0 * lateral
	var nearest: Player = _nearest_enemy_to_pos(target)
	if nearest != null:
		var to_e: Vector2 = nearest.global_position - target
		var d: float = to_e.length()
		if d < support_avoid_range and d > 0.001:
			var away: Vector2 = -to_e / d
			target += away * (support_avoid_range - d) * support_avoid_weight
	target.x = clamp(target.x, -780.0, 780.0)
	target.y = clamp(target.y, -380.0, 380.0)
	var to: Vector2 = target - player.global_position
	if to.length() < 18.0:
		return Vector2.ZERO
	return to.normalized()

func _chase_or_position() -> Vector2:
	var ball_pos: Vector2 = ball.global_position
	var enemy_owns: bool = ball.owner_player != null and (ball.owner_player as Node) != player and not _team_has_ball()
	var target: Vector2 = ball_pos
	match role:
		1:
			var defend_x: float = own_goal_pos.x + sign(enemy_goal_pos.x - own_goal_pos.x) * defender_offset
			var defend_pos: Vector2 = Vector2(defend_x, ball_pos.y * 0.55)
			if _team_closest_to_ball(player) or _ball_in_own_third():
				target = ball_pos
			elif enemy_owns and _i_am_closest_defender_to_ball():
				target = ball_pos
			else:
				target = defend_pos
		2:
			if _team_closest_to_ball(player):
				target = ball_pos
			else:
				target = Vector2((ball_pos.x + own_goal_pos.x * 0.3) * 0.55, ball_pos.y * 0.7)
		_:
			if _team_closest_to_ball(player):
				target = _approach_position(ball_pos)
			else:
				var bias_to_goal: Vector2 = (enemy_goal_pos - ball_pos).normalized()
				target = (ball_pos + enemy_goal_pos) * 0.5 + bias_to_goal * 80.0
	target.x = clamp(target.x, -780.0, 780.0)
	target.y = clamp(target.y, -380.0, 380.0)
	var to: Vector2 = target - player.global_position
	if to.length() < 14.0:
		return Vector2.ZERO
	return to.normalized()

func _ball_in_own_third() -> bool:
	var goal_dir: float = sign(enemy_goal_pos.x - own_goal_pos.x)
	var third_x: float = own_goal_pos.x + goal_dir * 540.0
	if goal_dir > 0:
		return ball.global_position.x < third_x
	return ball.global_position.x > third_x

func _i_am_closest_defender_to_ball() -> bool:
	var group: String = "team_home" if player.team == MatchState.TEAM_HOME else "team_away"
	var mates: Array = player.get_tree().get_nodes_in_group(group)
	var my_d: float = player.global_position.distance_to(ball.global_position)
	if my_d > defender_intercept_range:
		return false
	for m in mates:
		if m == player or not (m is Player):
			continue
		var d: float = (m as Player).global_position.distance_to(ball.global_position)
		if d < my_d:
			return false
	return true

func _approach_position(ball_pos: Vector2) -> Vector2:
	var to_goal: Vector2 = (enemy_goal_pos - ball_pos).normalized()
	return ball_pos - to_goal * 22.0

func _team_closest_to_ball(p: Player) -> bool:
	var group: String = "team_home" if p.team == MatchState.TEAM_HOME else "team_away"
	var mates: Array = p.get_tree().get_nodes_in_group(group)
	var my_d: float = p.global_position.distance_squared_to(ball.global_position)
	for m in mates:
		if m == p or not (m is Player):
			continue
		var d: float = (m as Player).global_position.distance_squared_to(ball.global_position)
		if d < my_d:
			return false
	return true

func _decide_kick() -> void:
	if _kick_cooldown > 0.0:
		return
	if not player.can_kick():
		return
	var has: bool = player.has_ball()
	if has:
		if _try_first_time_shot_or_pass():
			return
		if _try_shoot():
			return
		if _try_pass():
			return
		return
	if _should_clear_kick():
		var clear_dir: Vector2 = (enemy_goal_pos - player.global_position).normalized()
		player.kick_directed(clear_dir, randf_range(0.55, 0.85))
		_kick_cooldown = 0.4

func _try_shoot() -> bool:
	var dist_to_goal: float = player.global_position.distance_to(enemy_goal_pos)
	if dist_to_goal > shoot_range:
		return false
	if not _shot_lane_clear():
		return false
	var power: float = clamp(0.65 + (1.0 - dist_to_goal / shoot_range) * 0.4, 0.65, 1.0)
	var dir: Vector2 = (enemy_goal_pos - player.global_position).normalized()
	player.kick_directed(dir, power)
	_kick_cooldown = 0.55
	return true

func _try_first_time_shot_or_pass() -> bool:
	var ball_speed: float = ball.linear_velocity.length()
	var recent: bool = (Time.get_ticks_msec() / 1000.0) - 0.0 < first_time_recent_owner_secs
	if ball_speed < 220.0:
		return false
	var dist_goal: float = player.global_position.distance_to(enemy_goal_pos)
	if dist_goal < shoot_range * 0.85 and _shot_lane_clear():
		var dir: Vector2 = (enemy_goal_pos - player.global_position).normalized()
		player.kick_directed(dir, 1.0)
		_kick_cooldown = 0.5
		return true
	return false

func _try_pass() -> bool:
	var target: Player = _find_pass_target()
	if target == null:
		return false
	var lead_pos: Vector2 = target.global_position + target.linear_velocity * pass_lead_time
	var dir: Vector2 = lead_pos - player.global_position
	var dist: float = dir.length()
	if dist < pass_min_distance or dist > pass_max_distance:
		return false
	dir = dir / dist
	var power: float = lerp(pass_min_power, pass_max_power, clamp(dist / pass_max_distance, 0.0, 1.0))
	player.kick_directed(dir, power)
	_kick_cooldown = 0.5
	_last_pass_target_id = target.get_instance_id()
	return true

func _find_pass_target() -> Player:
	var teammates: Array = _team_mates()
	var my_score: float = _position_score(player.global_position)
	var best: Player = null
	var best_score: float = my_score + pass_score_advantage
	for tm in teammates:
		if tm == player or not (tm is Player):
			continue
		var tmp: Player = tm as Player
		var lead_pos: Vector2 = tmp.global_position + tmp.linear_velocity * pass_lead_time
		var dist: float = player.global_position.distance_to(lead_pos)
		if dist < pass_min_distance or dist > pass_max_distance:
			continue
		if not _pass_lane_clear(player.global_position, lead_pos):
			continue
		var s: float = _position_score(lead_pos)
		if s > best_score:
			best_score = s
			best = tmp
	return best

func _position_score(pos: Vector2) -> float:
	var goal_dist: float = pos.distance_to(enemy_goal_pos)
	var space: float = _open_space(pos)
	return -goal_dist * 0.5 + space * 0.4

func _open_space(pos: Vector2) -> float:
	var enemies: Array = _opponents()
	var min_d: float = 9999.0
	for e in enemies:
		if not (e is Player):
			continue
		var d: float = pos.distance_to((e as Player).global_position)
		if d < min_d:
			min_d = d
	return clamp(min_d, 0.0, 300.0)

func _pass_lane_clear(from_pos: Vector2, to_pos: Vector2) -> bool:
	var seg: Vector2 = to_pos - from_pos
	var seg_len_sq: float = seg.length_squared()
	if seg_len_sq < 0.001:
		return true
	for e in _opponents():
		if not (e is Player):
			continue
		var ep: Vector2 = (e as Player).global_position
		var rel: Vector2 = ep - from_pos
		var t: float = clamp(rel.dot(seg) / seg_len_sq, 0.0, 1.0)
		var closest: Vector2 = from_pos + seg * t
		if closest.distance_to(ep) < pass_lane_clearance:
			return false
	return true

func _shot_lane_clear() -> bool:
	return _pass_lane_clear(player.global_position, enemy_goal_pos)

func _team_mates() -> Array:
	var group: String = "team_home" if player.team == MatchState.TEAM_HOME else "team_away"
	return player.get_tree().get_nodes_in_group(group)

func _opponents() -> Array:
	var group: String = "team_away" if player.team == MatchState.TEAM_HOME else "team_home"
	return player.get_tree().get_nodes_in_group(group)

func _should_clear_kick() -> bool:
	if player.global_position.distance_to(ball.global_position) > 26.0:
		return false
	if _ball_in_own_third():
		return true
	return false
