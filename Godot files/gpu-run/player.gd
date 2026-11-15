extends CharacterBody2D

const NAMES = ["RTX 5090", "RTX 5080", "RTX 5070 Ti", "RTX 5070", "RTX 4090", "RTX 4080", "RTX 4070 Ti", "RTX 3090", "RTX 3080", "RTX 2080 Ti"]

@export var walk_speed = 150.0
@export var sprint_speed = 235.0
@export var accel = 3600.0
@export var friction = 5200.0
@export var turn_boost = 1.8
@export var pickup_radius = 32.0
@export var exit_radius = 40.0
@export var zoom_level = 4.0
@export var total_gpus = 10
@export var music_path = "res://music.mp3"
@export var death_music_path = "res://death.mp3"
@export var music_volume = -6.0
@export var death_volume = -2.0

var gpus = 0
var stamina = 100.0
var exhausted = false
var dead = false
var finished = false
var ended_at = 0
var counter = null
var bar = null
var message = null
var pause_label = null
var pause_button = null
var music_player = null
var death_player = null
var msg_id = 0
var cam = null
var tilemap = null
var astar = null
var solid = {}
var cards = []
var exit_node = null
var inside_exit = false

@onready var sprite = $Sprite2D

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	wall_min_slide_angle = 0.0
	Engine.physics_ticks_per_second = 120
	add_to_group("player")
	RenderingServer.set_default_clear_color(Color(0, 0, 0))
	setup_camera()
	setup_hud()
	setup_music()
	call_deferred("setup_world")

func setup_world():
	var root = get_parent()
	exit_node = root.find_child("Exit", true, false)
	cards = []
	for n in root.find_children("*", "Area2D", true, false):
		if n == exit_node:
			continue
		var nm = String(n.name).to_lower()
		if nm.begins_with("gpu") or nm.begins_with("rtx") or n.is_in_group("gpu"):
			cards.append(n)
	setup_nav(root)
	if cards.size() > 0:
		total_gpus = cards.size()
		toast("Found " + str(cards.size()) + " RTX cards in the level. Collect them all, then escape!")
	else:
		toast("No cards found! Name your card nodes GPU, GPU2, GPU3...")
	if exit_node == null:
		print("GPU RUN: no node named Exit found")

func setup_camera():
	cam = find_child("Camera2D", true, false)
	if cam == null:
		cam = Camera2D.new()
		add_child(cam)
	cam.enabled = true
	cam.anchor_mode = Camera2D.ANCHOR_MODE_DRAG_CENTER
	cam.offset = Vector2.ZERO
	cam.rotation = 0.0
	cam.position = sprite.position
	cam.zoom = Vector2(zoom_level, zoom_level)
	cam.position_smoothing_enabled = false
	cam.drag_horizontal_enabled = false
	cam.drag_vertical_enabled = false
	cam.ignore_rotation = true
	cam.limit_smoothed = false
	cam.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	cam.limit_left = -10000000
	cam.limit_top = -10000000
	cam.limit_right = 10000000
	cam.limit_bottom = 10000000
	cam.make_current()

func setup_nav(root):
	var maps = root.find_children("*", "TileMap", true, false)
	if maps.is_empty():
		print("GPU RUN: no TileMap found, monsters will chase directly")
		return
	tilemap = maps[0]
	var ts = tilemap.tile_set
	var has_phys = ts != null and ts.get_physics_layers_count() > 0
	var rect = tilemap.get_used_rect().grow(2)

	astar = AStarGrid2D.new()
	astar.region = rect
	astar.cell_size = Vector2.ONE
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.update()

	for x in range(rect.position.x, rect.end.x):
		for y in range(rect.position.y, rect.end.y):
			var cell = Vector2i(x, y)
			var has_tile = false
			var wall = false
			for layer in tilemap.get_layers_count():
				var td = tilemap.get_cell_tile_data(layer, cell)
				if td:
					has_tile = true
					if has_phys and td.get_collision_polygons_count(0) > 0:
						wall = true
			if wall or not has_tile:
				astar.set_point_solid(cell, true)
				solid[cell] = true

	var sides = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for x in range(rect.position.x, rect.end.x):
		for y in range(rect.position.y, rect.end.y):
			var cell = Vector2i(x, y)
			if solid.has(cell):
				continue
			for s in sides:
				if solid.has(cell + s):
					astar.set_point_weight_scale(cell, 3.0)
					break

func to_cell(world):
	return tilemap.local_to_map(tilemap.to_local(world))

func cell_to_world(cell):
	return tilemap.to_global(tilemap.map_to_local(cell))

