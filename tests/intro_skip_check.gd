extends SceneTree

## Headless check: the intro's SKIP is earned. On a first telling the button
## is hidden and skipping answers nothing; reaching the last beat earns the
## flag, and with it the skip.
##
## Run: godot --headless --path . -s res://tests/intro_skip_check.gd

var _intro: Node = null
var _stage := 0
var _ticks := 0
var _failures: Array[String] = []
var _save_backup: PackedByteArray = []
var _had_save: bool = false


func _initialize() -> void:
	_had_save = FileAccess.file_exists(GameState.SAVE_PATH)
	if _had_save:
		_save_backup = FileAccess.get_file_as_bytes(GameState.SAVE_PATH)
	_intro = (load("res://scenes/ui/intro_screen.tscn") as PackedScene).instantiate()


func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		_failures.append(what)


func _skip_button() -> Button:
	return _intro.find_child("Skip", true, false) as Button


func _process(_d: float) -> bool:
	_ticks += 1
	match _stage:
		0:
			if _ticks > 30:
				_stage = 1
				root.add_child(_intro)
		1:
			if _ticks > 90:
				_stage = 2
				var skip: Button = _skip_button()
				_check(skip != null and not skip.visible,
					"the SKIP button is hidden on a first telling")
				_intro.skip()
				_check(not _intro._done,
					"skipping on a first telling answers nothing")
		2:
			if _ticks > 150:
				_stage = 3
				_intro._advance()
				_check(not GameState.intro_seen_once and not _intro._done,
					"beat two: still no skip, still not done")
		3:
			if _ticks > 210:
				_stage = 4
				_intro._advance()
				_check(not GameState.intro_seen_once and not _intro._done,
					"beat three on screen: not yet earned")
		4:
			if _ticks > 270:
				_stage = 5
				_intro._advance()
				_check(GameState.intro_seen_once,
					"reading the last beat earns the skip")
				_check(_intro._done, "the telling finishes as read")
		5:
			if _ticks > 330:
				var fatal := _failures.size() > 0
				if _had_save:
					var f := FileAccess.open(GameState.SAVE_PATH, FileAccess.WRITE)
					f.store_buffer(_save_backup)
					f.close()
				elif FileAccess.file_exists(GameState.SAVE_PATH):
					DirAccess.remove_absolute(ProjectSettings.globalize_path(GameState.SAVE_PATH))
				print("intro_skip_check: %d failure(s)" % _failures.size())
				quit(1 if fatal else 0)
				return true
	return false
