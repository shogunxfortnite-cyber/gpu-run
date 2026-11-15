extends Area2D

var time = 0.0

@onready var sprite = get_node_or_null("Sprite2D")

func _ready():
	add_to_group("gpu")
	monitoring = false
	monitorable = false

func _process(delta):
	time += delta
	if sprite:
		sprite.rotation = sin(time * 3.0) * 0.15
		var pulse = (sin(time * 4.0) + 1.0) * 0.25
		sprite.modulate = Color(0.46, 0.73, 0.0).lerp(Color(1, 1, 1), pulse)