func open_cell(cell):
	if astar.is_in_boundsv(cell) and not astar.is_point_solid(cell):
		return cell
	for r in range(1, 8):
		for dx in range(-r, r + 1):
			for dy in range(-r, r + 1):
				if max(abs(dx), abs(dy)) == r:
					var c = cell + Vector2i(dx, dy)
					if astar.is_in_boundsv(c) and not astar.is_point_solid(c):
						return c
	return cell

func find_path(from_world, to_world):
	var result = []
	if astar == null or tilemap == null:
		return result
	var a = open_cell(to_cell(from_world))
	var b = open_cell(to_cell(to_world))
	if not astar.is_in_boundsv(a) or not astar.is_in_boundsv(b):
		return result
	var ids = astar.get_id_path(a, b)
	for c in ids:
		result.append(cell_to_world(c))
	return result

func setup_music():
	if ResourceLoader.exists(music_path):
		var stream = load(music_path)
		if "loop" in stream:
			stream.loop = true
		music_player = AudioStreamPlayer.new()
		music_player.stream = stream
		music_player.volume_db = music_volume
		add_child(music_player)
		music_player.play()
	if ResourceLoader.exists(death_music_path):
		var dstream = load(death_music_path)
		if "loop" in dstream:
			dstream.loop = false
		death_player = AudioStreamPlayer.new()
		death_player.stream = dstream
		death_player.volume_db = death_volume
		add_child(death_player)

func make_button(text, parent):
	var b = Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(b)
	return b

func setup_hud():
	var layer = CanvasLayer.new()
	layer.layer = 50
	add_child(layer)

	var top = ColorRect.new()
	top.color = Color(0, 0, 0, 0.7)
	top.custom_minimum_size = Vector2(0, 48)
	layer.add_child(top)
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)

	counter = Label.new()
	counter.position = Vector2(16, 8)
	counter.add_theme_font_size_override("font_size", 24)
	counter.add_theme_color_override("font_color", Color(0.46, 0.73, 0.0))
	top.add_child(counter)

	var back = ColorRect.new()
	back.color = Color(0.15, 0.15, 0.15)
	back.position = Vector2(330, 16)
	back.size = Vector2(204, 16)
	top.add_child(back)

	bar = ColorRect.new()
	bar.color = Color(0.46, 0.73, 0.0)
	bar.position = Vector2(332, 18)
	bar.size = Vector2(200, 12)
	top.add_child(bar)

	var box = HBoxContainer.new()
	box.anchor_left = 1.0
	box.anchor_right = 1.0
	box.offset_left = -330.0
	box.offset_right = -10.0
	box.offset_top = 6.0
	box.offset_bottom = 42.0
	box.add_theme_constant_override("separation", 8)
	top.add_child(box)

	pause_button = make_button("Pause", box)
	pause_button.pressed.connect(toggle_pause)
	var restart_button = make_button("Restart", box)
	restart_button.pressed.connect(restart_game)
	var menu_button = make_button("Menu", box)
	menu_button.pressed.connect(go_to_menu)

	message = Label.new()
	message.position = Vector2(16, 58)
	message.add_theme_font_size_override("font_size", 24)
	layer.add_child(message)

	pause_label = Label.new()
	pause_label.text = "PAUSED\n\nPress ESC or Resume"
	pause_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pause_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pause_label.add_theme_font_size_override("font_size", 44)
	pause_label.add_theme_color_override("font_color", Color(1, 1, 1))
	pause_label.visible = false
	pause_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(pause_label)
	pause_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

func toggle_pause():
	if dead or finished:
		return
	get_tree().paused = not get_tree().paused
	pause_label.visible = get_tree().paused
	if get_tree().paused:
		pause_button.text = "Resume"
	else:
		pause_button.text = "Pause"

func restart_game():
	get_tree().paused = false
	get_tree().reload_current_scene()

func go_to_menu():
	get_tree().paused = false
	get_tree().change_scene_to_file("res://main_menu.tscn")

func toast(text):
	msg_id += 1
	var id = msg_id
	message.text = text
	await get_tree().create_timer(4.0).timeout
	if id == msg_id and is_instance_valid(message):
		message.text = ""

func _process(delta):
	counter.text = "RTX CARDS  " + str(gpus) + " / " + str(total_gpus)
	bar.size.x = 200.0 * stamina / 100.0
	if exhausted:
		bar.color = Color(0.9, 0.2, 0.1)
	else:
		bar.color = Color(0.46, 0.73, 0.0)
	if Input.is_action_just_pressed("ui_cancel"):
		toggle_pause()
	if dead and Time.get_ticks_msec() - ended_at > 800:
		if Input.is_action_just_pressed("ui_accept"):
			get_tree().paused = false
			get_tree().reload_current_scene()

