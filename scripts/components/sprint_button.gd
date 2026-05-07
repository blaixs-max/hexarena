extends Control
class_name SprintButton

signal sprint_pressed
signal sprint_released

@export var inner_top := Color(0.30, 0.85, 0.35, 1)
@export var inner_bot := Color(0.18, 0.62, 0.22, 1)
@export var icon_color := Color(1, 1, 1, 0.95)
@export var label_text := ""
@export var label_color := Color(1, 1, 1, 1)
@export var press_scale := 0.92
@export var minimal_mode := false

var _holding := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	gui_input.connect(_on_input)
	pivot_offset = size * 0.5

func _on_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_press()
		else:
			_release()
	elif event is InputEventScreenTouch:
		if event.pressed:
			_press()
		else:
			_release()

func _press() -> void:
	if _holding:
		return
	_holding = true
	sprint_pressed.emit()
	var t := create_tween()
	t.tween_property(self, "scale", Vector2(press_scale, press_scale), 0.06)

func _release() -> void:
	if not _holding:
		return
	_holding = false
	sprint_released.emit()
	var t := create_tween()
	t.tween_property(self, "scale", Vector2.ONE, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func is_pressed_now() -> bool:
	return _holding

func _draw() -> void:
	if minimal_mode:
		_draw_minimal()
		return
	var c: Vector2 = size * 0.5
	var r_outer: float = min(size.x, size.y) * 0.5 - 4.0
	var r_inner: float = r_outer - 14.0
	draw_circle(c + Vector2(3, 5), r_outer, Color(0, 0, 0, 0.45))
	_draw_grad_circle(c, r_inner, inner_top, inner_bot)
	draw_arc(c, r_outer - 7.0, 0.0, TAU, 64, Color(0.05, 0.06, 0.1, 0.85), 6.0, true)
	if label_text != "":
		_draw_lightning(c + Vector2(0, -r_inner * 0.20), r_inner * 0.42)
		_draw_label(c + Vector2(0, r_inner * 0.55), r_inner * 0.42)
	else:
		_draw_lightning(c, r_inner * 0.55)

func _draw_minimal() -> void:
	var c: Vector2 = size * 0.5
	var r: float = min(size.x, size.y) * 0.5 - 4.0
	if _holding:
		draw_arc(c, r * 0.95, 0.0, TAU, 48, Color(icon_color.r, icon_color.g, icon_color.b, 0.45), 4.0, true)
	_draw_lightning(c + Vector2(0, -r * 0.32), r * 0.55)
	if label_text != "":
		_draw_label(c + Vector2(0, r * 0.62), r * 0.85)

func _draw_grad_circle(center: Vector2, r: float, top: Color, bot: Color) -> void:
	var bands := 14
	for i in bands:
		var t: float = float(i) / float(bands - 1)
		var col: Color = top.lerp(bot, t)
		var y_top: float = center.y + (-r + (2.0 * r * float(i) / float(bands)))
		var band_h: float = (2.0 * r) / float(bands)
		var w_y: float = -r + (2.0 * r * (float(i) + 0.5) / float(bands))
		var hw: float = sqrt(max(0.0, r * r - w_y * w_y))
		draw_rect(Rect2(center.x - hw, y_top, hw * 2.0, band_h + 0.5), col, true)
	draw_arc(center, r, 0.0, TAU, 64, Color(1, 1, 1, 0.18), 2.0, true)

func _draw_label(center: Vector2, r: float) -> void:
	var f: Font = ThemeDB.fallback_font
	if f == null:
		return
	var sz: int = int(r * 0.42)
	var ts: Vector2 = f.get_string_size(label_text, HORIZONTAL_ALIGNMENT_CENTER, -1, sz)
	var pos: Vector2 = center + Vector2(-ts.x * 0.5, ts.y * 0.32)
	draw_string_outline(f, pos, label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, 5, Color(0, 0, 0, 0.85))
	draw_string(f, pos, label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, label_color)

func _draw_lightning(center: Vector2, r: float) -> void:
	var col := icon_color
	var pts: PackedVector2Array = PackedVector2Array([
		center + Vector2(0.0, -r * 1.00),
		center + Vector2(r * 0.20, -r * 0.40),
		center + Vector2(r * 0.60, -r * 0.40),
		center + Vector2(0.0, r * 0.20),
		center + Vector2(r * 0.20, r * 0.20),
		center + Vector2(-r * 0.40, r * 1.00),
		center + Vector2(-r * 0.30, r * 0.40),
		center + Vector2(-r * 0.60, r * 0.40),
	])
	draw_colored_polygon(pts, col)
