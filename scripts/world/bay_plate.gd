class_name BayPlate
extends Node3D

## The number plate beside each bay doorway: the bay's number with its name
## under it, on the corridor face of the spine wall next to the opening.
##
## WHY IT EXISTS. The corridors read as a run of identical doorways, and the
## kiosk and the PA speak in bay numbers and system names, so each doorway has
## to say which bay it is at a glance - including the one doorway that carries
## no door at all (navigation was left open on purpose).
##
## The plate is a child of the doorway body, which stands in the wall plane
## with the floor at local y 0, so one authored position serves both decks;
## which way the text faces is derived from the doorway's own X, the same rule
## window_wall.gd uses to tell inboard from outboard.
##
## The labels are rebuilt here on every load rather than kept as scene nodes:
## the authoring tools run _ready while packing, so a plate that saved its own
## labels would load with two copies, and the sizes and colours below are the
## single source of truth for the plate's look.

const GOLD := Color(0.941, 0.722, 0.224)   ## attention/resolved - the HUD's placed colour
const SAND := Color(0.93, 0.86, 0.76)      ## the info/neutral step of the palette
const INK := Color(0.06, 0.03, 0.02, 1.0)  ## the warm near-black the grounds use

const PIXEL_SIZE := 0.004   ## metres per font pixel, so the number renders ~0.3 m tall
const NUMBER_SIZE := 110    ## the bay number, in font pixels
const NAME_SIZE := 34       ## the bay's name, under the number
const NUMBER_LIFT := 0.20   ## the number's centre above the plate origin
const NAME_DROP := 0.14     ## the name's centre below it

## Short names for the plates. The kiosk and the door prompts speak in
## GameState.display_name, whose suffixed forms ("CARGO / RESOURCES") are
## longer than the stretch of wall beside a door, so a plate carries the short
## form; anything not listed falls back to the full display name.
const SHORT_NAMES := {
	"navigation": "NAVIGATION",
	"life_support": "LIFE SUPPORT",
	"comms": "COMMS",
	"cargo": "CARGO",
	"engineering": "ENGINEERING",
}

@export var system_id: String = ""
## An authored plate for a room that is no bay - the helm, say. When both are
## set they replace the bay lookup: the same look, the room's own number and
## name.
@export var plate_number: String = ""
@export var plate_name: String = ""
## An authored facing in degrees. The decks' plates face the corridor off the
## doorway's own X; the ship's own doorways run fore-aft, where that rule does
## not apply, so a plate there states its facing outright. Anything above 360
## means "derive it the decks' way".
@export var plate_yaw_deg: float = 999.0


func _ready() -> void:
	## Rebuild rather than reuse: a plate saved with label children (the
	## authoring tools pack what _ready builds) must not load with two copies.
	for child in get_children():
		child.queue_free()
	var parent_body := get_parent() as Node3D
	if parent_body == null:
		push_warning("Bay plate '%s' has no doorway to read its wall side from." % name)
		return
	var yaw: float
	if plate_yaw_deg <= 360.0:
		yaw = deg_to_rad(plate_yaw_deg)
	else:
		## The plate faces the corridor: a doorway on the +X spine wall opens
		## toward -X, and one on the -X wall toward +X.
		yaw = PI * 0.5 if parent_body.global_position.x < 0.0 else -PI * 0.5
	if GameState.SYSTEMS.has(system_id):
		_add_label("Number", str(GameState.system_index(system_id)), NUMBER_SIZE, GOLD,
			NUMBER_LIFT, yaw)
		_add_label("Name", _short_name(), NAME_SIZE, SAND, -NAME_DROP, yaw)
		return
	if plate_number != "" and plate_name != "":
		_add_label("Number", plate_number, NUMBER_SIZE, GOLD, NUMBER_LIFT, yaw)
		_add_label("Name", plate_name, NAME_SIZE, SAND, -NAME_DROP, yaw)
		return
	push_warning("Bay plate '%s' names no known system ('%s') and no authored text, so it stays blank." % [
		name, system_id])


func _short_name() -> String:
	return String(SHORT_NAMES.get(system_id, GameState.display_name(system_id)))


func _add_label(label_name: String, text: String, size: int, colour: Color,
		lift: float, yaw: float) -> void:
	var label := Label3D.new()
	label.name = label_name
	label.text = text
	label.pixel_size = PIXEL_SIZE
	label.font_size = size
	label.outline_size = int(size * 0.14)
	label.modulate = colour
	label.outline_modulate = INK
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(0.0, lift, 0.0))
	add_child(label)
