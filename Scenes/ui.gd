extends CanvasLayer

@onready var try_again_button: Button = $TryAgain
@onready var game = get_parent()

func _ready() -> void:
	# Hide button initially
	try_again_button.hide()
	
	# Connect to button press
	try_again_button.pressed.connect(_on_try_again_pressed)

func _process(_delta: float) -> void:
	# Show button when score is calculated
	if game.score_calculated and try_again_button.visible == false:
		try_again_button.show()

func _on_try_again_pressed() -> void:
	# Restart the current scene
	get_tree().reload_current_scene()
