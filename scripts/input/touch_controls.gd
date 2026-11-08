class_name TouchControls
extends CanvasLayer

## Mobile input layer: two joysticks and no buttons.
##
## The sticks TELEPORT: tap the lower half of the screen and the nearest
## stick centres under your thumb, so you never have to hunt for it.
## There is no jump button: every touch outside a stick is either a look
## drag or an interact tap, so nothing can swallow a stick's release.
##
## LEFT thumb: the move stick - a ring with a smaller knob you drag inside
## it. The ring's edge is the limit of travel.
##
## RIGHT thumb: the look stick - the same kind of ring. This is what replaces
## the old raw drag-look: the knob's deflection is a RATE, not a delta, so the
## view turns smoothly and never whips - and when you let go the knob springs
## home and the view stops.
##
## A TAP on the world (not on a stick, not on a button) is interact: the
## tap casts to whatever the crew is looking at, so the whole screen is the
## interact surface and no button is needed.
##
## It feeds the same InputMap actions and the same InputRouter look delta as
## the mouse, so no room or puzzle script changes for mobile.

@export var force_visible: bool = false

## The move stick. The ring is how far the knob can travel; dead zone is the
## fraction of the ring that counts as rest. The stick sits at the bottom-left
## until a touch claims it.
@export var move_radius: float = 100.0
@export var move_knob_radius: float = 40.0
@export var move_dead_zone: float = 0.18
## The margin keeps the sticks off the screen edge and above the home-bar
## safe area; larger x pulls them inward, larger y lifts them off the bottom.
@export var stick_margin: Vector2 = Vector2(72, 96)
## The sticks only teleport within the lower half of the screen: a tap higher
## up is a look drag, not a stick claim.
@export var stick_grab_region: float = 0.5

## The look stick. The knob's deflection is a turn RATE in radians per second
## at full deflection - slow enough to keep the view readable, fast enough to
## turn when you mean it.
@export var look_radius: float = 100.0
@export var look_knob_radius: float = 40.0
@export var look_dead_zone: float = 0.16
@export var look_yaw_speed: float = 2.3
@export var look_pitch_speed: float = 1.7
## The knob springs home this fast when you let go - fast enough to feel like
## it centres, slow enough not to snap.
@export var stick_return_speed: float = 10.0

@onready var root: Control = $Root
@onready var move_base: Control = $Root/MoveStick
@onready var move_knob: Control = $Root/MoveStick/Knob
@onready var look_base: Control = $Root/LookStick
@onready var look_knob: Control = $Root/LookStick/Knob
@onready var tutorial_card: PanelContainer = $Root/TutorialCard
@onready var tutorial_title: Label = $Root/TutorialCard/Margin/VBox/Title
@onready var tutorial_text: Label = $Root/TutorialCard/Margin/VBox/Text
@onready var tutorial_progress: ProgressBar = $Root/TutorialCard/Margin/VBox/Progress
@onready var tutorial_arrow: Label = $Root/TutorialArrow

## The controls are taught in three stages: the move stick alone (the crew
## walk before they look), then the look stick alone (the view before the
## world reacts), then both together. Stage completion is tracked so the
## walkthrough runs exactly once: GameState.touch_tutorial_done persists it,
## so a returning crew starts with both sticks and no teaching.
enum TutorialStage {
	MOVE_ONLY,
	LOOK_ONLY,
	BOTH,
}
var _tutorial_stage: int = TutorialStage.BOTH
var _aim_wired: bool = false
var _console_in_focus: bool = false
var _console_prompt_open: bool = false

var _move_touch: int = -1
var _look_touch: int = -1
## The actions THIS layer pressed. Releasing an action it never pressed is
## what dropped the keyboard's move keys mid-stride on touch-capable desktops:
## the stick centred, released the winner's held key, and the crew stuttered.
var _owned: Dictionary = {}
var _move_center: Vector2 = Vector2.ZERO
var _look_center: Vector2 = Vector2.ZERO
var _move_dir: Vector2 = Vector2.ZERO
var _look_dir: Vector2 = Vector2.ZERO
var _active_override: bool = false


