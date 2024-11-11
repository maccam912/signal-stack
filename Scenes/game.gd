extends Node2D

@onready var camera: Camera2D = $Camera2D
var highest_y: float = 0.0
var base_height: float = 540.0  # Bottom of the frame
var min_zoom: float = 1.0
var zoom_speed: float = 2.0

# Dragging variables
var dragged_body: RigidBody2D = null
var drag_joint: DampedSpringJoint2D = null
var touch_index: int = -1  # For touch input tracking
var original_angular_damp: float = 0.0  # Store original angular damp value
var original_linear_damp: float = 0.0   # Store original linear damp value

# Spring properties
const SPRING_STIFFNESS = 1000.0  # Controls how "rigid" the spring is
const SPRING_DAMPING = 30.0     # Controls how quickly oscillations settle
const REST_LENGTH = 10.0       # The spring's rest length
const MAX_LENGTH = 200.0       # Maximum length before spring maxes out
const HELD_ANGULAR_DAMP = 10.0  # Angular damping while held
const HELD_LINEAR_DAMP = 5.0   # Linear damping while held

const scenes = [
	preload("res://Scenes/Junk/Umbrella.tscn"),
	preload("res://Scenes/Junk/Stopsign.tscn"),
	preload("res://Scenes/Junk/Safe.tscn"),
	preload("res://Scenes/Junk/Piano.tscn"),
	preload("res://Scenes/Junk/Robot.tscn"),
	preload("res://Scenes/Junk/Fence.tscn"),
	preload("res://Scenes/Junk/Beachball.tscn"),
]

func _ready() -> void:
	# Initialize camera position
	camera.position = Vector2(0, 0)  # Center horizontally, top at 0
	
	# Spawn initial objects in a 4x5 grid
	var x_spacing = 1920.0 / 5  # 5 columns
	var y_spacing = 1080.0 / 4  # 4 rows
	
	for row in range(4):
		for col in range(5):
			var x = (col * x_spacing) - 960 + (x_spacing / 2)  # Center in cell
			var y = (row * y_spacing) - 540 + (y_spacing / 2)  # Center in cell
			spawn_random_object(Vector2(x, y))

func spawn_random_object(pos: Vector2) -> void:
	var scene = scenes[randi_range(0, len(scenes)-1)]
	var s = scene.instantiate()
	s.position = pos
	s.add_to_group("rigid_bodies")
	add_child(s)

func _unhandled_input(event: InputEvent) -> void:
	# Handle mouse input
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_start_drag(get_world_position(event.position))
			else:
				_end_drag()
	
	# Handle mouse motion while dragging
	elif event is InputEventMouseMotion and dragged_body:
		_update_drag(get_world_position(event.position))
	
	# Handle touch input
	elif event is InputEventScreenTouch:
		if event.pressed and touch_index == -1:
			touch_index = event.index
			_start_drag(get_world_position(event.position))
		elif !event.pressed and event.index == touch_index:
			touch_index = -1
			_end_drag()
	
	# Handle touch drag
	elif event is InputEventScreenDrag and event.index == touch_index:
		_update_drag(get_world_position(event.position))

func get_world_position(screen_pos: Vector2) -> Vector2:
	# Convert screen coordinates to world coordinates
	return get_canvas_transform().affine_inverse() * screen_pos

func is_draggable_body(node: Node) -> bool:
	# Check if the node itself is a RigidBody2D in the rigid_bodies group
	if node is RigidBody2D and node.is_in_group("rigid_bodies"):
		return true
	
	# Check if the node is a RigidBody2D and its parent is in the rigid_bodies group
	if node is RigidBody2D and node.get_parent().is_in_group("rigid_bodies"):
		return true
	
	return false

func _start_drag(world_pos: Vector2) -> void:
	var space = get_world_2d().direct_space_state
	var query = PhysicsPointQueryParameters2D.new()
	query.position = world_pos
	query.collision_mask = 1  # Adjust based on your collision layers
	query.collide_with_bodies = true
	
	var result = space.intersect_point(query)
	if result:
		for collision in result:
			var collider = collision.collider
			# Check if the collider is draggable
			if is_draggable_body(collider):
				dragged_body = collider
				
				# Store original damping values and set new values
				original_angular_damp = dragged_body.angular_damp
				original_linear_damp = dragged_body.linear_damp
				dragged_body.angular_damp = HELD_ANGULAR_DAMP
				dragged_body.linear_damp = HELD_LINEAR_DAMP
				
				# Create spring joint
				drag_joint = DampedSpringJoint2D.new()
				add_child(drag_joint)
				drag_joint.length = REST_LENGTH
				drag_joint.rest_length = REST_LENGTH
				drag_joint.stiffness = SPRING_STIFFNESS
				drag_joint.damping = SPRING_DAMPING
				drag_joint.position = world_pos
				drag_joint.node_a = dragged_body.get_path()
				
				# Create temporary static body for the joint
				var static_body = StaticBody2D.new()
				add_child(static_body)
				static_body.position = world_pos
				drag_joint.node_b = static_body.get_path()
				
				break

func _update_drag(world_pos: Vector2) -> void:
	if drag_joint and drag_joint.node_b:
		# Update the static body position
		var static_body = get_node(drag_joint.node_b)
		
		# Calculate the direction and distance to the target
		var direction = (world_pos - dragged_body.global_position).normalized()
		var distance = world_pos.distance_to(dragged_body.global_position)
		
		# Limit the maximum distance to prevent excessive stretching
		if distance > MAX_LENGTH:
			world_pos = dragged_body.global_position + direction * MAX_LENGTH
		
		static_body.global_position = world_pos

func _end_drag() -> void:
	if drag_joint:
		# Restore original damping values
		if dragged_body:
			dragged_body.angular_damp = original_angular_damp
			dragged_body.linear_damp = original_linear_damp
		
		# Clean up the static body
		var static_body = get_node(drag_joint.node_b)
		static_body.queue_free()
		
		# Clean up the joint
		drag_joint.queue_free()
		drag_joint = null
		dragged_body = null

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
