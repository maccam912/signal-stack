extends Node

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	$Control/PlayButton.pressed.connect(_on_play_button_pressed)
	$Control/Volume.value_changed.connect(_on_volume_changed)
	pass # Replace with function body.

func _on_play_button_pressed() -> void:
	get_tree().change_scene_to_file("res://Scenes/Game.tscn")

func _on_volume_changed(value: float) -> void:
	var player = get_tree().root.get_node("MusicPlayer/AudioStreamPlayer")
	# Convert slider value (1-100) to a more natural volume scale
	var volume_percent = value / 100.0
	# Use logarithmic scaling for more natural volume control
	# -40 db is about 1% volume, which is quiet but still audible
	var db = linear_to_db(volume_percent)
	if value <= 1:
		db = -80 # Essentially muted
	player.volume_db = db

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