func _ready() -> void:
	_setup_tutorial()
	_refresh_visibility()
	_layout_sticks()
	_center_knob(move_knob, move_radius, move_knob_radius)
	_center_knob(look_knob, look_radius, look_knob_radius)
	get_viewport().size_changed.connect(_layout_sticks)
	# The aim signal lives on the player, which may not be in the tree yet:
	# the wiring defers one frame so the group lookup always finds it.
	call_deferred("_wire_aim")
	TextZoom.register(root)


## First-time crews learn the sticks in two steps: walk, then look. The stage
## is chosen here, before anything else touches the sticks' visibility, so the
## walkthrough never flashes both sticks for a frame.
func _setup_tutorial() -> void:
	if GameState.touch_tutorial_done:
		_tutorial_stage = TutorialStage.BOTH
	else:
		_tutorial_stage = TutorialStage.MOVE_ONLY
	_apply_tutorial_stage()
	# The walkthrough opens with a pop, so the first stick reads as arriving
	# rather than simply being there. The same pop plays on every later
	# arrival, so every handover lands with the same reveal.
	for base in [move_base, look_base]:
		if base.visible:
			_pop_in(base)


## Stage visibility and the teaching line. The look stick stays hidden until
## the crew have walked the ship, and the hint names the one skill the stage
## is teaching - naming both at once is how nobody reads either.
func _apply_tutorial_stage() -> void:
	var move_shown: bool = _tutorial_stage != TutorialStage.LOOK_ONLY
	var look_shown: bool = _tutorial_stage != TutorialStage.MOVE_ONLY
	var move_was: bool = move_base.visible
	var look_was: bool = look_base.visible
	move_base.visible = move_shown
	look_base.visible = look_shown
	if move_shown and not move_was:
		_pop_in(move_base)
	if look_shown and not look_was:
		_pop_in(look_base)
	_refresh_hint()


## A stick that appears arrives with a pop: it scales up past its rest size
## and settles, so a stage handover reads as a reveal rather than a flicker.
func _pop_in(base: Control) -> void:
	if base == null:
		return
	base.pivot_offset = base.size * 0.5
	var tween := create_tween()
	base.modulate.a = 0.0
	base.scale = Vector2(0.5, 0.5)
	tween.set_parallel(true)
	tween.tween_property(base, "scale", Vector2.ONE, 0.45) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(base, "modulate:a", 1.0, 0.18)


## The teaching card. Each walkthrough stage gets a SHIPMIND-style card dead
## centre - a directive title, one instruction in large type and a progress
## bar - instead of a small line at the bottom nobody reads while steering.
## After the walkthrough the card returns only while a console is in reach,
## so the tap instruction arrives with the target - and only until the crew
## have used a console once: the lesson is its own persisted step, taught
## once, never repeated until a full wipe hands it back.
func _refresh_hint() -> void:
	match _tutorial_stage:
		TutorialStage.MOVE_ONLY:
			_show_card("WALK THE SHIP", "Drag the stick to walk", -1.0)
		TutorialStage.LOOK_ONLY:
			_show_card("LOOK AROUND",
				"Drag the stick to look around", 0.0)
		TutorialStage.BOTH:
			if GameState.touch_console_taught:
				_hide_card()
			elif _console_in_focus:
				if not _console_prompt_open:
					_show_card("USE IT", "Tap the console to use it", -1.0)
					_console_prompt_open = true
			else:
				_hide_card()


