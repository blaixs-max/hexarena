extends Control
class_name VirtualJoystick

@export var max_radius := 110.0
@export var dead_zone := 0.18
@export var anchor := Vector2(0.0, 0.4)
@export var size_frac := Vector2(0.5, 0.6)

var _touch_index := -1
var _origin := Vector2.ZERO
var _output := Vector2.ZERO

@onready var base: Control = $Base
@onready var knob: Control = $Base/Knob

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	base.visible = true
	_center_knob()

func get_vector() -> Vector2:
	return _output

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_handle_touch(event.index, event.pressed, event.position)
	elif event is InputEventScreenDrag and event.index == _touch_index:
		_update_drag(event.position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_handle_touch(0, event.pressed, event.position)
	elif event is InputEventMouseMotion and _touch_index == 0:
		_update_drag(event.position)

func _handle_touch(idx: int, pressed: bool, pos: Vector2) -> void:
	if pressed:
		if _touch_index != -1:
			return
		if not _is_in_base(pos):
			return
		_touch_index = idx
		_origin = base.global_position + base.size * 0.5
	elif idx == _touch_index:
		_touch_index = -1
		_output = Vector2.ZERO
		_center_knob()

func _update_drag(pos: Vector2) -> void:
	var delta: Vector2 = pos - _origin
	if delta.length() > max_radius:
		delta = delta.normalized() * max_radius
	knob.position = base.size * 0.5 + delta - knob.size * 0.5
	var raw: Vector2 = delta / max_radius
	_output = raw if raw.length() > dead_zone else Vector2.ZERO

func _is_in_base(pos: Vector2) -> bool:
	var rect := Rect2(base.global_position, base.size)
	return rect.has_point(pos)

func _center_knob() -> void:
	knob.position = base.size * 0.5 - knob.size * 0.5
