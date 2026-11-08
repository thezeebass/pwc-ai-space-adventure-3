extends Node3D

## Station controller. It owns nothing about a decision: it wires the shared UI
## to whatever puzzles, sealed doors and bay triggers exist in the station,
## picks the platform input layer, and runs the auto-save.
##
## Adding system 2-5 means dropping a bay console with a Puzzle child into
## station.tscn. This file does not need to change (docs/adding-a-system.md).

const XR_RIG_PATH := "res://scenes/player/xr_rig.tscn"
const DESKTOP_RIG_PATH := "res://scenes/player/player.tscn"

@onready var hud: HUD = $UI/HUD
@onready var terminal: TerminalUI = $UI/TerminalUI
@onready var principle_card: PrincipleCard = $UI/PrincipleCard
@onready var pause_menu: PauseMenu = $UI/PauseMenu
@onready var completion: CompletionScreen = $UI/CompletionScreen

var _player: Node3D = null
var _pending_pa: String = ""
## The station's own environment, kept so a test swing into VR and back can
## restore the desktop look instead of leaving it with XR's post-processing.
var _desktop_environment: Environment = null


func _ready() -> void:
	# The audio buses are scene nodes in main.tscn (groups "sfx_ambience" and
	# "sfx_voice"), so they are already valid here. Creating players lazily
	# during tree setup is what made the console and ambience sounds silent.
	GameState.load_data()
	_player = _activate_player()
	_wire_puzzles()
	_wire_cockpit()
	_wire_doors()
	_wire_triggers()
	_wire_interactors()
	_apply_saved_world_state()
	_refresh_decision_states()
	terminal.opened.connect(_on_terminal_opened)
	terminal.closed.connect(_on_overlay_closed)
	principle_card.closed.connect(_on_overlay_closed)
	## The end of the run: the cutscene hands the camera back to the crew in the
	## cockpit, and the completion screen then states what the five decisions
	## added up to. It is the only screen that reads the whole run at once.
	if completion != null and not completion.closed.is_connected(_on_completion_closed):
		completion.closed.connect(_on_completion_closed)
	## The in-run menu is wired here rather than in the menu itself, because
	## "back to the title card" and "reset the run" are the controller's job.
	if pause_menu != null:
		if not pause_menu.main_menu_requested.is_connected(_on_main_menu_requested):
			pause_menu.main_menu_requested.connect(_on_main_menu_requested)
		if not pause_menu.reset_requested.is_connected(_on_reset_requested):
			pause_menu.reset_requested.connect(_on_reset_requested)
		if hud != null and not hud.menu_requested.is_connected(pause_menu.open):
			hud.menu_requested.connect(pause_menu.open)
	hud.refresh_objective()
	# Two beds for the whole experience, started here and left running: the room
	# tone under everything, the soundtrack over it. The mixer's saved state is
	# read back first, so the beds launch at the level the crew left behind -
	# music muted stays muted, a fader parked at 40% stays parked there.
	Sfx.load_settings()
	Sfx.play_ambience()
	Sfx.play_music()
	await get_tree().process_frame
	if OS.is_debug_build():
		print("[Sfx] ", Sfx.debug_state())
	## The mandate is fixed and the landing screen is gone: the ship loads
	## straight into play, with the narrative intro (when one is wanted) the
	## only thing standing between the crew and the corridor.
	var intro := get_node_or_null("UI/IntroScreen") as IntroScreen
	if intro != null and not get_tree().has_meta("shipmind_intro_played"):
		hud.visible = false
		intro.finished.connect(_on_intro_finished)
	else:
		if intro != null:
			intro.visible = false
		_on_session_begin()


## The intro has told its three beats. The crew takes the ship directly - the
## mandate card is retired, so the story hands straight over to the corridor.
func _on_intro_finished() -> void:
	get_tree().set_meta("shipmind_intro_played", true)
	_on_session_begin()
