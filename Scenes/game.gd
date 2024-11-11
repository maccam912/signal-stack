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

# Scoring variables
var antenna_instance: Node = null
var last_antenna_y: float = 0.0
var stable_time: float = 0.0
var score_calculated: bool = false
var settling_time: float = 0.0
var max_settling_time: float = 10.0
var settling_started: bool = false

# Dragging variables
var dragged_body: RigidBody2D = null
var drag_joint: DampedSpringJoint2D = null
var original_angular_damp: float = 0.0  # Store original angular damp value
var original_linear_damp: float = 0.0   # Store original linear damp value

# Spring properties
const SPRING_STIFFNESS = 1000.0  # Controls how "rigid" the spring is
const SPRING_DAMPING = 30.0     # Controls how quickly oscillations settle
const REST_LENGTH = 10.0       # The spring's rest length
const MAX_LENGTH = 200.0       # Maximum length before spring maxes out
const HELD_ANGULAR_DAMP = 10.0  # Angular damping while held
const HELD_LINEAR_DAMP = 5.0   # Linear damping while held

# Spawn stack state
var is_spawning = false
var objects_to_spawn = 20
var x_pos = 0
var last_spawn_height = 0  # Track the last object's final position

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

func spawn_one_object() -> void:
	var step_size = 5  # Move down 5 pixels at a time
	
	# Calculate start height based on last object
	var start_y = last_spawn_height - 1000  # 1000 pixels above last object
	if objects_to_spawn == 20:  # First object
		start_y = base_height - 1000  # 1000 pixels above base
	
	# Spawn an item
	var obj = spawn_random_object(Vector2(x_pos, start_y))
	# Create a temporary CharacterBody2D for collision testing
	var test_body = CharacterBody2D.new()
	add_child(test_body)
	
	# Copy the collision shape from the spawned object
	for child in obj.get_children():
		if child is CollisionShape2D or child is CollisionPolygon2D:
			var shape_copy = child.duplicate()
			test_body.add_child(shape_copy)
	
	var current_pos = Vector2(x_pos, start_y)
	var last_good_pos = current_pos
	var moving = true
	
	while moving:
		# Test moving down by step_size
		var motion = Vector2(0, step_size)
		var collision = KinematicCollision2D.new()
		
		# Test the move
		if test_body.test_move(Transform2D(0, current_pos), motion, collision):
			# Collision detected, use last good position
			moving = false
			obj.position = last_good_pos
			last_spawn_height = last_good_pos.y  # Store the final height
		else:
			# No collision, update positions and continue down
			last_good_pos = current_pos
			current_pos += motion
			if current_pos.y >= base_height:  # Stop if we hit the bottom
				moving = false
				obj.position = last_good_pos
				last_spawn_height = last_good_pos.y  # Store the final height
	
	# Clean up the test body
	test_body.queue_free()
	
	# Decrease remaining objects counter
	objects_to_spawn -= 1
	if objects_to_spawn <= 0:
		is_spawning = false

func spawn_stack() -> void:
	is_spawning = true
	objects_to_spawn = 20
	x_pos = 0  # Center horizontally
	last_spawn_height = base_height  # Reset last spawn height
	
func spawn_random_object(pos: Vector2) -> Node:
	var scene
	if objects_to_spawn > 1:
		scene = scenes[randi_range(0, len(scenes)-1)]
	else:
		scene = antenna
		antenna_instance = scene.instantiate()
		antenna_instance.position = pos
		antenna_instance.add_to_group("rigid_bodies")
		add_child(antenna_instance)
		return antenna_instance
	var s = scene.instantiate()
	s.position = pos
	s.add_to_group("rigid_bodies")
	add_child(s)
	return s

func _unhandled_input(event: InputEvent) -> void:
	if not can_interact:
		return
		
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

var stack_spawned_count = 0

func _physics_process(delta: float) -> void:
	if stack_spawned_count < 2:
		stack_spawned_count += 1
		if stack_spawned_count == 2:
			spawn_stack()
	
	# Spawn one object per physics frame if we're in spawning mode
	if is_spawning:
		spawn_one_object()
		
	# Handle settling and scoring after timer runs out
	if not can_interact:
		if not settling_started:
			settling_started = true
			score_label.text = "[right][color=#990000]Settling...[/color][/right]"
			
		settling_time += delta
		# Check if objects have settled or max time reached
		if are_all_objects_sleeping() or settling_time >= max_settling_time:
			if not score_calculated and antenna_instance:
				var current_y = antenna_instance.position.y
				if abs(current_y - last_antenna_y) < 1.0:  # Check if position is almost the same
					stable_time += delta
					if stable_time >= 1.0:  # If stable for 1 second
						var height = base_height - current_y  # Convert y coordinate to height
						# Convert pixels to meters (500 pixels = 2 meters)
						var height_meters = (height / 500.0) * 2.0
						score_label.text = "[right][color=#990000]Score: %.2f m[/color][/right]" % height_meters
						score_calculated = true
				else:
					stable_time = 0.0  # Reset stability timer if moving too much
				last_antenna_y = current_y

func _process(delta: float) -> void:
	# Update timer display
	var time_left = timer.time_left
	timer_label.text = "[color=#990000]%.2f[/color]" % time_left
	
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
