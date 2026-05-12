extends Control
class_name KickButton

signal kick_requested(power: float)

@export var max_charge_time := 0.6
@export var min_kick_power := 0.35
@export var arc_color := Color(1, 0.95, 0.4, 1)
@export var arc_color_full := Color(0.4, 1, 0.5, 1)
@export var charge_color_low := Color(0.30, 0.85, 0.35, 1)
@export var charge_color_mid := Color(1.0, 0.85, 0.20, 1)
@export var charge_color_high := Color(1.0, 0.25, 0.20, 1)
@export var inner_color_top := Color(1.0, 0.65, 0.18, 1)
@export var inner_color_bot := Color(0.85, 0.32, 0.1, 1)
@export var press_scale := 0.94
@export var instant := false
@export var fixed_power := 0.5
@export var label_text := ""
@export var minimal_mode := false
@export var icon_kind := ""
@export var icon_color := Color(1, 1, 1, 0.95)
@export var label_color := Color(1, 1, 1, 0.95)
@export var letter := ""

var _holding := false
var _hold_start := 0.0
var _charge := 0.0
var _external_charging := false
var _external_charge_start := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	gui_input.connect(_on_input)
	pivot_offset = size * 0.5
	queue_redraw()

func _on_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_start()
		else:
			_release()
	elif event is InputEventScreenTouch:
		if event.pressed:
			_start()
		else:
			_release()

func _start() -> void:
	_holding = true
	_hold_start = Time.get_ticks_msec() / 1000.0
	var t := create_tween()
	t.tween_property(self, "scale", Vector2(press_scale, press_scale), 0.08).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if instant:
		kick_requested.emit(fixed_power)

