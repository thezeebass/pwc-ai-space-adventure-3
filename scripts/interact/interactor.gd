class_name Interactor
extends RayCast3D

## Aim-based interaction.
##
## Parent it to the Camera3D for desktop and touch, or to an XRController3D for
## VR: the ray, the highlight, and the interact call are identical on every
## platform, which is what keeps the puzzle logic platform-agnostic.

signal target_changed(target: Interactable)

## Generous on purpose: the crew should be able to use a console from where it
## reads well, not from one exact spot on the floor.
@export var reach: float = 4.2

var current: Interactable = null


func _ready() -> void:
	target_position = Vector3(0.0, 0.0, -reach)
	collision_mask = 4
	collide_with_areas = false
	collide_with_bodies = true
	enabled = true


func _physics_process(_delta: float) -> void:
	if InputRouter.ui_blocking:
		InputRouter.consume_interact()
		InputRouter.consume_interact_position()
		_set_target(null)
		return
	force_raycast_update()
	var found: Interactable = get_collider() as Interactable
	if found != null and not found.can_interact(self):
		found = null
	_set_target(found)
	if current != null and InputRouter.consume_interact():
		## A touch tap carries where it landed: the tap must land on the
		## highlighted console's own orange box, not anywhere on the screen.
		## The aim path (a click, a key, a controller button) keeps the
		## reticule rule.
		var tap: Variant = InputRouter.consume_interact_position()
		if tap != null and not current.screen_rect_contains(get_viewport().get_camera_3d(), tap):
			return
		current.interact(self)


## A second ray through the tap's screen position: the console counts as
## tapped when the ray reaches this interactor's reach with the console's
## collider as the first hit.
func _tap_hits_current(screen_position: Vector2) -> bool:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return true
	var from := camera.project_ray_origin(screen_position)
	var direction := camera.project_ray_normal(screen_position)
	var params := PhysicsRayQueryParameters3D.create(
		from, from + direction * target_position.length(), collision_mask)
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(params)
	return not hit.is_empty() and hit.collider == current


func _set_target(next: Interactable) -> void:
	if next == current:
		return
	if current != null and is_instance_valid(current):
		current.set_highlighted(false)
	current = next
	if current != null:
		current.set_highlighted(true)
	target_changed.emit(current)