## One teaching card: the directive title, the instruction in large type and
## a progress bar (-1 hides the bar). The arrow is separate - it points at a
## stick, not at text.
func _show_card(title: String, text: String, progress: float) -> void:
	tutorial_title.text = title
	tutorial_text.text = text
	## The card reads at the menu's TEXT SIZE choice; its title stays a step
	## above, the same step the terminal's title keeps over its body.
	tutorial_title.add_theme_font_size_override("font_size", 36)
	tutorial_text.add_theme_font_size_override("font_size", 30)
	TextZoom.apply(tutorial_card)
	if progress < 0.0:
		tutorial_progress.visible = false
	else:
		tutorial_progress.visible = true
		tutorial_progress.value = progress * tutorial_progress.max_value
	if not tutorial_card.visible:
		tutorial_card.visible = true
		_pop_in(tutorial_card)


func _hide_card() -> void:
	tutorial_card.visible = false
	tutorial_arrow.visible = false


## The arrow floats between the card and the stick it is teaching, pointing
## at the stick. It hides while the thumb holds the stick - they found it -
## and returns when the stick glides home.
func _update_tutorial_arrow() -> void:
	var teaching: Control = null
	if _tutorial_stage == TutorialStage.MOVE_ONLY and move_base.visible:
		teaching = move_base
	elif _tutorial_stage == TutorialStage.LOOK_ONLY and look_base.visible:
		teaching = look_base
	var thumb_holds: bool = (_tutorial_stage == TutorialStage.MOVE_ONLY \
		and _move_touch != -1) or (_tutorial_stage == TutorialStage.LOOK_ONLY \
		and _look_touch != -1)
	if teaching == null or thumb_holds:
		if tutorial_arrow.visible:
			tutorial_arrow.visible = false
			_arrow_bob.kill()
		return
	var view: Vector2 = get_viewport().get_visible_rect().size
	var center: Vector2 = view * 0.5
	var target: Vector2 = teaching.position \
		+ Vector2(teaching.size.x, teaching.size.y) * 0.5
	var toward: Vector2 = (center - target).normalized()
	var anchor: Vector2 = target + toward * 150.0
	tutorial_arrow.position = anchor - Vector2(28.0, 30.0)
	tutorial_arrow.rotation = (target - anchor).angle()
	if not tutorial_arrow.visible:
		tutorial_arrow.visible = true
		if _arrow_bob == null or not _arrow_bob.is_valid():
			_arrow_bob = create_tween().set_loops()
			_arrow_bob.tween_property(tutorial_arrow, "scale",
				Vector2(1.18, 1.18), 0.4).set_trans(Tween.TRANS_SINE)
			_arrow_bob.tween_property(tutorial_arrow, "scale",
				Vector2.ONE, 0.4).set_trans(Tween.TRANS_SINE)


var _arrow_bob: Tween


## The teaching line follows the crew's aim: the player reports when the ray
## lands on an interactable, and the hint swaps to the tap instruction while
## it does. Wired once, the first time the layer is asked for anything. The
## console lesson latches on the terminal actually opening - a tap that misses
## the box teaches nothing.
func _wire_aim() -> void:
	if _aim_wired:
		return
	_aim_wired = true
	var player: Node = get_tree().get_first_node_in_group("player")
	if player != null and player.has_signal("aim_target_changed"):
		player.aim_target_changed.connect(_on_aim_target_changed)
	for terminal in get_tree().get_nodes_in_group("terminal_ui"):
		if terminal.has_signal("opened") \
				and not terminal.opened.is_connected(_on_console_used):
			terminal.opened.connect(_on_console_used)


## The first console to open teaches the lesson for good: the card goes away
## and the flag persists, so no crew is re-taught what they have done - until
## a full wipe clears it with the rest of the walkthrough.
func _on_console_used() -> void:
	if GameState.touch_console_taught:
		return
	GameState.touch_console_taught = true
	GameState.save()
	_console_prompt_open = false
	_hide_card()


func _on_aim_target_changed(in_focus: bool) -> void:
	if in_focus == _console_in_focus:
		return
	_console_in_focus = in_focus
	_refresh_hint()


