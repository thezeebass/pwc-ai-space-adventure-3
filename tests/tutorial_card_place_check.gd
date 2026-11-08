extends SceneTree

## Headless check: the tutorial card sits BELOW SHIPMIND's dialogue (not on
## it), stays between the sticks' rest pockets when both are visible, and
## never drops past the bottom edge.
##
## Run: godot --headless --path . -s res://tests/tutorial_card_place_check.gd

var _ui: Node = null
var _stage := 0
var _ticks := 0
var _failures: Array[String] = []


func _initialize() -> void:
	_ui = Node.new()
	_ui.name = "UI"


func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		_failures.append(what)


func _process(_d: float) -> bool:
	_ticks += 1
	match _stage:
		0:
			if _ticks > 30:
				_stage = 1
				root.add_child(_ui)
				var hud := (load("res://scenes/ui/hud.tscn") as PackedScene).instantiate()
				var touch := (load("res://scenes/ui/touch_controls.tscn") as PackedScene).instantiate()
				_ui.add_child(hud)
				_ui.add_child(touch)
				hud.set_compact(true)
				OperatingModel.declare("home_intact", "cautious")
				hud.say_system("Left thumb walks. Right thumb looks.", 30.0)
		1:
			# Two layout passes, then read the card against the dialogue.
			if _ticks > 150:
				_stage = 2
				var view: Vector2 = root.get_viewport().get_visible_rect().size
				var touch: CanvasLayer = _ui.get_node("TouchControls")
				var card: Control = touch.get_node("Root/TutorialCard")
				var hud: Node = _ui.get_node("HUD")
				var subtitle: Control = hud.get("subtitle")
				_check(subtitle.visible, "SHIPMIND's dialogue is up")
				_check(card.visible, "the first tutorial card is up")
				_check(card.global_position.y + card.size.y >= view.y - 40.0,
					"the card sits near the bottom of the screen (%.0f bottom vs %.0f view)" % [
						card.global_position.y + card.size.y, view.y])
				var subtitle_bottom: float = subtitle.global_position.y + subtitle.size.y
				var both_fit: bool = subtitle_bottom + card.size.y + 36.0 <= view.y
				if both_fit:
					_check(card.global_position.y >= subtitle_bottom + 11.0,
						"the card clears the dialogue (%.0f vs dialogue bottom %.0f)" % [
							card.global_position.y, subtitle_bottom])
				else:
					print("NOTE the dialogue reaches the card's band on this viewport; the card keeps the bottom")
				_check(card.global_position.y + card.size.y <= view.y - 7.0,
					"the card stays inside the bottom edge")
				var card_center: float = card.global_position.x + card.size.x * 0.5
				_check(absf(card_center - view.x * 0.5) < 1.0,
					"the card is centred between the sticks")
				var fatal := _failures.size() > 0
				print("tutorial_card_place_check: %d failure(s)" % _failures.size())
				quit(1 if fatal else 0)
				return true
	return false
