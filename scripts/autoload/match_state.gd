extends Node

signal score_changed(home: int, away: int)
signal goal_scored(scoring_team: int)
signal time_changed(seconds_left: float)
signal match_started
signal match_ended(home: int, away: int)
signal kickoff_started(kicker_team: int)
signal kickoff_ended
signal awaiting_kickoff_pass_started(kicker_team: int)
signal awaiting_kickoff_pass_ended
signal teams_set(home_name: String, away_name: String)

const TEAM_HOME := 0
const TEAM_AWAY := 1

const GOAL_LIMIT := 3
const MATCH_DURATION := 180.0
const KICKOFF_FREEZE_INITIAL := 1.5
const KICKOFF_FREEZE_AFTER_GOAL := 3.2

const TEAM_NAMES := [
	"FC Lupus", "Red Wolves", "Crimson Stars", "Phoenix United",
	"Iron Hearts", "Storm Riders", "Falcon SK", "Titan FC",
	"Black Hawks", "Royal Lions", "Yıldız SK", "Kale FC",
	"Atilla SK", "Zafer FC", "Şahin United", "Aslan SK",
	"Kartal FC", "Boğa United", "Anka SK", "Fırtına FC",
	"Demir SK", "Çelik FC", "Kaplan United", "Şimşek SK"
]

var home_score := 0
var away_score := 0
var time_left := MATCH_DURATION
var running := false
var freeze_until := 0.0
var current_kicker := TEAM_HOME
var awaiting_kickoff_pass := false
var awaiting_pass_started_at := 0.0
var _was_frozen := false

var home_team_name := "HOME"
var away_team_name := "AWAY"

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func reset_match() -> void:
	home_score = 0
	away_score = 0
	time_left = MATCH_DURATION
	running = false
	freeze_until = 0.0
	current_kicker = TEAM_HOME
	awaiting_kickoff_pass = false
	_pick_random_teams()
	score_changed.emit(home_score, away_score)
	time_changed.emit(time_left)
	teams_set.emit(home_team_name, away_team_name)

func begin_awaiting_pass() -> void:
	awaiting_kickoff_pass = true
	awaiting_pass_started_at = Time.get_ticks_msec() / 1000.0
	awaiting_kickoff_pass_started.emit(current_kicker)

func mark_kickoff_pass_taken() -> void:
	if not awaiting_kickoff_pass:
		return
	awaiting_kickoff_pass = false
	awaiting_kickoff_pass_ended.emit()

func seconds_since_awaiting() -> float:
	if not awaiting_kickoff_pass:
		return 0.0
	return Time.get_ticks_msec() / 1000.0 - awaiting_pass_started_at

func _pick_random_teams() -> void:
	var pool: Array = TEAM_NAMES.duplicate()
	pool.shuffle()
	home_team_name = pool[0]
	away_team_name = pool[1]

func start_match() -> void:
	running = true
	current_kicker = TEAM_HOME
	match_started.emit()
	begin_kickoff(KICKOFF_FREEZE_INITIAL)

func begin_kickoff(duration := KICKOFF_FREEZE_INITIAL) -> void:
	freeze_until = Time.get_ticks_msec() / 1000.0 + duration
	_was_frozen = true
	kickoff_started.emit(current_kicker)

func is_frozen() -> bool:
	return Time.get_ticks_msec() / 1000.0 < freeze_until

func _process(delta: float) -> void:
	if not running:
		return
	var frozen_now: bool = is_frozen()
	if _was_frozen and not frozen_now:
		kickoff_ended.emit()
	_was_frozen = frozen_now
	if frozen_now:
		return
	time_left = max(0.0, time_left - delta)
	time_changed.emit(time_left)
	if time_left <= 0.0:
		_end_match()

func register_goal(team: int) -> void:
	if team == TEAM_HOME:
		home_score += 1
	else:
		away_score += 1
	score_changed.emit(home_score, away_score)
	goal_scored.emit(team)
	if home_score >= GOAL_LIMIT or away_score >= GOAL_LIMIT:
		_end_match()
	else:
		current_kicker = TEAM_AWAY if team == TEAM_HOME else TEAM_HOME
		begin_kickoff(KICKOFF_FREEZE_AFTER_GOAL)

func _end_match() -> void:
	running = false
	match_ended.emit(home_score, away_score)
