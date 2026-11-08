extends SceneTree

## Headless check: the touch walkthrough's cards dismiss on touch, not just on
## full deflection. Run: godot --headless --path . -s res://tests/tutorial_touch_check.gd

var _controls: Node = null
var _stage := 0
var _ticks := 0


func _initialize() -> void:
	_controls = (load("res://scenes/ui/touch_controls.tscn") as PackedScene).instantiate()
	_controls.force_visible = true


func _touch(index: int, position: Vector2, pressed: bool) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = index
	ev.position = position
	ev.pressed = pressed
	Input.parse_input_event(ev)


func _drag(index: int, position: Vector2) -> void:
	var ev := InputEventScreenDrag.new()
	ev.index = index
	ev.position = position
	Input.parse_input_event(ev)


func _view() -> Vector2:
	return root.get_viewport().get_visible_rect().size


func _process(_d: float) -> bool:
	_ticks += 1
	match _stage:
		0:
			if _ticks > 30:
				_stage = 1
				root.add_child(_controls)
		1:
			# Walk: claim the move stick on the left and deflect it. The walk
			# card yields, the look card appears (LOOK AROUND).
			if _ticks > 150:
				_stage = 2
				var view := _view()
				_touch(5, Vector2(view.x * 0.25, view.y * 0.9), true)
				_drag(5, Vector2(view.x * 0.25, view.y * 0.9))
				_drag(5, Vector2(view.x * 0.32, view.y * 0.9))
				_drag(5, Vector2(view.x * 0.42, view.y * 0.9))
		2:
			if _ticks > 260:
				_stage = 3
				var stage_now: int = _controls._tutorial_stage
				var card_up: bool = _controls.tutorial_card.visible
				var done: bool = GameState.touch_tutorial_done
				# Claiming either stick finishes the walkthrough at once: no
				# instruction card outlives the touch that answers it.
				print("TUTORIAL after walk touch: stage=%d (2=BOTH) card=%s done=%s" % [stage_now, card_up, done])
				if stage_now == 2 and not card_up and done:
					print("TUTORIAL CHECK: PASS")
					quit(0)
				else:
					print("TUTORIAL CHECK: FAIL - the card did not dismiss on touch")
					quit(1)
	return false