## "Back to the title card" now means "start the run again": the mandate card
## is retired, so there is no screen to hand back to. The full reset wipes the
## record and reloads the scene, which is exactly the clean start the crew is
## asking for when they leave the run.
func _on_main_menu_requested() -> void:
	GameState.clear_save()
	InputRouter.set_ui_blocking(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().call_deferred("reload_current_scene")


## A full reset: the save is wiped, then the scene is reloaded so every door,
## window, lamp, console and the HUD are rebuilt from one clean record. Patching
## the live state instead would leave each Puzzle's own is_solved flag set.
func _on_reset_requested() -> void:
	GameState.clear_save()
	InputRouter.set_ui_blocking(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().call_deferred("reload_current_scene")


## The run starts here. The clock begins at the moment the crew takes the ship,
## not when the title card loads, so reading the briefing is not billed to them.
func _on_session_begin() -> void:
	hud.visible = true
	## The landing card is gone, so its hand-over duty lives here: the intro
	## holds the input block while it tells, and the corridor needs it back
	## the moment the crew takes the ship.
	InputRouter.set_ui_blocking(false)
	GameState.begin_run()
	_announce_boot()
	## The crew have the ship: the cursor is taken back here as well as at the
	## close of any overlay, because a capture requested while a window is
	## still coming up is refused, and the first look must work without a click.
	_grab_cursor_back()


## Platform selection. The input mode layer decides - hardware detection first,
## with the pause menu's mode chips able to override it for the session - and
## this controller re-wires the rig, the touch layer and the HUD whenever it
## changes.
func _activate_player() -> Node3D:
	InputMode.ensure_detected()
	var default_player: Node3D = get_node_or_null("Player") as Node3D
	if InputMode.mode != InputMode.Mode.VR or not _xr_available() or default_player == null:
		return default_player
	return _install_rig(XR_RIG_PATH, default_player)


func _process(_delta: float) -> void:
	if InputMode.consume_dirty():
		_apply_mode()


## Android's back gesture and a browser's back action arrive here rather than as
## a key, and the default is to quit the app outright - which on a phone means
## dropping the run from inside a menu. The rule is the same one the ESC key
## follows: one layer back at a time, and only the title card lets go of the app.
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_on_back_requested()


func _on_back_requested() -> void:
	if completion != null and completion.is_open():
		completion.close()
		return
	if terminal.is_open():
		terminal.close()
		return
	if principle_card.is_open():
		principle_card.dismiss()
		return
	var intro := get_node_or_null("UI/IntroScreen") as IntroScreen
	if intro != null and intro.is_open():
		intro.skip()
		return
	if pause_menu != null and pause_menu.is_open():
		pause_menu.close()
		return
	if pause_menu != null:
		pause_menu.open()
		return
	if OS.has_feature("android") or OS.has_feature("web"):
		get_tree().quit()


## The test switch, honoured live: desktop and touch share the same body and
## only swap their input layer and HUD density, so they flip instantly. VR
## needs a different rig, so it swaps nodes - and when no OpenXR runtime is
## reachable it says so and stays on the desktop body rather than failing
## silently.
func _apply_mode() -> void:
	var touch := get_node_or_null("UI/TouchControls") as TouchControls
	match InputMode.mode:
		InputMode.Mode.TOUCH:
			_ensure_desktop_rig()
			if touch != null:
				touch.set_active(true)
			hud.set_compact(true)
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			hud.say_system("Mobile mode. Left thumb walks, right thumb looks, tap to use.", 4.5)
		InputMode.Mode.VR:
			if _xr_available():
				_ensure_xr_rig()
				if touch != null:
					touch.set_active(false)
				hud.set_compact(false)
			else:
				InputMode.mode = InputMode.Mode.DESKTOP
				hud.set_compact(false)
				hud.say_system("No OpenXR runtime found - staying on desktop.", 4.5)
		_:
			_ensure_desktop_rig()
			if touch != null:
				touch.set_active(false)
			hud.set_compact(false)
			_grab_cursor_back()


func _ensure_desktop_rig() -> void:
	if _player is Player:
		return
	var current := get_node_or_null("Player") as Node3D
	_player = _install_rig(DESKTOP_RIG_PATH, current)
	_restore_desktop_environment()
	_wire_interactors()


func _ensure_xr_rig() -> void:
	if _player is XRRig:
		return
	var current := get_node_or_null("Player") as Node3D
	_player = _install_rig(XR_RIG_PATH, current)
	_apply_xr_safe_environment()
	_wire_interactors()


## Swaps whatever stands at "Player" for a fresh instance of the given rig
## scene, keeping its transform so a mode change never teleports the crew.
func _install_rig(rig_path: String, current: Node3D) -> Node3D:
	var scene: PackedScene = load(rig_path) as PackedScene
	if scene == null or current == null:
		push_warning("Rig scene missing at %s; keeping the current player." % rig_path)
		return current
	var transform: Transform3D = current.transform
	var parent: Node = current.get_parent()
	parent.remove_child(current)
	current.queue_free()
	var rig: Node3D = scene.instantiate()
	rig.transform = transform
	parent.add_child(rig)
	## A fresh node would otherwise interpolate from the origin on its first
	## drawn frame after a mode switch.
	rig.reset_physics_interpolation()
	rig.name = "Player"
	return rig


func _restore_desktop_environment() -> void:
	get_viewport().use_xr = false
	if _desktop_environment == null:
		return
	var world_env := get_node_or_null("Station/WorldEnvironment") as WorldEnvironment
	if world_env != null:
		world_env.environment = _desktop_environment
	_desktop_environment = null


## The same hand-back every overlay close performs: whoever owns the
## "input_layer" group decides whether the cursor may be captured, and in a
## touch or XR mode it will decline on its own. Refused while an overlay owns
## the input - a mode flip inside the pause menu must not capture the cursor
## out from under the menu the player is using.
func _grab_cursor_back() -> void:
	if InputRouter.ui_blocking:
		return
	for node in get_tree().get_nodes_in_group("input_layer"):
		if node.has_method("grab_mouse"):
			node.grab_mouse()


func _xr_available() -> bool:
	if not bool(ProjectSettings.get_setting("xr/openxr/enabled", false)):
		return false
	var interface: XRInterface = XRServer.find_interface("OpenXR")
	if interface == null:
		return false
	if interface.is_initialized():
		return true
	if not interface.initialize():
		push_warning("OpenXR is enabled but could not start; using the desktop player.")
		return false
	get_viewport().use_xr = true
	_apply_xr_safe_environment()
	return true


## Post-processing that survives stereo.
##
## Godot warns that many post-process effects are not stereoscopic-aware, and
## this ship's look leans on two of them: glow (bloom) and SSAO. Both are
## screen-space passes computed from one depth buffer, so in a headset they can
## resolve differently in each eye. They are switched off for an XR run only,
## and on a COPY of the environment, so the desktop look is untouched and this
## is not destructive - quitting the headset run leaves the scene as it was.
##
## Fog is deliberately left on: it is evaluated per fragment in the shader
## rather than as a screen-space pass, so stereo does not affect it, and it is
## doing real work in the corridors.
func _apply_xr_safe_environment() -> void:
	var world_env := get_node_or_null("Station/WorldEnvironment") as WorldEnvironment
	if world_env == null or world_env.environment == null:
		return
	if _desktop_environment == null:
		_desktop_environment = world_env.environment
	var xr_env: Environment = _desktop_environment.duplicate()
	xr_env.glow_enabled = false
	xr_env.ssao_enabled = false
	world_env.environment = xr_env


func _wire_puzzles() -> void:
	for node in get_tree().get_nodes_in_group("puzzle"):
		var puzzle := node as Puzzle
		if puzzle == null or puzzle.puzzle_id == "":
			continue
		## The helm is wired by _wire_cockpit instead: its solved signal ends the
		## game, so it must not also be handled as a restored ship system.
		if puzzle is FlightConsole:
			continue
		if not puzzle.solved.is_connected(_on_puzzle_solved):
			puzzle.solved.connect(_on_puzzle_solved)


func _wire_doors() -> void:
	for node in get_tree().get_nodes_in_group("interactable"):
		var door := node as LockedDoor
		if door == null:
			continue
		if not door.denied.is_connected(_on_door_denied):
			door.denied.connect(_on_door_denied)
		if not door.opened.is_connected(_on_door_opened):
			door.opened.connect(_on_door_opened)


func _wire_triggers() -> void:
	for node in get_tree().get_nodes_in_group("bay_trigger"):
		var trigger := node as BayTrigger
		if trigger != null and not trigger.speak.is_connected(_on_bay_speak):
			trigger.speak.connect(_on_bay_speak)


func _wire_interactors() -> void:
	for interactor in _collect_interactors(_player):
		if not interactor.target_changed.is_connected(_on_target_changed):
			interactor.target_changed.connect(_on_target_changed)


func _collect_interactors(node: Node) -> Array[Interactor]:
	var found: Array[Interactor] = []
	if node == null:
		return found
	for child in node.get_children():
		if child is Interactor:
			found.append(child)
		found.append_array(_collect_interactors(child))
	return found


## The opening monologue. A fresh session gets the briefing with an explicit
## first action; a resumed one gets the recap of what the crew already holds,
## followed by the override log, so a restored ship reads as a continued story.
func _announce_boot() -> void:
	hud.say_shipmind_lines(Shipmind.boot_state(), 6.5)
	if GameState.override_log.is_empty():
		return
	for entry in GameState.override_log:
		hud.say_shipmind("ON RECORD: %s" % String(entry), 5.0)
		await get_tree().create_timer(5.0).timeout


## The bridge helm is the last room, and its puzzle ends the game rather than
## returning a system, so it is wired separately: solved starts the departure.
func _wire_cockpit() -> void:
	for node in get_tree().get_nodes_in_group("puzzle"):
		var helm := node as FlightConsole
		if helm != null and not helm.solved.is_connected(_on_cockpit_launch):
			helm.solved.connect(_on_cockpit_launch)
	var cutscene := get_node_or_null("Station/LaunchCutscene") as LaunchCutscene
	if cutscene != null and not cutscene.finished.is_connected(_on_departure_finished):
		cutscene.finished.connect(_on_departure_finished)


func _on_cockpit_launch(_system_id: String) -> void:
	## The terminal is still open beneath the cutscene, so it is closed first -
	## otherwise the crew would land back on a screen of text after the flight.
	if terminal.is_open():
		terminal.close()
	## The run is flown. The clock stops at the helm rather than when the last
	## screen is dismissed, so the session's duration stays the session's.
	GameState.finish_run()
	var cutscene := get_node_or_null("Station/LaunchCutscene") as LaunchCutscene
	if cutscene == null:
		push_warning("No LaunchCutscene under Station; the flight would have no ending.")
		return
	cutscene.play()


## The ship has gone, and the crew are back in the cockpit watching the record.
## The completion screen takes over: the run as a matrix, and the one thing left
## to do with it - put it on the board.
func _on_departure_finished() -> void:
	if completion == null:
		return
	if hud != null:
		hud.visible = false
	completion.show_screen()


## Back from the completion screen: the readout returns, and the crew's cursor
## goes back to the ship the same way it does after any overlay closes.
func _on_completion_closed() -> void:
	if hud != null:
		hud.visible = true
	_grab_cursor_back()


## Test door for the end of the run, which otherwise needs five decisions and a
## flight: the F9 replay of the departure has a companion here so the completion
## screen can be looked at directly. Development builds only.
func dev_show_completion() -> void:
	if not OS.is_debug_build():
		return
	if terminal.is_open():
		terminal.close()
	_on_departure_finished()


## Test record for the screens that need a whole run behind them: a declared
## mandate and one placement per decision, at levels a real crew might choose.
## It writes the record in memory only - it does NOT save - so looking at the
## end screen cannot overwrite the person's own progress with a test run.
func dev_seed_run() -> void:
	if not OS.is_debug_build():
		return
	OperatingModel.declare("finish_the_survey", "balanced")
	GameState.placements = {
		"navigation": {"level": "signoff", "level_index": 2},
		"life_support": {"level": "review", "level_index": 1},
		"comms": {"level": "automated", "level_index": 0},
		"cargo": {"level": "human_only", "level_index": 3},
		"engineering": {"level": "signoff", "level_index": 2},
	}
	if hud != null:
		hud.refresh_objective()


## Opens the read-back card for one decision, for looking at its layout without
## placing five decisions first.
func dev_show_card(system_id: String) -> void:
	if not OS.is_debug_build():
		return
	if not GameState.has_placement(system_id):
		dev_seed_run()
	principle_card.show_card(system_id)


## Opens one bay's console as if the crew had walked up and pressed it, and
## forgets any test placement so the spectrum itself is on screen. Debug builds
## only, and memory only.
func dev_show_terminal(system_id: String) -> void:
	if not OS.is_debug_build():
		return
	if not OperatingModel.is_declared():
		OperatingModel.declare("finish_the_survey", "balanced")
	for node in get_tree().get_nodes_in_group("puzzle"):
		var puzzle := node as Puzzle
		if puzzle == null or puzzle.puzzle_id != system_id:
			continue
		puzzle.is_solved = false
		GameState.placements.erase(system_id)
		GameState.restored.erase(system_id)
		terminal.open(puzzle)
		return
	push_warning("dev_show_terminal: no console for '%s'." % system_id)


## Developer helper: write what the game is drawing to user://shots/<name>.png,
## so a frame can be inspected without somebody sitting in front of the window.
## This is how the intro, the read-back card and the completion screen get their
## layouts checked at more than one window size. Debug builds only.
func dev_capture(file_name: String) -> void:
	if not OS.is_debug_build():
		return
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	if image == null:
		push_warning("DevCapture: the viewport had no texture to copy.")
		return
	var dir := DirAccess.open("user://")
	if dir != null and not dir.dir_exists("shots"):
		dir.make_dir("shots")
	var path := "user://shots/%s.png" % file_name
	var err := image.save_png(path)
	if err != OK:
		push_warning("DevCapture: could not write %s (%d)." % [path, err])
		return
	print("[DevCapture] %s" % ProjectSettings.globalize_path(path))


## Developer helper: the same capture, from a camera of its own at a given place
## and aim ("x,y,z" as text, because the editor's runtime transport passes every
## argument as a string). It lets a corner of the ship be looked at without
## walking there, which is how the helm doorway's dressing gets checked.
func dev_capture_view(file_name: String, from_text: String, look_text: String) -> void:
	if not OS.is_debug_build():
		return
	var from := _dev_vec(from_text, Vector3(0.0, 1.8, 0.0))
	var look := _dev_vec(look_text, Vector3(0.0, 1.7, 1.0))
	var previous := get_viewport().get_camera_3d()
	var camera := Camera3D.new()
	camera.name = "DevCaptureCamera"
	camera.fov = 70.0
	camera.near = 0.05
	add_child(camera)
	camera.global_position = from
	camera.look_at(look, Vector3.UP)
	camera.current = true
	await dev_capture(file_name)
	camera.queue_free()
	if previous != null and is_instance_valid(previous):
		previous.current = true


func _dev_vec(text: String, fallback: Vector3) -> Vector3:
	var parts: PackedStringArray = text.split(",")
	if parts.size() != 3:
		return fallback
	return Vector3(float(parts[0]), float(parts[1]), float(parts[2]))


## A decision has been placed. The reflection card states what was placed and
## whether it follows from the mandate, so the verdict lands with the decision
## rather than in a record nobody reads until the end.
func _on_puzzle_solved(system_id: String) -> void:
	if system_id == "":
		return
	# mark_restored is idempotent: the first release writes the "Call made" log
	# line, and a repeated release only re-asserts the flag.
	GameState.mark_restored(system_id)
	hud.refresh_objective()
	_open_system_window(system_id)
	_set_bay_light(system_id)
	if terminal.is_open():
		terminal.close()
	principle_card.show_card(system_id)
	# Held until the card is dismissed, so SHIPMIND's response to the placement
	# is not buried behind the reflection card.
	_pending_pa = Shipmind.system_restored(system_id)


func _on_door_denied(system_id: String) -> void:
	hud.say_shipmind(Shipmind.denial(system_id), 7.0)


func _on_door_opened(system_id: String) -> void:
	hud.say_shipmind("Opening the %s room. The console inside is live - take your time." % GameState.display_name(system_id), 6.0)


## Scene children run _ready before this controller loads the save, so a bay door
## or a window belonging to a system the crew already holds has to be told so
## once the save is actually in memory. Without this a restored ship reloads with
## its doors shut and its windows dark.
func _apply_saved_world_state() -> void:
	for node in get_tree().get_nodes_in_group("interactable"):
		var door := node as LockedDoor
		if door != null:
			door.refresh_from_state()
	for node in get_tree().get_nodes_in_group("window_wall"):
		var wall := node as WindowWall
		if wall != null:
			wall.refresh_from_state()
	for node in get_tree().get_nodes_in_group("bay_light"):
		var light := node as BayLight
		if light != null:
			light.refresh_from_state()


## A bay whose decision is placed turns its room light over to the crew, so a
## finished room reads as finished from inside it. The doorway plates carry
## the bay's number; this carries its state.
func _set_bay_light(system_id: String) -> void:
	for node in get_tree().get_nodes_in_group("bay_light"):
		var light := node as BayLight
		if light != null and light.system_id == system_id:
			light.set_placed(GameState.is_restored(system_id))


## A puzzle's own _ready also fires before the save is in memory, so a decision
## the record already holds has to be told so once it has landed. Without this a
## resumed session would re-offer a decision that is already placed.
func _refresh_decision_states() -> void:
	for node in get_tree().get_nodes_in_group("puzzle"):
		var puzzle := node as Puzzle
		if puzzle != null and GameState.is_restored(puzzle.puzzle_id):
			puzzle.is_solved = true


## Taking a system back is what reveals the outside: each restored bay opens its
## window onto the exterior, so the reward for the override is the view.
func _open_system_window(system_id: String) -> void:
	for node in get_tree().get_nodes_in_group("window_wall"):
		var wall := node as WindowWall
		if wall != null and wall.system_id == system_id:
			wall.set_open(true)


func _on_bay_speak(lines: PackedStringArray) -> void:
	hud.say_shipmind_lines(Array(lines), 4.5)


func _on_target_changed(target: Interactable) -> void:
	if target == null:
		hud.clear_prompt()
	else:
		hud.set_prompt("[%s]  %s" % [_interact_hint(), target.get_prompt()])


func _on_terminal_opened() -> void:
	# The terminal overlay covers the world, so the aim prompt goes with it.
	hud.clear_prompt()


func _on_overlay_closed() -> void:
	if _player != null and _player.has_method("on_ui_closed"):
		_player.on_ui_closed()
	if _pending_pa != "":
		var line: String = _pending_pa
		_pending_pa = ""
		hud.say_shipmind(line, 8.0)


func _interact_hint() -> String:
	match InputMode.mode:
		InputMode.Mode.VR:
			return "TRIGGER"
		InputMode.Mode.TOUCH:
			return "TAP"
	return "E"
