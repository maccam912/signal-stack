extends Node2D

@onready var camera: Camera2D = $Camera2D
@onready var timer: Timer = $UI/Timer
@onready var timer_label: RichTextLabel = $UI/Timer/Label
@onready var score_label: RichTextLabel = $UI/Score

var highest_y: float = 0.0
var base_height: float = 540.0  # Bottom of the frame
var min_zoom: float = 1.0
var zoom_speed: float = 2.0
var can_interact: bool = true
var use_damping: bool = false  # New flag to control damping

# Scoring variables
var antenna_instance: Node = null
var last_antenna_y: float = 0.0
var settling_started = false
var settling_time = 0.0
var max_settling_time = 10.0
var score_calculated = false

# Dragging variables
var dragged_body: RigidBody2D = null
var drag_joint: DampedSpringJoint2D = null
var original_angular_damp: float = 0.0  # Store original angular damp value
var original_linear_damp: float = 0.0   # Store original linear damp value

# Spring properties
const SPRING_STIFFNESS = 400.0  # Reduced stiffness for smoother movement
const SPRING_DAMPING = 50.0     # Increased damping to prevent oscillation
const REST_LENGTH = 0.0        # Spring should try to stay at mouse position
const MAX_LENGTH = 200.0       # Maximum length before spring maxes out
const HELD_ANGULAR_DAMP = 10.0  # Angular damping while held
const HELD_LINEAR_DAMP = 5.0   # Linear damping while held

# Spawn stack state
var is_spawning = false
var objects_to_spawn = 20
var grid_points: Array[Vector2] = []

const scenes = [
	preload("res://Scenes/Junk/Umbrella.tscn"),
	preload("res://Scenes/Junk/Stopsign.tscn"),
	preload("res://Scenes/Junk/Safe.tscn"),
	preload("res://Scenes/Junk/Piano.tscn"),
	#preload("res://Scenes/Junk/Robot.tscn"),
	preload("res://Scenes/Junk/Fence.tscn"),
	preload("res://Scenes/Junk/Beachball.tscn"),
]

const antenna = preload("res://Scenes/Junk/Antenna.tscn")

func _ready() -> void:
	# Initialize camera position
	camera.position = Vector2(0, 0)  # Center horizontally, top at 0
	
	# Initialize timer
	timer.wait_time = 20.0
	timer.one_shot = true
	timer.start()
	timer.timeout.connect(_on_timer_timeout)
	
	# Generate grid points
	generate_grid_points()
	spawn_grid_objects()

func generate_grid_points() -> void:
	var rows = 10  # More rows for increased vertical spacing
	var cols = 2   # Only two columns as requested
	var x_start = -800.0  # Start from far left
	var x_spacing = 400.0  # Space between columns
	var y_start = 0.0
	var y_end = -2000.0   # Increased vertical range
	
	var y_step = (y_end - y_start) / (rows - 1)
	
	for i in range(rows):
		for j in range(cols):
			var x = x_start + (j * x_spacing)
			var y = y_start + (i * y_step)
			grid_points.append(Vector2(x, y))
	
	# Spawn antenna at the top
	antenna_instance = antenna.instantiate()
	add_child(antenna_instance)
	antenna_instance.position = Vector2(0, y_end - 100)  # Place antenna above the highest row
	if antenna_instance is RigidBody2D:
		antenna_instance.add_to_group("rigid_bodies")

func spawn_grid_objects() -> void:
	for point in grid_points:
		spawn_random_object(point)

func spawn_random_object(pos: Vector2) -> Node2D:
	var scene = scenes.pick_random()
	var obj = scene.instantiate()
	add_child(obj)
	
	# Set random rotation
	obj.rotation = randf_range(0, PI * 2)
	
	# Try to find a non-colliding position
	var max_attempts = 10
	var attempt = 0
	var found_valid_pos = false
	var test_pos = pos
	
	while attempt < max_attempts and not found_valid_pos:
		obj.position = test_pos
		
		# Check for collisions
		if obj is CharacterBody2D:
			# Test move and check for collision
			obj.move_and_collide(Vector2.ZERO)
			found_valid_pos = not obj.get_slide_collision_count()
		else:
			# For non-CharacterBody2D nodes, use area overlap test
			var space = get_world_2d().direct_space_state
			var query = PhysicsShapeQueryParameters2D.new()
			query.transform = obj.global_transform
			if obj.get_node_or_null("CollisionShape2D"):
				query.shape = obj.get_node("CollisionShape2D").shape
				var result = space.intersect_shape(query)
				found_valid_pos = result.is_empty()
			else:
				found_valid_pos = true  # No collision shape, assume it's fine
		
		if not found_valid_pos:
			# Try a slightly offset position
			test_pos = pos + Vector2(
				randf_range(-50, 50),
				randf_range(-50, 50)
			)
			attempt += 1
	
	if obj is RigidBody2D:
		obj.add_to_group("rigid_bodies")
	
	return obj

func _unhandled_input(event: InputEvent) -> void:
	if not can_interact:
		return
		
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			print("Left mouse button event - pressed: ", event.pressed)
			if event.pressed:
				print("Mouse position: ", get_global_mouse_position())
				_start_drag(get_global_mouse_position())
			else:
				_end_drag()

