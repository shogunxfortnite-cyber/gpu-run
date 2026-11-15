extends Button

func _ready():
	pressed.connect(_on_start)

func _on_start():
	get_tree().change_scene_to_file("res://node.tscn")
