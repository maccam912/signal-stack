extends Node

var songs = [
	"res://Audio/1.mp3",
	"res://Audio/2.mp3",
	"res://Audio/3.mp3",
	"res://Audio/4.mp3",
	"res://Audio/5.mp3",
]
var current_song_index = -1
var audio_player: AudioStreamPlayer

func _ready():
	audio_player = $AudioStreamPlayer
	# Connect the finished signal to play the next song
	audio_player.finished.connect(_on_song_finished)
	# Start playing a random song
	play_random_song()

func play_random_song():
	# Create a temporary array excluding the current song
	var available_songs = songs.duplicate()
	if current_song_index != -1:
		available_songs.erase(songs[current_song_index])
	
	# Pick a random song from the available ones
	var random_index = randi() % available_songs.size()
	var selected_song = available_songs[random_index]
	
	# Find the actual index in the original songs array
	current_song_index = songs.find(selected_song)
	
	# Load and play the song
	var stream = load(selected_song)
	audio_player.stream = stream
	audio_player.play()

func _on_song_finished():
	play_random_song()  # Play another random song when the current one finishes
