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
var last_dragged_body: RigidBody2D = null  # Track the most recently interacted object
var waiting_for_pin: bool = false  # True when an object is ready to create its next pin

# Spring properties
const SPRING_STIFFNESS = 400.0  # Reduced stiffness for smoother movement
const SPRING_DAMPING = 50.0     # Increased damping to prevent oscillation
const REST_LENGTH = 0.0        # Spring should try to stay at mouse position
const MAX_LENGTH = 200.0       # Maximum length before spring maxes out
const HELD_ANGULAR_DAMP = 10.0  # Angular damping while held
const HELD_LINEAR_DAMP = 5.0   # Linear damping while held

# Joint creation properties
const PIN_JOINT_BIAS = 0.2  # Reduced bias for more flexibility (was 0.3)
const PIN_JOINT_SOFTNESS = 1.0  # Added softness to allow stretching
const PIN_JOINT_LENGTH = 20.0  # Allow some length variation
const MAX_JOINTS_PER_BODY = 3  # Limit joints per object to prevent over-constraint

# Dictionary to track joints between bodies
var body_joints = {}

# Spawn stack state
var is_spawning = false
var cars_per_row = 10
var num_rows = 2
var objects_to_spawn = cars_per_row * num_rows
var grid_points: Array[Vector2] = []
var car_spacing = 1024.0  # Spacing between cars in pixels
var row_spacing = 1024.0  # Spacing between rows
var ground_height = 500.0  # Height above ground for cars

