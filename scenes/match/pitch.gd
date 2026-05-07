extends Node2D
class_name Pitch

signal goal_triggered(scoring_team: int)

@onready var goal_left_area: Area2D = $GoalLeftArea
@onready var goal_right_area: Area2D = $GoalRightArea
@onready var center_marker: Node2D = $CenterMarker

const FIELD_HALF := Vector2(800.0, 400.0)
const GOAL_HALF_HEIGHT := 110.0

func _ready() -> void:
	goal_left_area.body_entered.connect(_on_left_goal)
	goal_right_area.body_entered.connect(_on_right_goal)

func ball_spawn() -> Vector2:
	return center_marker.global_position

func home_positions(kicker_team: int) -> Array:
	if kicker_team == 0:
		return [Vector2(-30, 0), Vector2(-340, -180), Vector2(-580, 180)]
	return [Vector2(-260, 0), Vector2(-500, -180), Vector2(-680, 180)]

func away_positions(kicker_team: int) -> Array:
	if kicker_team == 1:
		return [Vector2(30, 0), Vector2(340, -180), Vector2(580, 180)]
	return [Vector2(260, 0), Vector2(500, -180), Vector2(680, 180)]

func _on_left_goal(body: Node) -> void:
	if body.is_in_group("ball"):
		goal_triggered.emit(MatchState.TEAM_AWAY)

func _on_right_goal(body: Node) -> void:
	if body.is_in_group("ball"):
		goal_triggered.emit(MatchState.TEAM_HOME)
