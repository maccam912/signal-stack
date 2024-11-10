extends Node2D

const UmbrellaScene = preload("res://Scenes/Junk/Umbrella.tscn")

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	if Input.is_action_just_released("Drop"):
		# Spawn the thingy
		var u = UmbrellaScene.instantiate()
		u.position = position
		add_sibling(u)
	if Input.is_action_pressed("Left"):
		position.x -= 10
	if Input.is_action_pressed("Right"):
		position.x += 10
