class_name InputRouter
extends RefCounted

## Platform-agnostic input bus.
##
## Gameplay and puzzle code read only three things: the InputMap actions
## (move_forward / move_back / move_left / move_right / interact), this look
## delta, and the interact edge. Desktop mouse, touch drag, and an XR controller
## all feed the SAME two values, so no puzzle or room script ever needs to know
## which platform is running.
##
## Static by design: no autoload entry, nothing to wire in project.godot.

static var look_delta: Vector2 = Vector2.ZERO
static var interact_just_pressed: bool = false
## The screen position a touch tap landed on, carried through to the
## interactor so it can require the tap to land on the console itself. Null
## for aim-path interactions (a click, a key, a controller button), which
## keep the reticule rule.
static var interact_position: Variant = null
static var ui_blocking: bool = false


static func add_look(delta: Vector2) -> void:
	look_delta += delta


static func consume_look() -> Vector2:
	var delta: Vector2 = look_delta
	look_delta = Vector2.ZERO
	return delta


static func queue_interact() -> void:
	interact_just_pressed = true


## A touch tap that wants the console: the position rides along so the
## interactor can require the tap to land on the highlighted console.
static func queue_interact_at(position: Vector2) -> void:
	interact_position = position
	interact_just_pressed = true


static func consume_interact() -> bool:
	var pressed: bool = interact_just_pressed
	interact_just_pressed = false
	return pressed


## Returns the tap's screen position when the queued interact carried one,
## and clears it. Null for aim-path interactions.
static func consume_interact_position() -> Variant:
	var position: Variant = interact_position
	interact_position = null
	return position


static func set_ui_blocking(value: bool) -> void:
	ui_blocking = value
	if value:
		look_delta = Vector2.ZERO
		interact_just_pressed = false
		interact_position = null
