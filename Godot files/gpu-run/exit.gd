extends Area2D

@onready var block = get_node_or_null("ColorRect")

func _ready():
	monitoring = false

func _process(delta):
	var p = get_tree().get_first_node_in_group("player")
	if p and block:
		if p.gpus >= p.total_gpus:
			block.color = Color(0.46, 0.73, 0.0)
		else:
			block.color = Color(0.8, 0.1, 0.1)
