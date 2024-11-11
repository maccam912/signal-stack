extends Node2D

@onready var camera: Camera2D = $Camera2D
var highest_y: float = 0.0
var base_height: float = 540.0  # Bottom of the frame
var min_zoom: float = 1.0
var zoom_speed: float = 2.0

func _ready() -> void:
	# Initialize camera position
	camera.position = Vector2(0, 0)  # Center horizontally, top at 0

func _process(delta: float) -> void:
	# Find highest rigid body
	var new_highest_y: float = min(-540, find_highest_rigid_body())
	# fake it out, give us 20% above the highest
	var height = 1.2 * (base_height - new_highest_y)
	
	new_highest_y = base_height - height
	# Update highest_y with some smoothing
	highest_y = lerp(highest_y, new_highest_y, delta * zoom_speed)
	
	# Calculate required zoom to keep bottom at base_height
	# and show up to the highest object
	var height_needed = base_height - highest_y
	var target_zoom: float = min(min_zoom, 1080.0 / height_needed)  # Changed to min() to allow zooming out
	# Smoothly adjust zoom
	camera.zoom = camera.zoom.lerp(Vector2(target_zoom, target_zoom), delta * zoom_speed)
	
	# Adjust camera y position to maintain bottom edge at base_height
	var target_y: float = (base_height + highest_y) / 2.0
	camera.position.y = lerp(camera.position.y, target_y, delta * zoom_speed)
	
	$Funnel.position.y = new_highest_y
	
func find_highest_rigid_body() -> float:
	var highest: float = 540
	
	# Get all RigidBody2D nodes in the scene
	var rigid_bodies = get_tree().get_nodes_in_group("rigid_bodies")
	if rigid_bodies.is_empty():
		return highest
	
	# Find the highest y position (remember y is negative going up)
	for body in rigid_bodies:
		if body is RigidBody2D:
			highest = min(highest, body.global_position.y)
	
	return highest