const scenes = [
	preload("res://Scenes/Junk/car.tscn"),
	preload("res://Scenes/Junk/car_2.tscn"),
	preload("res://Scenes/Junk/car_3.tscn"),
	preload("res://Scenes/Junk/car_4.tscn"),
	preload("res://Scenes/Junk/car_5.tscn"),
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
	
	# Connect all existing rigid bodies
	connect_rigid_bodies()

func generate_grid_points() -> void:
	var x_start = -(cars_per_row - 1) * car_spacing / 2  # Center the row of cars
	
	# Generate two rows of points
	for row in range(num_rows):
		var row_height = ground_height - (row * row_spacing)
		for col in range(cars_per_row):
			var x = x_start + (col * car_spacing)
			grid_points.append(Vector2(x, row_height))
	
	# Spawn antenna at the top
	antenna_instance = antenna.instantiate()
	add_child(antenna_instance)
	antenna_instance.position = Vector2(0, ground_height - (row_spacing * 2))  # Place antenna above both rows
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

func connect_rigid_bodies():
	var rigid_bodies = get_tree().get_nodes_in_group("rigid_bodies")
	for body in rigid_bodies:
		if not body.is_connected("body_entered", _on_rigid_body_collision):
			body.body_entered.connect(_on_rigid_body_collision.bind(body))
			body_joints[body] = []

func _on_rigid_body_collision(other_body: RigidBody2D, this_body: RigidBody2D):
	# Only create joints if one is the last dragged body AND we're waiting for a pin
	if not waiting_for_pin:
		return
		
	# Skip if neither body was the last dragged one
	if this_body != last_dragged_body and other_body != last_dragged_body:
		return
	
	# Skip if either body is not in the rigid_bodies group
	if not this_body.is_in_group("rigid_bodies") or not other_body.is_in_group("rigid_bodies"):
		return
		
	# Get which body is the last dragged one
	var sticky_body = last_dragged_body
	var other = other_body if other_body != last_dragged_body else this_body
	
	# Skip if these bodies are already connected
	if not body_joints.has(sticky_body):
		body_joints[sticky_body] = []
	if not body_joints.has(other):
		body_joints[other] = []
		
	for joint in body_joints[sticky_body]:
		if get_node(joint.node_a) == other or get_node(joint.node_b) == other:
			return
	
	# Get collision point (approximate using body positions)
	var collision_point = (sticky_body.global_position + other.global_position) / 2
	
	# Create pin joint
	var pin = PinJoint2D.new()
	add_child(pin)
	pin.global_position = collision_point
	pin.node_a = sticky_body.get_path()
	pin.node_b = other.get_path()
	pin.bias = PIN_JOINT_BIAS
	pin.softness = PIN_JOINT_SOFTNESS
	pin.disable_collision = false  # Keep collisions between connected bodies
	
	# Store joint reference
	body_joints[sticky_body].append(pin)
	body_joints[other].append(pin)
	
	# Create a small angular spring effect
	sticky_body.angular_damp = 3.0
	other.angular_damp = 3.0
	
	# We've created our one pin, so stop waiting
	waiting_for_pin = false

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
	query.collision_mask = 1  # Use the appropriate collision mask
	var result = space.intersect_point(query)
	
	if result:
		var found_object = result[0].collider
		if found_object is RigidBody2D:
			dragged_body = found_object
			last_dragged_body = found_object  # Track the last dragged body
			waiting_for_pin = false  # Reset pin waiting while dragging
			
			original_angular_damp = dragged_body.angular_damp
			original_linear_damp = dragged_body.linear_damp
			
			# Apply held damping
			dragged_body.angular_damp = HELD_ANGULAR_DAMP
			dragged_body.linear_damp = HELD_LINEAR_DAMP
			
			_create_drag_joint(world_pos)
		else:
			print("Found object is not a RigidBody2D")
	else:
		print("No objects found at click position")

func _create_drag_joint(world_pos: Vector2) -> void:
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

func _end_drag() -> void:
	print("Ending drag")
	if dragged_body:
		print("Releasing body: ", dragged_body.name)
		# Restore original damping values
		dragged_body.angular_damp = original_angular_damp
		dragged_body.linear_damp = original_linear_damp
		dragged_body.lock_rotation = false
		waiting_for_pin = true  # Now we're ready to create one pin
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
	var center_x = 0.0
	var despawn_distance = car_spacing * 15  # This gives roughly 10 cars worth of space on each side beyond center
	
	for body in rigid_bodies:
		if body is RigidBody2D:
			# Skip the antenna since we want to keep it for scoring
			if body == antenna_instance:
				continue
			# Check if object is too far from center on x-axis
			if abs(body.position.x - center_x) > despawn_distance:
				# Remove any joints connected to this body before despawning
				if body_joints.has(body):
					for joint in body_joints[body]:
						if is_instance_valid(joint):
							joint.queue_free()
					body_joints.erase(body)
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

func _process(delta: float) -> void:
	if can_interact:
		# Update timer display
		var time_left = timer.time_left
		timer_label.text = "[color=#990000]%.2f[/color]" % time_left
		
		# Update camera zoom based on object positions
		var min_x = INF
		var max_x = -INF
		var min_y = INF
		var max_y = -INF
		
		# Find the bounds of all cars
		for child in get_children():
			if child is RigidBody2D:
				min_x = min(min_x, child.position.x)
				max_x = max(max_x, child.position.x)
				min_y = min(min_y, child.position.y)
				max_y = max(max_y, child.position.y)
		
		if min_x != INF:
			# Add padding to the bounds
			var padding = 200.0
			var width = (max_x - min_x) + padding * 2
			var height = (max_y - min_y) + padding * 2
			
			# Calculate required zoom to fit all objects
			var zoom_x = get_viewport_rect().size.x / width
			var zoom_y = get_viewport_rect().size.y / height
			var target_zoom = min(zoom_x, zoom_y)
			
			# Smoothly interpolate to the target zoom
			var current_zoom = camera.zoom.x
			camera.zoom = Vector2.ONE * lerp(current_zoom, target_zoom, delta * 2.0)
			
			# Update camera position to center on all objects
			var target_pos = Vector2(
				(min_x + max_x) / 2,
				(min_y + max_y) / 2
			)
			camera.position = lerp(camera.position, target_pos, delta * 4.0)

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
