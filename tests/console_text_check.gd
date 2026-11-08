extends SceneTree

## Headless check: the TEXT SIZE setting drives the console TUI screens.
## Run: godot --headless --path . -s res://tests/console_text_check.gd

var _console: Node = null
var _stage := 0
var _ticks := 0


func _initialize() -> void:
	_console = (load("res://scenes/ui/console_ui.tscn") as PackedScene).instantiate()


func _process(_d: float) -> bool:
	_ticks += 1
	match _stage:
		0:
			if _ticks > 30:
				_stage = 1
				root.add_child(_console)
		1:
			if _ticks > 150:
				_stage = 2
				TextZoom.set_size(24)
		2:
			if _ticks > 240:
				_stage = 3
				var band: int = _console.band_title.get_theme_font_size("font_size")
				var status: int = _console.band_status.get_theme_font_size("font_size")
				# Title 36 base: 36 * 0.8 * 0.9 = 25.92 -> 26. Body 30 base: 21.6 -> 22.
				print("CONSOLE S(24): title=%d (expect 26) body=%d (expect 22)" % [band, status])
				if band == 26 and status == 22:
					TextZoom.set_size(30)
				else:
					print("CONSOLE CHECK: FAIL at S")
					quit(1)
					return true
		3:
			if _ticks > 330:
				var band: int = _console.band_title.get_theme_font_size("font_size")
				var status: int = _console.band_status.get_theme_font_size("font_size")
				# Title 36 base: 36 * 1.0 * 0.9 = 32.4 -> 32. Body: 27.
				print("CONSOLE L(30): title=%d (expect 32) body=%d (expect 27)" % [band, status])
				if band == 32 and status == 27:
					print("CONSOLE CHECK: PASS")
					quit(0)
				else:
					print("CONSOLE CHECK: FAIL at L")
					quit(1)
	return false
