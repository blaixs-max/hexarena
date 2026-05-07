extends Node2D
class_name GoalBurst

@onready var particles: CPUParticles2D = $Particles

func setup_color(col: Color) -> void:
	if particles:
		var grad := Gradient.new()
		grad.add_point(0.0, Color(1, 1, 1, 1))
		grad.add_point(0.4, col)
		grad.add_point(1.0, Color(col.r, col.g, col.b, 0.0))
		particles.color_ramp = grad

func play() -> void:
	if particles:
		particles.emitting = true
	await get_tree().create_timer(2.0).timeout
	queue_free()
