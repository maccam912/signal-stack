extends Node2D

@export var cooldown: float = 0.5

const scenes = [
		preload("res://Scenes/Junk/Umbrella.tscn"),
		preload("res://Scenes/Junk/Stopsign.tscn"),
		preload("res://Scenes/Junk/Safe.tscn"),
		preload("res://Scenes/Junk/Piano.tscn"),
		preload("res://Scenes/Junk/Robot.tscn"),
		preload("res://Scenes/Junk/Fence.tscn"),
		preload("res://Scenes/Junk/Beachball.tscn"),
	]

var last_drop_time: float = 0.0

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	if Input.is_action_just_released("Drop"):
		var current_time = Time.get_unix_time_from_system()
		if current_time - last_drop_time >= cooldown:
			# Spawn the thingy
			var scene = scenes[randi_range(0, len(scenes)-1)]
			var s = scene.instantiate()
			s.position = position
			add_sibling(s)
			last_drop_time = current_time
	if Input.is_action_pressed("Left"):
		position.x -= 10
	if Input.is_action_pressed("Right"):
		position.x += 10
