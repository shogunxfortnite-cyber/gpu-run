extends CharacterBody2D

@export var grace_time = 4.0

var base_speed = 175.0
var predict_time = 0.0
var kill_distance = 16.0
var accel = 1400.0
var maker = "Intel"
var player = null
var grace_left = 0.0
var path = []
var repath_left = 0.0
var stuck_check = 0.0
var stuck_time = 0.0
var last_pos = Vector2.ZERO

@onready var sprite = get_node_or_null("Sprite2D")

func _ready():
	var tint = Color(0.2, 0.5, 1.0)
	if name.to_lower().begins_with("amd"):
		maker = "AMD"
		base_speed = 150.0
		predict_time = 0.7
		tint = Color(1.0, 0.2, 0.2)
	if sprite:
		sprite.modulate = tint
	grace_left = grace_time
	last_pos = global_position

func _physics_process(delta):
	if player == null:
		player = get_tree().get_first_node_in_group("player")
		return

	if grace_left > 0.0:
		grace_left -= delta
		return

	var speed = base_speed * (1.0 + 0.03 * player.gpus)
	var aim = player.global_position + player.velocity * predict_time
	var dist = global_position.distance_to(player.global_position)

	repath_left -= delta
	if repath_left <= 0.0:
		repath_left = 0.25
		path = player.find_path(global_position, aim)

	var target = aim
	if dist < 200.0 and clear_to(player.global_position):
		target = player.global_position
	else:
		for i in range(6):
			if path.size() > 1 and clear_to(path[1]):
				path.pop_front()
			else:
				break
		while path.size() > 0 and global_position.distance_to(path[0]) < 8.0:
			path.pop_front()
		if path.size() > 0:
			target = path[0]

	var dir = (target - global_position).normalized()
	velocity = velocity.move_toward(dir * speed, accel * delta)
	move_and_slide()

	stuck_check += delta
	if stuck_check >= 0.4:
		var moved = global_position.distance_to(last_pos)
		last_pos = global_position
		stuck_check = 0.0
		if moved < 5.0:
			stuck_time += 0.4
		else:
			stuck_time = 0.0
		if stuck_time >= 0.8:
			stuck_time = 0.0
			repath_left = 0.0

	if sprite and velocity.length() > 1.0:
		sprite.rotation = lerp_angle(sprite.rotation, velocity.angle(), 12.0 * delta)

	for i in get_slide_collision_count():
		if get_slide_collision(i).get_collider() == player:
			player.die(maker)
			return

	if dist < kill_distance:
		player.die(maker)

func clear_to(point):
	var d = point - global_position
	var side = Vector2(-d.y, d.x).normalized() * 7.0
	for offset in [Vector2.ZERO, side, -side]:
		var q = PhysicsRayQueryParameters2D.create(global_position + offset, point + offset)
		q.exclude = [get_rid()]
		var r = get_world_2d().direct_space_state.intersect_ray(q)
		if r.size() > 0 and r.collider != player:
			return false
	return true