func _release() -> void:
	if not _holding:
		return
	_holding = false
	if not instant:
		var power: float = lerp(min_kick_power, 1.0, _charge)
		kick_requested.emit(power)
	_charge = 0.0
	queue_redraw()
	var t := create_tween()
	t.tween_property(self, "scale", Vector2.ONE, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _process(_d: float) -> void:
	if _holding:
		_charge = clamp((Time.get_ticks_msec() / 1000.0 - _hold_start) / max_charge_time, 0.0, 1.0)
	elif _external_charging:
		_charge = clamp((Time.get_ticks_msec() / 1000.0 - _external_charge_start) / max_charge_time, 0.0, 1.0)
	queue_redraw()

func external_charge_start() -> void:
	_external_charging = true
	_external_charge_start = Time.get_ticks_msec() / 1000.0
	_charge = 0.0

func external_charge_release() -> void:
	_external_charging = false
	_charge = 0.0
	queue_redraw()

func _draw() -> void:
	if minimal_mode:
		_draw_minimal()
		return
	var c: Vector2 = size * 0.5
	var r_outer: float = min(size.x, size.y) * 0.5 - 4.0
	var r_inner: float = r_outer - 14.0
	draw_circle(c + Vector2(3, 5), r_outer, Color(0, 0, 0, 0.45))
	_draw_grad_circle(c, r_inner, inner_color_top, inner_color_bot)
	draw_arc(c, r_outer - 7.0, 0.0, TAU, 64, Color(0.05, 0.06, 0.1, 0.85), 6.0, true)
	var charge_col: Color = _charge_color_lerp(_charge)
	if _charge > 0.0:
		draw_arc(c, r_outer - 7.0, -PI * 0.5, -PI * 0.5 + TAU * _charge, 64, charge_col, 6.0, true)
	if label_text != "":
		_draw_label_text(c, r_inner)
	else:
		_draw_ball_icon(c, r_inner * 0.55)
	if _holding or _external_charging:
		draw_arc(c, r_outer + 4.0, 0.0, TAU, 48, Color(charge_col.r, charge_col.g, charge_col.b, 0.35 * _charge), 3.0, true)

func _draw_minimal() -> void:
	var c: Vector2 = size * 0.5
	var r: float = min(size.x, size.y) * 0.5 - 4.0
	# Beyaz transparan daire arka plan (Dream League tarzı)
	draw_circle(c, r, Color(1, 1, 1, 0.12))
	draw_arc(c, r - 1.5, 0.0, TAU, 48, Color(1, 1, 1, 0.55), 3.0, true)
	var icon_pos: Vector2 = c + Vector2(0, -r * 0.32)
	var icon_size: float = r * 0.55
	var glow: float = 0.0
	if _holding or _external_charging:
		glow = 0.25 + 0.4 * _charge
	if glow > 0.0:
		var charge_col: Color = _charge_color_lerp(_charge)
		draw_arc(c, r * 0.92, 0.0, TAU, 48, Color(charge_col.r, charge_col.g, charge_col.b, glow), 4.0, true)
		if _charge > 0.01:
			draw_arc(c, r * 0.92, -PI * 0.5, -PI * 0.5 + TAU * _charge, 48, charge_col, 5.0, true)
	if letter != "":
		_draw_letter(c + Vector2(0, -r * 0.10), r * 0.92)
	else:
		match icon_kind:
			"ball_foot":
				_draw_ball_foot_icon(icon_pos, icon_size)
			"arrow":
				_draw_arrow_icon(icon_pos, icon_size)
			"lightning":
				_draw_lightning_icon(icon_pos, icon_size)
			"ball":
				_draw_ball_icon(icon_pos, icon_size)
			_:
				_draw_ball_icon(icon_pos, icon_size)
	if label_text != "":
		_draw_minimal_label(c + Vector2(0, r * 0.62), r * 0.85)

func _draw_letter(center: Vector2, r: float) -> void:
	var f: Font = ThemeDB.fallback_font
	if f == null:
		return
	var sz: int = int(r * 1.05)
	var ts: Vector2 = f.get_string_size(letter, HORIZONTAL_ALIGNMENT_CENTER, -1, sz)
	var pos: Vector2 = center + Vector2(-ts.x * 0.5, ts.y * 0.32)
	draw_string_outline(f, pos, letter, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, 5, Color(0, 0, 0, 0.65))
	draw_string(f, pos, letter, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, icon_color)

func _draw_minimal_label(center: Vector2, r: float) -> void:
	var f: Font = ThemeDB.fallback_font
	if f == null:
		return
	var sz: int = int(r * 0.42)
	var ts: Vector2 = f.get_string_size(label_text, HORIZONTAL_ALIGNMENT_CENTER, -1, sz)
	var pos: Vector2 = center + Vector2(-ts.x * 0.5, ts.y * 0.32)
	draw_string_outline(f, pos, label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, 5, Color(0, 0, 0, 0.85))
	draw_string(f, pos, label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, label_color)

func _draw_arrow_icon(center: Vector2, r: float) -> void:
	var col: Color = icon_color
	var raw_pts: PackedVector2Array = PackedVector2Array([
		Vector2(-r * 0.75, -r * 0.22),
		Vector2(r * 0.10, -r * 0.22),
		Vector2(r * 0.10, -r * 0.55),
		Vector2(r * 0.80, 0),
		Vector2(r * 0.10, r * 0.55),
		Vector2(r * 0.10, r * 0.22),
		Vector2(-r * 0.75, r * 0.22),
	])
	var ang: float = -PI / 5.0
	var co: float = cos(ang)
	var si: float = sin(ang)
	var rotated: PackedVector2Array = PackedVector2Array()
	for p in raw_pts:
		var x: float = p.x * co - p.y * si
		var y: float = p.x * si + p.y * co
		rotated.append(center + Vector2(x, y))
	draw_colored_polygon(rotated, col)

func _draw_lightning_icon(center: Vector2, r: float) -> void:
	var col: Color = icon_color
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

func _draw_ball_foot_icon(center: Vector2, r: float) -> void:
	var col: Color = icon_color
	var ball_c: Vector2 = center + Vector2(-r * 0.55, -r * 0.55)
	var ball_r: float = r * 0.34
	draw_circle(ball_c, ball_r, col)
	draw_arc(ball_c, ball_r, 0.0, TAU, 24, Color(0, 0, 0, 0.6), 1.5, true)
	_draw_hex(ball_c, ball_r * 0.42, Color(0, 0, 0, 0.7))
	var foot_pts: PackedVector2Array = PackedVector2Array([
		center + Vector2(-r * 0.55, r * 0.45),
		center + Vector2(-r * 0.15, r * 0.05),
		center + Vector2(r * 0.30, -r * 0.10),
		center + Vector2(r * 0.65, -r * 0.05),
		center + Vector2(r * 0.85, r * 0.15),
		center + Vector2(r * 0.80, r * 0.45),
	])
	draw_colored_polygon(foot_pts, col)
	for i in 3:
		var sx: float = -r * 0.20 + float(i) * r * 0.30
		var stud_pts: PackedVector2Array = PackedVector2Array([
			center + Vector2(sx - r * 0.07, r * 0.45),
			center + Vector2(sx + r * 0.07, r * 0.45),
			center + Vector2(sx + r * 0.07, r * 0.62),
			center + Vector2(sx - r * 0.07, r * 0.62),
		])
		draw_colored_polygon(stud_pts, col)

func _charge_color_lerp(t: float) -> Color:
	if t < 0.5:
		return charge_color_low.lerp(charge_color_mid, t * 2.0)
	return charge_color_mid.lerp(charge_color_high, (t - 0.5) * 2.0)

func _draw_label_text(center: Vector2, r_inner: float) -> void:
	var f: Font = ThemeDB.fallback_font
	if f == null:
		return
	var sz: int = int(r_inner * 0.55)
	var ts: Vector2 = f.get_string_size(label_text, HORIZONTAL_ALIGNMENT_CENTER, -1, sz)
	var pos: Vector2 = center + Vector2(-ts.x * 0.5, ts.y * 0.32)
	draw_string_outline(f, pos, label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, 4, Color(0, 0, 0, 0.7))
	draw_string(f, pos, label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, sz, Color(1, 1, 1, 1))

func _draw_grad_circle(center: Vector2, r: float, top: Color, bot: Color) -> void:
	var bands := 12
	for i in bands:
		var t: float = float(i) / float(bands - 1)
		var col: Color = top.lerp(bot, t)
		var y_top: float = center.y + (-r + (2.0 * r * float(i) / float(bands)))
		var band_h: float = (2.0 * r) / float(bands)
		var w_y: float = -r + (2.0 * r * (float(i) + 0.5) / float(bands))
		var hw: float = sqrt(max(0.0, r * r - w_y * w_y))
		draw_rect(Rect2(center.x - hw, y_top, hw * 2.0, band_h + 0.5), col, true)
	draw_circle(center, r, Color(1, 1, 1, 0))
	draw_arc(center, r, 0.0, TAU, 64, Color(1, 1, 1, 0.18), 2.0, true)

func _draw_ball_icon(center: Vector2, r: float) -> void:
	draw_circle(center, r, Color(1, 1, 1, 0.95))
	draw_arc(center, r, 0.0, TAU, 32, Color(0.05, 0.06, 0.1, 1), 2.0, true)
	var hex_r: float = r * 0.34
	for i in 5:
		var ang: float = TAU * float(i) / 5.0 - PI * 0.5
		var p: Vector2 = center + Vector2(cos(ang), sin(ang)) * (r * 0.55)
		_draw_hex(p, hex_r, Color(0.06, 0.07, 0.1, 1))
	_draw_hex(center, r * 0.42, Color(0.06, 0.07, 0.1, 1))

func _draw_hex(c: Vector2, r: float, col: Color) -> void:
	var pts: PackedVector2Array = []
	for i in 6:
		var a: float = TAU * float(i) / 6.0
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	draw_colored_polygon(pts, col)
