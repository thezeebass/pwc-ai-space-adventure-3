extends SceneTree

## Headless check: the HUD's corner MENU button fits its own label, and the
## touch-mode SHIPMIND dialogue sits below the mandate strip instead of on
## top of it.
##
## Run: godot --headless --path . -s res://tests/hud_layout_check.gd

var _hud: CanvasLayer = null
var _stage := 0
var _ticks := 0
var _failures: Array[String] = []


func _initialize() -> void:
	_hud = (load("res://scenes/ui/hud.tscn") as PackedScene).instantiate()


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
				root.add_child(_hud)
				OperatingModel.declare("home_intact", "cautious")
				_hud.set_compact(true)
		1:
			# Two layout passes so the strip and the safe-area pass have run.
			if _ticks > 120:
				_stage = 2
				var view: Vector2 = root.get_viewport().get_visible_rect().size
				var button: Button = _hud.get_node("Root/MenuButton")
				var font := button.get_theme_font("font")
				var fsize: int = button.get_theme_font_size("font_size")
				var text_w: float = font.get_string_size(
					"MENU", HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
				_check(button.size.x >= text_w + 12.0,
					"MENU button fits its own text (%d px button vs %d px label)"
						% [button.size.x, text_w])
				_check(button.global_position.x + button.size.x <= view.x + 0.5,
					"MENU button stays inside the viewport")
				var strip: Control = _hud.get_node("Root/Strip")
				var subtitle: Control = _hud.get_node("Root/Subtitle")
				_check(subtitle.global_position.y >= \
						strip.global_position.y + strip.size.y + 4.0,
					"SHIPMIND dialogue sits below the mandate strip (%.0f vs strip bottom %.0f)"
						% [subtitle.global_position.y,
						strip.global_position.y + strip.size.y])
				var fatal := _failures.size() > 0
				print("hud_layout_check: %d failure(s)" % _failures.size())
				quit(1 if fatal else 0)
				return true
	return false