## Walk the crew to the next stage of the walkthrough. The move stage hands
## over to the look stage; the look stage hands over the whole ship and
## persists the completion, so no crew ever walks the walkthrough twice.
func _advance_tutorial() -> void:
	_tutorial_stage = mini(_tutorial_stage + 1, TutorialStage.BOTH)
	_apply_tutorial_stage()
	if _tutorial_stage == TutorialStage.BOTH:
		GameState.touch_tutorial_done = true
		GameState.save()


## The crew reached for the look stick on their own: the walkthrough's job is
## done. Ends every stage at once, hides the card and remembers it.
func _finish_tutorial_now() -> void:
	_tutorial_stage = TutorialStage.BOTH
	_apply_tutorial_stage()
	_hide_card()
	GameState.touch_tutorial_done = true
	GameState.save()


## The sticks rest at the bottom corners, and teleport to under a thumb that
## claims them in the lower half of the screen.
func _layout_sticks() -> void:
	if root == null or not root.visible:
		return
	if _move_touch != -1 or _look_touch != -1:
		return
	var view: Vector2 = get_viewport().get_visible_rect().size
	move_base.position = Vector2(stick_margin.x,
		view.y - stick_margin.y - move_radius * 2.0)
	look_base.position = Vector2(view.x - stick_margin.x - look_radius * 2.0,
		view.y - stick_margin.y - look_radius * 2.0)


## The station controller's mode switch. On a desktop the override also lets
## the mouse drive the sticks, because a test is only useful if it can actually
## be driven.
func set_active(value: bool) -> void:
	if value == _active_override:
		return
	_active_override = value
	_refresh_visibility()
	if not root.visible:
		_release_all()


## Something owns the whole screen - the departure cutscene, for example - and
## the sticks have no business sitting over it. Suppression wins over every
## other visibility rule, including a touchscreen's always-on default, and
## lets go of any stick a thumb was still holding.
var _suppressed: bool = false


func set_suppressed(value: bool) -> void:
	if value == _suppressed:
		return
	_suppressed = value
	_refresh_visibility()
	if not root.visible:
		_release_all()


func _refresh_visibility() -> void:
	root.visible = not _suppressed and (force_visible or _active_override \
		or DisplayServer.is_touchscreen_available())


func _mouse_drives() -> bool:
	if force_visible:
		return true
	return _active_override and not DisplayServer.is_touchscreen_available()


func _process(delta: float) -> void:
	# When an overlay (terminal, cards, pause menu) blocks input, the thumb
	# that was on a stick loses its release event: the stick would stay
	# claimed and the camera would keep spinning with the last deflection.
	# Force-release the sticks so nothing survives a blocked frame.
	if InputRouter.ui_blocking or not root.visible:
		_release_all()
		return
	# The look stick is a rate, not a delta: every frame the view turns by the
	# knob's deflection, so it turns smoothly and stops dead when you let go.
	if root.visible and _look_dir.length_squared() > 0.0001:
		InputRouter.add_look(Vector2(_look_dir.x * look_yaw_speed,
			_look_dir.y * look_pitch_speed) * delta)
		# The walkthrough's second stage ends the first time the crew turn the
		# view: the stick has done its one job, and the ship is theirs.
		if _tutorial_stage == TutorialStage.LOOK_ONLY:
			_advance_tutorial()
	# A released stick glides home instead of snapping, which reads as the
	# knob settling rather than disappearing.
	_ease_knob(move_knob, move_radius, delta)
	_ease_knob(look_knob, look_radius, delta)
	# The arrow follows the stick it teaches - the stick teleports and glides,
	# so the pointer has to track it every frame, not sit where it spawned.
	_update_tutorial_arrow()


func _ease_knob(knob: Control, radius: float, delta: float) -> void:
	if knob == null or knob.visible == false:
		return
	var home := Vector2(radius - (knob.size.x * 0.5), radius - (knob.size.y * 0.5))
	var from: Vector2 = knob.position
	if (home - from).length() < 0.5:
		knob.position = home
		return
	knob.position = from.lerp(home, 1.0 - exp(-stick_return_speed * delta))


