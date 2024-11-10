extends Node2D

const scenes = [
		preload("res://Scenes/Junk/Umbrella.tscn"),
		preload("res://Scenes/Junk/Stopsign.tscn"),
		preload("res://Scenes/Junk/Safe.tscn"),
		preload("res://Scenes/Junk/Piano.tscn"),
		preload("res://Scenes/Junk/Robot.tscn"),
		preload("res://Scenes/Junk/Fence.tscn"),
		preload("res://Scenes/Junk/Beachball.tscn"),
	]

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	if Input.is_action_just_released("Drop"):
		# Spawn the thingy
		# select random scene from scenes
		var scene = scenes[randi_range(0, len(scenes)-1)]
		var s = scene.instantiate()
		s.position = position
		add_sibling(s)
	if Input.is_action_pressed("Left"):
		position.x -= 10
	if Input.is_action_pressed("Right"):
		position.x += 10
