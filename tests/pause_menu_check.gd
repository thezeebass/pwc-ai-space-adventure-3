extends SceneTree

## Headless check: the in-run menu carries no RESUME and no MAIN MENU button -
## the crew leave by tapping outside the card (or Escape) - and the dim tap
## still closes it. LEADERBOARD, AUDIO and TEXT SIZE stay.
##
## Run: godot --headless --path . -s res://tests/pause_menu_check.gd

var _menu: CanvasLayer = null
var _stage := 0
var _ticks := 0
var _failures: Array[String] = []


func _initialize() -> void:
	_menu = (load("res://scripts/ui/pause_menu.gd") as GDScript).new()


func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		_failures.append(what)


func _collect_buttons(node: Node, found: Array[Button]) -> void:
	for child in node.get_children():
		if child is Button:
			found.append(child)
		_collect_buttons(child, found)


func _process(_d: float) -> bool:
	_ticks += 1
	match _stage:
		0:
			if _ticks > 30:
				_stage = 1
				root.add_child(_menu)
				_menu.open()
		1:
			if _ticks > 90:
				_stage = 2
				var labels: Array[String] = []
				var buttons: Array[Button] = []
				_collect_buttons(_menu, buttons)
				for button in buttons:
					labels.append(button.text)
				_check(not labels.has("RESUME"), "no RESUME button")
				_check(not labels.has("MAIN MENU"), "no MAIN MENU button")
				_check(labels.has("LEADERBOARD"), "LEADERBOARD still present")
				_check(_menu.is_open(), "the menu is open")
				# The card reads wide and short: one header over two columns.
				var card: PanelContainer = _menu.get_node("Root/Card")
				var body: HBoxContainer = null
				for child in card.get_child(0).get_children():
					if child is HBoxContainer:
						body = child
				_check(body != null and body.get_child_count() == 2,
					"the menu body is two columns")
				_check(card.custom_minimum_size.x >= 500.0,
					"the card reads wide (%d px)" % int(card.custom_minimum_size.x))
				var s_chip: Button = null
				for button in buttons:
					if button.text == "S":
						s_chip = button
				_check(s_chip != null and s_chip.button_pressed,
					"S is the default text size")
				# A press on the dim - the gesture outside the card - closes it.
				var dim: ColorRect = _menu.get_node("Root/Dim")
				var tap := InputEventMouseButton.new()
				tap.button_index = MOUSE_BUTTON_LEFT
				tap.pressed = true
				tap.position = Vector2(40.0, 40.0)
				dim.gui_input.emit(tap)
		2:
			if _ticks > 120:
				var fatal := _failures.size() > 0
				_check(not _menu.is_open(), "tapping outside the card closes the menu")
				var fatal2 := _failures.size() > 0
				print("pause_menu_check: %d failure(s)" % _failures.size())
				quit(1 if (fatal or fatal2) else 0)
				return true
	return false