func read_input():
	var k = Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_A):
		k.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D):
		k.x += 1.0
	if Input.is_physical_key_pressed(KEY_W):
		k.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S):
		k.y += 1.0
	if k != Vector2.ZERO:
		return k.normalized()
	return Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")

func _physics_process(delta):
	if dead or finished or get_tree().paused:
		return
	var dir = read_input()
	var wants_sprint = Input.is_key_pressed(KEY_SHIFT) and dir != Vector2.ZERO
	var sprinting = wants_sprint and not exhausted and stamina > 0.0
	if sprinting:
		stamina = max(0.0, stamina - 35.0 * delta)
		if stamina <= 0.0:
			exhausted = true
	else:
		stamina = min(100.0, stamina + 22.0 * delta)
		if exhausted and stamina >= 30.0:
			exhausted = false

	var speed = walk_speed
	if sprinting:
		speed = sprint_speed
	var target = dir * speed
	if dir != Vector2.ZERO:
		var a = accel
		if velocity.dot(target) < 0.0:
			a *= turn_boost
		velocity = velocity.move_toward(target, a * delta)
		sprite.rotation = lerp_angle(sprite.rotation, dir.angle(), 22.0 * delta)
	else:
		velocity = velocity.move_toward(Vector2.ZERO, friction * delta)
	move_and_slide()

	if cam:
		cam.global_position = sprite.global_position
	check_pickups()

func visual_pos(n):
	var s = n.get_node_or_null("Sprite2D")
	if s:
		return s.global_position
	var c = n.get_node_or_null("CollisionShape2D")
	if c:
		return c.global_position
	return n.global_position

func exit_pos():
	var c = exit_node.get_node_or_null("CollisionShape2D")
	if c:
		return c.global_position
	var r = exit_node.get_node_or_null("ColorRect")
	if r:
		return r.global_position + r.size / 2.0
	return exit_node.global_position

func check_pickups():
	var here = sprite.global_position
	for i in range(cards.size()):
		var card = cards[i]
		if not is_instance_valid(card) or card.is_queued_for_deletion():
			continue
		if here.distance_to(visual_pos(card)) < pickup_radius:
			card.hide()
			card.queue_free()
			collect(NAMES[i % NAMES.size()])
	if exit_node and is_instance_valid(exit_node):
		var near = here.distance_to(exit_pos()) < exit_radius
		if near and not inside_exit:
			try_exit()
		inside_exit = near

func collect(card_name):
	gpus += 1
	if gpus >= total_gpus:
		toast("All cards found! Run to the EXIT!")
	else:
		toast("Found " + card_name + "   (" + str(gpus) + "/" + str(total_gpus) + ")")

func try_exit():
	if dead or finished:
		return
	if gpus >= total_gpus:
		win_game()
	else:
		toast("Exit locked. " + str(total_gpus - gpus) + " cards still missing!")

func win_game():
	finished = true
	get_tree().paused = true
	if music_player:
		music_player.stop()
	show_screen("CONGRATULATIONS!", "You escaped with all " + str(total_gpus) + " RTX cards!\n\nReturning to the main menu...", Color(0.46, 0.73, 0.0), Color(1, 1, 1), Color(0, 0.04, 0, 0.92))
	await get_tree().create_timer(3.0).timeout
	if not is_inside_tree():
		return
	get_tree().paused = false
	get_tree().change_scene_to_file("res://main_menu.tscn")

func die(by = "A"):
	if dead or finished:
		return
	dead = true
	ended_at = Time.get_ticks_msec()
	get_tree().paused = true
	if music_player:
		music_player.stop()
	if death_player:
		death_player.play()
	var sub_color = Color(1.0, 0.25, 0.25)
	if by == "Intel":
		sub_color = Color(0.3, 0.6, 1.0)
	var sub = "Killed by the " + by.to_upper() + " monster\n\nPress SPACE to respawn"
	show_screen("YOU DIED", sub, Color(0.8, 0.05, 0.05), sub_color, Color(0.04, 0, 0, 0.92))

func show_screen(title, sub, title_color, sub_color, bg_color):
	var layer = CanvasLayer.new()
	layer.layer = 100
	add_child(layer)

	var bg = ColorRect.new()
	bg.color = bg_color
	layer.add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var box = VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 20)
	layer.add_child(box)
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var title_label = Label.new()
	title_label.text = title
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 72)
	title_label.add_theme_color_override("font_color", title_color)
	box.add_child(title_label)

	var sub_label = Label.new()
	sub_label.text = sub
	sub_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub_label.add_theme_font_size_override("font_size", 32)
	sub_label.add_theme_color_override("font_color", sub_color)
	box.add_child(sub_label)