func _input(event: InputEvent) -> void:
	if not root.visible or InputRouter.ui_blocking:
		return
	if event is InputEventScreenTouch:
		_handle_press(event.index, event.position, event.pressed)
	elif event is InputEventScreenDrag:
		_handle_drag(event.index, event.position)
	elif event is InputEventMouseButton:
		_handle_press(-2, event.position, event.pressed)
	elif event is InputEventMouseMotion \
			and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		_handle_drag(-2, event.position)


var _pending_touch: int = -1
var _pending_start: Vector2 = Vector2.ZERO
## A tap that travels this far is a drag, not a tap, so the finger wobbling
## while it touches never counts as a use.
const TAP_MAX_TRAVEL := 18.0


func _handle_press(index: int, position: Vector2, pressed: bool) -> void:
	if pressed:
		# Every touch is a candidate tap first: it only becomes a stick once the
		# thumb moves, so a quick touch-and-release is always a use, never a
		# stick that briefly appeared.
		# A thumb landing on the right half ends the walkthrough at once: the
		# look stick appears under the thumb's next drag, and no instruction
		# card stays up while the crew are already reaching for it.
		if _tutorial_stage != TutorialStage.BOTH:
			var view: Vector2 = get_viewport().get_visible_rect().size
			if position.x >= view.x * 0.5 \
					and position.y > view.y * (1.0 - stick_grab_region):
				_finish_tutorial_now()
		_pending_touch = index
		_pending_start = position
		return
	if index == _pending_touch:
		var is_tap: bool = position.distance_to(_pending_start) < TAP_MAX_TRAVEL
		_pending_touch = -1
		if is_tap and _move_touch == -1 and _look_touch == -1:
			# The tap is the use the prompt was teaching: dismiss it, whether
			# or not the console actually reacts - the lesson is done.
			if _console_prompt_open:
				_console_prompt_open = false
				_hide_card()
			# The tap carries where it landed: the interactor requires the tap
			# to land on the highlighted console, not anywhere on the screen.
			InputRouter.queue_interact_at(position)
		return
	if index == _move_touch:
		_move_touch = -1
		_move_dir = Vector2.ZERO
		_set_move(Vector2.ZERO)
		_center_knob(move_knob, move_radius, move_knob_radius)
		_return_stick(move_base, move_radius, true)
	elif index == _look_touch:
		_look_touch = -1
		_look_dir = Vector2.ZERO
		_center_knob(look_knob, look_radius, look_knob_radius)
		_return_stick(look_base, look_radius, false)


func _handle_drag(index: int, position: Vector2) -> void:
	# A pending touch that has moved is a stick, not a tap: claim the nearest
	# one and start dragging, so the first pixel of movement already moves.
	if index == _pending_touch and position.distance_to(_pending_start) > TAP_MAX_TRAVEL:
		_claim_stick(index, position)
		_pending_touch = -1
	if index == _move_touch:
		_move_dir = _stick_input(position - _move_center, move_radius, move_dead_zone)
		_set_knob(move_knob, move_radius, move_knob_radius, _move_dir)
		_set_move(_move_dir)
	elif index == _look_touch:
		_look_dir = _stick_input(position - _look_center, look_radius, look_dead_zone)
		_set_knob(look_knob, look_radius, look_knob_radius, _look_dir)


