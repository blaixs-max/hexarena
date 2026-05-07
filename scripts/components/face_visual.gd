extends Node2D
class_name FaceVisual

@export var skin_color := Color(0.97, 0.82, 0.65)
@export var hair_color := Color(0.18, 0.13, 0.08)
@export var hair_style := 0
@export var has_beard := false
@export var face_radius := 17.0

func _ready() -> void:
	_build()

func _build() -> void:
	for c in get_children():
		c.queue_free()
	_add_skin()
	_add_hair()
	_add_eyes()
	_add_mouth()
	if has_beard:
		_add_beard()

func _add_skin() -> void:
	var p := Polygon2D.new()
	p.color = skin_color
	p.polygon = _circle_pts(0, 0, face_radius, 28)
	add_child(p)

func _add_hair() -> void:
	var p := Polygon2D.new()
	p.color = hair_color
	match hair_style:
		0:
			p.polygon = PackedVector2Array([
				Vector2(-face_radius * 0.95, -face_radius * 0.15),
				Vector2(-face_radius * 0.85, -face_radius * 0.95),
				Vector2(-face_radius * 0.4, -face_radius * 1.05),
				Vector2(0, -face_radius * 1.10),
				Vector2(face_radius * 0.4, -face_radius * 1.05),
				Vector2(face_radius * 0.85, -face_radius * 0.95),
				Vector2(face_radius * 0.95, -face_radius * 0.15),
				Vector2(face_radius * 0.7, -face_radius * 0.55),
				Vector2(face_radius * 0.3, -face_radius * 0.7),
				Vector2(-face_radius * 0.3, -face_radius * 0.7),
				Vector2(-face_radius * 0.7, -face_radius * 0.55),
			])
		1:
			p.polygon = PackedVector2Array([
				Vector2(-face_radius * 0.9, -face_radius * 0.4),
				Vector2(-face_radius * 0.5, -face_radius * 1.05),
				Vector2(face_radius * 0.55, -face_radius * 1.05),
				Vector2(face_radius * 0.9, -face_radius * 0.45),
				Vector2(face_radius * 0.55, -face_radius * 0.85),
				Vector2(0, -face_radius * 0.95),
				Vector2(-face_radius * 0.55, -face_radius * 0.85),
			])
		2:
			p.polygon = PackedVector2Array([
				Vector2(-face_radius * 1.0, -face_radius * 0.3),
				Vector2(-face_radius * 0.95, -face_radius * 0.95),
				Vector2(0, -face_radius * 1.10),
				Vector2(face_radius * 0.95, -face_radius * 0.95),
				Vector2(face_radius * 1.0, -face_radius * 0.3),
				Vector2(face_radius * 0.5, -face_radius * 0.5),
				Vector2(-face_radius * 0.5, -face_radius * 0.5),
			])
		_:
			return
	add_child(p)

func _add_eyes() -> void:
	var ey: float = -face_radius * 0.12
	var ex: float = face_radius * 0.34
	for s in [-1, 1]:
		var sclera := Polygon2D.new()
		sclera.color = Color(1, 1, 1, 1)
		sclera.polygon = _circle_pts(ex * s, ey, face_radius * 0.18, 14)
		add_child(sclera)
		var pupil := Polygon2D.new()
		pupil.color = Color(0.06, 0.06, 0.10, 1)
		pupil.polygon = _circle_pts(ex * s, ey, face_radius * 0.10, 10)
		add_child(pupil)

func _add_mouth() -> void:
	var p := Polygon2D.new()
	p.color = Color(0.55, 0.22, 0.20, 1)
	var y: float = face_radius * 0.45
	var w: float = face_radius * 0.32
	p.polygon = PackedVector2Array([
		Vector2(-w, y),
		Vector2(w, y),
		Vector2(w * 0.7, y + face_radius * 0.16),
		Vector2(-w * 0.7, y + face_radius * 0.16),
	])
	add_child(p)

func _add_beard() -> void:
	var p := Polygon2D.new()
	p.color = hair_color
	var r := face_radius
	p.polygon = PackedVector2Array([
		Vector2(-r * 0.85, r * 0.15),
		Vector2(-r * 0.6, r * 0.85),
		Vector2(0, r * 1.0),
		Vector2(r * 0.6, r * 0.85),
		Vector2(r * 0.85, r * 0.15),
		Vector2(r * 0.55, r * 0.55),
		Vector2(-r * 0.55, r * 0.55),
	])
	add_child(p)

func _circle_pts(cx: float, cy: float, r: float, n: int) -> PackedVector2Array:
	var pts: PackedVector2Array = PackedVector2Array()
	for i in n:
		var a: float = float(i) * TAU / float(n)
		pts.append(Vector2(cx + cos(a) * r, cy + sin(a) * r))
	return pts
