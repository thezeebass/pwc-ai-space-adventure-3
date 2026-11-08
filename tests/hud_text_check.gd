extends SceneTree

## Headless check: the TEXT SIZE setting drives the HUD's real font sizes.
## Run: godot --headless --path . -s res://tests/hud_text_check.gd

var _hud: Node = null
var _stage := 0
var _ticks := 0


func _initialize() -> void:
	_hud = (load("res://scenes/ui/hud.tscn") as PackedScene).instantiate()


func _process(_d: float) -> bool:
	_ticks += 1
	match _stage:
		0:
			if _ticks > 30:
				_stage = 1
				root.add_child(_hud)
		1:
			if _ticks > 150:
				_stage = 2
				TextZoom.set_size(24)
		2:
			if _ticks > 240:
				_stage = 3
				var sub: int = _hud.subtitle_text.get_theme_font_size("font_size")
				var mandate: int = _hud._mandate_label.get_theme_font_size("font_size")
				var menu: int = _hud._menu_button_ref.get_theme_font_size("font_size")
				print("SIZE CHECK S(24): subtitle=%d mandate=%d menu=%d" % [sub, mandate, menu])
				if sub == 24 and mandate == 24 and menu == 24:
					TextZoom.set_size(30)
				else:
					print("SIZE CHECK: FAIL at S")
					quit(1)
					return true
		3:
			if _ticks > 330:
				var sub: int = _hud.subtitle_text.get_theme_font_size("font_size")
				print("SIZE CHECK L(30): subtitle=%d" % sub)
				if sub == 30:
					print("SIZE CHECK: PASS")
					quit(0)
				else:
					print("SIZE CHECK: FAIL at L")
					quit(1)
	return false
