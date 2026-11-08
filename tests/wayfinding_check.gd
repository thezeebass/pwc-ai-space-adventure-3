extends SceneTree

## Headless check: the wayfinding phases. At start the cockpit pocket and the
## first room are lit, the passage idles at 5%; a placed bay lights its zone;
## three upper bays light the lower deck; all five leave an ember passage, a
## blue stair light, and the white light by the cockpit.
##
## Run: godot --headless --path . -s res://tests/wayfinding_check.gd

var _ship: Node = null
var _wf: Node = null
var _stage := 0
var _ticks := 0
var _refresh_ms := 0
var _failures: Array[String] = []


func _settled() -> bool:
	## Headless frames run uncapped, so ticks say nothing about time: the
	## tweens need their real 1.1 seconds before the energies are read.
	var elapsed: int = Time.get_ticks_msec() - _refresh_ms
	if elapsed > 1400 and elapsed % 200 < 40:
		print("DEBUG tween age=", elapsed, " blue=", _light("Wayfinding_Stairs").light_energy)
	return elapsed > 2500


var _save_backup: PackedByteArray = []
var _had_save: bool = false


func _initialize() -> void:
	_had_save = FileAccess.file_exists(GameState.SAVE_PATH)
	if _had_save:
		_save_backup = FileAccess.get_file_as_bytes(GameState.SAVE_PATH)
	_ship = (load("res://scenes/world/station.tscn") as PackedScene).instantiate()


func _check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		_failures.append(what)


func _light(name: String) -> OmniLight3D:
	return _ship.find_child(name, true, false) as OmniLight3D


func _corridor_dim() -> bool:
	for entry in _wf._corridor:
		var l: OmniLight3D = entry["light"]
		if entry["zone"] in ["", "life_support", "comms", "cargo", "engineering", "stairs", "peripheral"]:
			if absf(l.light_energy - entry["base"] * _wf.DIM_RATIO) > 0.02:
				return false
	return true


func _process(_d: float) -> bool:
	_ticks += 1
	match _stage:
		0:
			if _ticks > 30:
				_stage = 1
				root.add_child(_ship)
		1:
			if _ticks > 150:
				_stage = 2
				_wf = _ship.get_node_or_null("Wayfinding")
				_check(_wf != null, "the wayfinding controller is in the ship")
				_check(_wf._corridor.size() >= 5, "corridor lights collected (%d)" % _wf._corridor.size())
				_check(_light("Wayfinding_Cockpit") != null, "the white cockpit light exists")
				_check(_light("Wayfinding_Stairs") != null, "the blue stair light exists")
				var targets: Dictionary = _wf._targets()
				_check(absf(float(targets[_light("Wayfinding_Cockpit").get_instance_id()]) - 1.25) < 0.01,
					"the white cockpit light is lit from the start")
				_check(absf(float(targets[_light("Wayfinding_Stairs").get_instance_id()])) < 0.01,
					"the blue stair light starts dark")
				var idle_ok := true
				var lit_pockets := 0
				for entry in _wf._corridor:
					var l: OmniLight3D = entry["light"]
					var t: float = float(targets[l.get_instance_id()])
					if entry["zone"] == "cockpit" or entry["zone"] == "navigation":
						if absf(t - entry["base"]) < 0.01:
							lit_pockets += 1
					elif absf(t - entry["base"] * _wf.DIM_RATIO) > 0.01:
						idle_ok = false
				_check(lit_pockets >= 1, "the first room's pocket is lit from the start (%d lights)" % lit_pockets)
				_check(idle_ok, "the unvisited passage idles at 5%")
		2:
			if _ticks > 210:
				_stage = 3
				GameState.mark_restored("life_support")
				var targets: Dictionary = _wf._targets()
				var lit := false
				for entry in _wf._corridor:
					var l: OmniLight3D = entry["light"]
					if entry["zone"] == "life_support":
						lit = absf(float(targets[l.get_instance_id()]) - entry["base"]) < 0.01
				_check(lit, "a placed bay's zone lights up")
		3:
			# The last upper bay sends the crew downstairs: the whole route
			# lights, end to end - including the peripheral passage lights by
			# the stairs and the stairwell.
			if _ticks > 270:
				_stage = 4
				GameState.mark_restored("navigation")
				GameState.mark_restored("comms")
				var route: Dictionary = _wf._targets()
				var peripheral_lit := true
				for entry in _wf._corridor:
					var l: OmniLight3D = entry["light"]
					if entry["zone"] == "":
						if absf(float(route[l.get_instance_id()]) - entry["base"]) > 0.01:
							peripheral_lit = false
				_check(peripheral_lit, "the route to the stairs lights end to end")
				for id in GameState.SYSTEMS:
					GameState.mark_restored(id)
				var targets: Dictionary = _wf._targets()
				var ember := true
				for entry in _wf._corridor:
					var l: OmniLight3D = entry["light"]
					if absf(float(targets[l.get_instance_id()]) - entry["base"] * _wf.EMBER_RATIO) > 0.01:
						ember = false
				_check(ember, "the passage drops to an ember glow (2%)")
				_check(absf(float(targets[_light("Wayfinding_Stairs").get_instance_id()]) - 1.0) < 0.01,
					"the blue stair light rises to 80%")
				_check(absf(float(targets[_light("Wayfinding_Cockpit").get_instance_id()]) - 1.25) < 0.01,
					"the white cockpit light stands at full")
				var burn := _ship.find_child("BurnLight", true, false) as OmniLight3D
				_check(burn == null or not targets.has(burn.get_instance_id()),
					"the launch burn lights stay outside the system")
		4:
			if _ticks > 330:
				var fatal := _failures.size() > 0
				print("wayfinding_check: %d failure(s)" % _failures.size())
				quit(1 if fatal else 0)
				return true
	return false
