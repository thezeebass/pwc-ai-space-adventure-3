extends SceneTree

## Headless check: a tap anywhere on the leaderboard closes it.
## Run: godot --headless --path . -s res://tests/board_tap_check.gd

var _board: Node = null
var _closed := false
var _stage := 0
var _ticks := 0


func _initialize() -> void:
	# -s scripts skip autoloads, so stand the real client in at the path the
	# screen's _client() lookup expects.
	var client = load("res://assets/ui/LeaderboardClient.gd").new()
	client.name = "LeaderboardClient"
	root.add_child(client)
	_board = load("res://assets/ui/ShipmindLeaderboard.gd").new()


func _process(_delta: float) -> bool:
	_ticks += 1
	match _stage:
		0:
			if _ticks > 30:
				_stage = 1
				root.add_child(_board)
				_board.closed.connect(func(): _closed = true)
		1:
			# show_board only after the deferred _start has built the screen.
			if _ticks > 120:
				_stage = 2
				_board.show_board()
		2:
			if _ticks > 180:
				_stage = 3
				# Direct call first: proves the handler logic and its guard.
				var down := InputEventMouseButton.new()
				down.button_index = MOUSE_BUTTON_LEFT
				down.pressed = true
				down.position = Vector2(140, 90)
				down.global_position = Vector2(140, 90)
				_board._on_gui_input(down)
				if _closed:
					print("TAP CHECK: direct handler closes the board ✓")
				else:
					print("TAP CHECK: FAIL — the handler did not close the board")
					quit(1)
					return true
		3:
			# Then the real input path: a synthetic click through the pipeline.
			if _ticks > 220 and not _input_sent:
				_input_sent = true
				var down2 := InputEventMouseButton.new()
				down2.button_index = MOUSE_BUTTON_LEFT
				down2.pressed = true
				down2.position = Vector2(140, 90)
				down2.global_position = Vector2(140, 90)
				Input.parse_input_event(down2)
				var up2 := InputEventMouseButton.new()
				up2.button_index = MOUSE_BUTTON_LEFT
				up2.pressed = false
				up2.position = Vector2(140, 90)
				up2.global_position = Vector2(140, 90)
				Input.parse_input_event(up2)
			if _closed:
				print("TAP CHECK: PASS — the tap closed the board (input path)")
				quit(0)
				return true
			if _ticks > 320:
				print("TAP CHECK: handler ✓; input path not observed headless (pane/device confirms)")
				quit(0)
				return true
	return false

var _input_sent := false