func _start_drag(world_pos: Vector2) -> void:
	print("Starting drag at position: ", world_pos)
	var space = get_world_2d().direct_space_state
	var query = PhysicsPointQueryParameters2D.new()
	query.position = world_pos
	query.collision_mask = 1  # Adjust based on your collision layers
	query.collide_with_bodies = true
	
	var result = space.intersect_point(query)
	print("Physics query results: ", result.size(), " objects found")
	
	if result.size() > 0:
		var body = result[0].collider
		print("Found collider: ", body.name, " of type: ", body.get_class())
		if body is RigidBody2D:
			print("Successfully grabbed RigidBody2D")
			dragged_body = body
			
			# Store original damping values
			original_angular_damp = dragged_body.angular_damp
			original_linear_damp = dragged_body.linear_damp
			
			# Apply high damping while dragging
			dragged_body.angular_damp = HELD_ANGULAR_DAMP
			dragged_body.linear_damp = HELD_LINEAR_DAMP
			
			# Lock rotation while dragging
			dragged_body.lock_rotation = true
			
			# Create anchor point for the joint
			var anchor = StaticBody2D.new()
			add_child(anchor)
			anchor.global_position = world_pos
			
			# Create spring joint
			drag_joint = DampedSpringJoint2D.new()
			add_child(drag_joint)
			
			# Connect the joint between the static anchor and the dragged body
			drag_joint.node_a = anchor.get_path()
			drag_joint.node_b = dragged_body.get_path()
			
			# Configure joint properties
			drag_joint.length = 0  # Want the object to try to stay at mouse position
			drag_joint.rest_length = 0
			drag_joint.stiffness = SPRING_STIFFNESS
			drag_joint.damping = SPRING_DAMPING
			
			# Set the anchor points relative to each body
			drag_joint.bias = 0.9  # High bias for better following
			
			print("Joint created between anchor and body")
		else:
			print("Found object is not a RigidBody2D")
	else:
		print("No objects found at click position")

func _end_drag() -> void:
	print("Ending drag")
	if dragged_body:
		print("Releasing body: ", dragged_body.name)
		# Restore original damping values
		dragged_body.angular_damp = original_angular_damp
		dragged_body.linear_damp = original_linear_damp
		dragged_body.lock_rotation = false
		dragged_body = null
	
	if drag_joint:
		print("Removing drag joint")
		drag_joint.queue_free()
		drag_joint = null

func _physics_process(_delta: float) -> void:
	if drag_joint and dragged_body:
		_update_drag_position()
	
	# Check for objects that are too far from center and despawn them
	var rigid_bodies = get_tree().get_nodes_in_group("rigid_bodies")
	for body in rigid_bodies:
		if body is RigidBody2D:
			# Skip the antenna since we want to keep it for scoring
			if body == antenna_instance:
				continue
			# Check if object is too far from center on x-axis
			if abs(body.position.x) > 3000:
				body.queue_free()
		
	# Handle settling and scoring after timer runs out
	if not can_interact:
		if not settling_started:
			settling_started = true
			settling_time = 0.0  # Reset settling time
			score_label.text = "[right][color=#990000]Settling...[/color][/right]"
			return  # Wait for next frame before starting to check settling
			
		settling_time += _delta
		# Check if objects have settled or max time reached
		if (are_all_objects_sleeping() or settling_time >= max_settling_time) and not score_calculated:
			if antenna_instance:
				var height = base_height - antenna_instance.position.y  # Convert y coordinate to height
				# Convert pixels to meters (500 pixels = 2 meters)
				var height_meters = (height / 500.0) * 2.0
				score_label.text = "[right][color=#990000]Score: %.2f m[/color][/right]" % height_meters
				score_calculated = true

func _process(_delta: float) -> void:
	# Update timer display
	var time_left = timer.time_left
	timer_label.text = "[color=#990000]%.2f[/color]" % time_left
	
	# Find highest rigid body
	var new_highest_y: float = min(-540, find_highest_rigid_body())
	# fake it out, give us 20% above the highest
	var height = 1.2 * (base_height - new_highest_y)
	
	new_highest_y = base_height - height
	# Update highest_y with some smoothing
	highest_y = lerp(highest_y, new_highest_y, _delta * zoom_speed)
	
	# Calculate required zoom to keep bottom at base_height
	# and show up to the highest object
	var height_needed = base_height - highest_y
	var target_zoom: float = min(min_zoom, 1080.0 / height_needed)  # Changed to min() to allow zooming out
	# Smoothly adjust zoom
	camera.zoom = camera.zoom.lerp(Vector2(target_zoom, target_zoom), _delta * zoom_speed)
	
	# Adjust camera y position to maintain bottom edge at base_height
	var target_y: float = (base_height + highest_y) / 2.0
	camera.position.y = lerp(camera.position.y, target_y, _delta * zoom_speed)
	
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

func _on_timer_timeout() -> void:
	can_interact = false
	if dragged_body:
		_end_drag()

func are_all_objects_sleeping() -> bool:
	var rigid_bodies = get_tree().get_nodes_in_group("rigid_bodies")
	if rigid_bodies.is_empty():
		return true
		
	for body in rigid_bodies:
		if body is RigidBody2D and not body.sleeping:
			return false
	
	return true

func toggle_damping(enabled: bool) -> void:
	use_damping = enabled

func _update_drag_position() -> void:
	if drag_joint and dragged_body:
		var mouse_pos = get_global_mouse_position()
		# Update the anchor position
		var anchor = get_node(drag_joint.node_a)
		anchor.global_position = mouse_pos
