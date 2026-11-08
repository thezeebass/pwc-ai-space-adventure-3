class_name Interactable
extends StaticBody3D

## Base class for everything the crew member can aim at and use.
##
## Sits on collision layer 3 (value 4) so the interaction ray (mask 4) finds it,
## and keeps mask 1 so the player still bumps into it instead of walking through.
##
## A child Node3D whose name starts with "Highlight" is the aim outline; it is
## hidden until the player looks at this node.

signal interacted(by)

@export var prompt: String = "Use"
@export var active: bool = true
@export var one_shot: bool = false

var _highlight_nodes: Array[Node3D] = []


func _ready() -> void:
	collision_layer = 4
	collision_mask = 1
	add_to_group("interactable")
	for child in get_children():
		if child is Node3D and String(child.name).begins_with("Highlight"):
			_highlight_nodes.append(child)
			child.visible = false


func get_prompt() -> String:
	return prompt


func can_interact(_by: Node) -> bool:
	return active


func interact(by: Node) -> void:
	interacted.emit(by)
	if one_shot:
		active = false


func set_highlighted(value: bool) -> void:
	for node in _highlight_nodes:
		if is_instance_valid(node):
			node.visible = value


## The orange box, as the player sees it: the aim outline's world box
## projected onto the screen. A tap inside this rectangle is a tap on the
## console. An empty rect means the box is not on screen at all.
func screen_rect(camera: Camera3D) -> Rect2:
	if _highlight_nodes.is_empty():
		return Rect2()
	var source: Node3D = _highlight_nodes[0]
	var aabb := _world_aabb(source)
	if aabb.size == Vector3.ZERO:
		return Rect2()
	var corners: Array[Vector3] = [
		aabb.position,
		aabb.position + Vector3(aabb.size.x, 0, 0),
		aabb.position + Vector3(0, aabb.size.y, 0),
		aabb.position + Vector3(aabb.size.x, aabb.size.y, 0),
		aabb.position + Vector3(0, 0, aabb.size.z),
		aabb.position + Vector3(aabb.size.x, 0, aabb.size.z),
		aabb.position + Vector3(0, aabb.size.y, aabb.size.z),
		aabb.end,
	]
	var rect := Rect2()
	var started := false
	for corner in corners:
		if camera.is_position_behind(corner):
			return Rect2()
		var point: Vector2 = camera.unproject_position(corner)
		if started:
			rect = rect.expand(point)
		else:
			rect = Rect2(point, Vector2.ZERO)
			started = true
	return rect.grow(12.0)


func screen_rect_contains(camera: Camera3D, position: Vector2) -> bool:
	var rect := screen_rect(camera)
	return rect.size != Vector2.ZERO and rect.has_point(position)


static func _world_aabb(node: Node3D) -> AABB:
	var result := AABB()
	var started := false
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for child in n.get_children():
			stack.append(child)
		if n is MeshInstance3D:
			var mesh_aabb: AABB = (n as MeshInstance3D).get_aabb()
			var world: AABB = (n as MeshInstance3D).global_transform * mesh_aabb
			if started:
				result = result.merge(world)
			else:
				result = world
				started = true
	return result


func flash() -> void:
	## Short visual acknowledgement so every input has feedback.
	var target: Node3D = _highlight_nodes[0] if not _highlight_nodes.is_empty() else null
	if target == null:
		return
	target.visible = true
	var tween := create_tween()
	tween.tween_interval(0.08)
	tween.tween_callback(func() -> void: target.visible = false)