## A drag in the lower half of the screen claims the nearest stick and centres
## it under the thumb, so the stick is under the finger the moment it starts
## to move - not under the finger it has to hunt for. A thumb landing on the
## right half during the walk lesson is the look stick asking in person: the
## walkthrough steps aside at once and the stick claims under the thumb.
func _claim_stick(index: int, position: Vector2) -> void:
	var view: Vector2 = get_viewport().get_visible_rect().size
	var in_grab: bool = position.y > view.y * (1.0 - stick_grab_region)
	if in_grab and _move_touch == -1 and position.x < view.x * 0.5 \
			and _tutorial_stage != TutorialStage.LOOK_ONLY:
		_move_touch = index
		_move_center = position
		move_base.position = position - Vector2(move_radius, move_radius)
		_center_knob(move_knob, move_radius, move_knob_radius)
		if _tutorial_stage == TutorialStage.MOVE_ONLY:
			_finish_tutorial_now()
	elif in_grab and _look_touch == -1 and position.x >= view.x * 0.5:
		if _tutorial_stage == TutorialStage.MOVE_ONLY:
			_advance_tutorial()
		_look_touch = index
		_look_center = position
		look_base.position = position - Vector2(look_radius, look_radius)
		_center_knob(look_knob, look_radius, look_knob_radius)
		if _tutorial_stage == TutorialStage.LOOK_ONLY:
			_finish_tutorial_now()


## A released stick glides back to its corner instead of staying where the
## thumb left it, so the layout resets itself for the next tap.
func _return_stick(base: Control, radius: float, _left: bool) -> void:
	var view: Vector2 = get_viewport().get_visible_rect().size
	var target := Vector2(stick_margin.x, view.y - stick_margin.y - radius * 2.0)
	if not _left:
		target.x = view.x - stick_margin.x - radius * 2.0
	var tween := create_tween()
	tween.tween_property(base, "position", target, 0.22).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


## Normalised stick input: 0..1 inside the dead zone, then a smooth ramp to
## full deflection at the ring's edge. The dead zone keeps a resting thumb
## from drifting, and the ramp keeps small movements slow and precise.
func _stick_input(offset: Vector2, radius: float, dead_zone: float) -> Vector2:
	var v: Vector2 = offset / radius
	var mag: float = v.length()
	if mag < dead_zone:
		return Vector2.ZERO
	var scaled: float = clampf((mag - dead_zone) / (1.0 - dead_zone), 0.0, 1.0)
	return (v / mag) * scaled if mag > 0.001 else Vector2.ZERO


func _center_knob(knob: Control, radius: float, knob_radius: float) -> void:
	if knob != null:
		knob.position = Vector2(radius - knob_radius, radius - knob_radius)


func _set_knob(knob: Control, radius: float, knob_radius: float, direction: Vector2) -> void:
	if knob == null:
		return
	var travel: float = radius - knob_radius
	knob.position = Vector2(radius, radius) - Vector2(knob_radius, knob_radius) + direction * travel


func _set_move(vector: Vector2) -> void:
	# The walkthrough's first stage ends when the crew have pushed the stick
	# every way the ship can go: a stage you can skip is a stick they never
	## The walkthrough's first gate used to demand all four directions before
	## the look stick appeared; any real deflection teaches the stick, so the
	## look stick arrives the moment the crew walks at all.
	if _tutorial_stage == TutorialStage.MOVE_ONLY and vector != Vector2.ZERO:
		_advance_tutorial()
	_action("move_left", vector.x < -0.5)
	_action("move_right", vector.x > 0.5)
	_action("move_forward", vector.y < -0.5)
	_action("move_back", vector.y > 0.5)


func _action(action: StringName, pressed: bool) -> void:
	if pressed:
		if not _owned.has(action):
			Input.action_press(action)
			_owned[action] = true
	elif _owned.has(action):
		Input.action_release(action)
		_owned.erase(action)


## Left pressed after a deactivation would walk the crew into a wall forever.
## Both knobs come home too, so the buttons and the sticks cannot outlive the
## touch that was driving them.
func _release_all() -> void:
	_move_touch = -1
	_look_touch = -1
	_pending_touch = -1
	_move_dir = Vector2.ZERO
	_look_dir = Vector2.ZERO
	_set_move(Vector2.ZERO)
	_center_knob(move_knob, move_radius, move_knob_radius)
	_center_knob(look_knob, look_radius, look_knob_radius)
	_owned.clear()
	_return_stick(move_base, move_radius, true)
	_return_stick(look_base, look_radius, false)


func _exit_tree() -> void:
	_release_all()
